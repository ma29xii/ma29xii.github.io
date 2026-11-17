import Intents
import IntentsUI
import SwiftUI

/// Eigene Siri-Sätze ganz ohne App-Namen („Hey Siri, heute Lesen gemacht“).
///
/// Apple lässt Apps keine fertigen Kurzbefehle in die Kurzbefehle-App schreiben
/// (Dateien müssen signiert sein). Der offizielle Weg ist Apples „Zu Siri hinzufügen“-
/// Blatt: Der Satz ist schon eingetragen, man tippt nur noch auf „Hinzufügen“.
/// Danach steht der Kurzbefehl auch in der Kurzbefehle-App.
///
/// Ein solcher Kurzbefehl öffnet Stetig kurz, hakt die Gewohnheit ab und zeigt
/// eine Bestätigung. Er braucht keine Siri-Berechtigung, die kostenlose
/// Apple-IDs nicht bekommen.
enum VoiceShortcut {
    static let habitKey = "habit"

    static var activityType: String {
        (Bundle.main.bundleIdentifier ?? "io.github.ma29xii.stetig") + ".complete-habit"
    }

    static func phrase(for name: String) -> String {
        "Heute \(name) gemacht"
    }

    static func activity(habitID: String, name: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = "\(name) erledigen"
        activity.userInfo = [habitKey: habitID]
        activity.requiredUserInfoKeys = [habitKey]
        activity.isEligibleForPrediction = true
        activity.isEligibleForSearch = false
        activity.persistentIdentifier = "complete-\(habitID)"
        activity.suggestedInvocationPhrase = phrase(for: name)
        return activity
    }

    static func habitID(from activity: NSUserActivity) -> String? {
        activity.userInfo?[habitKey] as? String
    }

    /// Bereits angelegte Sätze, nach Gewohnheit. Leer, wenn das System nichts liefert.
    static func existing() async -> [String: INVoiceShortcut] {
        let type = activityType
        return await withCheckedContinuation { continuation in
            INVoiceShortcutCenter.shared.getAllVoiceShortcuts { shortcuts, _ in
                var result: [String: INVoiceShortcut] = [:]
                for shortcut in shortcuts ?? [] {
                    guard let activity = shortcut.shortcut.userActivity,
                          activity.activityType == type,
                          let id = VoiceShortcut.habitID(from: activity) else { continue }
                    result[id] = shortcut
                }
                continuation.resume(returning: result)
            }
        }
    }
}

/// Apples Blatt zum Anlegen bzw. Bearbeiten eines Siri-Satzes.
struct VoiceShortcutSheet: UIViewControllerRepresentable {
    let habitID: String
    let name: String
    var existing: INVoiceShortcut?
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        if let existing {
            let controller = INUIEditVoiceShortcutViewController(voiceShortcut: existing)
            controller.delegate = context.coordinator
            return controller
        }
        let shortcut = INShortcut(userActivity: VoiceShortcut.activity(habitID: habitID, name: name))
        let controller = INUIAddVoiceShortcutViewController(shortcut: shortcut)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, INUIAddVoiceShortcutViewControllerDelegate, INUIEditVoiceShortcutViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: (any Error)?) {
            onFinish()
        }

        func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
            onFinish()
        }

        func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didUpdate voiceShortcut: INVoiceShortcut?, error: (any Error)?) {
            onFinish()
        }

        func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didDeleteVoiceShortcutWithIdentifier deletedVoiceShortcutIdentifier: UUID) {
            onFinish()
        }

        func editVoiceShortcutViewControllerDidCancel(_ controller: INUIEditVoiceShortcutViewController) {
            onFinish()
        }
    }
}

/// Eine Zeile pro Gewohnheit mit „Zu Siri hinzufügen“ bzw. dem schon angelegten Satz.
struct VoiceShortcutRow: View {
    let habitID: String
    let name: String
    let symbol: String
    let tint: HabitColor
    let existing: INVoiceShortcut?
    let add: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HabitIcon(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("„\(existing?.invocationPhrase ?? VoiceShortcut.phrase(for: name))“")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if existing == nil {
                Button(action: add) {
                    Label("Hinzufügen", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("\(name) zu Siri hinzufügen")
            } else {
                Button(action: add) {
                    Label("Aktiv", systemImage: "checkmark")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Siri-Satz für \(name) bearbeiten")
            }
        }
    }
}

/// Kurze Bestätigung oben im Bild, nachdem ein eigener Siri-Satz die App geöffnet hat.
struct VoiceBanner: View {
    let text: String
    let tint: HabitColor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(tint.onColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.gradient))
            Text(text)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}
