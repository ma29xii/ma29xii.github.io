import Foundation
import WidgetKit

@MainActor
enum WidgetBridge {
    nonisolated static func snapshot(for dashboard: DashboardDay, checkedAt: Date, calendar: Calendar) -> WidgetSnapshot? {
        WidgetSnapshot(recovery: dashboard.recovery, strain: dashboard.strain, sleep: dashboard.sleepScore,
                       updatedAt: checkedAt, day: dashboard.day.date, calendar: calendar)
    }

    static func publish(_ snapshot: WidgetSnapshot?, invalidateTimeline: Bool = false) -> Bool {
        do {
            let changed = try WidgetSnapshotStore.shared.replace(with: snapshot)
            if changed || invalidateTimeline {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
            }
            return true
        } catch {
            // Die Lesefreigabe kann bereits widerrufen sein, auch wenn sich die Datei nicht löschen ließ.
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
            return false
        }
    }
}
