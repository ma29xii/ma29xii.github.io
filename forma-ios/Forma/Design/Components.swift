import SwiftUI

// MARK: - Flächen und Zeilen

/// Ruhige Inhaltsfläche (kein Glas): 4,5 % Weiß, feine Lichtkante.
struct Plate<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
                    .fill(Theme.plate)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
                    .strokeBorder(Theme.plateEdge, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.plate, style: .continuous))
    }
}

/// Abschnitt mit Überschrift (20 pt) auf der 16-pt-Kante.
struct FormaSection<Content: View>: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.formaSection)
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.formaBody)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                }
            }
            content
        }
        .padding(.top, Space.s6)
    }
}

/// Haarlinie zwischen Zeilen, eingerückt auf 16 pt.
struct RowDivider: View {
    var inset: CGFloat = Space.s4
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

/// Standardzeile: Titel, Untertitel, Wert, optionales Element rechts.
struct MetricRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var unit: String? = nil
    var valueColor: Color = Theme.textPrimary
    var showsChevron: Bool = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.formaRowTitle)
                if let subtitle {
                    Text(subtitle).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Space.s2)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.formaValue).foregroundStyle(valueColor)
                    if let unit {
                        Text(unit).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            trailing
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textQuaternary)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

extension MetricRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, value: String? = nil, unit: String? = nil, valueColor: Color = Theme.textPrimary, showsChevron: Bool = false) {
        self.init(title: title, subtitle: subtitle, value: value, unit: unit, valueColor: valueColor, showsChevron: showsChevron) { EmptyView() }
    }
}

/// Kleines Symbolfeld vor einer Zeile.
struct Glyph: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .medium))
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

/// Kurzer Hinweis-Chip (Inhalt, kein Glas).
struct InfoChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// Kennzeichnung für Beispieldaten.
struct SampleDataBadge: View {
    var text = "Beispieldaten"
    var body: some View {
        Label(text, systemImage: "flask")
            .font(.formaMicro)
            .foregroundStyle(Theme.warning)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Theme.warning.opacity(0.12)))
    }
}

// MARK: - Kleine Grafiken

/// Bereichsbalken: Normalbereich als helles Band, aktueller Wert als Punkt.
struct RangeBar: View {
    let low: Double
    let high: Double
    let value: Double
    let minimum: Double
    let maximum: Double
    var dotColor: Color = Theme.textPrimary
    var width: CGFloat = 64

    private func position(_ x: Double) -> CGFloat {
        let p = (x - minimum) / max(0.0001, maximum - minimum)
        return CGFloat(Swift.min(1, Swift.max(0, p)))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
            Capsule().fill(Color.white.opacity(0.2))
                .frame(width: width * (position(high) - position(low)), height: 4)
                .offset(x: width * position(low))
            Circle().fill(dotColor)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                .offset(x: width * position(value) - 4)
        }
        .frame(width: width, height: 10)
        .accessibilityHidden(true)
    }
}

/// Fortschrittsbalken ohne Beschriftung.
struct ProgressLine: View {
    let fraction: Double
    var color: Color = Theme.textPrimary
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(Swift.min(1, Swift.max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

/// Weiche Verlaufslinie mit rundem Endpunkt und optionalem Normalband.
struct Sparkline: View {
    let values: [Double]
    var band: ClosedRange<Double>? = nil
    var color: Color = Theme.textPrimary
    var height: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let lo = Swift.min(values.min() ?? 0, band?.lowerBound ?? .infinity)
            let hi = Swift.max(values.max() ?? 1, band?.upperBound ?? -.infinity)
            let pad = Swift.max((hi - lo) * 0.15, 0.001)
            let y: (Double) -> CGFloat = { v in h - CGFloat((v - lo + pad) / (hi - lo + 2 * pad)) * h }
            let x: (Int) -> CGFloat = { i in values.count < 2 ? 0 : CGFloat(i) / CGFloat(values.count - 1) * w }
            ZStack(alignment: .topLeading) {
                if let band {
                    Rectangle().fill(Color.white.opacity(0.05))
                        .frame(width: w, height: Swift.max(1, y(band.lowerBound) - y(band.upperBound)))
                        .offset(y: y(band.upperBound))
                }
                Path { p in
                    guard values.count > 1 else { return }
                    p.move(to: CGPoint(x: x(0), y: y(values[0])))
                    for i in 1..<values.count {
                        let x0 = x(i - 1), x1 = x(i), xm = (x0 + x1) / 2
                        p.addCurve(to: CGPoint(x: x1, y: y(values[i])),
                                   control1: CGPoint(x: xm, y: y(values[i - 1])),
                                   control2: CGPoint(x: xm, y: y(values[i])))
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = values.last {
                    Circle().fill(color).frame(width: 8, height: 8)
                        .position(x: w, y: y(last))
                }
            }
        }
        .frame(height: height)
        .padding(.trailing, 4)
        .accessibilityHidden(true)
    }
}

/// Balken für 7 Tage: vergangene Tage grau mit Farbkappe, heute voll.
struct DayBars: View {
    let values: [Double]
    let labels: [String]
    var maximum: Double? = nil
    let color: (Double) -> Color

    var body: some View {
        let m = maximum ?? (values.max() ?? 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let isToday = index == values.count - 1
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        let barHeight = Swift.max(4, geo.size.height * CGFloat(value / Swift.max(m, 0.001)))
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            ZStack(alignment: .top) {
                                UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 4)
                                    .fill(isToday ? color(value) : Theme.barGray)
                                if !isToday {
                                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 4)
                                        .fill(color(value))
                                        .frame(height: 3)
                                }
                            }
                            .frame(height: barHeight)
                        }
                    }
                    Text(index < labels.count ? labels[index] : "")
                        .font(.formaMicro)
                        .foregroundStyle(isToday ? Theme.textPrimary : Theme.textTertiary)
                }
            }
        }
        .frame(height: 96)
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s4)
        .accessibilityHidden(true)
    }
}

/// Ja/Nein-Schalter mit einheitlichem Auswahlzustand.
struct YesNoSwitch: View {
    @Binding var value: Bool?
    var body: some View {
        HStack(spacing: 0) {
            segment("Nein", selected: value == false) { value = false }
            segment("Ja", selected: value == true) { value = true }
        }
        .padding(2)
        .frame(width: 116, height: 34)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .sensoryFeedback(.selection, trigger: value)
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Theme.onSelection : Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(selected ? Theme.selection : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.snappy(duration: 0.22), value: selected)
    }
}

/// Primärer Knopf in der Inhaltsebene (hell, ruhig).
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.onSelection)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(Theme.selection))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Kleiner heller Knopf in Zeilen.
struct SmallPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.onSelection)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(Theme.selection))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

// MARK: - Formatierung

enum Format {
    static func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).locale(.german))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .german))
    }

    static func timer(_ seconds: Int) -> String {
        let s = Swift.max(0, seconds)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    static func dayTitle(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: .german).weekday(.wide).day().month(.wide))
    }

    static func shortWeekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: .german).weekday(.abbreviated))
            .replacingOccurrences(of: ".", with: "")
    }

    static func weight(_ kg: Double, unit: WeightUnit) -> String {
        let v = unit == .kg ? kg : kg * 2.20462
        let rounded = (v * 10).rounded() / 10
        return rounded.truncatingRemainder(dividingBy: 1) == 0 ? number(rounded) : number(rounded, decimals: 1)
    }
}

enum WeightUnit: String, CaseIterable, Identifiable, Sendable {
    case kg, lb
    var id: String { rawValue }
}
