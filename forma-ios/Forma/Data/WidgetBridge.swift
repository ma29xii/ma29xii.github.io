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

    /// Tageswerte für Health Age, Schlaf, Schritte, Energie und Körpersignale. `nil`, wenn heute noch nichts gemessen wurde.
    nonisolated static func daySnapshot(
        days: [DayMetrics], person: PersonInfo, formaSessions: [(start: Date, minutes: Double)],
        sleepNeed: TimeInterval?, bedtime: Date?, updatedAt: Date, calendar: Calendar
    ) -> DayWidgetSnapshot? {
        let today = calendar.startOfDay(for: updatedAt)
        guard let day = days.last(where: { calendar.isDate($0.date, inSameDayAs: today) }) else { return nil }
        let dashboard = DashboardDay(day: day, history: days.filter { $0.date < day.date })
        let goal = StepGoal.target(on: day.date, history: dashboard.history, recovery: dashboard.recovery,
                                   sleepScore: dashboard.sleepScore,
                                   sleepDebt: ScoreEngine.sleepDebt(history: dashboard.history),
                                   strainTarget: dashboard.recovery.map { ScoreEngine.target(recovery: $0) },
                                   calendar: calendar)
        var healthAge: Double?, age: Double?
        let strength = BodyAge.strengthMinutes(days: days, formaSessions: formaSessions, now: updatedAt)
        if case .ready(let result) = BodyAge.evaluate(days: days, person: person, strength: strength, now: updatedAt) {
            healthAge = result.bodyAge
            age = result.age
        }
        let signal = IllnessSignal.evaluate(day: day, history: dashboard.history)
        let asleep = (day.sleep?.asleep ?? 0) > 0 ? day.sleep?.asleep : nil
        let snapshot = DayWidgetSnapshot(
            updatedAt: updatedAt, day: today, healthAge: healthAge, chronologicalAge: age,
            steps: day.steps.flatMap { $0.isFinite ? Int($0.rounded()) : nil }, stepGoal: goal,
            sleepMinutes: asleep.map { Int(($0 / 60).rounded()) },
            sleepNeedMinutes: sleepNeed.map { Int(($0 / 60).rounded()) },
            sleepScore: dashboard.sleepScore, bedtime: bedtime,
            activeEnergy: day.activeEnergy.flatMap { $0.isFinite ? Int($0.rounded()) : nil }, strain: dashboard.strain,
            signalLevel: signal?.level.rawValue, signalTitles: signal?.flagged.map(\.kind.title))
        return snapshot.hasValues ? snapshot : nil
    }

    static func publishDay(_ snapshot: DayWidgetSnapshot?) {
        do {
            if try DayWidgetSnapshotStore.shared.replace(with: snapshot) { reloadDayWidgets() }
        } catch {
            reloadDayWidgets()
        }
    }

    private static func reloadDayWidgets() {
        DayWidgetSnapshotStore.kinds.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
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
