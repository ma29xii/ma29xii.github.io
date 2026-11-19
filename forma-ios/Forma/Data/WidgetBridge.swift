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
            if changed || invalidateTimeline { reload(all: invalidateTimeline && snapshot == nil) }
            return true
        } catch {
            // Die Lesefreigabe kann bereits widerrufen sein, auch wenn sich die Datei nicht löschen ließ.
            reload(all: invalidateTimeline && snapshot == nil)
            return false
        }
    }

    private static func reload(all: Bool) {
        if all { WidgetCenter.shared.reloadAllTimelines() }
        else { WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind) }
    }
}
