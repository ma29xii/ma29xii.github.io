import SwiftUI

/// „Nährwerte tracken“: Scannen, Fotografieren oder Suchen in einem kleinen Blatt.
/// Das gewählte Verfahren öffnet sich darüber; danach schließt auch dieses Blatt.
struct FoodTrackSheet: View {
    private enum Method: String, Identifiable, CaseIterable {
        case scan, photo, search
        var id: String { rawValue }

        var title: String {
            switch self {
            case .scan: "Scannen"
            case .photo: "Foto"
            case .search: "Suchen"
            }
        }

        var systemImage: String {
            switch self {
            case .scan: "barcode.viewfinder"
            case .photo: "camera.viewfinder"
            case .search: "magnifyingglass"
            }
        }

        var tint: Color {
            switch self {
            case .scan: Theme.younger
            case .photo: Theme.warning
            case .search: Theme.strain
            }
        }
    }

    /// Mahlzeit, zu der hinzugefügt wird; `nil` wählt nach Uhrzeit.
    var meal: FoodMeal?
    @Environment(\.dismiss) private var dismiss
    @State private var method: Method?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Nährwerte tracken").formaLabelStyle()
            HStack(spacing: Space.s2) {
                ForEach(Method.allCases) { item in
                    Button { method = item } label: {
                        VStack(spacing: Space.s2) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(item.tint)
                                .frame(height: 30)
                                .accessibilityHidden(true)
                            Text(item.title).font(.formaCaptionStrong)
                        }
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.plate))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Theme.plateEdge, lineWidth: 0.75))
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("track." + item.rawValue)
                }
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.s5)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.textPrimary)
        .background(ScreenBackground())
        .presentationDetents([.height(210)])
        .presentationDragIndicator(.visible)
        .sheet(item: $method, onDismiss: { dismiss() }) { item in
            switch item {
            case .scan: FoodScanSheet(meal: meal)
            case .photo: FoodPhotoSheet(meal: meal)
            case .search: FoodScanSheet(startInSearch: true, meal: meal)
            }
        }
    }
}
