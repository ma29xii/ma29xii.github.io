import SwiftUI

/// Kennzahlen mit Einheit und Nachkommastellen.
enum MetricKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case hrv, restingHR, respiratoryRate, spo2, vo2max, sleepDuration, steps, activeEnergy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv: "HRV"
        case .restingHR: "Ruhepuls"
        case .respiratoryRate: "Atemfrequenz"
        case .spo2: "Sauerstoffsättigung"
        case .vo2max: "VO₂max"
        case .sleepDuration: "Schlafdauer"
        case .steps: "Schritte"
        case .activeEnergy: "Aktive Energie"
        }
    }

    var unit: String {
        switch self {
        case .hrv: "ms"
        case .restingHR: "bpm"
        case .respiratoryRate: "/min"
        case .spo2: "%"
        case .vo2max: "ml/kg/min"
        case .sleepDuration: "h"
        case .steps: ""
        case .activeEnergy: "kcal"
        }
    }

    var decimals: Int {
        switch self {
        case .respiratoryRate, .vo2max, .sleepDuration: 1
        default: 0
        }
    }

    /// Kennfarbe des Messwerts (wie in Apple Health je Kategorie), bewertet nichts.
    var tint: Color {
        switch self {
        case .hrv: Color(hex: 0x7FD8B6)
        case .restingHR: Color(hex: 0xFF8A93)
        case .respiratoryRate: Color(hex: 0x7CCBE6)
        case .spo2: Color(hex: 0x93B8FF)
        case .vo2max: Color(hex: 0xFFB672)
        case .sleepDuration: Theme.sleep
        case .steps: Theme.strain
        case .activeEnergy: Color(hex: 0xFFD27A)
        }
    }

    func value(_ day: DayMetrics) -> Double? {
        switch self {
        case .hrv: day.hrv
        case .restingHR: day.restingHR
        case .respiratoryRate: day.respiratoryRate
        case .spo2: day.spo2
        case .vo2max: day.vo2max
        case .sleepDuration: day.sleep.map { $0.asleep / 3600 }
        case .steps: day.steps
        case .activeEnergy: day.activeEnergy
        }
    }

    func formatted(_ value: Double) -> String {
        if self == .sleepDuration { return Format.duration(value * 3600) }
        return Format.number(value, decimals: decimals)
    }

    func measurement(_ value: Double) -> String {
        let formatted = formatted(value)
        return self == .sleepDuration || unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }
}

/// Eine Zeile der Biomarker-Liste: Name und Zustand links, Mini-Verlauf und Wert rechts.
/// Bei großer Schrift stehen die Teile untereinander statt zu schrumpfen (K-03-26).
struct MetricSummaryRow: View {
    @Environment(DataHub.self) private var hub
    @Environment(\.dynamicTypeSize) private var typeSize
    let kind: MetricKind

    var body: some View {
        let evaluation = BiomarkerComparison.evaluate(kind, days: hub.longDays)
        let status = evaluation.status
        let start = Date.now.startOfDay.adding(days: -13)
        let recent = hub.longDays.filter { $0.date >= start }.compactMap { day in
            kind.value(day).map { HealthChartPoint(date: day.date, value: $0) }
        }
        let large = typeSize.isAccessibilitySize
        let value = evaluation.latest.map { kind.measurement($0.value) } ?? "–"

        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: Space.s2) {
                    Circle()
                        .fill(kind.tint)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(kind.title)
                        .font(.formaRowTitle)
                        .foregroundStyle(Theme.textPrimary)
                }
                if large {
                    Text(value)
                        .font(.formaNumber)
                        .foregroundStyle(Theme.textPrimary)
                }
                BiomarkerStatusLabel(status: status)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !large {
                if recent.count >= 2 {
                    MetricSparkline(points: recent, range: evaluation.range, tint: kind.tint)
                        .frame(width: 84, height: 34)
                        .accessibilityHidden(true)
                }
                Text(value)
                    .font(.formaValue)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .formaNumberTransition(evaluation.latest?.value ?? 0)
                    .frame(minWidth: 64, alignment: .trailing)
            }
            Image(systemName: "chevron.right")
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue("\(value), \(status.title)")
    }
}

/// Zustand neutral: im Bereich leise mit Haken, Abweichung heller mit Pfeil in einer kleinen Kapsel.
struct BiomarkerStatusLabel: View {
    let status: BiomarkerStatus

    var body: some View {
        switch status {
        case .above, .below:
            Label(status.title, systemImage: status.symbol ?? "arrow.up")
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 3)
                .background(Theme.cardRaised, in: Capsule())
        case .within:
            Label(status.title, systemImage: "checkmark")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        default:
            Text(status.title)
                .font(.formaCaption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

/// 14 Tage in der Kennfarbe: zarte Fläche, dein Bereich als Band, letzter Wert mit Lichthof.
/// Die X-Position folgt dem Kalendertag; eine fehlende Messung unterbricht Linie und Fläche.
private struct MetricSparkline: View {
    let points: [HealthChartPoint]
    let range: ClosedRange<Double>?
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let values = points.map(\.value) + (range.map { [$0.lowerBound, $0.upperBound] } ?? [])
            guard let low = values.min(), let high = values.max() else { return }
            let first = Date.now.startOfDay.adding(days: -13)
            let span = max(high - low, 0.001)
            func y(_ value: Double) -> CGFloat {
                high == low ? size.height / 2 : size.height - 4 - (size.height - 8) * CGFloat((value - low) / span)
            }
            func x(_ date: Date) -> CGFloat {
                let days = Calendar.forma.dateComponents([.day], from: first, to: date).day ?? 0
                return 3 + (size.width - 8) * CGFloat(days) / 13
            }
            if let range {
                let top = y(range.upperBound)
                let bottom = y(range.lowerBound)
                context.fill(Path(roundedRect: CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top)),
                                  cornerRadius: 3), with: .color(Color.white.opacity(0.06)))
            }
            // Zusammenhängende Abschnitte (Tag für Tag) einzeln zeichnen.
            var segments: [[CGPoint]] = []
            var previous: Date?
            for point in points {
                let position = CGPoint(x: x(point.date), y: y(point.value))
                if previous?.adding(days: 1) == point.date, !segments.isEmpty {
                    segments[segments.count - 1].append(position)
                } else {
                    segments.append([position])
                }
                previous = point.date
            }
            let fade = Gradient(colors: [tint.opacity(0.28), tint.opacity(0)])
            for segment in segments {
                guard let head = segment.first, let tail = segment.last else { continue }
                if segment.count == 1 {
                    context.fill(Path(ellipseIn: CGRect(x: head.x - 1.5, y: head.y - 1.5, width: 3, height: 3)),
                                 with: .color(tint.opacity(0.8)))
                    continue
                }
                var line = Path()
                line.move(to: head)
                for next in segment.dropFirst() { line.addLine(to: next) }
                var area = line
                area.addLine(to: CGPoint(x: tail.x, y: size.height))
                area.addLine(to: CGPoint(x: head.x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(fade, startPoint: CGPoint(x: 0, y: 0),
                                                         endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(line, with: .color(tint),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            if let end = segments.last?.last {
                context.fill(Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)),
                             with: .color(tint.opacity(0.25)))
                context.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)),
                             with: .color(tint))
            }
        }
    }
}
