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

    var body: some View {
        let boundary = anchor.adding(days: 1)
        let start = range.border(for: page + 1, anchor: boundary)
        let end = range.border(for: page, anchor: boundary)
        let lastDay = end.adding(days: -1)
        let points = DashboardTrends.points(kind: kind, days: days, domain: start...lastDay)
        let average = DashboardTrends.mean(points: points, minimum: 1)
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
                    windowPicker(start: start, lastDay: lastDay)
                        .frame(maxWidth: .infinity)
                    Text(points.isEmpty ? "Keine Messung in diesem Zeitraum" : "\(points.count) Tage mit Messung")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .formaNumberTransition(Double(points.count))
                    if !points.isEmpty {
                        chart(points, start: start, end: end, average: average)
                            .animation(reduceMotion ? nil : .smooth, value: range)
                    }
                }
                .padding(Space.s4)
            }
        }
        .accessibilityIdentifier("ring.trend")
        .onChange(of: range) { _, _ in page = 0 }
        .onChange(of: anchor) { _, _ in page = 0 }
    }

    private func windowPicker(start: Date, lastDay: Date) -> some View {
        let title = "\(Format.shortDate(start)) – \(Format.shortDate(lastDay))"
        return HStack(spacing: 0) {
            windowButton("left", label: "Vorheriger Zeitraum", enabled: (days.first?.date ?? anchor) < start) {
                page += 1
            }
            Text(title)
                .font(.formaCaptionStrong)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .padding(.horizontal, Space.s1)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("trend.window.date")
            windowButton("right", label: "Nächster Zeitraum", enabled: page > 0) {
                page -= 1
            }
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: title)
    }

    private func windowButton(_ direction: String, label: String, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow." + direction)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textQuaternary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("trend.window." + direction)
    }

    private func valueText(_ value: Double) -> String {
        Format.number(value) + (kind == .strain ? "" : " %")
    }

    private func chart(_ points: [HealthChartPoint], start: Date, end: Date, average: Double?) -> some View {
        let entries = segments(points)
        return Chart {
            ForEach(entries, id: \.point.date) { entry in
                let point = entry.point
                let center = insightDayCenter(point.date)
                LineMark(x: .value("Tag", center), y: .value(kind.title, point.value),
                         series: .value("Abschnitt", entry.segment))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Tag", center), y: .value(kind.title, point.value))
                    .symbolSize(range == .week ? 25 : 9)
                    .foregroundStyle(color)
                    .annotation(position: .top, spacing: 3) {
                        if range == .week {
                            Text(Format.number(point.value))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                                .formaNumberTransition(point.value)
                        }
                    }
            }
            if let average {
                RuleMark(y: .value("Durchschnitt", average))
                    .foregroundStyle(Theme.textQuaternary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0.0...110.0)
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

struct RingStrainPath: View {
    let end: Date
    let history: [DayMetrics]
    let tint: Color

    var body: some View {
        let path = StrainInsight.path(endingAt: end, history: InsightHistory(history))
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Belastungspfad")
            DashboardCard {
                if let start = path.first?.date, path.contains(where: { $0.value != nil }) {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        if let latest = path.last?.value {
                            HStack(alignment: .firstTextBaseline) {
                                Text(latest.state.title)
                                    .font(.formaRowTitle)
                                    .foregroundStyle(latest.state == .tooMuch ? Theme.warning : Theme.textPrimary)
                                Spacer(minLength: Space.s2)
                                Text(Format.shortDate(end))
                                    .font(.formaCaption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: Space.s5) {
                                    mean(latest.short, days: 7, color: tint).fixedSize(horizontal: true, vertical: false)
                                    mean(latest.long, days: 28, color: Theme.textSecondary)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                VStack(alignment: .leading, spacing: Space.s2) {
                                    mean(latest.short, days: 7, color: tint)
                                    mean(latest.long, days: 28, color: Theme.textSecondary)
                                }
                            }
                        } else {
                            Text("Kein Vergleich am \(Format.shortDate(end))")
                                .font(.formaCaption)
                                .foregroundStyle(Theme.textSecondary)
                            HStack(spacing: Space.s3) {
                                Text("7 Tage").formaLabelStyle(tint)
                                Text("28 Tage").formaLabelStyle()
                            }
                        }
                        chart(path, start: start)
                    }
                    .padding(Space.s4)
                } else {
                    DashboardEmpty(title: "Noch kein 7- und 28-Tage-Vergleich")
                }
            }
        }
        .accessibilityIdentifier("strain.path")
    }

    private func mean(_ value: InsightAverage, days: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("\(days) Tage").formaLabelStyle(color)
            Text(Format.number(value.mean, decimals: 1))
                .font(.formaBigNumber)
                .formaNumberTransition(value.mean)
            Text("\(value.count) von \(days) erfasst")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func chart(_ path: [InsightDay<StrainInsight>], start: Date) -> some View {
        Chart {
            ForEach(insightSegments(path), id: \.date) { point in
                let x = PlottableValue.value("Tag", insightDayCenter(point.date))
                let short = point.value.short.mean
                let long = point.value.long.mean
                AreaMark(x: x, yStart: .value("Untergrenze", min(short, long)),
                         yEnd: .value("Obergrenze", max(short, long)), series: .value("Band", point.segment))
                    .foregroundStyle(tint.opacity(0.16))
                    .accessibilityHidden(true)
                LineMark(x: x, y: .value("28 Tage", long), series: .value("Verlauf", "lang-\(point.segment)"))
                    .foregroundStyle(Theme.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                LineMark(x: x, y: .value("7 Tage", short), series: .value("Verlauf", "kurz-\(point.segment)"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                PointMark(x: x, y: .value("7 Tage", short))
                    .symbolSize(11)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                PointMark(x: x, y: .value("28 Tage", long))
                    .symbolSize(11)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .insightDateAxis(from: start, through: end, stride: 7)
        .chartYScale(domain: 0.0...100.0)
        .chartYAxis { insightScale([0, 50, 100]) }
        .frame(height: 168)
        .accessibilityLabel("Strain im Vergleich über 7 und 28 Tage")
        .accessibilityIdentifier("strain.path.chart")
    }
}

struct RingSleepConsistency: View {
    let end: Date
    let history: [DayMetrics]

    var body: some View {
        let result = SleepConsistency(endingAt: end, history: InsightHistory(history))
        let value = result.percent.map { "\($0) %" } ?? "Noch kein Vergleich"
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Schlafkonstanz")
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(value)
                            .font(result.percent == nil ? .formaRowTitle : .formaBigNumber)
                            .foregroundStyle(result.percent == nil ? Theme.textSecondary : Theme.sleep)
                            .formaNumberTransition(Double(result.percent ?? 0))
                            .accessibilityLabel("Schlafkonstanz")
                            .accessibilityValue("\(value), \(result.measured) von 14 Nächten erfasst")
                        Spacer(minLength: Space.s2)
                        Text("\(result.measured)/14 Nächte")
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    if let start = result.nights.first?.date, result.measured > 0 {
                        HStack(spacing: Space.s3) {
                            Label("Bettzeit", systemImage: "minus")
                                .foregroundStyle(Theme.sleep)
                            Label("Aufwachen", systemImage: "minus.rectangle")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .font(.formaCaption)
                        .accessibilityHidden(true)
                        chart(result.nights, start: start)
                    }
                }
                .padding(Space.s4)
            }
        }
        .accessibilityIdentifier("sleep.consistency")
    }

    private func chart(_ nights: [InsightDay<SleepConsistency.Times>], start: Date) -> some View {
        Chart {
            ForEach(nights) { night in
                if let times = night.value {
                    let x = PlottableValue.value("Aufwachtag", insightDayCenter(night.date))
                    PointMark(x: x, y: .value("Bettzeit", plotMinute(times.bedtime)))
                        .symbol {
                            Capsule().fill(Theme.sleep).frame(width: 10, height: 4)
                        }
                        .accessibilityLabel("Bettzeit \(Format.shortDate(night.date))")
                        .accessibilityValue(Format.clock(times.start))
                    PointMark(x: x, y: .value("Aufwachzeit", plotMinute(times.wake)))
                        .symbol {
                            Capsule().strokeBorder(Theme.textSecondary, lineWidth: 1).frame(width: 10, height: 5)
                        }
                        .accessibilityLabel("Aufwachen \(Format.shortDate(night.date))")
                        .accessibilityValue(Format.clock(times.end))
                }
            }
        }
        .insightDateAxis(from: start, through: end, stride: 3)
        .chartYScale(domain: 0...1440)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 360, 720, 1080, 1440]) { tick in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let minute = tick.as(Int.self) {
                        Text(String(format: "%02d:00", (minute / 60 + 12) % 24))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .frame(height: 168)
        .accessibilityLabel("Bett- und Aufwachzeiten über 14 Nächte")
        .accessibilityIdentifier("sleep.consistency.chart")
    }

    private func plotMinute(_ minute: Int) -> Int { (minute + 720) % 1440 }
}
