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
