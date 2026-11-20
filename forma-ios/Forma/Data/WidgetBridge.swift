import Foundation
import WidgetKit

@MainActor
enum WidgetBridge {
    nonisolated static func snapshot(for dashboard: DashboardDay, checkedAt: Date, calendar: Calendar) -> WidgetSnapshot? {
        WidgetSnapshot(recovery: dashboard.recovery, strain: dashboard.strain, sleep: dashboard.sleepScore,
                       updatedAt: checkedAt, day: dashboard.day.date, calendar: calendar)
    }

    nonisolated static func weekSnapshot(for history: [DayMetrics], updatedAt: Date, calendar: Calendar) -> WeekWidgetSnapshot {
        let dates = Set(WeekWidgetSnapshot.dates(endingAt: updatedAt, calendar: calendar))
        let measurements = history.compactMap { day -> WeekWidgetSnapshot.Day? in
            guard dates.contains(calendar.startOfDay(for: day.date)) else { return nil }
            // Wie in der App: nur Tage davor als Vergleichsbasis.
            let dashboard = DashboardDay(day: day, history: history.filter { $0.date < day.date })
            return WeekWidgetSnapshot.Day(date: day.date, recovery: dashboard.recovery,
                                          strain: dashboard.strain, sleep: dashboard.sleepScore)
        }
        return WeekWidgetSnapshot(measurements: measurements, updatedAt: updatedAt, calendar: calendar)
    }

    static func publishWeek(_ history: [DayMetrics], updatedAt: Date, calendar: Calendar,
                            invalidateTimeline: Bool = false) {
        let snapshot = weekSnapshot(for: history, updatedAt: updatedAt, calendar: calendar)
        let storedSnapshot = snapshot.days.contains(where: \.hasMeasurements) ? snapshot : nil
        do {
            let changed = try WeekWidgetSnapshotStore.shared.replace(with: storedSnapshot)
            if changed || invalidateTimeline {
                WidgetCenter.shared.reloadTimelines(ofKind: WeekWidgetSnapshotStore.widgetKind)
            }
        } catch {
            WidgetCenter.shared.reloadTimelines(ofKind: WeekWidgetSnapshotStore.widgetKind)
        }
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
