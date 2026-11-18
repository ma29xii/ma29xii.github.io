import SwiftUI
import Charts

struct HealthChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
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
    @State private var selection: Date?

    var body: some View {
        let end = anchor ?? Date.now.startOfDay
        let start = end.adding(days: 1 - range)
        let visible = points.filter { (start...end).contains($0.date) }
        let selectedDay = selection?.startOfDay
        FormaSection(title: title) {
            Picker("Zeitraum", selection: $range) {
                Text("7 Tage").tag(7)
                Text("30 Tage").tag(30)
            }
            .pickerStyle(.segmented)
            .onChange(of: range) { _, _ in selection = nil }

            Plate {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if visible.isEmpty {
                        ChartEmptyState(text: "Keine Daten in diesem Zeitraum")
                    } else {
                        if let selectedDay {
                            let value = visible.first { $0.date == selectedDay }.map { valueText($0.value) } ?? "Keine Messung"
                            Text("\(Format.shortDate(selectedDay)) · \(value)").font(.formaCaptionStrong)
                        }
                        Chart {
                            ForEach(visible) { p in
                                BarMark(x: .value("Tag", p.date, unit: .day), y: .value(title, p.value))
                                    .foregroundStyle(color.opacity(selectedDay == nil || selectedDay == p.date ? 0.9 : 0.34))
                                    .cornerRadius(3)
                                if p.value == 0 {
                                    PointMark(x: .value("Tag", p.date, unit: .day), y: .value(title, p.value))
                                        .foregroundStyle(color)
                                }
                            }
                        }
                        .chartXScale(domain: start...end.adding(days: 1))
                        .chartYScale(domain: 0...max(1, maximum ?? 0, visible.map(\.value).max() ?? 0))
                        .chartXSelection(value: $selection)
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
