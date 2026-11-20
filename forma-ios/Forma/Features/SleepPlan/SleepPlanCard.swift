import SwiftUI

struct SleepPlanCard: View {
    @Environment(DataHub.self) private var hub

    var body: some View {
        SleepPlanLink(store: FoodSettings.store(isSample: hub.isSample),
                      sleepNeed: hub.measuredSleepNeed)
            .id(hub.isSample)
    }
}

private struct SleepPlanLink: View {
    @AppStorage private var savedPlan: Data
    let store: UserDefaults
    let fallback: SleepPlanner
    let sleepNeed: TimeInterval?

    init(store: UserDefaults, sleepNeed: TimeInterval?) {
        _savedPlan = AppStorage(wrappedValue: Data(), SleepPlanner.storageKey, store: store)
        self.store = store
        fallback = SleepPlanner.fallback(in: store)
        self.sleepNeed = sleepNeed
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let plan = SleepPlanner.restore(savedPlan, fallback: fallback)
            let window = plan.nextWindow(after: context.date, sleepNeed: sleepNeed)
            let wake = window?.wake ?? plan.nextWake(after: context.date)
            NavigationLink {
                SleepPlanView(store: store)
            } label: {
                SleepPlanSummary(title: "Schlafplan", window: window, calendar: .forma, wake: wake)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Schlafplan")
            .accessibilityValue(SleepPlanTimes.spoken(window, wake: wake))
            .accessibilityIdentifier("sleepplan.card")
        }
    }
}
