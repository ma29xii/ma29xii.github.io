import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Wahr, solange der Bildschirm im Anpassen-Modus ist (für Teile außerhalb des Stapels).
    @Entry var tilesEditing = false
}

/// Bearbeiten auf demselben Bildschirm. Training nutzt weiterhin seinen eigenen Einstieg.
struct InlineTileStack<Kind: TileKind, Content: View>: View {
    private let storageKey: String
    private let content: (Kind) -> Content
    private let sharedEditing: Binding<Bool>?
    @AppStorage private var raw: String
    @State private var ownEditing = false
    @State private var dropTarget: Kind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `editing`: optional von außen, wenn andere Teile des Bildschirms den Modus mitbekommen sollen.
    init(storageKey: String, editing: Binding<Bool>? = nil, @ViewBuilder content: @escaping (Kind) -> Content) {
        self.storageKey = storageKey
        self.content = content
        sharedEditing = editing
        _raw = AppStorage(wrappedValue: "", storageKey)
    }

    private var editing: Bool { sharedEditing?.wrappedValue ?? ownEditing }

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
            if editing {
                Button {
                    setEditing(false)
                } label: {
                    Text("Fertig")
                        .font(.formaCaptionStrong)
                        .frame(minHeight: 44)
                        .padding(.horizontal, Space.s3)
                }
                .buttonStyle(.glass)
                .padding(.top, Space.s2)
                .accessibilityIdentifier("tiles.done")
            } else {
                // Kein sichtbarer Knopf (F7-07): ganz unten weiterziehen füllt einen Kreis und öffnet „Anpassen“.
                PullToEditControl { setEditing(true) }
            }
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
                // Karten ↔ Balken gibt es nur hier, nicht in der normalen Ansicht.
                if kind.rawValue == "healthMonitor" { StoredTileLayoutToggle(key: HealthMonitor.layoutKey) }
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
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86)) {
            if let sharedEditing { sharedEditing.wrappedValue = value } else { ownEditing = value }
        }
    }
}

// MARK: - Hochziehen zum Anpassen

/// Unsichtbarer Einstieg „Anpassen“ am Ende eines Kachelstapels.
/// Wer ganz unten weiterzieht, sieht einen Kreis, der sich mit der Zugstrecke füllt. Ist er voll, gibt es einen
/// Tick, und beim Loslassen beginnt das Anpassen. Vorher loslassen oder zurückziehen bricht ab.
/// VoiceOver und Schalter-Bedienung behalten den Knopf „Anpassen“; er hat nur keine sichtbare Fläche.
private struct PullToEditControl: View {
    let onEdit: () -> Void
    @State private var progress = 0.0
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onEdit) {
            Color.clear.frame(maxWidth: .infinity).frame(height: 44)
        }
        .buttonStyle(.plain)
        // Sehende tippen hier nicht versehentlich; nur der UI-Rundgang braucht die Trefferfläche.
        .allowsHitTesting(FormaApp.isUITest)
        .accessibilityLabel("Anpassen")
        .accessibilityHint("Kacheln sortieren und ausblenden")
        .accessibilityIdentifier("tiles.edit")
        .overlay {
            PullCircle(progress: progress, armed: armed, reduceMotion: reduceMotion)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background {
            PullToEditProbe { progress, armed in
                self.progress = progress
                if self.armed != armed { self.armed = armed }
            } onCommit: {
                onEdit()
            }
        }
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: armed) { old, new in !old && new }
    }
}

private struct PullCircle: View {
    let progress: Double
    let armed: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().fill(Theme.textPrimary.opacity(0.06 + 0.10 * progress))
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.textPrimary.opacity(armed ? 0.9 : 0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(armed ? 1 : 0.5 + 0.3 * progress))
        }
        .frame(width: 40, height: 40)
        .scaleEffect(reduceMotion ? 1 : (0.7 + 0.3 * progress) * (armed ? 1.1 : 1))
        .opacity(min(1, progress * 4))
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.6), value: armed)
    }
}

/// Liest die Dehnung am unteren Rand des umgebenden `UIScrollView`, ohne dass der Aufrufer etwas ändern muss.
private struct PullToEditProbe: UIViewRepresentable {
    /// Zugstrecke bis zum vollen Kreis.
    static let threshold: CGFloat = 72

    let onChange: (_ progress: Double, _ armed: Bool) -> Void
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        view.onAttach = { scrollView in coordinator.attach(scrollView) }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onCommit = onCommit
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ProbeView: UIView {
        var onAttach: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var candidate = superview
            while let view = candidate, !(view is UIScrollView) { candidate = view.superview }
            if let scrollView = candidate as? UIScrollView { onAttach?(scrollView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: (Double, Bool) -> Void = { _, _ in }
        var onCommit: () -> Void = {}
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var previousBounce = false
        /// Der Finger liegt am Rand und zieht weiter; nur dann zeigt der Kreis etwas (kein Aufflackern beim Auslaufen).
        private var engaged = false
        private var armed = false

        func attach(_ scrollView: UIScrollView) {
            guard self.scrollView !== scrollView else { return }
            detach()
            self.scrollView = scrollView
            // Auch bei kurzem Inhalt soll sich der Rand dehnen lassen.
            previousBounce = scrollView.alwaysBounceVertical
            scrollView.alwaysBounceVertical = true
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
            observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                MainActor.assumeIsolated { self?.update(scrollView) }
            }
        }

        func detach() {
            observation?.invalidate()
            observation = nil
            if let scrollView {
                scrollView.panGestureRecognizer.removeTarget(self, action: #selector(pan(_:)))
                scrollView.alwaysBounceVertical = previousBounce
            }
            scrollView = nil
            engaged = false
            armed = false
        }

        private func update(_ scrollView: UIScrollView) {
            let inset = scrollView.adjustedContentInset
            let restY = max(scrollView.contentSize.height + inset.bottom - scrollView.bounds.height, -inset.top)
            let over = max(0, scrollView.contentOffset.y - restY)
            if over == 0 { engaged = false; armed = false }
            if scrollView.isTracking && over > 0 { engaged = true }
            guard engaged else { onChange(0, false); return }
            let progress = min(1, Double(over / PullToEditProbe.threshold))
            if scrollView.isTracking {
                // Etwas Spielraum nach unten, damit der Tick nicht flackert.
                armed = armed ? progress > 0.9 : progress >= 1
            }
            onChange(progress, armed)
        }

        @objc private func pan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let commit = armed
            armed = false
            engaged = false
            onChange(0, false)
            if commit { onCommit() }
        }
    }
}
