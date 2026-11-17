import AppIntents

/// Siri-Sätze, die sofort nach der Installation funktionieren.
/// Apple verlangt, dass jeder dieser Sätze den App-Namen enthält. Einen Satz ganz
/// ohne App-Namen („Hey Siri, heute Lesen gemacht“) legt man als eigenen Kurzbefehl an –
/// die Anleitung steht in der App unter Einstellungen › Widgets & Siri.
struct StetigShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteHabitIntent(),
            phrases: [
                "Heute \(\.$habit) in \(.applicationName) gemacht",
                "\(\.$habit) in \(.applicationName) erledigt",
                "\(\.$habit) in \(.applicationName) abhaken",
                "Hake \(\.$habit) in \(.applicationName) ab",
                "Gewohnheit in \(.applicationName) erledigen",
                "In \(.applicationName) etwas abhaken",
            ],
            shortTitle: "Gewohnheit erledigen",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: HabitStatusIntent(),
            phrases: [
                "Wie läuft \(\.$habit) in \(.applicationName)",
                "Serie von \(\.$habit) in \(.applicationName)",
                "Wie läuft meine Serie in \(.applicationName)",
            ],
            shortTitle: "Serie abfragen",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: TodayStatusIntent(),
            phrases: [
                "Was ist heute in \(.applicationName) offen",
                "Was steht heute in \(.applicationName) an",
                "Mein Tag in \(.applicationName)",
            ],
            shortTitle: "Heute offen",
            systemImageName: "list.bullet"
        )
    }
}

/// Hält Siri über die aktuellen Gewohnheitsnamen auf dem Laufenden.
enum SiriSync {
    static func refresh() {
        StetigShortcuts.updateAppShortcutParameters()
    }
}
