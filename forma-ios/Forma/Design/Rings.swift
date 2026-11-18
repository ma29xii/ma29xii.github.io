import SwiftUI

enum RingKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case strain, recovery, sleep
    var id: String { rawValue }

    var title: String {
        switch self {
        case .strain: "Belastung"
        case .recovery: "Erholung"
        case .sleep: "Schlaf"
        }
    }
}

/// Dünner Ring mit Wert 0–100 (ohne Prozentzeichen).
/// Optional: gestrichelter Bogen außen für den empfohlenen Bereich.
struct RingView: View {
    var value: Double
    var color: Color
    var size: CGFloat
    var lineWidth: CGFloat
    var target: ClosedRange<Double>? = nil
    var dimmed: Bool = false
    var showsNumber: Bool = true
    var numberSize: CGFloat? = nil
    /// Keine Messgrundlage: leerer Ring mit Strich statt einer erfundenen Zahl.
    var missing: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: missing ? 0 : CGFloat(min(100, max(0, value)) / 100))
                .stroke(color.opacity(dimmed ? 0.4 : 1), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(dimmed || size < 40 ? 0 : 0.45), radius: lineWidth * 1.6)
            if let target {
                Circle()
                    .trim(from: CGFloat(target.lowerBound / 100), to: CGFloat(target.upperBound / 100))
                    .stroke(Color.white.opacity(dimmed ? 0.25 : 0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3.5]))
                    .rotationEffect(.degrees(-90))
                    .padding(-(lineWidth / 2 + 5))
            }
            if showsNumber && missing {
                Text("–")
                    .font(.system(size: numberSize ?? size * 0.3, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            } else if showsNumber {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: numberSize ?? size * 0.3, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .kerning(-0.5)
                    .contentTransition(.numericText(value: value))
                    .foregroundStyle(dimmed ? Theme.textTertiary : Theme.textPrimary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Drei Ringe mit gestaffelter Animation vom zuletzt gezeigten Wert.
/// Animiert nur beim Öffnen oder wenn neue Werte kommen.
struct RingTrio: View {
    let strain: Int?
    let recovery: Int?
    let sleep: Int?
    let target: ClosedRange<Int>
    var dimmedRecoverySleep: Bool = false
    var compact: Bool = false
    /// Für den Zoom-Übergang in die Detailseite (Apple-Stil: Herkunft bleibt sichtbar).
    var zoomNamespace: Namespace.ID? = nil
    var onTap: (RingKind) -> Void = { _ in }

    @AppStorage("forma.lastRings") private var lastRings = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: [RingKind: Double] = [:]

    private func current(_ kind: RingKind) -> Int? {
        switch kind {
        case .strain: strain
        case .recovery: recovery
        case .sleep: sleep
        }
    }

    private func color(_ kind: RingKind) -> Color {
        switch kind {
        case .strain: Theme.strain
        case .recovery: Theme.recovery(recovery ?? 0)
        case .sleep: Theme.sleep
        }
    }

    var body: some View {
        HStack(alignment: compact ? .center : .bottom, spacing: compact ? Space.s4 : 0) {
            ForEach(RingKind.allCases) { kind in
                let big = kind == .recovery && !compact
                let dim = dimmedRecoverySleep && kind != .strain
                Button { onTap(kind) } label: {
                    let layout = compact ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: Space.s2))
                    layout {
                        RingView(
                            value: shown[kind] ?? Double(current(kind) ?? 0),
                            color: color(kind),
                            size: compact ? 22 : (big ? 120 : 88),
                            lineWidth: compact ? 3 : (big ? 5.5 : 5),
                            target: kind == .strain && !compact ? Double(target.lowerBound)...Double(target.upperBound) : nil,
                            dimmed: dim,
                            showsNumber: !compact,
                            missing: current(kind) == nil
                        )
                        if compact {
                            Text(current(kind).map(String.init) ?? "–")
                                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(dim ? Theme.textTertiary : Theme.textPrimary)
                        } else {
                            Text(kind.title)
                                .font(.formaCaptionStrong)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: compact ? nil : .infinity)
                    .contentShape(Rectangle())
                    .modifier(ZoomSource(id: kind, namespace: compact ? nil : zoomNamespace))
                }
                .buttonStyle(RingPressStyle())
                .accessibilityLabel(current(kind).map { "\(kind.title) \($0) von 100" } ?? "\(kind.title): keine Daten für heute")
                .accessibilityHint("Öffnet die Details")
                .frame(maxWidth: compact ? nil : (big ? .infinity : .infinity))
                .layoutPriority(big ? 1.28 : 1)
            }
        }
        .onAppear { animateIfNeeded() }
        .onChange(of: [strain, recovery, sleep]) { _, _ in animateIfNeeded() }
    }

    private func animateIfNeeded() {
        guard !compact else { return }
        if reduceMotion {
            shown = [.strain: Double(strain ?? 0), .recovery: Double(recovery ?? 0), .sleep: Double(sleep ?? 0)]
            lastRings = "\(strain ?? 0),\(recovery ?? 0),\(sleep ?? 0)"
            return
        }
        let stored = lastRings.split(separator: ",").compactMap { Double($0) }
        let start: [RingKind: Double] = stored.count == 3
            ? [.strain: stored[0], .recovery: stored[1], .sleep: stored[2]]
            : [.strain: 0, .recovery: 0, .sleep: 0]
        let target: [RingKind: Double] = [.strain: Double(strain ?? 0), .recovery: Double(recovery ?? 0), .sleep: Double(sleep ?? 0)]
        let isNew = shown.isEmpty || RingKind.allCases.contains { shown[$0] != target[$0] }
        guard isNew else { return }
        if shown.isEmpty { shown = start }
        for (index, kind) in [RingKind.strain, .recovery, .sleep].enumerated() {
            withAnimation(.spring(duration: 1.1, bounce: 0.05).delay(0.12 + Double(index) * 0.08)) {
                shown[kind] = target[kind]
            }
        }
        lastRings = "\(strain ?? 0),\(recovery ?? 0),\(sleep ?? 0)"
    }
}

private struct RingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Markiert eine Quelle für `.navigationTransition(.zoom)`, nur wenn ein Namespace da ist.
struct ZoomSource<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Zoom-Ziel passend zu `ZoomSource`.
struct ZoomDestination<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        }
    }
}
