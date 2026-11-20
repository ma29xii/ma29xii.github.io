import AppIntents
import Foundation
import WidgetKit

struct ToggleFastingIntent: AppIntent {
    static let title: LocalizedStringResource = "Fasten starten/beenden"
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Fasten läuft") var expectedActive: Bool?

    init() {}

    init(expectedActive: Bool) {
        self.expectedActive = expectedActive
    }

    func perform() async throws -> some IntentResult {
        do {
            try FastingWidgetStore.shared.toggle(expectedActive: expectedActive)
        } catch {
            throw SaveFastingError()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: FastingWidgetStore.widgetKind)
        return .result()
    }
}

private struct SaveFastingError: LocalizedError {
    var errorDescription: String? { "Fasten konnte nicht gespeichert werden." }
}
