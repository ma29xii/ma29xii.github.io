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

    /// Ruhepuls und Atemfrequenz sind niedriger besser, alles andere höher.
    var higherIsBetter: Bool {
        switch self {
        case .restingHR, .respiratoryRate: false
        default: true
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

/// Eine Zeile der Biomarker-Liste: Name, Zustandswort farbig, Wert, Verlauf der letzten 14 Tage.
struct MetricSummaryRow: View {
    @Environment(DataHub.self) private var hub
    let kind: MetricKind

    var body: some View {
        let points = hub.days.compactMap { day in
            kind.value(day).map { HealthChartPoint(date: day.date, value: $0) }
        }
        let last = points.last
        let recent = points.filter { $0.date >= Date.now.startOfDay.adding(days: -13) }
        let status = BiomarkerStatus.evaluate(latest: last.map { (date: $0.date, value: $0.value) },
                                              baseline: ScoreEngine.baseline(points.dropLast().map(\.value)))
        let color = status.color(for: kind)

        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.formaRowTitle)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(status.title).foregroundStyle(color)
                    if let last {
                        Text("·").foregroundStyle(Theme.textTertiary).accessibilityHidden(true)
                        Text(kind.measurement(last.value))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .font(.formaCaptionStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if recent.count >= 2 {
                MetricSparkline(points: recent, color: color == Theme.textSecondary ? Theme.textTertiary : color)
                    .frame(width: 64, height: 28)
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Die X-Position folgt dem Kalendertag. Eine fehlende Messung unterbricht die Linie.
private struct MetricSparkline: View {
    let points: [HealthChartPoint]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard let low = points.map(\.value).min(), let high = points.map(\.value).max() else { return }
            let first = Date.now.startOfDay.adding(days: -13)
            let span = max(high - low, 0.001)
            var path = Path()
            var previous: Date?
            var end: CGPoint?
            for point in points {
                let days = Calendar.forma.dateComponents([.day], from: first, to: point.date).day ?? 0
                let x = 2 + (size.width - 6) * CGFloat(days) / 13
                let y = high == low ? size.height / 2 : size.height - 3 - (size.height - 6) * CGFloat((point.value - low) / span)
                let position = CGPoint(x: x, y: y)
                if previous?.adding(days: 1) == point.date {
                    path.addLine(to: position)
                } else {
                    path.move(to: position)
                }
                previous = point.date
                end = position
                context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(color.opacity(0.6)))
            }
            context.stroke(path, with: .color(color.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let end {
                context.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)), with: .color(color))
            }
        }
    }
}
