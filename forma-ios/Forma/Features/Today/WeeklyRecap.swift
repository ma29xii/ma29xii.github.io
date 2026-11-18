import SwiftUI

struct WeeklyRecapLink: View {
    let period: WeeklyInsight.Period

    var body: some View {
        InsightLink(title: "Wochenrückblick", subtitle: Self.span(period.currentStart, days: period.dayCount),
                    icon: "calendar", tint: Theme.textSecondary, identifier: "today.weekly.open") {
            WeeklyRecapDetail(period: period)
        }
    }

    static func span(_ first: Date, days: Int) -> String {
        "\(Format.shortDate(first))–\(Format.shortDate(first.adding(days: days - 1)))"
    }
}

private struct WeeklyRecapDetail: View {
    let period: WeeklyInsight.Period
    @Environment(DataHub.self) private var hub
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        let history = InsightHistory(hub.dashboardHistory(recent: hub.days))
        let rows = WeeklyInsight.rows(period: period, history: history)
        InsightPage(title: "Wochenrückblick") {
            VStack(alignment: .leading, spacing: Space.s1) {
                DashboardHeading(title: "Tagesdurchschnitt")
                Text("\(WeeklyRecapLink.span(period.currentStart, days: period.dayCount)) im Vergleich zu \(WeeklyRecapLink.span(period.previousStart, days: period.dayCount))")
                    .font(.formaRowTitle)
                if period.dayCount == 6 {
                    Text("Am Montag kommt der Sonntag dazu.")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                } else if !hub.isSample, let updated = hub.lastUpdate, updated < period.currentStart.adding(days: 7) {
                    Text("Abgerufen am \(Format.shortDate(updated)). Sonntagswerte können noch unvollständig sein.")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let scale = max(1, row.current?.mean ?? 0, row.previous?.mean ?? 0)
                DashboardCard {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        DashboardHeading(title: row.metric.title)
                        reading(row.current, metric: row.metric, title: "Rückblick", scale: scale, highlighted: true)
                        reading(row.previous, metric: row.metric, title: "Vorwoche", scale: scale, highlighted: false)
                    }
                    .padding(Space.s4)
                }
                .opacity(revealed ? 1 : (reduceMotion ? 1 : 0.65))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.26).delay(Double(index) * 0.035), value: revealed)
                .accessibilityIdentifier("today.weekly.\(row.metric.rawValue)")
            }
        }
        .onAppear { revealed = true }
    }

    private func reading(_ value: InsightAverage?, metric: WeeklyInsight.Metric, title: String,
                         scale: Double, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: Space.s2)
                Text(value.map { metric.formatted($0.mean) } ?? "Keine Messung")
                    .font(value == nil ? .formaCaption : .formaValue)
                    .multilineTextAlignment(.trailing)
                    .formaNumberTransition(value?.mean ?? 0)
            }
            if let value {
                ProgressLine(fraction: reduceMotion || revealed ? value.mean / scale : 0,
                             color: highlighted ? metric.tint : Theme.textSecondary, height: 4)
                    .accessibilityHidden(true)
                Text("\(value.count) von \(period.dayCount) Tagen")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .formaNumberTransition(Double(value.count))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension WeeklyInsight.Metric {
    var title: String {
        switch self {
        case .sleep: "Schlafdauer"
        case .recovery: "Recovery"
        case .strain: "Strain"
        case .steps: "Schritte"
        case .hrv: "HRV"
        }
    }

    var tint: Color {
        switch self {
        case .sleep: Theme.sleep
        case .recovery: Theme.younger
        case .strain: DashboardRing.tint(kind: .strain, value: nil)
        case .steps, .hrv: Theme.textPrimary
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .sleep: Format.duration(value)
        case .recovery: "\(Format.number(value)) %"
        case .strain, .steps: Format.number(value)
        case .hrv: "\(Format.number(value)) ms"
        }
    }
}
