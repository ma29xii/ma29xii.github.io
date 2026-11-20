import SwiftData
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
    case coach, readiness, bodySignals, healthMonitor, stress, energy, food, weekly, metrics, sleepPlan, hydration
    case sleepDebt, calmTime, streak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coach: "Coach"
        case .readiness: "Bereit für"
        case .bodySignals: "Körpersignale"
        case .sleepDebt: "Schlafschuld"
        case .calmTime: "Erholte Zeit"
        case .streak: "Serie"
        case .healthMonitor: "Health Monitor"
        case .stress: "Stress Monitor"
        case .energy: "Energie"
        case .food: "Heutiges Essen"
        case .weekly: "Wochenrückblick"
        case .metrics: "Schritte"
        case .sleepPlan: "Schlafplan"
        case .hydration: "Wasser"
        }
    }
    var systemImage: String {
        switch self {
        case .coach: "sparkle"
        case .readiness: "figure.run"
        case .bodySignals: "thermometer.medium"
        case .sleepDebt: "bed.double"
        case .calmTime: "leaf"
        case .streak: "flame"
        case .healthMonitor: "heart.text.square"
        case .stress: "gauge.with.dots.needle.33percent"
        case .energy: "bolt.fill"
        case .food: "fork.knife"
        case .weekly: "calendar"
        case .metrics: "figure.walk"
        case .sleepPlan: "moon.stars"
        case .hydration: "drop.fill"
        }
    }
    var summary: String { title }
    /// Die neuen schlauen Kacheln sind bis auf „Bereit für“ und „Körpersignale“ zunächst ausgeblendet.
    static var defaultHidden: Set<Self> { [.sleepDebt, .calmTime, .streak] }
    static var requiredVisible: Set<Self> { [.metrics] }
    static func storedKinds(for id: String) -> [Self] { Self(rawValue: id).map { [$0] } ?? [] }
}

struct TodayWaterCard: View {
    @Query private var entries: [FoodWaterEntry]
    @AppStorage(FoodSettings.waterGoalKey) private var goal = FoodSettings.defaultWaterMl

    init(day: Date) {
        let start = day.startOfDay
        let end = start.adding(days: 1)
        _entries = Query(filter: #Predicate<FoodWaterEntry> { $0.date >= start && $0.date < end })
    }

    var body: some View {
        let total = entries.reduce(0) { $0 + $1.milliliters }
        let target = FoodSettings.waterRange.contains(goal) ? goal : FoodSettings.defaultWaterMl
        let value = "\(Format.number(total)) von \(Format.number(target)) ml"
        NavigationLink {
            FoodWaterView()
        } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Label("Wasser", systemImage: "drop.fill")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.strain)
                    Text(value).font(.formaRowTitle).foregroundStyle(Theme.textPrimary)
                    MetricScale(value: total / target * 100, tint: Theme.strain)
                        .frame(height: 10)
                        .accessibilityHidden(true)
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Wasser")
        .accessibilityValue(value)
        .accessibilityIdentifier("today.hydration")
    }
}

struct TodayFoodCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var entries: [FoodEntry]
    @AppStorage("forma.birthYear") private var birthYear = 0
    @AppStorage("forma.sex") private var sex = BiologicalSex.unknown.rawValue
    @AppStorage(FoodSettings.bodyWeightKey) private var weight = 0.0
    @AppStorage(FoodGoal.heightKey) private var height = 0.0
    let day: DayMetrics

    init(day: DayMetrics) {
        self.day = day
        let start = day.date.startOfDay
        let end = start.adding(days: 1)
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= start && $0.date < end })
    }

    var body: some View {
        let values = entries.map(\.energy)
        let sum = FoodSum(values)
        let goal = FoodGoal.forDay(day.date, birthYear: birthYear, weight: weight, height: height, sex: sex,
                                   activeEnergy: day.activeEnergy).target
        let remainder = sum.remaining(of: goal)
        Button {
            app.selectTab(.food)
        } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    DashboardHeading(title: "Heutiges Essen")
                    Text("\(FoodAmountText.text(values)) kcal")
                        .font(.formaDisplay)
                        .foregroundStyle(Theme.textPrimary)
                    if let remainder {
                        Text("\(FoodText.number(abs(remainder))) kcal \(remainder < 0 ? "über Ziel" : "übrig")")
                            .font(.formaCaptionStrong)
                            .foregroundStyle(remainder < 0 ? Theme.older : Theme.textSecondary)
                    }
                    if goal > 0 {
                        MetricScale(value: 100 * sum.known / goal, tint: remainder.map { $0 < 0 } == true ? Theme.older : Theme.younger)
                            .frame(height: 12)
                            .accessibilityHidden(true)
                    }
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s2))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: Space.s2))
                    layout {
                        macro("Protein", entries.map(\.protein), tint: Theme.younger)
                        macro("Kohlenhydrate", entries.map(\.carbohydrates), tint: Theme.warning)
                        macro("Fett", entries.map(\.fat), tint: Theme.sleep)
                    }
                }
                .padding(Space.s4)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Öffnet Food")
        .accessibilityIdentifier("today.food")
    }

    private func macro(_ title: String, _ values: [Double?], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title)
                .font(.formaMicro)
                .foregroundStyle(Theme.textSecondary)
            Text("\(FoodAmountText.text(values)) g")
                .font(.formaValue)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
