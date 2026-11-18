import SwiftUI

/// Eine Kachel, die man auf einem Bildschirm ein- und ausblenden und verschieben kann.
protocol TileKind: RawRepresentable, CaseIterable, Identifiable, Hashable, Sendable where RawValue == String {
    var title: String { get }
    var systemImage: String { get }
    var summary: String { get }
    /// Kacheln, die neu hinzukommen, aber zunächst ausgeblendet sein sollen.
    static var defaultHidden: Set<Self> { get }
}

extension TileKind {
    static var defaultHidden: Set<Self> { [] }
}

/// Reihenfolge und Sichtbarkeit, gespeichert als einfacher Text: „a,b,c|x,y“ (sichtbar/ausgeblendet getrennt).
struct TileArrangement<Kind: TileKind>: Equatable {
    var order: [Kind]
    var hidden: Set<Kind>

    var visible: [Kind] { order.filter { !hidden.contains($0) } }
    var hiddenInOrder: [Kind] { order.filter { hidden.contains($0) } }

    static var standard: TileArrangement {
        TileArrangement(order: Array(Kind.allCases), hidden: Kind.defaultHidden)
    }

    init(order: [Kind], hidden: Set<Kind>) {
        self.order = order
        self.hidden = hidden
    }

    init(storage: String) {
        guard !storage.isEmpty else { self = .standard; return }
        let parts = storage.split(separator: "|", omittingEmptySubsequences: false)
        let orderIDs = parts.first.map { $0.split(separator: ",").map(String.init) } ?? []
        let hiddenIDs = parts.count > 1 ? parts[1].split(separator: ",").map(String.init) : []
        // Doppelte oder unbekannte Einträge (z. B. kaputte Speicherung) verwerfen.
        var order: [Kind] = []
        for kind in orderIDs.compactMap(Kind.init(rawValue:)) where !order.contains(kind) { order.append(kind) }
        var hidden = Set(hiddenIDs.compactMap(Kind.init(rawValue:)))
        // Neue Kacheln aus späteren Versionen hinten anhängen.
        for kind in Kind.allCases where !order.contains(kind) {
            order.append(kind)
            if Kind.defaultHidden.contains(kind) { hidden.insert(kind) }
        }
        self.order = order
        self.hidden = hidden
    }

    var storage: String {
        order.map(\.rawValue).joined(separator: ",") + "|" + hidden.map(\.rawValue).sorted().joined(separator: ",")
    }

    mutating func move(_ kind: Kind, before target: Kind) {
        guard kind != target, let from = order.firstIndex(of: kind) else { return }
        order.remove(at: from)
        let to = order.firstIndex(of: target) ?? order.endIndex
        order.insert(kind, at: to)
    }

    /// Um eine Position unter den sichtbaren Kacheln verschieben.
    mutating func shift(_ kind: Kind, by offset: Int) {
        let shown = visible
        guard let i = shown.firstIndex(of: kind) else { return }
        let j = i + offset
        guard shown.indices.contains(j) else { return }
        let neighbour = shown[j]
        guard let a = order.firstIndex(of: kind), let b = order.firstIndex(of: neighbour) else { return }
        order.swapAt(a, b)
    }

    mutating func moveVisible(fromOffsets: IndexSet, toOffset: Int) {
        var shown = visible
        shown.move(fromOffsets: fromOffsets, toOffset: toOffset)
        order = shown + hiddenInOrder
    }

    mutating func hide(_ kind: Kind) { hidden.insert(kind) }

    mutating func show(_ kind: Kind) {
        hidden.remove(kind)
        // Wieder eingeblendete Kacheln landen unten.
        if let i = order.firstIndex(of: kind) { order.remove(at: i) }
        let lastVisible = order.lastIndex { !hidden.contains($0) }.map { $0 + 1 } ?? 0
        order.insert(kind, at: lastVisible)
    }
}

/// Kachelstapel für einen Bildschirm.
/// Verschieben geht auf drei Wegen: lange drücken und ziehen, Kontextmenü (Nach oben/unten)
/// oder unten „Anpassen“ mit Liste zum Sortieren und Ein-/Ausblenden.
struct TileStack<Kind: TileKind, Content: View>: View {
    let screenTitle: String
    let content: (Kind) -> Content
    @AppStorage private var raw: String
    @Binding private var editing: Bool
    @State private var dropTarget: Kind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `isEditing` erlaubt einen zusätzlichen Einstieg oben in der Navigationsleiste (Codex R-01-13).
    init(storageKey: String, screenTitle: String, isEditing: Binding<Bool>, @ViewBuilder content: @escaping (Kind) -> Content) {
        self.screenTitle = screenTitle
        self.content = content
        _raw = AppStorage(wrappedValue: "", storageKey)
        _editing = isEditing
    }

    private var arrangement: TileArrangement<Kind> { TileArrangement(storage: raw) }

    private func update(_ change: (inout TileArrangement<Kind>) -> Void) {
        var a = arrangement
        change(&a)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { raw = a.storage }
    }

    var body: some View {
        let shown = arrangement.visible
        VStack(spacing: Space.s3) {
            if shown.isEmpty {
                VStack(spacing: Space.s3) {
                    Text("Alle Kacheln sind ausgeblendet.").font(.formaBody).foregroundStyle(Theme.textSecondary)
                    Button("Standard wiederherstellen") { update { $0 = .standard } }.buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s5)
            }
            ForEach(shown) { kind in
                content(kind)
                    .overlay {
                        if dropTarget == kind {
                            RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.6), lineWidth: 1.5)
                        }
                    }
                    .contextMenu {
                        if shown.first != kind {
                            Button("Nach oben", systemImage: "arrow.up") { update { $0.shift(kind, by: -1) } }
                        }
                        if shown.last != kind {
                            Button("Nach unten", systemImage: "arrow.down") { update { $0.shift(kind, by: 1) } }
                        }
                        Button("Ausblenden", systemImage: "eye.slash") { update { $0.hide(kind) } }
                        Divider()
                        Button("\(screenTitle) anpassen …", systemImage: "square.grid.2x2") { editing = true }
                    }
                    .draggable(kind.rawValue) {
                        Label(kind.title, systemImage: kind.systemImage)
                            .font(.formaCaptionStrong)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let id = items.first, let moved = Kind(rawValue: id) else { return false }
                        update { $0.move(moved, before: kind) }
                        return true
                    } isTargeted: { targeted in
                        if targeted { dropTarget = kind } else if dropTarget == kind { dropTarget = nil }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                    // Nur am unteren Rand leicht einblenden, oben nichts bewegen (ruhig).
                    .scrollTransition(.animated(.smooth), axis: .vertical) { content, phase in
                        content
                            .opacity(reduceMotion || phase != .bottomTrailing ? 1 : 0.55)
                            .scaleEffect(reduceMotion || phase != .bottomTrailing ? 1 : 0.97)
                    }
                    // VoiceOver: Verschieben ohne Ziehen.
                    .accessibilityAction(named: "Nach oben") { update { $0.shift(kind, by: -1) } }
                    .accessibilityAction(named: "Nach unten") { update { $0.shift(kind, by: 1) } }
                    .accessibilityAction(named: "Ausblenden") { update { $0.hide(kind) } }
            }
            Button { editing = true } label: {
                Label("\(screenTitle) anpassen", systemImage: "square.grid.2x2")
                    .font(.formaCaptionStrong)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.glass)
            .padding(.top, Space.s3)
            .accessibilityHint("Kacheln sortieren, ein- und ausblenden")
        }
        .sensoryFeedback(.selection, trigger: raw)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: dropTarget)
        .animation(.snappy, value: dropTarget)
        .sheet(isPresented: $editing) {
            TileEditor<Kind>(raw: $raw, screenTitle: screenTitle)
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
        }
    }
}

/// Liste zum Sortieren und Ein-/Ausblenden.
struct TileEditor<Kind: TileKind>: View {
    @Binding var raw: String
    let screenTitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        let a = TileArrangement<Kind>(storage: raw)
        NavigationStack {
            List {
                Section {
                    ForEach(a.visible) { kind in
                        row(kind, shown: true)
                    }
                    .onMove { from, to in
                        var b = TileArrangement<Kind>(storage: raw)
                        b.moveVisible(fromOffsets: from, toOffset: to)
                        raw = b.storage
                    }
                } header: {
                    Text("Angezeigt")
                } footer: {
                    Text("Ziehen zum Sortieren. Tipp: Auf dem Bildschirm selbst kannst du Kacheln auch lange drücken und verschieben.")
                }
                if !a.hiddenInOrder.isEmpty {
                    Section("Ausgeblendet") {
                        ForEach(a.hiddenInOrder) { kind in
                            row(kind, shown: false)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .navigationTitle("\(screenTitle) anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Standard") { confirmReset = true }
                        .confirmationDialog("Reihenfolge auf Standard zurücksetzen?", isPresented: $confirmReset, titleVisibility: .visible) {
                            Button("Zurücksetzen", role: .destructive) { withAnimation { raw = TileArrangement<Kind>.standard.storage } }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func row(_ kind: Kind, shown: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.formaRowTitle)
                Text(kind.summary).font(.formaCaption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                var b = TileArrangement<Kind>(storage: raw)
                if shown { b.hide(kind) } else { b.show(kind) }
                withAnimation { raw = b.storage }
            } label: {
                Image(systemName: shown ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.onSelection, shown ? Theme.textTertiary : Theme.younger)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shown ? "\(kind.title) ausblenden" : "\(kind.title) einblenden")
        }
        .padding(.vertical, 2)
    }
}
