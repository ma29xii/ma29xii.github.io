import SwiftData
import SwiftUI

/// Frühere Chats: antippen öffnet, wischen löscht. Unten der Zugang zu dem, was der Coach über dich weiß.
struct CoachHistorySheet: View {
    @Query(sort: \CoachChat.updatedAt, order: .reverse) private var chats: [CoachChat]
    @Environment(\.dismiss) private var dismiss
    let onOpen: (CoachChat) -> Void
    let onDelete: (CoachChat) -> Void
    let onNew: () -> Void
    let onShowFacts: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if chats.isEmpty {
                        Text("Noch keine Chats")
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Theme.card)
                    }
                    ForEach(chats) { chat in
                        Button { onOpen(chat); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chat.title)
                                    .font(.formaBody)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                Text(chat.updatedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: .german)))
                                    .font(.formaMicro)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.card)
                        .swipeActions(edge: .trailing) {
                            Button("Löschen", systemImage: "trash", role: .destructive) { onDelete(chat) }
                        }
                        .accessibilityHint("Öffnet den Chat. Nach links wischen löscht ihn.")
                    }
                }
                Section {
                    Button { dismiss(); onShowFacts() } label: {
                        Label("Was der Coach über dich weiß", systemImage: "brain.head.profile")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                    .accessibilityIdentifier("coach.facts")
                }
            }
            .formaScreen()
            .navigationTitle("Verlauf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Neuer Chat", systemImage: "square.and.pencil") { onNew(); dismiss() }
                        .accessibilityIdentifier("coach.history.new")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// „Was der Coach über dich weiß“: gemerkte Fakten ansehen und einzeln löschen.
struct CoachFactsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var facts: [CoachFact] = CoachMemory.facts(in: .standard)

    var body: some View {
        NavigationStack {
            List {
                if facts.isEmpty {
                    Text("Noch nichts gemerkt. Schreib „Merk dir: …“ oder erzähl dem Coach etwas über dich.")
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.card)
                }
                ForEach(facts) { fact in
                    Text(fact.text)
                        .font(.formaBody)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .listRowBackground(Theme.card)
                        .swipeActions(edge: .trailing) {
                            Button("Löschen", systemImage: "trash", role: .destructive) { remove(fact) }
                        }
                        .accessibilityHint("Nach links wischen löscht den Eintrag.")
                }
            }
            .formaScreen()
            .navigationTitle("Was der Coach über dich weiß")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func remove(_ fact: CoachFact) {
        CoachMemory.forget(fact.id, in: .standard)
        facts = CoachMemory.facts(in: .standard)
    }
}
