import Foundation
import UserNotifications

/// Der Coach arbeitet auch, wenn die App geschlossen ist:
/// - **Morgenbericht**, sobald die heutige Nacht in Apple Health angekommen ist (einmal pro Tag).
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
    static let wakeKey = "forma.wakeMinutes"            // Weckzeit in Minuten nach Mitternacht

    static var morningEnabled: Bool { UserDefaults.standard.object(forKey: morningKey) as? Bool ?? true }
    static var bedtimeEnabled: Bool { UserDefaults.standard.object(forKey: bedtimeKey) as? Bool ?? true }
    static var showValues: Bool { UserDefaults.standard.bool(forKey: detailsKey) }
    nonisolated static var wakeMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: wakeKey)
        return (1...(24 * 60 - 1)).contains(v) ? v : 6 * 60 + 55
    }

    /// Fragt nur auf ausdrückliche Aktion des Nutzers nach der Erlaubnis (Codex R-02-26).
    static func requestPermission() async -> Bool {
        guard !FormaApp.isUITest else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    nonisolated static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Nach jedem Abruf mit frischen Daten (Vordergrund oder Hintergrund).
    static func afterSync(_ hub: DataHub) {
        guard !hub.isSample, !FormaApp.isUITest else { return }
        Task {
            guard await authorizationStatus() == .authorized else { return }
            await sendMorningReportIfDue(hub)
            await scheduleBedtimeReminder(hub)
        }
    }

    private static func sentKey(_ date: Date) -> String { "forma.coach.morningSent." + FitbitService.dayString(date) }

    static func sendMorningReportIfDue(_ hub: DataHub, now: Date = .now) async {
        let hour = Calendar.forma.component(.hour, from: now)
        // Nur mit einer Nacht von *heute* – nie aus einem alten Stand (Codex R-02-07/24).
        guard morningEnabled, (4...13).contains(hour), Calendar.forma.isDate(hub.today.date, inSameDayAs: now),
              hub.today.sleep != nil, !UserDefaults.standard.bool(forKey: sentKey(now)) else { return }
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
                recoveryAvailable: hub.availability.recovery, strainAvailable: hub.availability.strain)
            content.title = hub.availability.recovery ? "Erholung \(s.recovery) · Schlaf \(s.sleep)" : "Schlaf \(s.sleep)"
            content.body = CoachEngine.dailyLine(context)
        } else {
            content.title = "Dein Tagesbericht ist bereit"
            content.body = "Deine Nacht ist da. Öffne Forma für Erholung, Schlaf und deinen Plan für heute."
        }
        let id = "forma.morning." + FitbitService.dayString(now)
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            // Erst nach erfolgreicher Annahme als erledigt merken (Codex R-02-07).
            UserDefaults.standard.set(true, forKey: sentKey(now))
        } catch {
            // Beim nächsten Abruf erneut versuchen.
        }
    }

    static func scheduleBedtimeReminder(_ hub: DataHub, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        guard bedtimeEnabled, !hub.isSample else {
            center.removePendingNotificationRequests(withIdentifiers: ["forma.bedtime"])
            return
        }
        let s = hub.scores
        guard let plan = bedtimePlan(sleepNeed: s.sleepNeed, now: now) else { return }
        let remind = plan.bed.addingTimeInterval(-30 * 60)
        guard remind > now.addingTimeInterval(60) else { return }
        let content = UNMutableNotificationContent()
        content.title = "In 30 Minuten Schlafenszeit"
        content.body = showValues
            ? "Geschätzter Bedarf \(Format.duration(s.sleepNeed)). Bei Wecker \(Format.clock(plan.wake)): gegen \(Format.clock(plan.bed)) ins Bett."
            : "Bei Wecker \(Format.clock(plan.wake)): gegen \(Format.clock(plan.bed)) ins Bett."
        content.sound = .default
        content.threadIdentifier = "coach"
        var comps = Calendar.forma.dateComponents([.year, .month, .day, .hour, .minute], from: remind)
        comps.timeZone = Calendar.forma.timeZone   // ausdrücklich, damit Reisen nichts verschiebt (Codex R-02-08)
        // Ersetzen statt erst löschen: gleiche Kennung überschreibt die alte Planung.
        try? await center.add(UNNotificationRequest(identifier: "forma.bedtime", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    /// Eine Quelle für Weckzeit und Bettzeit – UI und Mitteilung zeigen dieselbe Uhrzeit (Codex R-02-08).
    /// Nächster Wecker = nächste Weckzeit, die mindestens 3 Stunden in der Zukunft liegt (nach Mitternacht also heute früh).
    nonisolated static func bedtimePlan(sleepNeed: TimeInterval, now: Date = .now, wakeMinutes: Int? = nil,
                                        calendar: Calendar = .forma) -> (wake: Date, bed: Date)? {
        guard sleepNeed.isFinite, sleepNeed > 0, sleepNeed < 14 * 3600 else { return nil }
        let minutes = wakeMinutes ?? self.wakeMinutes
        let today = calendar.startOfDay(for: now)
        guard var wake = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: today) else { return nil }
        while wake < now.addingTimeInterval(3 * 3600) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: wake) else { return nil }
            wake = next
        }
        return (wake, wake.addingTimeInterval(-sleepNeed - 10 * 60))
    }

    /// Für bestehende Aufrufer und Tests.
    nonisolated static func bedtimeDate(sleepNeed: TimeInterval, now: Date = .now, wakeHour: Int = 6, wakeMinute: Int = 55) -> Date? {
        bedtimePlan(sleepNeed: sleepNeed, now: now, wakeMinutes: wakeHour * 60 + wakeMinute)?.bed
    }
}
