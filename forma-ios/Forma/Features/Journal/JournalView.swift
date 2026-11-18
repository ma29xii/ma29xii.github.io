import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var answers: [JournalAnswer]
    @State private var day: Date = Date.now.startOfDay.adding(days: -1)

    static let questions = [
        "Koffein nach 14 Uhr", "Alkohol", "Spät gegessen", "Bildschirm im Bett", "Meditation",
        "Dehnen / Mobility", "Spaziergang", "Tageslicht am Morgen", "Stress bei der Arbeit", "Krank", "Muskelkater"
    ]

    private func answer(_ q: String) -> Bool? {
        answers.first { $0.question == q && Calendar.forma.isDate($0.day, inSameDayAs: day) }?.answer
    }

    private func set(_ q: String, _ value: Bool?) {
        let existing = answers.first { $0.question == q && Calendar.forma.isDate($0.day, inSameDayAs: day) }
        if let value {
            if let existing { existing.answer = value } else { context.insert(JournalAnswer(day: day, question: q, answer: value)) }
        } else if let existing {
            context.delete(existing)
        }
        try? context.save()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("Tag", selection: $day) {
                        Text("Gestern").tag(Date.now.startOfDay.adding(days: -1))
                        Text("Heute").tag(Date.now.startOfDay)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, Space.s3)

                    let answered = Self.questions.filter { answer($0) != nil }.count
                    HStack {
                        Text(Format.dayTitle(day)).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("\(answered) von \(Self.questions.count)").font(.formaCaptionStrong).monospacedDigit().foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, Space.s5)

                    Plate {
                        ForEach(Array(Self.questions.enumerated()), id: \.offset) { index, q in
                            if index > 0 { RowDivider() }
                            HStack {
                                Text(q).font(.formaRowTitle)
                                Spacer()
                                YesNoSwitch(value: Binding(get: { answer(q) }, set: { set(q, $0) }))
                            }
                            .padding(.horizontal, Space.s4)
                            .frame(minHeight: 56)
                        }
                    }
                    .padding(.top, Space.s3)

                    Button("Wie am Vortag ausfüllen") { copyPrevious() }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s5)

                    Text("Nach etwa zwei Wochen zeigt dir der Coach, wie diese Gewohnheiten deine Erholung beeinflussen.")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, Space.s4)
                    Color.clear.frame(height: Space.s6)
                }
                .padding(.horizontal, Space.page)
            }
            .formaScreen()
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }

    private func copyPrevious() {
        let previous = day.adding(days: -1)
        for q in Self.questions where answer(q) == nil {
            if let old = answers.first(where: { $0.question == q && Calendar.forma.isDate($0.day, inSameDayAs: previous) }) {
                set(q, old.answer)
            }
        }
    }
}
