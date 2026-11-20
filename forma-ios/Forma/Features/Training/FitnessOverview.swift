import SwiftUI

struct FitnessActivityHistory: View {
    let workouts: [WorkoutSummary]
    var title: String? = nil
    var limit: Int? = nil

    var body: some View {
        let shown = limit.map { Array(workouts.prefix($0)) } ?? workouts
        let groups = Dictionary(grouping: shown) { Calendar.forma.startOfDay(for: $0.start) }
        VStack(alignment: .leading, spacing: Space.s3) {
            if let title { DashboardHeading(title: title) }
            if shown.isEmpty {
                DashboardCard { DashboardEmpty(title: "Keine Aktivitäten erfasst") }
            }
            ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                VStack(alignment: .leading, spacing: Space.s2) {
                    DashboardHeading(title: day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.german)))
                    DashboardCard {
                        ForEach(Array((groups[day] ?? []).enumerated()), id: \.element.id) { index, activity in
                            if index > 0 { RowDivider() }
                            NavigationLink(value: TrainingRoute.activity(activity.id)) {
                                activityRow(activity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if limit.map({ workouts.count > $0 }) == true {
                NavigationLink("Alle Aktivitäten", value: TrainingRoute.activities(cardioOnly: false))
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .accessibilityIdentifier("fitness.activities")
    }

    private func activityRow(_ activity: WorkoutSummary) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: activity.isStrength ? "dumbbell" : "figure.walk")
                .font(.formaValue)
                .foregroundStyle(activity.isStrength ? Theme.strain : Theme.younger)
                .frame(width: 32, height: 32)
                .background(Theme.plate, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(activity.name).font(.formaRowTitle)
                Text(activity.start.formatted(.dateTime.hour().minute().locale(.german)))
                    .font(.formaCaption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Space.s2)
            Text(Format.duration(activity.duration))
                .font(.formaValue)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct FitnessActivityDetail: View {
    let activity: WorkoutSummary

    var body: some View {
        InsightPage(title: activity.name) {
            DashboardCard {
                MetricRow(title: "Beginn", value: activity.start.formatted(.dateTime.day().month().hour().minute().locale(.german)))
                RowDivider()
                MetricRow(title: "Dauer", value: Format.duration(activity.duration))
                RowDivider()
                MetricRow(title: "Aktive Energie", value: activity.energy.map { Format.number($0) + " kcal" } ?? "–")
            }
        }
    }
}

enum FitnessCardio {
    /// Bekannte Ausdaueraktivitäten aus Google Health. Unklassifizierte Einträge bleiben im Aktivitätsverlauf.
    private static let types: Set<String> = [
        "AEROBIC_WORKOUT", "ASSAULT_BIKE", "BACKPACKING", "BIKING", "CARDIO_WORKOUT", "CROSS_COUNTRY_SKI",
        "ELLIPTICAL", "HIKING", "INCLINE_RUN", "INDOOR_BIKING", "ROWING", "ROWING_MACHINE", "RUNNING",
        "STAIR_CLIMBING", "SWIMMING", "TREADMILL", "WALKING"
    ]
    private static let legacyNames: Set<String> = ["lauf", "laufen", "run", "running", "spaziergang", "gehen", "walk", "walking"]

    static func includes(_ workout: WorkoutSummary) -> Bool {
        guard !workout.isStrength else { return false }
        if let type = workout.activityType { return types.contains(type) }
        return legacyNames.contains(workout.name.lowercased())
    }

    static func energy(_ workouts: [WorkoutSummary]) -> (value: Double, complete: Bool)? {
        let known = workouts.compactMap(\.energy).filter { $0.isFinite && $0 >= 0 }
        guard !known.isEmpty else { return nil }
        return (known.reduce(0, +), known.count == workouts.count)
    }
}

struct FitnessMetricGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2, alignment: .top),
                                    count: typeSize.isAccessibilitySize ? 1 : 2), spacing: Space.s2) {
                content
            }
        }
    }
}

struct FitnessMetricCard: View {
    let title: String
    let value: String
    let tint: Color
    let bars: [Double?]

    var body: some View {
        let maximum = bars.compactMap { $0 }.max() ?? 0
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title)
                    .font(.formaCaptionStrong)
                    .foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(.formaValue)
                    .foregroundStyle(Theme.textPrimary)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(bars.indices, id: \.self) { index in
                        let amount = bars[index].map { value in
                            value.isFinite && maximum > 0 ? min(1, max(0, value / maximum)) : 0
                        } ?? 0
                        Capsule()
                            .fill(bars[index] == nil ? Theme.track : tint.opacity(index == bars.indices.last ? 0.95 : 0.60))
                            .frame(height: 2 + 22 * amount)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 24, alignment: .bottom)
                .accessibilityHidden(true)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }
}
