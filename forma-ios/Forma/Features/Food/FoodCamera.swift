import AVFoundation
import SwiftUI
import UIKit

/// Gemeinsame Kamera-Berechtigung für Barcode-Scanner, Essensfoto und Coach-Fotos.
enum CameraAccess {
    enum State: Equatable, Sendable { case ready, needsRequest, denied, unavailable }

    static func state(hasCamera: Bool, status: AVAuthorizationStatus) -> State {
        guard hasCamera else { return .unavailable }
        switch status {
        case .authorized: return .ready
        case .notDetermined: return .needsRequest
        default: return .denied   // .denied, .restricted, künftige Fälle
        }
    }

    @MainActor static var current: State {
        state(hasCamera: UIImagePickerController.isSourceTypeAvailable(.camera),
              status: AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// Fragt nur, wenn iOS noch nicht gefragt hat. Liefert den Zustand danach.
    @MainActor static func request() async -> State {
        if current == .needsRequest { _ = await AVCaptureDevice.requestAccess(for: .video) }
        return current
    }

    @MainActor static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Hinweis bei verweigertem Kamerazugriff: Weg zu den Einstellungen, Alternative im Text.
struct CameraDeniedNotice: View {
    var alternative = "Du kannst stattdessen ein Foto aus deiner Mediathek wählen."

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Kein Zugriff auf die Kamera")
                .font(.formaRowTitle)
            Text(alternative)
                .font(.formaBody)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Einstellungen öffnen") { CameraAccess.openSettings() }
                .font(.formaBody.weight(.semibold))
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Ernährungs-Einstellungen in der Vorschau getrennt halten (Beispieldaten überschreiben nie das echte Profil).
    func foodSettingsStore() -> some View { modifier(FoodSettingsStore()) }
}

private struct FoodSettingsStore: ViewModifier {
    @Environment(DataHub.self) private var hub
    func body(content: Content) -> some View {
        content.defaultAppStorage(FoodSettings.store(isSample: hub.isSample))
    }
}
