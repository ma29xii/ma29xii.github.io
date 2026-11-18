import SwiftUI

/// Einzige Naht zum Tracker in `Features/Food/` (codex-food): Essen, Wasser, Fasten, Gewicht.
/// Was noch fehlt (`FoodLogView`, Foto, Wasser, Fasten, Gewicht), zeigt einen Platzhalter.
/// Umstellen: nur die Funktionen unten ändern.
enum PlusFood {
    // Barcode und Suche sind zwei Reiter im selben Sheet (Standard: Barcode).
    @ViewBuilder static func scan() -> some View { FoodScanSheet() }
    @ViewBuilder static func photo() -> some View { PlusFoodPlaceholder(title: "Essen fotografieren", systemImage: "camera.viewfinder") }
    @ViewBuilder static func water() -> some View { PlusFoodPlaceholder(title: "Wasser", systemImage: "drop") }
    @ViewBuilder static func fasting() -> some View { PlusFoodPlaceholder(title: "Fasten", systemImage: "timer") }
    @ViewBuilder static func weight() -> some View { PlusFoodPlaceholder(title: "Gewicht", systemImage: "scalemass") }
    @ViewBuilder static func search() -> some View { FoodScanSheet() }
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
