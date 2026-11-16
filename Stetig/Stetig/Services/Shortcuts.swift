import AppIntents

/// Macht „Gewohnheit abhaken“ in der Kurzbefehle-App und per Siri verfügbar.
struct StetigShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogHabitIntent(),
            phrases: [
                "Gewohnheit in \(.applicationName) abhaken",
                "Hake eine Gewohnheit in \(.applicationName) ab",
            ],
            shortTitle: "Gewohnheit abhaken",
            systemImageName: "checkmark.circle.fill"
        )
    }
}
