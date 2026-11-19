import AppIntents
import Foundation
import WidgetKit

struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Wasser +250 ml"
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult {
        do {
            try WaterWidgetStore.shared.recordGlass()
        } catch {
            throw SaveWaterError()
        }
        // Auch der Control-Center-Button aktualisiert das Home-Screen-Widget.
        WidgetCenter.shared.reloadTimelines(ofKind: WaterWidgetStore.widgetKind)
        return .result()
    }
}

private struct SaveWaterError: LocalizedError {
    var errorDescription: String? { "Wasser konnte nicht gespeichert werden." }
}
