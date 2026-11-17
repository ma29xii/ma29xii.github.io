import AppIntents
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
        let example = habits.first?.name ?? "Lesen"

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

                SiriGuide(habitName: example)
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

/// Siri-Sätze für eine Gewohnheit plus Anleitung für einen eigenen Satz ohne App-Namen.
struct SiriGuide: View {
    let habitName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("Sofort nutzbar", subtitle: "Diese Sätze kennt Siri direkt nach der Installation.")
                Phrase(text: "Hey Siri, heute \(habitName) in Stetig gemacht")
                Phrase(text: "Hey Siri, \(habitName) in Stetig erledigt")
                Phrase(text: "Hey Siri, wie läuft \(habitName) in Stetig?")
                Phrase(text: "Hey Siri, was ist heute in Stetig offen?")
            }
            .card(padding: 18)

            StepsCard(title: "Eigener Satz ohne „in Stetig“", steps: [
                "Unten auf „Kurzbefehle öffnen“ tippen.",
                "Neuen Kurzbefehl mit „+“ anlegen und die Aktion „Gewohnheit erledigen“ von Stetig hinzufügen.",
                "Als Gewohnheit „\(habitName)“ wählen.",
                "Den Kurzbefehl „Heute \(habitName) gemacht“ nennen.",
            ], footnote: "Danach reicht: „Hey Siri, heute \(habitName) gemacht.“ Siri antwortet mit deiner aktuellen Serie. Apple erlaubt Apps nur Sätze mit App-Namen – eigene Kurzbefehle sind der offizielle Weg für kürzere Sätze.")

            ShortcutsLink()
                .shortcutsLinkStyle(.automatic)
                .frame(maxWidth: .infinity)
        }
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
            .background(WidgetBackdrop(tint: tint), in: .rect(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
    }
}

/// Blatt aus der Detailseite: Siri für genau diese Gewohnheit.
struct SiriHabitSheet: View {
    let habit: Habit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SiriGuide(habitName: habit.name)
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
