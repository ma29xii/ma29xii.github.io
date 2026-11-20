import SwiftUI
import Charts

enum DashboardTrends {
    static func points(kind: RingKind, days: [DayMetrics], domain: ClosedRange<Date>) -> [HealthChartPoint] {
        days.filter { domain.contains($0.date) }.compactMap { day in
            let snapshot = DashboardDay(day: day, history: days)
            return snapshot.value(for: kind).map { HealthChartPoint(date: day.date, value: Double($0)) }
        }
        .sorted { $0.date < $1.date }
    }

    static func mean(points: [HealthChartPoint], minimum: Int = 4) -> Double? {
        guard !points.isEmpty, points.count >= minimum else { return nil }
        return points.reduce(0) { $0 + $1.value } / Double(points.count)
    }
}

enum RingTrendRange: String, CaseIterable, Identifiable {
    case week = "W", month = "M", halfYear = "6M"
    var id: String { rawValue }

    var caption: String {
        switch self {
        case .week: "Eine Woche"
        case .month: "Ein Monat"
        case .halfYear: "Sechs Monate"
        }
    }

    func domain(ending anchor: Date) -> ClosedRange<Date> {
        let end = anchor.startOfDay
        let boundary = end.adding(days: 1)
        let start: Date
        switch self {
        case .week:
            start = end.adding(days: -6)
        case .month, .halfYear:
            start = Calendar.forma.date(byAdding: .month, value: self == .month ? -1 : -6, to: boundary) ?? end
        }
        return min(start, end)...end
    }
}

struct RingTrendChart: View {
    let kind: RingKind
    let anchor: Date
    let days: [DayMetrics]
    let color: Color

    var body: some View {
        RingTrendCard(title: kind.title, anchor: anchor, tint: color, percentScale: true,
                      smoothLongRanges: kind == .strain,
                      valueText: { Format.number($0) + (kind == .strain ? "" : " %") }) { domain in
            DashboardTrends.points(kind: kind, days: days, domain: domain)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ring.trend")
    }
}

struct RingTrendCard: View {
    let title: String
    let anchor: Date
    let tint: Color
    var percentScale = false
    var usual: ClosedRange<Double>? = nil
    var smoothLongRanges = false
    let valueText: (Double) -> String
    let measurements: (ClosedRange<Date>) -> [HealthChartPoint]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var range = RingTrendRange.week
    @State private var expanded = false

    var body: some View {
        let domain = range.domain(ending: anchor)
        let points = measurements(domain)
        let average = DashboardTrends.mean(points: points, minimum: 1)
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Trend")
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: Space.s4) {
                            averageLabel(average)
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                            rangePicker.frame(width: 150)
                        }
                        VStack(alignment: .leading, spacing: Space.s2) {
                            averageLabel(average)
                            rangePicker
                        }
                    }
                    if !points.isEmpty {
                        chart(points, domain: domain, average: average)
                            .animation(reduceMotion ? nil : .smooth, value: range)
                        measurementList(points)
                    } else {
                        ChartEmptyState(text: "Keine Messung in diesem Zeitraum")
                    }
                }
                .padding(Space.s4)
            }
        }
    }

    private func averageLabel(_ average: Double?) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Durchschnitt").font(.formaCaption).foregroundStyle(Theme.textSecondary)
            Text(average.map(valueText) ?? "–")
                .font(.formaBigNumber)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: average ?? 0))
                .animation(reduceMotion ? nil : .snappy, value: average)
                .accessibilityIdentifier("trend.average")
        }
    }

    private var rangePicker: some View {
        Picker("Zeitraum", selection: $range) {
            ForEach(RingTrendRange.allCases) { period in
                Text(period.rawValue).accessibilityLabel(period.caption).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 44)
        .accessibilityIdentifier("trend.range")
    }

    private func chart(_ measurements: [HealthChartPoint], domain: ClosedRange<Date>, average: Double?) -> some View {
        let showsWeeklyMeans = smoothLongRanges && range == .halfYear
        let points = switch (smoothLongRanges, range) {
        case (true, .month): RingChartSeries.smoothedDays(measurements)
        case (true, .halfYear): RingChartSeries.weeklyMeans(measurements)
        default: measurements
        }
        let dateLabel = showsWeeklyMeans ? "Woche" : "Tag"
        let values = points.map(\.value) + (usual.map { [$0.lowerBound, $0.upperBound] } ?? [])
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let margin = max((high - low) * 0.12, max(abs(high), 1) * 0.03)
        let showWeekLabels = percentScale && range == .week && !typeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: Space.s1) {
            Chart {
                if let usual {
                    RectangleMark(xStart: .value("Start", domain.lowerBound),
                                  xEnd: .value("Ende", domain.upperBound.adding(days: 1)),
                                  yStart: .value("Untergrenze", usual.lowerBound),
                                  yEnd: .value("Obergrenze", usual.upperBound))
                        .foregroundStyle(tint.opacity(0.1))
                        .accessibilityHidden(true)
                }
                ForEach(RingChartSeries.segments(points, daysBetweenPoints: showsWeeklyMeans ? 7 : 1), id: \.point.date) { entry in
                    let point = entry.point
                    let date = showsWeeklyMeans
                        ? min(max(point.date.adding(days: 3), domain.lowerBound), domain.upperBound)
                        : point.date
                    let center = insightDayCenter(date)
                    LineMark(x: .value(dateLabel, center), y: .value(title, point.value),
                             series: .value("Abschnitt", entry.segment))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value(dateLabel, center), y: .value(title, point.value))
                        .symbolSize(range == .week ? 25 : range == .month ? 16 : 10)
                        .foregroundStyle(tint)
                        .annotation(position: .top, spacing: 3) {
                            if showWeekLabels {
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
                        .accessibilityHidden(true)
                }
            }
            .chartXScale(domain: domain.lowerBound...domain.upperBound.adding(days: 1))
            .chartYScale(domain: percentScale ? 0...110 : (low - margin)...(high + margin))
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .chartYAxis {
                if percentScale {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel().foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel().foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(height: 180)
            // Randdaten außerhalb der Zeichenfläche halten, damit der erste und letzte Tag vollständig sichtbar sind.
            HStack(alignment: .top, spacing: Space.s2) {
                Text(Format.shortDate(domain.lowerBound))
                Spacer(minLength: 0)
                Text(Format.shortDate(domain.upperBound))
                    .multilineTextAlignment(.trailing)
            }
            .font(.formaCaption)
            .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)-Trend, \(range.caption)" + (showsWeeklyMeans ? ", Wochenmittel" : ""))
        .accessibilityValue(average.map { "Durchschnitt \(valueText($0)), \(measurements.count) Tage mit Messung" } ?? "Keine Messung")
    }

    @ViewBuilder
    private func measurementList(_ points: [HealthChartPoint]) -> some View {
        RowDivider(inset: 0)
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: Space.s2) {
                Text("Einzelwerte").font(.formaCaptionStrong)
                Spacer(minLength: 0)
                Image(systemName: expanded ? "minus" : "plus")
                    .font(.formaCaptionStrong)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? "Ausgeklappt" : "Eingeklappt")
        .accessibilityIdentifier("trend.measurements")

        if expanded {
            LazyVStack(spacing: 0) {
                ForEach(points.reversed()) { point in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(Format.shortDate(point.date)).foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                        Text(valueText(point.value)).font(.formaCaptionStrong.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.formaCaption)
                    .padding(.vertical, Space.s2)
                    .accessibilityElement(children: .combine)
                    if point.date != points.first?.date {
                        RowDivider(inset: 0)
                    }
                }
            }
        }
    }
}

enum RingChartSeries {
    /// Glättet den Tagesverlauf über bis zu drei aufeinanderfolgende Messungen.
    static func smoothedDays(_ points: [HealthChartPoint]) -> [HealthChartPoint] {
        let valuesByDay = Dictionary(points.map { ($0.date, $0.value) }, uniquingKeysWith: { _, latest in latest })
        return points.map { point in
            let neighbors = [valuesByDay[point.date.adding(days: -1)], valuesByDay[point.date.adding(days: 1)]]
                .compactMap { $0 }
            let average = neighbors.reduce(point.value, +) / Double(neighbors.count + 1)
            return HealthChartPoint(date: point.date, value: average)
        }
    }

    /// Ein Mittelwert je Kalenderwoche mit Messungen innerhalb des gewählten Zeitraums.
    static func weeklyMeans(_ points: [HealthChartPoint]) -> [HealthChartPoint] {
        let calendar = Calendar.forma
        let weeks = Dictionary(grouping: points) { point in
            calendar.dateInterval(of: .weekOfYear, for: point.date)?.start ?? point.date
        }
        return weeks.compactMap { week, measurements in
            DashboardTrends.mean(points: measurements, minimum: 1).map { HealthChartPoint(date: week, value: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    static func segments(_ points: [HealthChartPoint], daysBetweenPoints: Int = 1) -> [(point: HealthChartPoint, segment: Int)] {
        var previous: Date?
        var segment = 0
        return points.map { point in
            if previous?.adding(days: daysBetweenPoints) != point.date { segment += 1 }
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
        let endDay = end.startOfDay
        let window = endDay.adding(days: -54)...endDay
        let recent = history.filter { window.contains($0.date) }
        let path = StrainInsight.path(endingAt: end, history: InsightHistory(recent))
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

    // InsightHistory bereinigt auch die Schlafphasen. Nur das angezeigte Fenster vorbereiten.
    nonisolated static func relevantDays(endingAt end: Date, history: [DayMetrics]) -> [DayMetrics] {
        let day = end.startOfDay
        let window = day.adding(days: -13)..<day.adding(days: 1)
        return history.filter { window.contains($0.date) }
    }

    var body: some View {
        let recent = Self.relevantDays(endingAt: end, history: history)
        let result = SleepConsistency(endingAt: end, history: InsightHistory(recent))
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
