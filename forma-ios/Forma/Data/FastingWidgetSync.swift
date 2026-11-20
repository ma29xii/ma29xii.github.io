import Foundation
import SwiftData
import WidgetKit

@MainActor
enum FastingWidgetSync {
    static func sync(in context: ModelContext, planHours: Double, action: FastingWidgetStore.Event? = nil,
                     store: FastingWidgetStore = .shared) throws {
        if store.directory == nil {
            // Die App kann auch ohne App Group weiterhin Fasten im eigenen Speicher verwalten.
            if let action { _ = try apply([], action: action, in: context) }
            return
        }

        var saved = false
        do {
            let changed = try store.update { state in
                let imported = try apply(state.pending, action: action, in: context)
                // Das Widget muss ein noch wartendes Fasten weiterhin beenden können.
                let widgetFastIsPending = state.active.map { imported.pending.contains(.start($0)) } ?? false
                if !widgetFastIsPending { state.active = imported.active }
                state.planHours = FoodSettings.fastRange.contains(planHours) ? planHours : FastingWidgetStore.defaultPlanHours
                state.pending = imported.pending
                saved = true
            }
            if changed { WidgetCenter.shared.reloadTimelines(ofKind: FastingWidgetStore.widgetKind) }
        } catch where saved {
            // SwiftData ist bereits aktuell. Ein erneuter Import derselben Ereignisse ist sicher.
        }
    }

    private static func apply(
        _ pending: [FastingWidgetStore.Event], action: FastingWidgetStore.Event?, in context: ModelContext
    ) throws -> (active: FastingAttributes?, pending: [FastingWidgetStore.Event]) {
        let events = pending + (action.map { [$0] } ?? [])
        let descriptor = FetchDescriptor<FoodFast>(predicate: #Predicate { $0.end == nil },
                                                   sortBy: [SortDescriptor(\.start, order: .reverse)])
        var openFasts = try context.fetch(descriptor)
        var remaining: [FastingWidgetStore.Event] = []
        if let earliest = events.lazy.map(\.startDate).min() {
            let recorded = try context.fetch(FetchDescriptor<FoodFast>(predicate: #Predicate { $0.start >= earliest }))
            var knownStarts = Set(recorded.map(\.start))
            let endingStarts = Set(events.compactMap { event -> Date? in
                if case .end(let start, _) = event { return start }
                return nil
            })
            try FoodEntry.saveChange(in: context) {
                for (index, event) in events.enumerated() {
                    switch event {
                    case .start(let session):
                        guard !knownStarts.contains(session.start) else { continue }
                        // Abgeschlossene Sitzungen lassen sich auch bei einem anderen laufenden Fasten importieren.
                        let hasContinuingFast = openFasts.contains { !endingStarts.contains($0.start) }
                        guard endingStarts.contains(session.start) || !hasContinuingFast else {
                            if index < pending.count { remaining.append(event) }
                            continue
                        }
                        let fast = FoodFast(start: session.start, targetHours: session.targetHours)
                        knownStarts.insert(session.start)
                        context.insert(fast)
                        openFasts.append(fast)
                    case .end(let start, let end):
                        guard let fastIndex = openFasts.firstIndex(where: { $0.start == start }) else {
                            if !knownStarts.contains(start), index < pending.count { remaining.append(event) }
                            continue
                        }
                        let fast = openFasts.remove(at: fastIndex)
                        fast.end = max(start, end)
                    }
                }
            }
        }
        let active = openFasts.first.map { FastingAttributes(start: $0.start, targetHours: $0.targetHours) }
        return (active, remaining)
    }
}
