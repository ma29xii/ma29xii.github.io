import Foundation
import UserNotifications

/// Der Coach arbeitet auch, wenn die App geschlossen ist:
/// - **Morgenbericht**, sobald die Schlafdaten für heute aus Google Health geladen sind (einmal pro Tag).
/// - **Schlafenszeit-Erinnerung** 30 Minuten vor der empfohlenen Bettzeit.
/// Alles wird lokal berechnet, es geht nichts ins Internet.
///
/// Datenschutz (Codex R-02-07): Ohne ausdrückliche Einstellung stehen keine Gesundheitswerte in der
/// Mitteilung – sie kann auf dem Sperrbildschirm erscheinen.
@MainActor
enum CoachNotifier {
    static let morningKey = "forma.coach.morning"       // Einstellung an/aus
    static let bedtimeKey = "forma.coach.bedtime"       // Einstellung an/aus
    static let detailsKey = "forma.coach.showValues"    // Werte in der Mitteilung zeigen (Standard: aus)
    nonisolated static let wakeKey = "forma.wakeMinutes"            // Weckzeit in Minuten nach Mitternacht
    private static var morningReportsInFlight: Set<String> = []

    static var morningEnabled: Bool { UserDefaults.standard.object(forKey: morningKey) as? Bool ?? true }
    static var bedtimeEnabled: Bool { UserDefaults.standard.object(forKey: bedtimeKey) as? Bool ?? true }
    static var showValues: Bool { UserDefaults.standard.bool(forKey: detailsKey) }
    private static let bedtimeIDKey = "forma.coach.pendingBedtimeID"
    private static let stagedBedtimeIDsKey = "forma.coach.stagedBedtimeIDs"
    private static var bedtimeRevision = UUID()

    nonisolated static var wakeMinutes: Int { wakeMinutes(in: .standard) }

    nonisolated static func wakeMinutes(in defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: wakeKey) as? Int, (0..<(24 * 60)).contains(value) else {
            return 6 * 60 + 55
        }
        return value
    }

    /// Fragt nur auf ausdrückliche Aktion des Nutzers nach der Erlaubnis (Codex R-02-26).
    static func requestPermission() async -> Bool {
        guard !FormaApp.isUITest else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    nonisolated static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Wartet auf die Annahme beider Mitteilungen durch iOS.
    static func afterSync(_ hub: DataHub, confirmedSleep: CivilDay?, generation: Int) async -> String? {
        guard hub.canScheduleCoach(generation), !FormaApp.isUITest else { return nil }
        let morningIssue = await sendMorningReportIfDue(hub, confirmedSleep: confirmedSleep, generation: generation)
        let bedtimeIssue = await reconcileBedtime(hub, generation: generation, confirmedBySync: true)
        return morningIssue ?? bedtimeIssue
    }

    private static func dayStamp(_ date: Date) -> String {
        GoogleHealthTime.day(date, calendar: .forma)
    }

    private static func sendMorningReportIfDue(_ hub: DataHub, confirmedSleep: CivilDay?, generation: Int,
                                               now: Date = .now) async -> String? {
        let calendar = Calendar.forma
        let hour = calendar.component(.hour, from: now)
        let stamp = dayStamp(now)
        guard morningEnabled, (4...13).contains(hour), confirmedSleep == CivilDay(now, in: calendar),
              await authorizationStatus() == .authorized, hub.canScheduleCoach(generation),
              let asleep = hub.today.sleep?.asleep, asleep > 0 else { return nil }
        let content = UNMutableNotificationContent()
        content.threadIdentifier = "coach"
        content.sound = .default
        if showValues {
            let s = hub.scores
            let context = CoachEngine.Context(
                scores: s, today: hub.today,
                hrvDelta: hub.today.hrv.flatMap { v in hub.baseline(\.hrv).map { v - $0.mean } },
                rhrDelta: hub.today.restingHR.flatMap { v in hub.baseline(\.restingHR).map { v - $0.mean } },
                plannedRoutine: nil, trainedToday: false, isSample: false, hour: hour,
                recoveryAvailable: hub.availability.recovery, strainAvailable: hub.availability.strain, history: hub.history)
            let sleep = context.sleepScore.map { "Schlaf \($0)" } ?? "Schlaf \(Format.duration(asleep))"
            content.title = hub.availability.recovery ? "Erholung \(s.recovery) · \(sleep)" : sleep
            content.body = CoachEngine.dailyLine(context)
        } else {
            content.title = "Dein Tagesbericht ist bereit"
            content.body = "Deine Nacht ist da. Öffne Health für Erholung, Schlaf und deinen Plan für heute."
        }
        let id = "forma.morning." + stamp
        let center = UNUserNotificationCenter.current()
        let received = await enqueueMorningReportOnce(day: stamp) {
            guard hub.canScheduleCoach(generation), morningEnabled else { throw CancellationError() }
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            guard hub.canScheduleCoach(generation), morningEnabled else {
                center.removePendingNotificationRequests(withIdentifiers: [id])
                center.removeDeliveredNotifications(withIdentifiers: [id])
                throw CancellationError()
            }
        }
        return received ? nil : "Der Morgenbericht konnte nicht geplant werden."
    }

    @discardableResult
    static func enqueueMorningReportOnce(
        day: String, defaults: UserDefaults = .standard, enqueue: @MainActor () async throws -> Void
    ) async -> Bool {
        let sentKey = "forma.coach.morningSent." + day
        guard !defaults.bool(forKey: sentKey), morningReportsInFlight.insert(sentKey).inserted else { return true }
        defer { morningReportsInFlight.remove(sentKey) }
        do {
            try await enqueue()
            defaults.set(true, forKey: sentKey)
            return true
        } catch {
            return false
        }
    }

    static func removeCoachNotifications(now: Date = .now) {
        bedtimeRevision = UUID()
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.forma
        let morningIDs = (-7...1).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
            .map { "forma.morning." + dayStamp($0) }
        let ids = morningIDs + bedtimeIDs(in: .standard)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        clearBedtimeIDs(in: .standard)
        center.getDeliveredNotifications { delivered in
            let older = delivered.filter {
                let id = $0.request.identifier
                return $0.date <= now && (id.hasPrefix("forma.bedtime.") || id.hasPrefix("forma.morning."))
            }.map(\.request.identifier)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: older)
        }
    }

    /// Auch bei Änderungen der Weckzeit aus dem Profil aufrufbar.
    static func scheduleBedtimeReminder(_ hub: DataHub, now: Date = .now) async {
        let generation = hub.generation
        let issue = await reconcileBedtime(hub, generation: generation, now: now)
        hub.reportNotificationIssue(issue, generation: generation)
    }

    static func reconcileBedtime(
        _ hub: DataHub, generation: Int, now: Date = .now, confirmedBySync: Bool = false,
        defaults: UserDefaults = .standard, authorization: @MainActor () async -> UNAuthorizationStatus = { await authorizationStatus() },
        remove: @MainActor ([String]) -> Void = removeBedtimeRequests
    ) async -> String? {
        func enabled() -> Bool { defaults.object(forKey: bedtimeKey) as? Bool ?? true }
        guard hub.generation == generation, !Task.isCancelled, !FormaApp.isUITest else { return nil }
        guard enabled() else {
            removeBedtimeReminder(defaults: defaults, remove: remove)
            return nil
        }
        let token = UUID()
        bedtimeRevision = token
        let status = await authorization()
        guard bedtimeRevision == token, hub.canScheduleCoach(generation), enabled() else { return nil }
        if status == .denied { removeBedtimeReminder(defaults: defaults, remove: remove) }
        guard status == .authorized else { return nil }
        guard let need = CoachEngine.measuredSleepNeed(hub.scores, strainAvailable: hub.availability.strain, history: hub.history) else {
            if confirmedBySync && hub.bedtimeBasisIsConfirmedMissing {
                removeBedtimeReminder(defaults: defaults, remove: remove)
            }
            return nil
        }
        guard let plan = bedtimePlan(sleepNeed: need, now: now) else { return nil }
        let remind = plan.bed.addingTimeInterval(-30 * 60)
        guard remind > now.addingTimeInterval(60) else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "In 30 Minuten Schlafenszeit"
        content.body = showValues
            ? "Geschätzter Bedarf \(Format.duration(need)). Bei Wecker \(Format.clock(plan.wake)): gegen \(Format.clock(plan.bed)) ins Bett."
            : "Bei Wecker \(Format.clock(plan.wake)): gegen \(Format.clock(plan.bed)) ins Bett."
        content.sound = .default
        content.threadIdentifier = "coach"
        let id = "forma.bedtime." + token.uuidString
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        var components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: remind)
        components.timeZone = utc.timeZone
        return await replaceBedtimeReminder(id: id, defaults: defaults, isCurrent: {
            bedtimeRevision == token && hub.canScheduleCoach(generation) && enabled()
        }, enqueue: {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }, remove: remove)
    }

    static func removeBedtimeReminder() {
        removeBedtimeReminder(defaults: .standard, remove: removeBedtimeRequests)
    }

    private static func removeBedtimeReminder(defaults: UserDefaults, remove: @MainActor ([String]) -> Void) {
        bedtimeRevision = UUID()
        remove(bedtimeIDs(in: defaults))
        clearBedtimeIDs(in: defaults)
    }

    private static func removeBedtimeRequests(_ ids: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Hält den bestehenden Termin, bis iOS den neuen angenommen hat.
    static func replaceBedtimeReminder(
        id: String, defaults: UserDefaults = .standard, isCurrent: @MainActor () -> Bool,
        enqueue: @MainActor () async throws -> Void, remove: @MainActor ([String]) -> Void
    ) async -> String? {
        guard !Task.isCancelled, isCurrent() else { return nil }
        var staged = Set(defaults.stringArray(forKey: stagedBedtimeIDsKey) ?? [])
        staged.insert(id)
        defaults.set(staged.sorted(), forKey: stagedBedtimeIDsKey)
        do {
            try await enqueue()
        } catch {
            discardBedtime(id, defaults: defaults, remove: remove)
            guard !Task.isCancelled, isCurrent() else { return nil }
            return "Die Schlafenszeit-Erinnerung konnte nicht geplant werden."
        }
        guard !Task.isCancelled, isCurrent() else {
            discardBedtime(id, defaults: defaults, remove: remove)
            return nil
        }
        let previous = bedtimeIDs(in: defaults).filter { $0 != id }
        remove(previous)
        defaults.set(id, forKey: bedtimeIDKey)
        defaults.removeObject(forKey: stagedBedtimeIDsKey)
        return nil
    }

    private static func discardBedtime(_ id: String, defaults: UserDefaults, remove: ([String]) -> Void) {
        remove([id])
        let remaining = (defaults.stringArray(forKey: stagedBedtimeIDsKey) ?? []).filter { $0 != id }
        if remaining.isEmpty { defaults.removeObject(forKey: stagedBedtimeIDsKey) }
        else { defaults.set(remaining, forKey: stagedBedtimeIDsKey) }
    }

    private static func bedtimeIDs(in defaults: UserDefaults) -> [String] {
        var ids = Set(defaults.stringArray(forKey: stagedBedtimeIDsKey) ?? [])
        if let id = defaults.string(forKey: bedtimeIDKey) { ids.insert(id) }
        ids.insert("forma.bedtime")
        return ids.sorted()
    }

    private static func clearBedtimeIDs(in defaults: UserDefaults) {
        defaults.removeObject(forKey: bedtimeIDKey)
        defaults.removeObject(forKey: stagedBedtimeIDsKey)
    }

    /// Eine Quelle für Weckzeit und Bettzeit – UI und Mitteilung zeigen dieselbe Uhrzeit (Codex R-02-08).
    /// Nächster Wecker = nächste Weckzeit, die mindestens 3 Stunden in der Zukunft liegt (nach Mitternacht also heute früh).
    nonisolated static func bedtimePlan(sleepNeed: TimeInterval, now: Date = .now, wakeMinutes: Int? = nil,
                                        calendar: Calendar = .forma) -> (wake: Date, bed: Date)? {
        guard sleepNeed.isFinite, sleepNeed > 0, sleepNeed < 14 * 3600 else { return nil }
        let minutes = wakeMinutes ?? self.wakeMinutes
        guard (0..<(24 * 60)).contains(minutes) else { return nil }
        let today = calendar.startOfDay(for: now)
        let earliest = now.addingTimeInterval(3 * 3600)
        for offset in 0...2 {
            guard let day = calendar.startOfDay(offsetBy: offset, from: today),
                  let wake = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day,
                                           matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
                  calendar.isDate(wake, inSameDayAs: day), wake >= earliest else { continue }
            return (wake, wake.addingTimeInterval(-sleepNeed - 10 * 60))
        }
        return nil
    }

    /// Für bestehende Aufrufer und Tests.
    nonisolated static func bedtimeDate(sleepNeed: TimeInterval, now: Date = .now, wakeHour: Int = 6, wakeMinute: Int = 55) -> Date? {
        bedtimePlan(sleepNeed: sleepNeed, now: now, wakeMinutes: wakeHour * 60 + wakeMinute)?.bed
    }
}
