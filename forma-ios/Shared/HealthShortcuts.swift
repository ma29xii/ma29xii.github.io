import AppIntents
import Foundation

struct ReadRecoveryIntent: AppIntent {
    static let title: LocalizedStringResource = "Wie ist meine Erholung?"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = WidgetSnapshotStore.shared.current(at: .now),
              let recovery = snapshot.recovery else {
            return .result(dialog: "Für heute liegt keine Erholungsmessung vor.")
        }
        let time = snapshot.updatedAt.formatted(date: .omitted, time: .shortened)
        return .result(dialog: "Deine Erholung liegt bei \(recovery) Prozent. Stand \(time).")
    }
}

struct ScanFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Essen scannen"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        HealthIntentRouter.shared.request(.scanFood)
        return .result()
    }
}

struct HealthShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTrainingIntent(), phrases: ["Training mit \(.applicationName) starten"],
                    shortTitle: "Training starten", systemImageName: "dumbbell.fill")
        AppShortcut(intent: ReadRecoveryIntent(), phrases: ["Wie ist meine Erholung in \(.applicationName)"],
                    shortTitle: "Wie ist meine Erholung?", systemImageName: "heart.circle")
        AppShortcut(intent: ScanFoodIntent(), phrases: ["Essen mit \(.applicationName) scannen"],
                    shortTitle: "Essen scannen", systemImageName: "barcode.viewfinder")
    }
}
