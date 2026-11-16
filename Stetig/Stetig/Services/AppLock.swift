import LocalAuthentication
import Observation
import SwiftUI

/// Optionale Sperre per Face ID / Touch ID / Gerätecode.
@Observable
final class AppLock {
    var isLocked: Bool
    private var isAuthenticating = false

    init() {
        isLocked = UserDefaults.standard.bool(forKey: SettingsKey.appLock)
    }

    func lockIfEnabled() {
        if UserDefaults.standard.bool(forKey: SettingsKey.appLock) {
            isLocked = true
        }
    }

    func unlock() {
        guard isLocked, !isAuthenticating else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Kein Gerätecode eingerichtet – dann gibt es nichts, womit man sperren könnte.
            isLocked = false
            return
        }
        isAuthenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Stetig entsperren") { success, _ in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if success {
                    self.isLocked = false
                }
            }
        }
    }

    /// Prüft einmalig, ob das Gerät überhaupt entsperren kann (für den Schalter in den Einstellungen).
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
}

struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Stetig ist gesperrt")
                    .font(.title3.weight(.semibold))
                Button {
                    lock.unlock()
                } label: {
                    Label("Entsperren", systemImage: "faceid")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
            }
        }
    }
}
