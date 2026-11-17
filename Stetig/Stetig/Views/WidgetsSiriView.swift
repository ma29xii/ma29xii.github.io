import AppIntents
import Intents
import SwiftData
import SwiftUI

/// Einstellungen › Widgets & Siri: Vorschau der Widgets und alle Siri-Sätze.
struct WidgetsSiriView: View {
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: [SortDescriptor(\Habit.sortOrder), SortDescriptor(\Habit.createdAt)])
    private var habits: [Habit]

    var body: some View {
        let data = WidgetLoader.habits(from: habits)
        let first = data.first ?? .sample
        let summary = TodaySummary(habits: data.isEmpty ? [.sample] : data)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Widgets", symbol: "square.grid.2x2")

                HStack(spacing: 14) {
                    WidgetFrame(height: 170, tint: first.tint) {
                        HabitWidgetContent(habit: first, size: .small)
                    }
                    WidgetFrame(height: 170) {
                        TodayWidgetContent(summary: summary, size: .small)
                    }
                }
                WidgetFrame(height: 170, tint: first.tint) {
                    HabitWidgetContent(habit: first, size: .medium)
                }
                WidgetFrame(height: 170) {
                    MultiHabitWidgetContent(habits: data.isEmpty ? [.sample] : data, limit: 3)
                }
                WidgetFrame(height: 170) {
                    TodayWidgetContent(summary: summary, size: .medium)
                }
                WidgetFrame(height: 380, tint: first.tint) {
                    HabitWidgetContent(habit: first, size: .large)
                }

                StepsCard(title: "Widget zum Home-Bildschirm hinzufügen", steps: [
                    "Home-Bildschirm an einer freien Stelle gedrückt halten.",
                    "Oben links auf „Bearbeiten“ und dann „Widget hinzufügen“ tippen.",
                    "„Stetig“ suchen und „Gewohnheit“, „Mehrere Gewohnheiten“ oder „Heute“ wählen – klein, mittel oder groß.",
                    "Gewohnheiten wechseln: Widget gedrückt halten › „Widget bearbeiten“.",
                    "Für Liquid Glass: Home-Bildschirm gedrückt halten › „Bearbeiten“ › „Anpassen“ › „Klar“.",
                ], footnote: "Der Haken im Widget funktioniert direkt, ohne die App zu öffnen. Es gibt die Widgets auch für den Sperrbildschirm, und im Kontrollzentrum ein Steuerelement zum Abhaken.")

                SectionHeader(title: "Siri", symbol: "mic.fill")
                    .padding(.top, 8)

                SiriGuide(habits: habits.filter { !$0.isPaused })
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .ambientBackground()
        .navigationTitle("Widgets & Siri")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Siri einrichten: eigene Sätze per Knopfdruck, dazu die Sätze, die sofort gehen.
struct SiriGuide: View {
    let habits: [Habit]

    var body: some View {
        let name = habits.first?.name ?? "Lesen"
        VStack(alignment: .leading, spacing: 16) {
            VoiceShortcutsCard(habits: habits)

            VStack(alignment: .leading, spacing: 12) {
                CardTitle("Sofort nutzbar", subtitle: "Diese Sätze kennt Siri direkt nach der Installation – sie laufen im Hintergrund, auch ohne die App zu öffnen.")
                Phrase(text: "Hey Siri, heute \(name) in Stetig gemacht")
                Phrase(text: "Hey Siri, \(name) in Stetig erledigt")
                Phrase(text: "Hey Siri, wie läuft \(name) in Stetig?")
                Phrase(text: "Hey Siri, was ist heute in Stetig offen?")
            }
            .card(padding: 18)

            Text("Eigene Abläufe – etwa mehrere Gewohnheiten auf einmal – baust du in der Kurzbefehle-App mit der Aktion „Gewohnheit erledigen“.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ShortcutsLink()
                .shortcutsLinkStyle(.automatic)
                .frame(maxWidth: .infinity)
        }
    }
}

/// „Mit einem Tipp zu Siri“: pro Gewohnheit ein Knopf, der Apples Siri-Blatt mit
/// fertig eingetragenem Satz öffnet.
struct VoiceShortcutsCard: View {
    let habits: [Habit]

    @State private var existing: [String: INVoiceShortcut] = [:]
    @State private var target: Target?

    struct Target: Identifiable {
        let id: String
        let name: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle("Mit einem Tipp zu Siri", subtitle: "Der Satz ist schon eingetragen – nur noch „Hinzufügen“ tippen. Danach reicht „Hey Siri, heute \(habits.first?.name ?? "Lesen") gemacht“. Stetig öffnet sich kurz und hakt ab.")
            if habits.isEmpty {
                Text("Lege zuerst eine Gewohnheit an.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(habits) { habit in
                let id = habit.uuid.uuidString
                VoiceShortcutRow(
                    habitID: id,
                    name: habit.name,
                    symbol: habit.symbol,
                    tint: Palette.entry(habit.colorID),
                    existing: existing[id]
                ) {
                    target = Target(id: id, name: habit.name)
                }
            }
        }
        .card(padding: 18)
        .task { existing = await VoiceShortcut.existing() }
        .sheet(item: $target, onDismiss: refresh) { target in
            VoiceShortcutSheet(habitID: target.id, name: target.name, existing: existing[target.id]) {
                self.target = nil
            }
            .ignoresSafeArea()
        }
    }

    private func refresh() {
        Task { existing = await VoiceShortcut.existing() }
    }
}

// MARK: - Bausteine

private struct SectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.bold))
            .padding(.leading, 4)
    }
}

private struct Phrase: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 20)
            Text("„\(text)“")
                .font(.body)
        }
    }
}

struct StepsCard: View {
    let title: String
    let steps: [String]
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.tint))
                    Text(step)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: 18)
    }
}

/// Rahmen, der wie ein Widget auf dem Home-Bildschirm aussieht.
private struct WidgetFrame<Content: View>: View {
    let height: CGFloat
    var tint: HabitColor = WidgetLoader.accent
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(height: height)
            .background {
                WidgetBackdrop(tint: tint)
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
    }
}

/// Einstellungen › Siri-Kurzbefehle: alles zu Siri auf einer Seite.
struct SiriSetupView: View {
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: [SortDescriptor(\Habit.sortOrder), SortDescriptor(\Habit.createdAt)])
    private var habits: [Habit]

    var body: some View {
        ScrollView {
            SiriGuide(habits: habits.filter { !$0.isPaused })
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .readableWidth()
        }
        .ambientBackground()
        .navigationTitle("Siri-Kurzbefehle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Blatt aus der Detailseite: Siri für genau diese Gewohnheit.
struct SiriHabitSheet: View {
    let habit: Habit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SiriGuide(habits: [habit])
                    .padding(16)
                    .readableWidth()
            }
            .ambientBackground(Palette.entry(habit.colorID))
            .navigationTitle("Mit Siri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
