import SwiftData
import UIKit
import UserNotifications

/// Lokale Erinnerungen – brauchen weder Server noch kostenpflichtigen Entwickler-Account.
enum Reminders {
    static let categoryID = "HABIT_REMINDER"
    static let doneActionID = "HABIT_DONE"

    static func registerCategories() {
        // Mit App-Sperre braucht „Erledigt“ auf dem Sperrbildschirm Face ID.
        let locked = UserDefaults.standard.bool(forKey: SettingsKey.appLock)
        let done = UNNotificationAction(identifier: doneActionID, title: "Erledigt", options: locked ? [.authenticationRequired] : [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [done], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private static func identifiers(for uuid: UUID) -> [String] {
        (0..<7).map { "habit.\(uuid.uuidString).\($0)" }
    }

    static func cancel(uuid: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers(for: uuid))
    }

    /// Welche Wochentage (0 = Montag) erinnert werden.
    static func reminderWeekdays(for habit: Habit) -> [Int] {
        if habit.kind == .build, habit.frequency == .weekdays {
            return (0..<7).filter { habit.weekdayMask & (1 << $0) != 0 }
        }
        return Array(0..<7)
    }

    static func reschedule(_ habit: Habit) {
        cancel(uuid: habit.uuid)
        guard habit.reminderEnabled, !habit.isArchived, !habit.isPaused else { return }

        let center = UNUserNotificationCenter.current()
        let ids = identifiers(for: habit.uuid)
        let content = UNMutableNotificationContent()
        content.title = habit.name
        content.body = habit.kind == .quit ? "Bleib dran – du schaffst das." : habit.goalDescription
        content.sound = .default
        content.categoryIdentifier = habit.kind == .build ? categoryID : ""
        content.userInfo = ["habit": habit.uuid.uuidString]

        for weekday in reminderWeekdays(for: habit) {
            var components = DateComponents()
            let minutes = Sanitize.minutes(habit.reminderMinutes)
            components.hour = minutes / 60
            components.minute = minutes % 60
            // Apple: 1 = Sonntag … 7 = Samstag.
            components.weekday = (weekday + 1) % 7 + 1
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            center.add(UNNotificationRequest(identifier: ids[weekday], content: content, trigger: trigger))
        }
    }

    static let summaryID = "summary.daily"

    /// Eine tägliche Erinnerung, den Tag abzuschließen – unabhängig von einzelnen Gewohnheiten.
    static func scheduleSummary(enabled: Bool, minutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [summaryID])
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tagesabschluss"
        content.body = "Wirf einen Blick auf heute – ist noch etwas offen?"
        content.sound = .default
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: summaryID, content: content, trigger: trigger))
    }

    static func rescheduleAll(in context: ModelContext) {
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        for habit in habits {
            reschedule(habit)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.registerCategories()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let uuid = response.notification.request.content.userInfo["habit"] as? String
        let isDone = response.actionIdentifier == Reminders.doneActionID
        DispatchQueue.main.async {
            if isDone, let uuid {
                let context = ModelContext(Store.shared)
                if let habit = Store.habit(uuid: uuid, in: context), !habit.snapshot().isDone(.today) {
                    habit.setAmount(max(habit.dailyTarget, 1), on: .today, in: context)
                    AppGroup.noteExternalChange()
                }
            }
            completionHandler()
        }
    }
}
