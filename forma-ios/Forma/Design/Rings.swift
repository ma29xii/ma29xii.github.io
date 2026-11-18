import SwiftUI

enum RingKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case strain, recovery, sleep
    var id: String { rawValue }

    var title: String {
        switch self {
        case .strain: "Strain"
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        }
    }

    func zoomID(compact: Bool) -> String { (compact ? "compact." : "large.") + rawValue }
}

/// Der animierbare Wert treibt sowohl den Bogen als auch die Ziffern pro Frame.
struct RingView: View, Animatable {
    nonisolated var value: Double
    var color: Color
    var size: CGFloat
    var lineWidth: CGFloat
    var target: ClosedRange<Double>? = nil
    var dimmed = false
    var showsNumber = true
    var numberSize: CGFloat? = nil
    var missing = false

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let bounded = value.isFinite ? min(100, max(0, value)) : 0
        ZStack {
            Circle()
                .strokeBorder(Theme.track, lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: missing ? 0 : bounded / 100)
                .stroke(color.opacity(dimmed ? 0.4 : 1), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(dimmed || size < 40 ? 0 : 0.32), radius: lineWidth)
            if let target {
                Circle()
                    .inset(by: 1)
                    .trim(from: target.lowerBound / 100, to: target.upperBound / 100)
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3.5]))
                    .rotationEffect(.degrees(-90))
                    .padding(-6)
            }
            if showsNumber {
                Text(missing ? "–" : "\(Int(bounded.rounded()))")
                    .font(.system(size: numberSize ?? size * 0.3, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dimmed || missing ? Theme.textSecondary : Theme.textPrimary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct RingTrio: View {
    let strain: Int?
    let recovery: Int?
    let sleep: Int?
    let target: ClosedRange<Int>?
    var dimmedRecoverySleep = false
    var compact = false
    let zoomNamespace: Namespace.ID
    var onTap: (RingKind) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: [RingKind: Double] = [:]
    @State private var width: CGFloat = 360

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
        case .recovery: recovery.map(Theme.recovery) ?? Theme.textSecondary
        case .sleep: Theme.sleep
        }
    }

    var body: some View {
        HStack(alignment: compact ? .center : .bottom, spacing: compact ? 0 : Space.s2) {
            ForEach(RingKind.allCases) { kind in
                let big = kind == .recovery
                let size: CGFloat = compact ? 22 : min(big ? 120 : 88, max(44, (width - 64) / 3 + (big ? 16 : -8)))
                let dim = dimmedRecoverySleep && kind != .strain
                Button { onTap(kind) } label: {
                    let layout = compact ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(spacing: 0))
                    layout {
                        RingView(
                            value: compact || reduceMotion ? Double(current(kind) ?? 0) : (shown[kind] ?? 0),
                            color: color(kind), size: size, lineWidth: compact ? 3 : (big ? 5.5 : 5),
                            target: kind == .strain && !compact ? target.map { Double($0.lowerBound)...Double($0.upperBound) } : nil,
                            dimmed: dim, showsNumber: !compact, missing: current(kind) == nil
                        )
                        .padding(compact ? 2 : 8)
                        .clipShape(Circle())
                        .matchedTransitionSource(id: kind.zoomID(compact: compact), in: zoomNamespace) {
                            $0.clipShape(RoundedRectangle(cornerRadius: size / 2 + (compact ? 2 : 8))).background(.clear)
                        }

                        if compact {
                            Text(current(kind).map(String.init) ?? "–")
                                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(dim ? Theme.textTertiary : Theme.textPrimary)
                        } else {
                            Text(kind.title).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                    .frame(minWidth: 44, maxWidth: compact ? nil : .infinity, minHeight: 44)
                    .padding(.horizontal, compact ? 4 : 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(current(kind).map { "\(kind.title) \($0) von 100" } ?? "\(kind.title), keine Daten")
                .accessibilityIdentifier((compact ? "compactRing." : "ring.") + kind.rawValue)
                .accessibilityHint("Öffnet die Details")
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: [strain, recovery, sleep], initial: true) { _, _ in
            guard !compact else { return }
            let values = Dictionary(uniqueKeysWithValues: RingKind.allCases.map { ($0, Double(current($0) ?? 0)) })
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { shown = values }
        }
    }
}

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
