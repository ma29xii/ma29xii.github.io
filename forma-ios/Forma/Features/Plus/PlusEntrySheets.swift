import SwiftUI
import SwiftData

/// Stimmung und Energie erfassen: zwei Reihen mit 1 bis 5 und eine Notiz.
struct PlusMoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var mood = 3
    @State private var energy = 3
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    scale("Stimmung", value: $mood, id: "plus.mood.mood")
                    scale("Energie", value: $energy, id: "plus.mood.energy")
                    TextField("Notiz", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.formaBodyLarge)
                        .padding(Space.s3)
                        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Theme.plate))
                        .accessibilityIdentifier("plus.mood.note")
                    Button("Speichern", action: save)
                        .buttonStyle(PlusSaveStyle())
                        .accessibilityIdentifier("plus.mood.save")
                }
                .padding(Space.page)
            }
            .dashboardScreen()
            .navigationTitle("Stimmung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
    }

    private func scale(_ title: String, value: Binding<Int>, id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).formaLabelStyle()
            HStack(spacing: Space.s2) {
                ForEach(1...5, id: \.self) { level in
                    Button { value.wrappedValue = level } label: {
                        Text("\(level)")
                            .font(.formaNumber)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                .fill(value.wrappedValue == level ? Theme.accent.opacity(0.35) : Theme.plate))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .buttonStyle(FormaPressStyle())
                    .accessibilityLabel("\(title) \(level) von 5")
                    .accessibilityAddTraits(value.wrappedValue == level ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: value.wrappedValue)
            .accessibilityIdentifier(id)
        }
    }

    private func save() {
        context.insert(MoodEntry(mood: mood, energy: energy, note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        try? context.save()
        dismiss()
    }
}

/// Koffein erfassen: Tasse oder Espresso, mit Uhrzeit.
struct PlusCaffeineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CaffeineEntry.date, order: .reverse) private var entries: [CaffeineEntry]
    @State private var kind = CaffeineKind.cup
    @State private var time = Date.now

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    HStack(spacing: Space.s2) {
                        ForEach(CaffeineKind.allCases) { option in
                            Button { kind = option } label: {
                                VStack(spacing: Space.s2) {
                                    Image(systemName: option.systemImage).font(.system(size: 24, weight: .medium))
                                    Text(option.title).font(.formaCaptionStrong)
                                }
                                .frame(maxWidth: .infinity, minHeight: 84)
                                .background(RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
                                    .fill(kind == option ? Theme.warning.opacity(0.3) : Theme.plate))
                                .foregroundStyle(Theme.textPrimary)
                            }
                            .buttonStyle(FormaPressStyle())
                            .accessibilityAddTraits(kind == option ? .isSelected : [])
                            .accessibilityIdentifier("plus.caffeine." + option.rawValue)
                        }
                    }
                    DatePicker("Uhrzeit", selection: $time, in: ...Date.now, displayedComponents: .hourAndMinute)
                        .font(.formaBodyLarge)
                    HStack {
                        Text("Heute").formaLabelStyle()
                        Spacer()
                        Text(Int(today).formatted() + " mg")
                            .font(.formaNumber)
                            .formaNumberRoll(today)
                    }
                    Button("Speichern", action: save)
                        .buttonStyle(PlusSaveStyle())
                        .accessibilityIdentifier("plus.caffeine.save")
                }
                .padding(Space.page)
            }
            .dashboardScreen()
            .navigationTitle("Koffein")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
    }

    private var today: Double {
        PlusLogic.caffeineToday(entries.map { ($0.date, $0.milligrams) })
    }

    private func save() {
        context.insert(CaffeineEntry(date: time, kind: kind))
        try? context.save()
        dismiss()
    }
}

/// Schlafplan als eigenes Blatt (die Karte auf Today führt per Link dorthin).
struct PlusSleepPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataHub.self) private var hub

    var body: some View {
        NavigationStack {
            SleepPlanView(store: FoodSettings.store(isSample: hub.isSample))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
    }
}

private struct PlusSaveStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.formaRowTitle)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: Radius.plate, style: .continuous).fill(Theme.selection))
            .foregroundStyle(Theme.onSelection)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
