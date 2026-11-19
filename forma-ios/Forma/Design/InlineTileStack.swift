import SwiftUI

/// Bearbeiten auf demselben Bildschirm. Training nutzt weiterhin seinen eigenen Einstieg.
struct InlineTileStack<Kind: TileKind, Content: View>: View {
    private let storageKey: String
    private let content: (Kind) -> Content
    @AppStorage private var raw: String
    @State private var editing = false
    @State private var dropTarget: Kind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(storageKey: String, @ViewBuilder content: @escaping (Kind) -> Content) {
        self.storageKey = storageKey
        self.content = content
        _raw = AppStorage(wrappedValue: "", storageKey)
    }

    private var arrangement: TileArrangement<Kind> { TileArrangement(storage: raw) }

    var body: some View {
        let shown = arrangement.visible
        VStack(spacing: Space.s3) {
            if shown.isEmpty && !editing {
                Text("Alle Kacheln sind ausgeblendet.").foregroundStyle(Theme.textSecondary)
            }
            ForEach(shown) { kind in
                if editing {
                    editCard(kind, shown: shown)
                } else {
                    content(kind)
                }
            }
            if editing {
                ForEach(arrangement.hiddenInOrder) { kind in
                    Button {
                        update { $0.show(kind) }
                    } label: {
                        MetricRow(title: kind.title) {
                            Image(systemName: "plus.circle").font(.title3)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(kind.title) einblenden")
                }
            }
            Button {
                setEditing(!editing)
            } label: {
                Text(editing ? "Fertig" : "Anpassen")
                    .font(.formaCaptionStrong)
                    .frame(minHeight: 44)
                    .padding(.horizontal, Space.s3)
            }
            .buttonStyle(.glass)
            .padding(.top, Space.s2)
            .accessibilityIdentifier("tiles.edit")
        }
    }

    private func editCard(_ kind: Kind, shown: [Kind]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !Kind.requiredVisible.contains(kind) {
                    Button {
                        update { $0.hide(kind) }
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(kind.title) ausblenden")
                }
                Text(kind.title).font(.formaCaptionStrong)
                    .padding(.leading, Space.s2)
                Spacer(minLength: Space.s2)
                Image(systemName: "line.3.horizontal")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .draggable(storageKey + "/" + kind.rawValue) {
                        Label(kind.title, systemImage: kind.systemImage)
                            .padding(Space.s3)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.textSecondary)
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Nach oben") {
                if shown.first != kind { update { $0.shift(kind, by: -1) } }
            }
            .accessibilityAction(named: "Nach unten") {
                if shown.last != kind { update { $0.shift(kind, by: 1) } }
            }
            content(kind)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay {
            if dropTarget == kind {
                RoundedRectangle(cornerRadius: Radius.plate)
                    .strokeBorder(Theme.textSecondary, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            let prefix = storageKey + "/"
            guard items.count == 1, let id = items.first, id.hasPrefix(prefix),
                  let moved = Kind(rawValue: String(id.dropFirst(prefix.count))),
                  shown.contains(moved), moved != kind else { return false }
            dropTarget = nil
            update { $0.move(moved, toPositionOf: kind) }
            return true
        } isTargeted: { targeted in
            if targeted { dropTarget = kind } else if dropTarget == kind { dropTarget = nil }
        }
    }

    private func update(_ change: (inout TileArrangement<Kind>) -> Void) {
        var next = arrangement
        change(&next)
        guard next != arrangement else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { raw = next.storage }
    }

    private func setEditing(_ value: Bool) {
        dropTarget = nil
        editing = value
    }
}
