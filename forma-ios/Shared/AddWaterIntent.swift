import AppIntents
import Foundation
import WidgetKit

struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Wasser +250 ml"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = WaterWidgetStore.shared
        do {
            try store.recordGlass()
        } catch {
            throw SaveWaterError()
        }
        // Auch der Control-Center-Button aktualisiert das Home-Screen-Widget.
        WidgetCenter.shared.reloadTimelines(ofKind: WaterWidgetStore.widgetKind)
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        if let progress = try? store.progress(at: now, calendar: calendar) {
            let refresh = WaterReminderNotifications.refresh(goal: progress.goalMilliliters, total: progress.milliliters,
                                                             measuredAt: now, calendar: calendar, defaults: .standard)
            await refresh?.value
        }
        return .result()
    }
}

// Der Intent braucht den Benachrichtigungskontext und die Einstellungen der App.
@available(iOSApplicationExtension, unavailable)
@available(*, deprecated)
extension AddWaterIntent: ForegroundContinuableIntent {}

private struct SaveWaterError: LocalizedError {
    var errorDescription: String? { "Wasser konnte nicht gespeichert werden." }
}
