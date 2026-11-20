import Foundation
import SwiftData
import WidgetKit

/// Gleicht das Wasser-Widget (App Group) mit dem Wassertagebuch in SwiftData ab.
@MainActor
enum WaterWidgetSync {
    nonisolated static func missing<Key: Hashable>(_ pending: [WaterWidgetEvent], existing: Set<Key>,
                                                    identifiedBy key: KeyPath<WaterWidgetEvent, Key>) -> [WaterWidgetEvent] {
        pending.filter { !existing.contains($0[keyPath: key]) }
    }

    /// Übernimmt wartende Gläser, veröffentlicht den Tagesstand fürs Widget und lädt es neu.
    /// Nicht in der Vorschau und nicht im UI-Test. Bei einem Fehler bleiben die Gläser für den nächsten Versuch liegen.
    static func sync(in context: ModelContext, enabled: Bool, store: WaterWidgetStore = .shared,
                     now: Date = .now, calendar: Calendar = .autoupdatingCurrent,
                     defaults: UserDefaults = .standard) {
        guard enabled, !FormaApp.isUITest else { return }
        var importedEvents: [WaterWidgetEvent]?
        do {
            let pending = try store.pendingEntries()
            if !pending.isEmpty {
                let existing = try context.fetch(FetchDescriptor<FoodWaterEntry>(
                    predicate: #Predicate { $0.widgetEventID != nil }))
                let knownIDs = Set(existing.compactMap(\.widgetEventID))
                let new = missing(pending, existing: knownIDs, identifiedBy: \.id)
                if !new.isEmpty {
                    try FoodEntry.saveChange(in: context) {
                        for event in new {
                            context.insert(FoodWaterEntry(date: event.date,
                                                          milliliters: WaterWidgetStore.glassMilliliters,
                                                          widgetEventID: event.id))
                        }
                    }
                }
            }
            importedEvents = pending
        } catch {
            // App Group nicht erreichbar oder Import fehlgeschlagen: später erneut versuchen.
        }
        do {
            guard let day = calendar.dateInterval(of: .day, for: now) else { return }
            let start = day.start
            let end = day.end
            let today = try context.fetch(FetchDescriptor<FoodWaterEntry>(
                predicate: #Predicate { $0.date >= start && $0.date < end }))
            let total = today.reduce(0) { $0 + $1.milliliters }
            let stored = defaults.double(forKey: FoodSettings.waterGoalKey)
            let goal = WaterWidgetStore.goalRange.contains(stored) ? stored : WaterWidgetStore.defaultGoalMilliliters
            WaterReminderNotifications.refresh(goal: goal, total: total, measuredAt: now,
                                               calendar: calendar, defaults: defaults)
            guard let pending = importedEvents else { return }
            try store.publish(milliliters: total, goalMilliliters: goal, including: pending, at: now, calendar: calendar)
            try store.acknowledge(pending)
            WidgetCenter.shared.reloadTimelines(ofKind: WaterWidgetStore.widgetKind)
        } catch {
            // App Group nicht erreichbar oder Speichern fehlgeschlagen: nichts verlieren, später erneut versuchen.
        }
    }
}
