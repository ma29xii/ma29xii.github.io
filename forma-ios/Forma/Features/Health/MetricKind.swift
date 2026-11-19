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

/// Eine Zeile der Biomarker-Liste: Name, Zustand gegen deinen Bereich, Wert, Verlauf der letzten 14 Tage.
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

        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.formaRowTitle)
                    .foregroundStyle(Theme.textPrimary)
                if let latest = evaluation.latest {
                    Text(kind.measurement(latest.value))
                        .font(.formaValue)
                        .foregroundStyle(Theme.textPrimary)
                        .formaNumberTransition(latest.value)
                }
                Label {
                    Text(status.title)
                } icon: {
                    if let symbol = status.symbol { Image(systemName: symbol) }
                }
                .labelStyle(.titleAndIcon)
                .font(.formaCaptionStrong)
                .foregroundStyle(status.color)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !large, recent.count >= 2 {
                MetricSparkline(points: recent, range: evaluation.range)
                    .frame(width: 72, height: 32)
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
    let range: ClosedRange<Double>?

    var body: some View {
        Canvas { context, size in
            let values = points.map(\.value) + (range.map { [$0.lowerBound, $0.upperBound] } ?? [])
            guard let low = values.min(), let high = values.max() else { return }
            let first = Date.now.startOfDay.adding(days: -13)
            let span = max(high - low, 0.001)
            func y(_ value: Double) -> CGFloat {
                high == low ? size.height / 2 : size.height - 3 - (size.height - 6) * CGFloat((value - low) / span)
            }
            if let range {
                let top = y(range.upperBound), bottom = y(range.lowerBound)
                context.fill(Path(roundedRect: CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top)),
                                  cornerRadius: 2), with: .color(Color.white.opacity(0.07)))
            }
            var path = Path()
            var previous: Date?
            var end: (point: CGPoint, outside: Bool)?
            for point in points {
                let days = Calendar.forma.dateComponents([.day], from: first, to: point.date).day ?? 0
                let position = CGPoint(x: 2 + (size.width - 6) * CGFloat(days) / 13, y: y(point.value))
                if previous?.adding(days: 1) == point.date {
                    path.addLine(to: position)
                } else {
                    path.move(to: position)
                }
                previous = point.date
                end = (point: position, outside: range.map { !$0.contains(point.value) } ?? false)
                context.fill(Path(ellipseIn: CGRect(x: position.x - 1, y: position.y - 1, width: 2, height: 2)),
                             with: .color(Theme.textTertiary))
            }
            context.stroke(path, with: .color(Theme.textSecondary),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let end {
                context.fill(Path(ellipseIn: CGRect(x: end.point.x - 2.5, y: end.point.y - 2.5, width: 5, height: 5)),
                             with: .color(end.outside ? Theme.textPrimary : Theme.textSecondary))
            }
        }
    }
}
