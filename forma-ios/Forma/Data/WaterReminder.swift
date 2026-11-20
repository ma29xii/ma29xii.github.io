import Foundation
import UserNotifications

enum WaterReminder {
    private static let deficit = 500.0
    private static let minimumSpacing: TimeInterval = 2 * 60 * 60
    private static let dailyLimit = 4

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
    private static var isUpdating = false

    static func refresh(goal: Double, total: Double, measuredAt: Date, calendar: Calendar, defaults: UserDefaults) {
        guard !FormaApp.isUITest else { return }
        if !isUpdating, !defaults.bool(forKey: enabledKey), defaults.object(forKey: plannedKey) == nil { return }
        queued = Update(goal: goal, total: total, measuredAt: measuredAt, calendar: calendar, defaults: defaults)
        guard !isUpdating else { return }
        isUpdating = true
        // Nur ein Schreibvorgang zur Zeit. Neuere Wasserstände ersetzen wartende Aktualisierungen.
        Task { @MainActor in
            while let update = queued {
                queued = nil
                await apply(update)
            }
            isUpdating = false
        }
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
        guard defaults.bool(forKey: enabledKey), status == .authorized || status == .provisional,
              update.calendar.isDate(update.measuredAt, inSameDayAs: now),
              let next = WaterReminder.nextDate(goal: update.goal, total: update.total, now: now,
                                                history: history, calendar: update.calendar) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            defaults.removeObject(forKey: plannedKey)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Wasser"
        content.body = "Noch \(FoodText.liters(update.goal - update.total)) bis zu deinem Ziel"
        content.threadIdentifier = "water"
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        var components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: next)
        components.timeZone = utc.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        defaults.set(next, forKey: plannedKey)
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
