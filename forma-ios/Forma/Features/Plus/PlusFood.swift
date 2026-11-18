import SwiftUI

/// Einzige Naht zum Kalorien-Tracker (`Features/Food/`, codex-food).
/// Solange `FoodScanSheet` und `FoodLogView` fehlen, zeigen Platzhalter das Ziel.
/// Umstellen: nur die drei Funktionen unten ändern.
enum PlusFood {
    @ViewBuilder static func scan() -> some View { PlusFoodPlaceholder(title: "Mahlzeit scannen", systemImage: "barcode.viewfinder") }
    @ViewBuilder static func search() -> some View { PlusFoodPlaceholder(title: "Essen suchen", systemImage: "magnifyingglass") }
    @ViewBuilder static func log() -> some View { PlusFoodPlaceholder(title: "Ernährung heute", systemImage: "fork.knife") }
}

private struct PlusFoodPlaceholder: View {
    let title: String
    let systemImage: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.s3) {
                Glyph(systemName: systemImage)
                Text("Kommt gleich").font(.formaHeadline)
                Text("Der Kalorien-Tracker wird gerade fertiggestellt.")
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Space.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .formaScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}
