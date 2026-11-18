import SwiftUI

extension View {
    func dashboardScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .foregroundStyle(Theme.textPrimary)
            .background { Theme.screenGradient.ignoresSafeArea() }
    }
}

/// Ruhige Inhaltskarte (Radius 20) für Today und die Ring-Details.
struct DashboardCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 0.75).allowsHitTesting(false) }
            .clipShape(shape)
    }
}

struct DashboardHeading: View {
    let title: String

    var body: some View {
        Text(title).formaLabelStyle()
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

/// Datums- bzw. Zeitraum-Navigation „‹ HEUTE ›“ in einer Glas-Kapsel (Bedienung, kein Inhalt).
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
                .tracking(Tracking.micro)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .padding(.horizontal, Space.s1)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier(identifier + ".date")
            arrow("right", title: "Nächster " + unit, enabled: canNext, action: next)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: title)
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

/// Zeile „Symbol · TITEL · Wert ▲▼“: heute gegen die vorherigen 30 Tage.
struct ComparisonRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let icon: String
    let value: Double?
    let baseline: Double?
    let format: (Double) -> String
    var showsChevron = false

    /// +1 über, −1 unter dem Vergleich, 0 wenn gleich (nach Rundung) oder ohne Vergleich.
    static func direction(value: Double?, baseline: Double?, format: (Double) -> String) -> Int {
        guard let value, let baseline, value.isFinite, baseline.isFinite, format(value) != format(baseline) else { return 0 }
        return value > baseline ? 1 : -1
    }

    var body: some View {
        let delta = Self.direction(value: value, baseline: baseline, format: format)
        HStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(.formaLabel)
                .tracking(Tracking.micro)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
                .layoutPriority(1)
            Spacer(minLength: Space.s1)
            Text(value.map(format) ?? "Keine Messung")
                .font(value == nil ? .formaCaption : .formaValue)
                .foregroundStyle(value == nil ? Theme.textTertiary : Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: value ?? 0))
                .animation(reduceMotion ? nil : .snappy, value: value)
            Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundStyle(Theme.textSecondary)
                .opacity(delta == 0 ? 0 : 1)
                .accessibilityHidden(true)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textQuaternary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value.map(format) ?? "Keine Messung",
                             delta > 0 ? "über den vorherigen 30 Tagen" : delta < 0 ? "unter den vorherigen 30 Tagen" : nil]
            .compactMap { $0 }.joined(separator: ", "))
    }
}

struct ComparisonFooter: View {
    var body: some View {
        HStack(spacing: Space.s1) {
            Image(systemName: "arrowtriangle.up.fill")
            Image(systemName: "arrowtriangle.down.fill")
            Text("Gewählter Tag vs. vorherige 30 Tage")
        }
        .font(.formaMicro)
        .foregroundStyle(Theme.textTertiary)
        .padding(.leading, Space.s1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pfeile vergleichen den gewählten Tag mit den vorherigen 30 Tagen")
    }
}

/// Ring mit Hochzählen vom letzten Wert; bei Reduce Motion springt er sofort.
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

    static func spokenValue(kind: RingKind, value: Int?) -> String {
        value.map { kind == .strain ? "\($0) von 100" : "\($0) Prozent" } ?? "Keine Messung"
    }

    private var name: String {
        guard expanded else { return kind.title }
        return kind == .sleep ? "Schlafleistung" : kind.title
    }
    private var suffix: String { kind == .strain ? "" : "%" }

    var body: some View {
        RingView(value: displayed, color: Self.tint(kind: kind, value: value), size: size,
                 lineWidth: expanded ? 10 : 6, numberSize: expanded ? size * 0.28 : nil,
                 missing: value == nil, suffix: suffix, subtitle: expanded ? name : nil)
        .onChange(of: value, initial: true) { _, latest in
            withAnimation(reduceMotion || latest == nil ? nil : .easeOut(duration: 0.8)) {
                displayed = Double(latest ?? 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(Self.spokenValue(kind: kind, value: value))
    }
}
