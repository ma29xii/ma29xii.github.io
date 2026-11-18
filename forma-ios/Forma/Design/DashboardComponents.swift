import SwiftUI

extension View {
    func dashboardScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .foregroundStyle(Theme.textPrimary)
            .background {
                LinearGradient(stops: [
                    .init(color: Color(hex: 0x222325), location: 0),
                    .init(color: Color(hex: 0x161719), location: 0.32),
                    .init(color: Color(hex: 0x0D0E0F), location: 0.72)
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            }
    }
}

struct DashboardCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x202123), in: shape)
            .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 0.75).allowsHitTesting(false) }
            .clipShape(shape)
    }
}

struct DashboardHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.formaCaptionStrong)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct DashboardEmpty: View {
    var title = "Keine Messung"

    var body: some View {
        Text(title)
            .font(.formaBody)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
    }
}

struct DateStepper: View {
    let title: String
    let canPrevious: Bool
    let canNext: Bool
    var unit = "Tag"
    var identifier = "dashboard"
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrow("left", title: "Vorheriger " + unit, enabled: canPrevious, action: previous)
            Text(title)
                .font(.formaCaptionStrong)
                .tracking(0.65)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s1)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier(identifier + ".date")
            arrow("right", title: "Nächster " + unit, enabled: canNext, action: next)
        }
        .glassEffect(.regular, in: .capsule)
    }

    private func arrow(_ direction: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron." + direction)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textQuaternary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier + "." + direction)
    }
}

struct ComparisonRow: View {
    let title: String
    let icon: String
    let value: Double?
    let baseline: Double?
    let format: (Double) -> String

    private var delta: Int {
        guard let value, let baseline, format(value) != format(baseline) else { return 0 }
        return value > baseline ? 1 : -1
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: icon)
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 18)
                .accessibilityHidden(true)
            Text(title)
                .font(.formaCaptionStrong)
                .textCase(.uppercase)
                .layoutPriority(1)
            Spacer(minLength: Space.s1)
            Text(value.map(format) ?? "Keine Messung")
                .font(.formaValue)
                .foregroundStyle(value == nil ? Theme.textSecondary : Theme.textPrimary)
                .multilineTextAlignment(.trailing)
            if delta != 0 {
                Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel(delta > 0 ? "Über dem Vergleichswert" : "Unter dem Vergleichswert")
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ComparisonFooter: View {
    var body: some View {
        Text("▲▼ Gewählter Tag vs. vorherige 30 Tage")
            .font(.formaCaption)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Pfeile vergleichen den gewählten Tag mit den vorherigen 30 Tagen")
    }
}

struct DashboardRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed = 0.0

    let kind: RingKind
    let value: Int?
    let size: CGFloat
    var expanded = false

    static func tint(kind: RingKind, value: Int?) -> Color {
        switch kind {
        case .sleep: Theme.sleep
        case .recovery: value.map(Theme.recovery) ?? Theme.textSecondary
        case .strain: Color(hex: 0x66BEF0)
        }
    }

    private var name: String { expanded && kind == .sleep ? "Schlafleistung" : kind.title }
    private var suffix: String { kind == .strain ? "" : "%" }

    var body: some View {
        RingView(value: displayed, color: Self.tint(kind: kind, value: value), size: size,
                 lineWidth: expanded ? 8 : 5, numberSize: expanded ? size * 0.28 : nil,
                 missing: value == nil, suffix: suffix, subtitle: expanded ? name : nil)
        .onChange(of: value, initial: true) { _, latest in
            withAnimation(reduceMotion || latest == nil ? nil : .easeOut(duration: 0.65)) {
                displayed = Double(latest ?? 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(value.map { kind == .strain ? "\($0) von 100" : "\($0) Prozent" } ?? "Keine Messung")
    }
}
