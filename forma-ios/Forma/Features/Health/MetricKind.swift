import SwiftUI

/// Kennzahlen mit Einheit, Nachkommastellen und Quelle.
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

struct MetricSummaryRow: View {
    @Environment(DataHub.self) private var hub
    let kind: MetricKind

    var body: some View {
        let points = hub.days.compactMap { day in
            kind.value(day).map { HealthChartPoint(date: day.date, value: $0) }
        }
        let last = points.last
        let recent = points.filter { $0.date >= Date.now.startOfDay.adding(days: -13) }
        let prior = points.dropLast().map(\.value)
        let status = status(for: last, comparedWith: ScoreEngine.baseline(prior))

        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(kind.title).font(.formaRowTitle)
                Text(last.map { kind.measurement($0.value) } ?? "–").font(.formaValue)
                Text(status.title).font(.formaCaptionStrong).foregroundStyle(status.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !recent.isEmpty {
                MetricSparkline(points: recent, color: status.color)
                    .frame(width: 58, height: 28)
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func status(for last: HealthChartPoint?, comparedWith base: ScoreEngine.Baseline?) -> (title: String, color: Color) {
        guard let last else { return ("Keine Daten", Theme.textSecondary) }
        guard Calendar.forma.isDateInToday(last.date) else {
            return ("Stand \(Format.shortDate(last.date))", Theme.textSecondary)
        }
        guard let base else { return ("Noch kein Vergleich", Theme.textSecondary) }
        let z = base.z(last.value)
        if z > 1 { return ("Höher als üblich", Theme.warning) }
        if z < -1 { return ("Niedriger als üblich", Theme.warning) }
        return ("Wie üblich", Theme.younger)
    }
}

/// Die X-Position folgt dem Kalendertag. Eine fehlende Messung unterbricht die Linie.
private struct MetricSparkline: View {
    let points: [HealthChartPoint]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard let low = points.map(\.value).min(), let high = points.map(\.value).max() else { return }
            let today = Date.now.startOfDay
            let first = today.adding(days: -13)
            let span = max(high - low, 0.001)
            var path = Path()
            var previous: Date?
            for point in points {
                let days = Calendar.forma.dateComponents([.day], from: first, to: point.date).day ?? 0
                let x = 2 + (size.width - 4) * CGFloat(days) / 13
                let y = high == low ? size.height / 2 : size.height - 3 - (size.height - 6) * (point.value - low) / span
                let position = CGPoint(x: x, y: y)
                if previous?.adding(days: 1) == point.date {
                    path.addLine(to: position)
                } else {
                    path.move(to: position)
                }
                previous = point.date
                context.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(color))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}
