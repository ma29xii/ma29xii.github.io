import AppIntents
import Observation

enum HealthIntentDestination: Equatable, Sendable {
    case startTraining
    case scanFood
}

/// Bleibt auch erhalten, wenn das Hauptfenster erst nach dem Intent bereit wird.
@MainActor
@Observable
final class HealthIntentRouter {
    static let shared = HealthIntentRouter()
    private(set) var pending: HealthIntentDestination?

    func request(_ destination: HealthIntentDestination) {
        pending = destination
    }

    func consume() -> HealthIntentDestination? {
        defer { pending = nil }
        return pending
    }
}

enum TrainingIntentTarget: String, AppEnum {
    case training

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Training"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.training: "Training"]
}

/// Muss in der Haupt-App und in der Erweiterung enthalten sein, damit der Control die App öffnen kann.
struct StartTrainingIntent: OpenIntent {
    static let title: LocalizedStringResource = "Training starten"

    @Parameter(title: "Ziel", default: .training)
    var target: TrainingIntentTarget

    @MainActor
    func perform() async throws -> some IntentResult {
        HealthIntentRouter.shared.request(.startTraining)
        return .result()
    }
}
