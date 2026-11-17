import LocalAuthentication
import Observation
import SwiftUI
import UIKit

/// Optionale Sperre per Face ID / Touch ID / Gerätecode.
///
/// Der Sperrbildschirm liegt in einem eigenen Fenster über allem – auch über
/// offenen Blättern (Timer, Editor, Export) und im App-Umschalter-Vorschaubild.
@Observable
final class AppLock {
    private(set) var isLocked: Bool

    private var isAuthenticating = false
    @ObservationIgnored private var cover: UIWindow?

    init() {
        isLocked = UserDefaults.standard.bool(forKey: SettingsKey.appLock)
    }

    func lockIfEnabled() {
        if UserDefaults.standard.bool(forKey: SettingsKey.appLock) {
            setLocked(true)
        }
    }

    /// Beim Wechsel in den App-Umschalter oder ins Kontrollzentrum nur abdecken,
    /// ohne zu sperren – so zeigt das Vorschaubild nichts, und nach dem Zurückkommen
    /// ist kein Face ID nötig.
    func coverIfEnabled() {
        if UserDefaults.standard.bool(forKey: SettingsKey.appLock) {
            showCover()
        }
    }

    func unlock() {
        updateCover()
        guard isLocked, !isAuthenticating else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Kein Gerätecode eingerichtet – dann gibt es nichts, womit man sperren könnte.
            setLocked(false)
            return
        }
        isAuthenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Stetig entsperren") { success, _ in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if success {
                    self.setLocked(false)
                }
            }
        }
    }

    /// Prüft einmalig, ob das Gerät überhaupt entsperren kann (für den Schalter in den Einstellungen).
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    // MARK: Sperrfenster

    private func setLocked(_ locked: Bool) {
        isLocked = locked
        updateCover()
    }

    private func updateCover() {
        if isLocked {
            showCover()
        } else {
            hideCover()
        }
    }

    private func showCover() {
        guard cover == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        switch UserDefaults.standard.integer(forKey: SettingsKey.appearance) {
        case 1: window.overrideUserInterfaceStyle = .light
        case 2: window.overrideUserInterfaceStyle = .dark
        default: break
        }
        let host = UIHostingController(rootView: LockScreen().environment(self))
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        window.isHidden = false
        cover = window
    }

    private func hideCover() {
        guard let window = cover else { return }
        cover = nil
        UIView.animate(withDuration: 0.2) {
            window.alpha = 0
        } completion: { _ in
            window.isHidden = true
        }
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
