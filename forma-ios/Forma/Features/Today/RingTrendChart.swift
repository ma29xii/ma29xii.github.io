import SwiftUI
import Charts

enum DashboardTrends {
    static func points(kind: RingKind, days: [DayMetrics], domain: ClosedRange<Date>) -> [HealthChartPoint] {
        days.filter { domain.contains($0.date) }.compactMap { day in
            let snapshot = DashboardDay(day: day, history: days)
            return snapshot.value(for: kind).map { HealthChartPoint(date: day.date, value: Double($0)) }
        }
    }

    static func mean(points: [HealthChartPoint], minimum: Int = 4) -> Double? {
        guard !points.isEmpty, points.count >= minimum else { return nil }
        return points.reduce(0) { $0 + $1.value } / Double(points.count)
    }
}

struct RingTrendChart: View {
    let kind: RingKind
    let anchor: Date
    let days: [DayMetrics]
    let color: Color

    private enum Range: String, CaseIterable, Identifiable {
        case week = "W", month = "M", halfYear = "6M"
        var id: String { rawValue }

        var caption: String {
            switch self {
            case .week: "Eine Woche"
            case .month: "Ein Monat"
            case .halfYear: "Sechs Monate"
            }
        }

        var axisStride: Int {
            switch self {
            case .week: 2
            case .month: 7
            case .halfYear: 45
            }
        }

        func border(for page: Int, anchor: Date) -> Date {
            switch self {
            case .week: anchor.adding(days: -7 * page)
            case .month, .halfYear:
                Calendar.forma.date(byAdding: .month, value: -(self == .month ? 1 : 6) * page, to: anchor) ?? anchor
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var range = Range.week
    @State private var page = 0
    @State private var selection: Date?

    var body: some View {
        let boundary = anchor.adding(days: 1)
        let start = range.border(for: page + 1, anchor: boundary)
        let end = range.border(for: page, anchor: boundary)
        let lastDay = end.adding(days: -1)
        let points = DashboardTrends.points(kind: kind, days: days, domain: start...lastDay)
        let average = DashboardTrends.mean(points: points, minimum: 1)
        let selected = selection.map { min(lastDay, max(start, $0.startOfDay)) }
        let selectionValue = points.first { $0.date == selected }
        return VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Trend")
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text("Durchschnitt").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                            Text(average.map(valueText) ?? "–")
                                .font(.formaBigNumber)
                                .contentTransition(reduceMotion ? .opacity : .numericText(value: average ?? 0))
                                .animation(reduceMotion ? nil : .snappy, value: average)
                                .accessibilityIdentifier("trend.average")
                        }
                        Spacer(minLength: Space.s2)
                        Picker("Zeitraum", selection: $range) {
                            ForEach(Range.allCases) { period in
                                Text(period.rawValue).accessibilityLabel(period.caption).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(idealWidth: 150, maxWidth: 170, minHeight: 44)
                        .accessibilityIdentifier("trend.range")
                    }
                    DateStepper(title: "\(Format.shortDate(start)) – \(Format.shortDate(lastDay))",
                                canPrevious: (days.first?.date ?? anchor) < start, canNext: page > 0,
                                unit: "Zeitraum", identifier: "trend.window",
                                previous: { page += 1; selection = nil },
                                next: { page -= 1; selection = nil })
                        .frame(maxWidth: .infinity)
                    if let selected {
                        Text("\(Format.shortDate(selected)) · \(selectionValue.map { valueText($0.value) } ?? "Keine Messung")")
                            .font(.formaCaptionStrong)
                    } else {
                        Text(points.isEmpty ? "Keine Messung in diesem Zeitraum" : "\(points.count) Tage mit Messung")
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if !points.isEmpty {
                        chart(points, start: start, end: end, selected: selected, average: average)
                            .animation(reduceMotion ? nil : .smooth, value: range)
                    }
                }
                .padding(Space.s4)
            }
        }
        .accessibilityIdentifier("ring.trend")
        .sensoryFeedback(.selection, trigger: selection?.startOfDay)
        .onChange(of: range) { _, _ in resetPage() }
        .onChange(of: anchor) { _, _ in resetPage() }
    }

    private func resetPage() {
        page = 0
        selection = nil
    }

    private func valueText(_ value: Double) -> String {
        Format.number(value) + (kind == .strain ? "" : " %")
    }

    private func chart(_ points: [HealthChartPoint], start: Date, end: Date, selected: Date?, average: Double?) -> some View {
        let entries = segments(points)
        return Chart {
            ForEach(entries, id: \.point.date) { entry in
                let point = entry.point
                let center = point.date.addingTimeInterval(point.date.adding(days: 1).timeIntervalSince(point.date) / 2)
                LineMark(x: .value("Tag", center), y: .value(kind.title, point.value),
                         series: .value("Abschnitt", entry.segment))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                // Punkte nur in der Woche und am gewählten Tag, sonst wird die Linie unruhig.
                PointMark(x: .value("Tag", center), y: .value(kind.title, point.value))
                    .symbolSize(point.date == selected ? 70 : (range == .week ? 25 : 0))
                    .foregroundStyle(point.date == selected ? Theme.textPrimary : color)
                    .annotation(position: .top, spacing: 3) {
                        if range == .week && selected == nil {
                            Text(Format.number(point.value))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
            }
            if let average {
                RuleMark(y: .value("Durchschnitt", average))
                    .foregroundStyle(Theme.textQuaternary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            if let selected {
                let center = selected.addingTimeInterval(selected.adding(days: 1).timeIntervalSince(selected) / 2)
                RuleMark(x: .value("Auswahl", center))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0.0...110.0)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: .day, count: range.axisStride)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: 180)
        .accessibilityLabel("\(kind.title)-Trend, \(range.caption)")
        .accessibilityValue(average.map { "Durchschnitt \(valueText($0)), \(points.count) Tage mit Messung" } ?? "Keine Messung")
    }

    private func segments(_ points: [HealthChartPoint]) -> [(point: HealthChartPoint, segment: Int)] {
        var previous: Date?
        var segment = 0
        return points.map { point in
            if previous?.adding(days: 1) != point.date { segment += 1 }
            previous = point.date
            return (point, segment)
        }
    }
}
