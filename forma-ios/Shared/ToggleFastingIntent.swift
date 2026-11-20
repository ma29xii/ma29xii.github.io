import ActivityKit
import AppIntents
import Foundation
import WidgetKit

struct ToggleFastingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Fasten starten/beenden"

    @Parameter(title: "Fasten läuft") var expectedActive: Bool?
    @Parameter(title: "Fastenstart") var expectedStart: Date?

    init() {}

    init(expectedStart: Date?) {
        self.expectedActive = expectedStart != nil
        self.expectedStart = expectedStart
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let event: FastingWidgetStore.Event?
        do {
            event = try FastingWidgetStore.shared.toggle(expectedActive: expectedActive, expectedStart: expectedStart)
        } catch {
            throw SaveFastingError()
        }
        if case .end(let start, let end)? = event {
            let content = ActivityContent(state: FastingAttributes.ContentState(end: end), staleDate: nil)
            for activity in Activity<FastingAttributes>.activities where activity.attributes.start == start {
                nonisolated(unsafe) let target = activity
                await target.end(content, dismissalPolicy: .immediate)
            }
        }
        WidgetCenter.shared.reloadTimelines(ofKind: FastingWidgetStore.widgetKind)
        return .result()
    }
}

private struct SaveFastingError: LocalizedError {
    var errorDescription: String? { "Fasten konnte nicht gespeichert werden." }
}
