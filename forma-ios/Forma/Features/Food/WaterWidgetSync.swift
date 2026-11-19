import SwiftData
import WidgetKit

/// Gleicht das Wasser-Widget (App Group) mit dem Wassertagebuch in SwiftData ab.
@MainActor
enum WaterWidgetSync {
    /// Gläser aus dem Widget, die in SwiftData noch fehlen. Ein Eintrag mit gleichem Zeitstempel und 250 ml gilt als
    /// schon übernommen; so entstehen keine Doppelten, wenn die App zwischen Speichern und Bestätigen endet.
    /// shortcut: Der Abgleich nutzt den Zeitstempel statt einer eigenen UUID im Modell; ein Feld
    /// `widgetEventID` wäre nur nötig, wenn zwei Gläser denselben Zeitstempel haben könnten.
    nonisolated static func missing(_ pending: [WaterWidgetEvent],
                                    existing: [(date: Date, milliliters: Double)]) -> [WaterWidgetEvent] {
        let known = Set(existing.filter { $0.milliliters == WaterWidgetStore.glassMilliliters }.map(\.date))
        return pending.filter { !known.contains($0.date) }
    }

    /// Übernimmt wartende Gläser, veröffentlicht den Tagesstand fürs Widget und lädt es neu.
    /// Nicht in der Vorschau und nicht im UI-Test. Bei einem Fehler bleiben die Gläser für den nächsten Versuch liegen.
    static func sync(in context: ModelContext, enabled: Bool, store: WaterWidgetStore = .shared,
                     now: Date = .now, calendar: Calendar = .autoupdatingCurrent,
                     defaults: UserDefaults = .standard) {
        guard enabled, !FormaApp.isUITest else { return }
        do {
            let pending = try store.pendingEntries()
            if let earliest = pending.map(\.date).min() {
                let existing = try context.fetch(FetchDescriptor<FoodWaterEntry>(
                    predicate: #Predicate { $0.date >= earliest }))
                let new = missing(pending, existing: existing.map { ($0.date, $0.milliliters) })
                if !new.isEmpty {
                    try FoodEntry.saveChange(in: context) {
                        for event in new {
                            context.insert(FoodWaterEntry(date: event.date, milliliters: WaterWidgetStore.glassMilliliters))
                        }
                    }
                }
            }
            guard let day = calendar.dateInterval(of: .day, for: now) else { return }
            let start = day.start
            let end = day.end
            let today = try context.fetch(FetchDescriptor<FoodWaterEntry>(
                predicate: #Predicate { $0.date >= start && $0.date < end }))
            let total = today.reduce(0) { $0 + $1.milliliters }
            let stored = defaults.double(forKey: FoodSettings.waterGoalKey)
            let goal = WaterWidgetStore.goalRange.contains(stored) ? stored : WaterWidgetStore.defaultGoalMilliliters
            try store.publish(milliliters: total, goalMilliliters: goal, including: pending, at: now, calendar: calendar)
            try store.acknowledge(pending)
            WidgetCenter.shared.reloadTimelines(ofKind: WaterWidgetStore.widgetKind)
        } catch {
            // App Group nicht erreichbar oder Speichern fehlgeschlagen: nichts verlieren, später erneut versuchen.
        }
    }
}
