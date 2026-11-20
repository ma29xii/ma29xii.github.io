import Foundation
import UserNotifications

enum WaterReminder {
    private static let deficit = 500.0
    private static let minimumSpacing: TimeInterval = 2 * 60 * 60
    private static let dailyLimit = 4

    struct Plan {
        let date: Date
        let remainingMilliliters: Double
    }

    static func plan(goal: Double, total: Double, now: Date, history: [Date], calendar: Calendar) -> Plan? {
        guard total.isFinite, total >= 0 else { return nil }
        if let today = nextDate(goal: goal, total: total, now: now, history: history, calendar: calendar) {
            return Plan(date: today, remainingMilliliters: goal - total)
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let first = nextDate(goal: goal, total: 0, now: tomorrow, history: [], calendar: calendar) else { return nil }
        return Plan(date: first, remainingMilliliters: goal)
    }

    static func target(goal: Double, at date: Date, calendar: Calendar) -> Double {
        guard let window = window(on: date, calendar: calendar) else { return 0 }
        let fraction = date.timeIntervalSince(window.lowerBound)
            / window.upperBound.timeIntervalSince(window.lowerBound)
        return goal * min(1, max(0, fraction))
    }

    /// Erster planbarer Zeitpunkt am selben Tag. Die Grenze selbst reicht noch nicht.
    static func nextDate(goal: Double, total: Double, now: Date, history: [Date], calendar: Calendar) -> Date? {
        guard goal.isFinite, total.isFinite, total >= 0, total + deficit < goal,
              let window = window(on: now, calendar: calendar) else { return nil }
        let today = history.filter { calendar.isDate($0, inSameDayAs: now) }
        guard today.count < dailyLimit else { return nil }

        let duration = window.upperBound.timeIntervalSince(window.lowerBound)
        let crossing = window.lowerBound.addingTimeInterval(duration * ((total + deficit) / goal))
        let earliest = Date(timeIntervalSinceReferenceDate:
            max(now, crossing).timeIntervalSinceReferenceDate.rounded(.down) + 1)
        let spacing = today.max().map {
            Date(timeIntervalSinceReferenceDate:
                ($0.timeIntervalSinceReferenceDate + minimumSpacing).rounded(.up))
        } ?? earliest
        var next = max(earliest, spacing)
        if total >= target(goal: goal, at: next, calendar: calendar) - deficit {
            next = next.addingTimeInterval(1)
        }
        return next <= window.upperBound ? next : nil
    }

    private static func window(on date: Date, calendar: Calendar) -> ClosedRange<Date>? {
        guard let start = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: date),
              let end = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date),
              calendar.isDate(start, inSameDayAs: date), calendar.isDate(end, inSameDayAs: date),
              start < end else { return nil }
        return start...end
    }
}

@MainActor
enum WaterReminderNotifications {
    nonisolated static let enabledKey = "forma.water.enabled"
    private static let identifier = "forma.water.next"
    private static let plannedKey = "forma.water.plannedDate"
    private static let historyKey = "forma.water.history"

    private struct Update {
        let goal: Double
        let total: Double
        let measuredAt: Date
        let calendar: Calendar
        let defaults: UserDefaults
    }

    private static var queued: Update?
    private static var updateTask: Task<Void, Never>?

    @discardableResult
    static func refresh(goal: Double, total: Double, measuredAt: Date, calendar: Calendar,
                        defaults: UserDefaults) -> Task<Void, Never>? {
        guard !ProcessInfo.processInfo.arguments.contains("-uitest") else { return nil }
        if updateTask == nil, !defaults.bool(forKey: enabledKey), defaults.object(forKey: plannedKey) == nil { return nil }
        queued = Update(goal: goal, total: total, measuredAt: measuredAt, calendar: calendar, defaults: defaults)
        if let updateTask { return updateTask }
        // Nur ein Schreibvorgang zur Zeit. Neuere Wasserstände ersetzen wartende Aktualisierungen.
        let task = Task { @MainActor in
            while let update = queued {
                queued = nil
                await apply(update)
            }
            updateTask = nil
        }
        updateTask = task
        return task
    }

    private static func apply(_ update: Update) async {
        let defaults = update.defaults
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard queued == nil else { return }

        let planned = defaults.object(forKey: plannedKey) as? Date
        let deliveredAt: Date?
        if let planned, planned <= .now {
            deliveredAt = await lastDelivery(identifier: identifier, after: planned)
        } else {
            deliveredAt = nil
        }
        guard queued == nil else { return }

        let now = Date.now
        var history = (defaults.array(forKey: historyKey) as? [Date] ?? [])
            .filter { update.calendar.isDate($0, inSameDayAs: now) }
        if let planned, planned <= now {
            // Auch weggewischte und im Vordergrund empfangene Mitteilungen zählen.
            let date = deliveredAt ?? planned
            if update.calendar.isDate(date, inSameDayAs: now) { history.append(date) }
            defaults.set(history, forKey: historyKey)
            defaults.removeObject(forKey: plannedKey)
        }
        let total = update.calendar.isDate(update.measuredAt, inSameDayAs: now) ? update.total : 0
        guard defaults.bool(forKey: enabledKey), status == .authorized || status == .provisional,
              let plan = WaterReminder.plan(goal: update.goal, total: total, now: now,
                                            history: history, calendar: update.calendar) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            defaults.removeObject(forKey: plannedKey)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Wasser"
        let liters = (plan.remainingMilliliters / 1_000).formatted(
            .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "de_DE")))
        content.body = "Noch \(liters) l bis zu deinem Ziel"
        content.threadIdentifier = "water"
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        var components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.date)
        components.timeZone = utc.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        defaults.set(plan.date, forKey: plannedKey)
        do {
            try await center.add(request)
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            defaults.removeObject(forKey: plannedKey)
        }
    }

    nonisolated private static func lastDelivery(identifier: String, after planned: Date) async -> Date? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Date?, Never>) in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                let matchingDates = notifications.compactMap { notification -> Date? in
                    guard notification.request.identifier == identifier, notification.date >= planned else { return nil }
                    return notification.date
                }
                continuation.resume(returning: matchingDates.max())
            }
        }
    }
}
