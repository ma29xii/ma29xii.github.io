import SwiftUI

struct StepsDetail: View {
    @Environment(DataHub.self) private var hub
    let snapshot: DashboardDay
    let hours: [HourlyMetrics]

    var body: some View {
        let points = hours.compactMap { hour in
            hour.steps.map { HealthChartPoint(date: hour.start, value: $0) }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                if hub.isSample { SampleDataBadge() }
                DashboardCard {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        DashboardHeading(title: Format.dayTitle(snapshot.day.date))
                        Text(snapshot.day.steps.map { Format.number($0) } ?? "Keine Messung")
                            .font(.formaBigNumber)
                            .formaNumberTransition(snapshot.day.steps ?? 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s4)
                }
                HourlyValueChart(title: "Schritte pro Stunde", points: points, color: Theme.strain,
                                 maximum: max(100, (points.map(\.value).max() ?? 0) * 1.1),
                                 valueText: { Format.number($0) })
                DailyHistoryChart(title: "Schritte pro Tag",
                                  points: (snapshot.history + [snapshot.day]).compactMap { day in
                    day.steps.map { HealthChartPoint(date: day.date, value: $0) }
                }, color: Theme.strain, valueText: { Format.number($0) }, anchor: snapshot.day.date)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .dashboardScreen()
        .navigationTitle("Schritte")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Karten unter dem Today-Kopf. Kopf und Kennzahlen (mit Schritten) bleiben immer sichtbar.
enum TodayTile: String, TileKind {
    case coach, healthMonitor, stress, energy, weekly, activities, metrics

    var id: String { rawValue }
    var title: String {
        switch self {
        case .coach: "Coach"
        case .healthMonitor: "Health Monitor"
        case .stress: "Stress Monitor"
        case .energy: "Energie"
        case .weekly: "Wochenrückblick"
        case .activities: "Mein Tag"
        case .metrics: "Schritte"
        }
    }
    var systemImage: String {
        switch self {
        case .coach: "sparkle"
        case .healthMonitor: "heart.text.square"
        case .stress: "gauge.with.dots.needle.33percent"
        case .energy: "bolt.fill"
        case .weekly: "calendar"
        case .activities: "list.bullet"
        case .metrics: "figure.walk"
        }
    }
    var summary: String { title }
    static var requiredVisible: Set<Self> { [.metrics] }
    static func storedKinds(for id: String) -> [Self] { Self(rawValue: id).map { [$0] } ?? [] }
}
