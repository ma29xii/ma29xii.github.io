import Charts
import SwiftUI

struct InsightLink<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let identifier: String
    var number: Double? = nil
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            DashboardCard {
                HStack(spacing: Space.s3) {
                    Image(systemName: icon)
                        .font(.body.weight(.medium))
                        .foregroundStyle(tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        DashboardHeading(title: title)
                        Text(subtitle)
                            .font(.formaBody)
                            .monospacedDigit()
                            .formaNumberTransition(number ?? 0)
                    }
                    Spacer(minLength: Space.s2)
                    Image(systemName: "chevron.right")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(Space.s4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityIdentifier(identifier)
    }
}

struct InsightPage<Content: View>: View {
    @Environment(DataHub.self) private var hub
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.gap) {
                if hub.isSample { SampleDataBadge() }
                content
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .dashboardScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StrainPathLink: View {
    let end: Date
    let history: [DayMetrics]

    private var tint: Color { DashboardRing.tint(kind: .strain, value: nil) }

    var body: some View {
        let path = StrainInsight.path(endingAt: end, history: InsightHistory(history))
        let latest = path.last?.value
        InsightLink(title: "Belastungspfad", subtitle: latest?.state.title ?? "Noch kein 7- und 28-Tage-Vergleich",
                    icon: "chart.xyaxis.line", tint: tint, identifier: "strain.path.open") {
            StrainPathDetail(path: path, end: end, tint: tint)
        }
    }
}

private struct StrainPathDetail: View {
    let path: [InsightDay<StrainInsight>]
    let end: Date
    let tint: Color
    @State private var selection: Date?

    var body: some View {
        let selected = selection.map { min(end, $0.startOfDay) }
        let date = selected ?? end
        let value = path.first { $0.date == date }?.value
        InsightPage(title: "Belastungspfad") {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if let start = path.first?.date, path.contains(where: { $0.value != nil }) {
                        chart(start: start, selected: selected)
                    }
                    DashboardHeading(title: Format.dayTitle(date))
                    Text(value?.state.title ?? "Kein Vergleich für diesen Tag")
                        .font(.formaRowTitle)
                        .foregroundStyle(value?.state == .tooMuch ? Theme.warning : Theme.textPrimary)
                    if let value {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: Space.s5) {
                                mean(value.short, days: 7, color: tint).fixedSize(horizontal: true, vertical: false)
                                mean(value.long, days: 28, color: Theme.textSecondary).fixedSize(horizontal: true, vertical: false)
                            }
                            VStack(alignment: .leading, spacing: Space.s2) {
                                mean(value.short, days: 7, color: tint)
                                mean(value.long, days: 28, color: Theme.textSecondary)
                            }
                        }
                    }
                }
                .padding(Space.s4)
            }
            Text("Geschätzter Strain abgeschlossener Tage. Aufbau beginnt über 10 % und Zu viel über 25 % über dem 28-Tage-Schnitt. Der Vergleich braucht mindestens 5 von 7 und 20 von 28 Tagen.")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func mean(_ value: InsightAverage, days: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("\(days) Tage").formaLabelStyle(color)
            Text(Format.number(value.mean, decimals: 1))
                .font(.formaBigNumber)
                .formaNumberTransition(value.mean)
            Text("\(value.count)/\(days) Tage erfasst")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
                .formaNumberTransition(Double(value.count))
        }
        .accessibilityElement(children: .combine)
    }

    private func chart(start: Date, selected: Date?) -> some View {
        Chart {
            ForEach(insightSegments(path), id: \.date) { point in
                let x = PlottableValue.value("Tag", insightDayCenter(point.date))
                let short = point.value.short.mean
                let long = point.value.long.mean
                AreaMark(x: x, yStart: .value("Untergrenze", min(short, long)),
                         yEnd: .value("Obergrenze", max(short, long)), series: .value("Band", point.segment))
                    .foregroundStyle(tint.opacity(0.16))
                LineMark(x: x, y: .value("28 Tage", long), series: .value("Verlauf", "lang-\(point.segment)"))
                    .foregroundStyle(Theme.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                LineMark(x: x, y: .value("7 Tage", short), series: .value("Verlauf", "kurz-\(point.segment)"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                PointMark(x: x, y: .value("7 Tage", short))
                    .symbolSize(point.date == selected ? 45 : 11)
                    .foregroundStyle(tint)
                PointMark(x: x, y: .value("28 Tage", long))
                    .symbolSize(point.date == selected ? 45 : 11)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let selected { insightSelectionRule(selected) }
        }
        .insightDateAxis(from: start, through: end, stride: 7)
        .chartYScale(domain: 0.0...100.0)
        .chartYAxis { insightScale([0, 50, 100]) }
        .chartXSelection(value: $selection)
        .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
        .frame(height: 168)
        .accessibilityLabel("Strain im Vergleich über 7 und 28 Tage")
        .accessibilityIdentifier("strain.path.chart")
    }
}

struct SleepConsistencyLink: View {
    let end: Date
    let history: [DayMetrics]

    var body: some View {
        let result = SleepConsistency(endingAt: end, history: InsightHistory(history))
        InsightLink(title: "Schlafkonstanz", subtitle: result.percent.map { "\($0) %" } ?? "Noch kein Vergleich",
                    icon: "moon.zzz", tint: Theme.sleep, identifier: "sleep.consistency.open",
                    number: result.percent.map(Double.init)) {
            SleepConsistencyDetail(result: result, end: end)
        }
    }
}

private struct SleepConsistencyDetail: View {
    let result: SleepConsistency
    let end: Date
    @State private var selection: Date?

    var body: some View {
        let selected = selection.map { min(end, $0.startOfDay) }
        let times = result.nights.first { $0.date == selected }?.value
        InsightPage(title: "Schlafkonstanz") {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    DashboardHeading(title: "Letzte 14 Nächte")
                    Text(result.percent.map { "\($0) %" } ?? "Noch kein Vergleich")
                        .font(result.percent == nil ? .formaRowTitle : .formaBigNumber)
                        .formaNumberTransition(Double(result.percent ?? 0))
                    Text("\(result.measured) von 14 Nächten erfasst")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .formaNumberTransition(Double(result.measured))
                    if let start = result.nights.first?.date, result.measured > 0 {
                        chart(start: start, selected: selected)
                        if let selected {
                            Text(Format.dayTitle(selected)).formaLabelStyle()
                            if let times {
                                Text("Bettzeit \(Format.clock(times.start))")
                                    .formaNumberTransition(Double(times.bedtime))
                                Text("Aufwachen \(Format.clock(times.end))")
                                    .formaNumberTransition(Double(times.wake))
                            } else {
                                Text("Keine Messung")
                            }
                        } else {
                            Label("Bettzeit", systemImage: "minus").foregroundStyle(Theme.sleep)
                            Label("Aufwachen", systemImage: "minus.rectangle").foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .font(.formaCaption)
                .padding(Space.s4)
            }
            Text("Gezählt werden Nächte, deren Bett- und Aufwachzeit jeweils höchstens eine Stunde von deinem häufigsten Rhythmus abweichen. Dafür brauchst du mindestens vier gemessene Nächte.")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func chart(start: Date, selected: Date?) -> some View {
        Chart {
            ForEach(result.nights) { night in
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
            if let selected { insightSelectionRule(selected) }
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
        .chartXSelection(value: $selection)
        .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
        .frame(height: 168)
        .accessibilityLabel("Bett- und Aufwachzeiten über 14 Nächte")
        .accessibilityIdentifier("sleep.consistency.chart")
    }

    private func plotMinute(_ minute: Int) -> Int { (minute + 720) % 1440 }
}

struct StressTrendLink: View {
    let end: Date
    let history: [DayMetrics]

    var body: some View {
        let trend = StressInsight.trend(endingAt: end, history: InsightHistory(history))
        let latest = trend.last?.value
        InsightLink(title: "Langzeit-Stress", subtitle: latest.map { "\(Format.number($0.mean, decimals: 1)) von 3 · 7 Tage" }
                    ?? "Noch kein 7-Tage-Schnitt", icon: "waveform.path", tint: Theme.younger,
                    identifier: "stress.trend.open", number: latest?.mean) {
            StressTrendDetail(trend: trend, end: end)
        }
    }
}

private struct StressTrendDetail: View {
    let trend: [InsightDay<InsightAverage>]
    let end: Date
    @State private var selection: Date?

    var body: some View {
        let selected = selection.map { min(end, $0.startOfDay) }
        let date = selected ?? end
        let value = trend.first { $0.date == date }?.value
        InsightPage(title: "Langzeit-Stress") {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if let start = trend.first?.date, trend.contains(where: { $0.value != nil }) {
                        chart(start: start, selected: selected)
                    }
                    DashboardHeading(title: "7-Tage-Schnitt bis \(Format.shortDate(date))")
                    Text(value.map { "\(Format.number($0.mean, decimals: 1)) von 3" } ?? "Kein Schnitt für diesen Tag")
                        .font(value == nil ? .formaRowTitle : .formaBigNumber)
                        .formaNumberTransition(value?.mean ?? 0)
                    if let value {
                        Text("\(value.count) von 7 Tagen mit Messung")
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .formaNumberTransition(Double(value.count))
                    }
                }
                .padding(Space.s4)
            }
            Text("Schätzung aus HRV und Ruhepuls im Vergleich zu deinem persönlichen Verlauf. Der Schnitt berücksichtigt abgeschlossene Tage und braucht mindestens vier vergleichbare Tage in einer Woche.")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func chart(start: Date, selected: Date?) -> some View {
        Chart {
            ForEach(insightSegments(trend), id: \.date) { point in
                let x = PlottableValue.value("Tag", insightDayCenter(point.date))
                let y = PlottableValue.value("7-Tage-Stress", point.value.mean)
                LineMark(x: x, y: y, series: .value("Abschnitt", point.segment))
                    .foregroundStyle(Theme.younger)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                PointMark(x: x, y: y)
                    .symbolSize(point.date == selected ? 45 : 11)
                    .foregroundStyle(Theme.younger)
            }
            if let selected { insightSelectionRule(selected) }
        }
        .insightDateAxis(from: start, through: end, stride: 7)
        .chartYScale(domain: 0.0...3.0)
        .chartYAxis { insightScale([0, 1, 2, 3]) }
        .chartXSelection(value: $selection)
        .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
        .frame(height: 168)
        .accessibilityLabel("Geschätzter Stress als gleitender Schnitt über 7 Tage")
        .accessibilityIdentifier("stress.trend.chart")
    }
}
