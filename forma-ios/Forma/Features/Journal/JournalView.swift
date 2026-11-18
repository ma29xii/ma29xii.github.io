import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var answers: [JournalAnswer]
    @State private var day: Date = Date.now.startOfDay.adding(days: -1)
    @State private var notice: String?

    static let questions = [
        "Koffein nach 14 Uhr", "Alkohol", "Spät gegessen", "Bildschirm im Bett", "Meditation",
        "Dehnen / Mobility", "Spaziergang", "Tageslicht am Morgen", "Stress bei der Arbeit", "Krank", "Muskelkater"
    ]

    /// Anzeigetexte (eindeutiger, Codex R-02-22). Gespeichert wird weiter unter dem alten Schlüssel,
    /// damit bisherige Antworten erhalten bleiben.
    static func label(_ q: String) -> String {
        switch q {
        case "Spät gegessen": "Spät gegessen (nach 21 Uhr)"
        case "Dehnen / Mobility": "Gedehnt oder Beweglichkeit geübt"
        case "Bildschirm im Bett": "Handy oder Bildschirm im Bett"
        default: q
        }
    }

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
        do { try context.save() } catch { notice = "Konnte nicht gespeichert werden. Bitte nochmal versuchen." }
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
                        Text("\(answered) von \(Self.questions.count) beantwortet").font(.formaCaptionStrong).monospacedDigit().foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, Space.s5)

                    Plate {
                        ForEach(Array(Self.questions.enumerated()), id: \.offset) { index, q in
                            if index > 0 { RowDivider() }
                            HStack {
                                Text(Self.label(q)).font(.formaRowTitle)
                                Spacer()
                                YesNoSwitch(value: Binding(get: { answer(q) }, set: { set(q, $0) }), question: Self.label(q))
                            }
                            .padding(.horizontal, Space.s4)
                            .frame(minHeight: 56)
                        }
                    }
                    .padding(.top, Space.s3)

                    Button("Offene wie am Vortag ausfüllen") { copyPrevious() }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s5)
                        .disabled(previousCount == 0)
                    if let notice {
                        Text(notice).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity).padding(.top, Space.s2)
                    } else if previousCount == 0 {
                        Text("Für den Vortag gibt es noch keine Antworten.").font(.formaCaption).foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity).padding(.top, Space.s2)
                    }

                    Text("Halte fest, was gestern zutraf. Die Antworten bleiben auf deinem iPhone.")
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

    private var previousCount: Int {
        let previous = day.adding(days: -1)
        return answers.filter { Calendar.forma.isDate($0.day, inSameDayAs: previous) }.count
    }

    /// Übernimmt nur offene Fragen und sagt, wie viele es waren (Codex R-02-22/A-31).
    private func copyPrevious() {
        let previous = day.adding(days: -1)
        var copied = 0
        for q in Self.questions where answer(q) == nil {
            if let old = answers.first(where: { $0.question == q && Calendar.forma.isDate($0.day, inSameDayAs: previous) }) {
                set(q, old.answer)
                copied += 1
            }
        }
        notice = copied == 0 ? "Nichts zu übernehmen – alles schon beantwortet oder am Vortag leer." : "\(copied) Antworten vom Vortag übernommen."
    }
}
