import Foundation
import UserNotifications

/// Der Coach arbeitet auch, wenn die App geschlossen ist:
/// - **Morgenbericht**, sobald die Nacht in Apple Health angekommen ist (einmal pro Tag).
/// - **Schlafenszeit-Erinnerung** 30 Minuten vor der empfohlenen Bettzeit.
/// Alles wird lokal berechnet, es geht nichts ins Internet.
@MainActor
enum CoachNotifier {
    static let morningKey = "forma.coach.morning"     // Einstellung an/aus
    static let bedtimeKey = "forma.coach.bedtime"     // Einstellung an/aus

    static var morningEnabled: Bool { UserDefaults.standard.object(forKey: morningKey) as? Bool ?? true }
    static var bedtimeEnabled: Bool { UserDefaults.standard.object(forKey: bedtimeKey) as? Bool ?? true }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Nach jedem erfolgreichen Abruf aufrufen (Vordergrund oder Hintergrund).
    static func afterSync(_ hub: DataHub) {
        guard !hub.isSample, !FormaApp.isUITest else { return }
        sendMorningReportIfDue(hub)
        scheduleBedtimeReminder(hub)
    }

    private static func sentKey(_ date: Date) -> String { "forma.coach.morningSent." + FitbitService.dayString(date) }

    static func sendMorningReportIfDue(_ hub: DataHub, now: Date = .now) {
        let hour = Calendar.forma.component(.hour, from: now)
        guard morningEnabled, (4...13).contains(hour), hub.today.sleep != nil,
              !UserDefaults.standard.bool(forKey: sentKey(now)) else { return }
        UserDefaults.standard.set(true, forKey: sentKey(now))
        let s = hub.scores
        let context = CoachEngine.Context(
            scores: s, today: hub.today,
            hrvDelta: hub.today.hrv.flatMap { v in hub.baseline(\.hrv).map { v - $0.mean } },
            rhrDelta: hub.today.restingHR.flatMap { v in hub.baseline(\.restingHR).map { v - $0.mean } },
            plannedRoutine: nil, trainedToday: false, isSample: false, hour: hour)
        let content = UNMutableNotificationContent()
        content.title = hub.availability.recovery ? "Erholung \(s.recovery) · Schlaf \(s.sleep)" : "Schlaf \(s.sleep)"
        content.body = CoachEngine.dailyLine(context)
        content.sound = .default
        content.threadIdentifier = "coach"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "forma.morning", content: content, trigger: nil), withCompletionHandler: nil)
    }

    static func scheduleBedtimeReminder(_ hub: DataHub, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["forma.bedtime"])
        guard bedtimeEnabled else { return }
        let s = hub.scores
        guard let bed = bedtimeDate(sleepNeed: s.sleepNeed, now: now) else { return }
        let remind = bed.addingTimeInterval(-30 * 60)
        guard remind > now.addingTimeInterval(60) else { return }
        let content = UNMutableNotificationContent()
        content.title = "In 30 Minuten ins Bett"
        content.body = "Gegen \(Format.clock(bed)) schlafen gehen, dann holst du \(Format.duration(s.sleepNeed)) Schlaf."
        content.sound = .default
        content.threadIdentifier = "coach"
        let comps = Calendar.forma.dateComponents([.year, .month, .day, .hour, .minute], from: remind)
        center.add(UNNotificationRequest(identifier: "forma.bedtime", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)),
                   withCompletionHandler: nil)
    }

    /// Bettzeit heute Abend für einen Wecker um 6:55 (wie `CoachEngine.bedtime`).
    nonisolated static func bedtimeDate(sleepNeed: TimeInterval, now: Date = .now, wakeHour: Int = 6, wakeMinute: Int = 55) -> Date? {
        let cal = Calendar.forma
        let tomorrow = now.startOfDay.adding(days: 1)
        guard let wake = cal.date(bySettingHour: wakeHour, minute: wakeMinute, second: 0, of: tomorrow),
              sleepNeed.isFinite, sleepNeed > 0, sleepNeed < 14 * 3600 else { return nil }
        return wake.addingTimeInterval(-sleepNeed - 10 * 60)
    }
}
