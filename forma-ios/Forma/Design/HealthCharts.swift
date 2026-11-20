import SwiftUI
import Charts

struct HealthChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

func insightDayCenter(_ day: Date) -> Date {
    day.addingTimeInterval(day.adding(days: 1).timeIntervalSince(day) / 2)
}

func insightSegments<Value>(_ days: [InsightDay<Value>]) -> [(date: Date, value: Value, segment: Int)] {
    var segment = 0
    return days.compactMap { day in
        guard let value = day.value else {
            segment += 1
            return nil
        }
        return (day.date, value, segment)
    }
}

func insightSelectionRule(_ date: Date) -> some ChartContent {
    RuleMark(x: .value("Auswahl", insightDayCenter(date)))
        .foregroundStyle(Theme.textTertiary)
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .accessibilityHidden(true)
}

@AxisContentBuilder
func insightScale(_ ticks: [Double]) -> some AxisContent {
    AxisMarks(position: .leading, values: ticks) { _ in
        AxisGridLine().foregroundStyle(Theme.hairline)
        AxisValueLabel().foregroundStyle(Theme.textSecondary)
    }
}

extension View {
    func insightDateAxis(from start: Date, through end: Date, stride: Int) -> some View {
        chartXScale(domain: start...end.adding(days: 1))
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .stride(by: .day, count: stride)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
    }
}

/// Tageswerte bleiben auf ihrem Kalenderdatum. Tage ohne Messung bleiben leer.
struct DailyHistoryChart: View {
    let title: String
    let points: [HealthChartPoint]
    let color: Color
    let valueText: (Double) -> String
    var maximum: Double? = nil
    var anchor: Date? = nil

    @State private var range = 7

    var body: some View {
        let end = anchor ?? Date.now.startOfDay
        let start = end.adding(days: 1 - range)
        let visible = points.filter { (start...end).contains($0.date) }
        FormaSection(title: title) {
            Picker("Zeitraum", selection: $range) {
                Text("7 Tage").tag(7)
                Text("30 Tage").tag(30)
            }
            .pickerStyle(.segmented)

            Plate {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if visible.isEmpty {
                        ChartEmptyState(text: "Keine Daten in diesem Zeitraum")
                    } else {
                        Chart {
                            ForEach(visible) { p in
                                BarMark(x: .value("Tag", p.date, unit: .day), y: .value(title, p.value))
                                    .foregroundStyle(color.opacity(0.9))
                                    .cornerRadius(3)
                                    .accessibilityValue(valueText(p.value))
                                if p.value == 0 {
                                    PointMark(x: .value("Tag", p.date, unit: .day), y: .value(title, p.value))
                                        .foregroundStyle(color)
                                }
                            }
                        }
                        .chartXScale(domain: start...end.adding(days: 1))
                        .chartYScale(domain: 0...max(1, maximum ?? 0, visible.map(\.value).max() ?? 0))
                        .chartXAxis {
                            AxisMarks(preset: .aligned, values: .stride(by: .day, count: range == 7 ? 2 : 7)) { _ in
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing) { _ in
                                AxisGridLine().foregroundStyle(Theme.hairline)
                                AxisValueLabel().foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(height: 146)
                        .accessibilityLabel("\(title), \(visible.count) Messungen in \(range) Tagen")
                        Text("\(visible.count) von \(range) Tagen erfasst")
                            .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                            .formaNumberTransition(Double(visible.count))
                    }
                }
                .padding(Space.s4)
            }
        }
    }
}

struct ChartEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.formaBody)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 72)
    }
}

struct HourlyValueChart: View {
    let title: String
    let points: [HealthChartPoint]
    let color: Color
    let maximum: Double
    let valueText: (Double) -> String
    var emptyText = "Keine Stundenwerte verfügbar"

    @State private var selection: Date?

    var body: some View {
        let start = points.first?.date.startOfDay ?? Date.now.startOfDay
        let end = start.adding(days: 1)
        let selected = selection.flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }.flatMap { point in
            selection.map { abs(point.date.timeIntervalSince($0)) <= 35 * 60 } == true ? point : nil
        }
        FormaSection(title: title) {
            Plate {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if points.isEmpty {
                        ChartEmptyState(text: emptyText)
                    } else {
                        Text(selected.map { "\(Format.clock($0.date)) · \(valueText($0.value))" }
                             ?? (selection == nil ? "Heute" : "Keine Messung"))
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textSecondary)
                        .formaNumberTransition(selected?.value ?? 0)
                        Chart {
                            ForEach(segments(points), id: \.point.id) { entry in
                                LineMark(x: .value("Uhrzeit", entry.point.date), y: .value(title, entry.point.value),
                                         series: .value("Abschnitt", entry.index))
                                    .foregroundStyle(color)
                                PointMark(x: .value("Uhrzeit", entry.point.date), y: .value(title, entry.point.value))
                                    .foregroundStyle(color)
                                    .symbolSize(18)
                            }
                            if let selected {
                                RuleMark(x: .value("Auswahl", selected.date))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .chartXScale(domain: start...end)
                        .chartYScale(domain: 0...maximum)
                        .chartXSelection(value: $selection)
                        .sensoryFeedback(.selection, trigger: selected?.date) { _, new in new != nil }
                        .chartXAxis {
                            AxisMarks(preset: .aligned, values: .stride(by: .hour, count: 6)) { _ in
                                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing) { _ in
                                AxisGridLine().foregroundStyle(Theme.hairline)
                                AxisValueLabel().foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(height: 138)
                        .accessibilityLabel("\(title), Tagesverlauf mit \(points.count) Werten")
                    }
                }
                .padding(Space.s4)
            }
        }
    }

    private struct SegmentPoint {
        let point: HealthChartPoint
        let index: Int
    }

    private func segments(_ points: [HealthChartPoint]) -> [SegmentPoint] {
        var segment = 0
        return points.enumerated().map { offset, point in
            if offset > 0, point.date.timeIntervalSince(points[offset - 1].date) > 3600 {
                segment += 1
            }
            return SegmentPoint(point: point, index: segment)
        }
    }
}
