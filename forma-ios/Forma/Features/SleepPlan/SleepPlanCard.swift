import SwiftUI

struct SleepPlanCard: View {
    @Environment(DataHub.self) private var hub
    let day: DayMetrics
    let history: [DayMetrics]

    var body: some View {
        SleepPlanLink(store: FoodSettings.store(isSample: hub.isSample),
                      sleepNeed: SleepPlanner.sleepNeed(today: day, history: history))
            .id(hub.isSample)
    }
}

private struct SleepPlanLink: View {
    @AppStorage private var savedPlan: Data
    let fallback: SleepPlanner
    let sleepNeed: TimeInterval

    init(store: UserDefaults, sleepNeed: TimeInterval) {
        _savedPlan = AppStorage(wrappedValue: Data(), SleepPlanner.storageKey, store: store)
        fallback = SleepPlanner(workdayWake: CoachNotifier.wakeMinutes(in: store))
        self.sleepNeed = sleepNeed
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let plan = SleepPlanner.restore(savedPlan, fallback: fallback)
            let window = plan.nextWindow(after: context.date, sleepNeed: sleepNeed)
            NavigationLink {
                SleepPlanView(savedPlan: $savedPlan, fallback: fallback, sleepNeed: sleepNeed)
            } label: {
                SleepPlanSummary(title: "Schlafplan", window: window, calendar: .forma)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Schlafplan")
            .accessibilityValue(SleepPlanTimes.spoken(window))
            .accessibilityIdentifier("sleepplan.card")
        }
    }
}
