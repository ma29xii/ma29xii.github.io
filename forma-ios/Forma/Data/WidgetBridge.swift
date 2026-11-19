import Foundation
import WidgetKit

@MainActor
enum WidgetBridge {
    nonisolated static func snapshot(for dashboard: DashboardDay, checkedAt: Date, calendar: Calendar) -> WidgetSnapshot? {
        WidgetSnapshot(recovery: dashboard.recovery, strain: dashboard.strain, sleep: dashboard.sleepScore,
                       updatedAt: checkedAt, day: dashboard.day.date, calendar: calendar)
    }

    static func publish(_ snapshot: WidgetSnapshot?, invalidateTimeline: Bool = false) {
        let changed = (try? WidgetSnapshotStore.shared.replace(with: snapshot)) == true
        if changed || invalidateTimeline {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
        }
    }
}
