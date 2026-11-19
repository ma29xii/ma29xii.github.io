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
}

/// Der animierbare Wert treibt sowohl den Bogen als auch die Ziffern pro Frame.
struct RingView: View, Animatable {
    nonisolated var value: Double
    var color: Color
    var size: CGFloat
    var lineWidth: CGFloat
    var showsNumber = true
    var numberSize: CGFloat? = nil
    var missing = false
    var suffix = ""
    var subtitle: String? = nil

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
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(size < 40 ? 0 : 0.32), radius: lineWidth)
            if showsNumber {
                VStack(spacing: Space.s1) {
                    Text(missing ? "–" : "\(Int(bounded.rounded()))\(suffix)")
                        .font(.system(size: numberSize ?? size * 0.3, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(missing ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(.formaMicro)
                            .tracking(1.3)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.55)
                    }
                }
                .frame(width: size * 0.80)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Today-Kopf: offener Bogen (Recovery) und Kapseln (Strain, Sleep)

/// Offener 270°-Bogen mit Öffnung unten. Eigene Form statt eines geschlossenen Rings.
struct RecoveryArc: View, Animatable {
    nonisolated var value: Double
    var color: Color
    var size: CGFloat
    var lineWidth: CGFloat = 14
    var missing = false
    var caption = "Recovery"
    var word: String? = nil

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    /// Mittelpunkt-Versatz des Endpunkts; 0 % liegt unten links (135°), 100 % unten rechts (405°).
    nonisolated static func endpoint(fraction: Double, radius: CGFloat) -> CGSize {
        let angle = (135 + 270 * min(1, max(0, fraction))) * .pi / 180
        return CGSize(width: radius * cos(angle), height: radius * sin(angle))
    }

    var body: some View {
        let bounded = value.isFinite ? min(100, max(0, value)) : 0
        let fraction = missing ? 0 : bounded / 100
        let arc = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: 0.75)
                .stroke(Theme.track, style: arc)
                .rotationEffect(.degrees(135))
            if fraction > 0.001 {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(AngularGradient(colors: [color.opacity(0.7), color], center: .center,
                                            startAngle: .zero, endAngle: .degrees(270 * fraction)), style: arc)
                    .rotationEffect(.degrees(135))
                Circle()
                    .fill(color)
                    .frame(width: lineWidth, height: lineWidth)
                    .shadow(color: color.opacity(0.6), radius: 12)
                    .offset(Self.endpoint(fraction: fraction, radius: size / 2 - lineWidth / 2))
            }
            VStack(spacing: 0) {
                Text(caption)
                    .font(.system(size: max(11, size * 0.065), weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(missing ? "–" : "\(Int(bounded.rounded()))")
                        .font(.system(size: size * 0.41, weight: .semibold, design: .rounded))
                        .tracking(-1.5)
                    if !missing {
                        Text("%")
                            .font(.system(size: size * 0.13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(missing ? Theme.textSecondary : Theme.textPrimary)
            }
            .frame(width: size * 0.7)
            Text(missing ? "Keine Messung" : (word ?? ""))
                .font(.system(size: max(12, size * 0.08), weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: size * 0.6)
                .offset(y: size * 0.4)
        }
        .frame(width: size, height: size)
    }
}

/// Senkrechte Kapsel wie ein Füllstand, mit Zahl darüber und optionalem Zielband.
struct LevelCapsule: View, Animatable {
    nonisolated var value: Double
    var color: Color
    var height: CGFloat = 104
    var missing = false
    var band: ClosedRange<Double>? = nil
    var suffix = ""
    var numberSize: CGFloat = 28
    /// Feine Skalenstriche (Abschnitte); geben der Kapsel ohne Füllfarbe Halt.
    var ticks = 4

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let bounded = value.isFinite ? min(100, max(0, value)) : 0
        let width = height * 0.58
        let shape = Capsule(style: .continuous)
        VStack(spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(missing ? "–" : "\(Int(bounded.rounded()))")
                    .font(.system(size: numberSize, weight: .semibold, design: .rounded))
                if !missing && !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: numberSize * 0.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(missing ? Theme.textSecondary : Theme.textPrimary)
            ZStack(alignment: .bottom) {
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.075), Color.white.opacity(0.035)],
                                          startPoint: .top, endPoint: .bottom))
                if !missing {
                    Rectangle()
                        .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .frame(height: height * bounded / 100)
                }
                ForEach(1..<max(2, ticks), id: \.self) { index in
                    Rectangle()
                        .fill(Color.white.opacity(index * 2 == ticks ? 0.22 : 0.12))
                        .frame(width: width * (index * 2 == ticks ? 0.42 : 0.26), height: 1)
                        .offset(y: -height * Double(index) / Double(ticks))
                }
                if let band {
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.5)).frame(height: 1) }
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.5)).frame(height: 1) }
                        .frame(height: height * (band.upperBound - band.lowerBound) / 100)
                        .offset(y: -height * band.lowerBound / 100)
                }
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            }
        }
    }
}

// MARK: - Runde 11: Ringe-Variante und Schritte-Halbkreis

/// Ring für die wählbare Kopf-Variante „Ringe“: zählt beim Erscheinen hoch, bei Reduce Motion sofort.
struct HeaderRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed = 0.0
    let kind: RingKind
    let value: Int?
    let size: CGFloat
    var delay: Double = 0

    var body: some View {
        RingView(value: displayed, color: DashboardRing.tint(kind: kind, value: value), size: size,
                 lineWidth: kind == .recovery ? 12 : 8, numberSize: size * (kind == .recovery ? 0.3 : 0.28),
                 missing: value == nil, suffix: kind == .strain ? "" : "%")
            .onChange(of: value, initial: true) { _, latest in
                let motion: Animation = .spring(response: kind == .recovery ? 0.9 : 0.75, dampingFraction: 0.85).delay(delay)
                withAnimation(reduceMotion || latest == nil ? nil : motion) { displayed = Double(latest ?? 0) }
            }
    }
}

/// Halbkreis aus Strichen (wie eine Skala). Gefüllt bis zum Anteil am Ziel; ohne Ziel bleibt er neutral.
struct TickArc: View, Animatable {
    nonisolated var fraction: Double
    var color: Color
    var ticks = 41
    var lineWidth: CGFloat = 3

    nonisolated var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    /// Wie viele Striche bei einem Anteil gefüllt sind (0 bei keinem Fortschritt, alle ab 100 %).
    nonisolated static func filledTicks(fraction: Double, count: Int) -> Int {
        guard fraction.isFinite, fraction > 0, count > 0 else { return 0 }
        return min(count, Int((fraction * Double(count)).rounded(.up)))
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height)
            let radius = min(size.width / 2, size.height) - lineWidth
            let filled = Self.filledTicks(fraction: fraction, count: ticks)
            for index in 0..<ticks {
                // Von links (180°) über oben nach rechts (360°).
                let angle = Double.pi * (1 + Double(index) / Double(max(1, ticks - 1)))
                let long = index % 10 == 0
                let inner = radius - (long ? 16 : 11)
                var path = Path()
                path.move(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
                path.addLine(to: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
                context.stroke(path, with: .color(index < filled ? color : Color.white.opacity(0.18)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
    }
}
