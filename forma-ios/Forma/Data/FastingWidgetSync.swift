import Foundation
import SwiftData
import WidgetKit

@MainActor
enum FastingWidgetSync {
    static func sync(in context: ModelContext, planHours: Double, action: FastingWidgetStore.Event? = nil,
                     store: FastingWidgetStore = .shared) throws {
        if store.directory == nil {
            // Die App kann auch ohne App Group weiterhin Fasten im eigenen Speicher verwalten.
            if let action { _ = try apply([action], in: context) }
            return
        }

        var saved = false
        do {
            let changed = try store.update { state in
                let events = state.pending + (action.map { [$0] } ?? [])
                state.active = try apply(events, in: context)
                state.planHours = FoodSettings.fastRange.contains(planHours) ? planHours : FastingWidgetStore.defaultPlanHours
                state.pending.removeAll()
                saved = true
            }
            if changed { WidgetCenter.shared.reloadTimelines(ofKind: FastingWidgetStore.widgetKind) }
        } catch where saved {
            // SwiftData ist bereits aktuell. Ein erneuter Import derselben Ereignisse ist sicher.
        }
    }

    private static func apply(_ events: [FastingWidgetStore.Event], in context: ModelContext) throws -> FastingAttributes? {
        let descriptor = FetchDescriptor<FoodFast>(predicate: #Predicate { $0.end == nil },
                                                   sortBy: [SortDescriptor(\.start, order: .reverse)])
        var openFasts = try context.fetch(descriptor)
        if let earliest = events.lazy.map(\.startDate).min() {
            let recorded = try context.fetch(FetchDescriptor<FoodFast>(predicate: #Predicate { $0.start >= earliest }))
            var knownStarts = Set(recorded.map(\.start))
            try FoodEntry.saveChange(in: context) {
                for event in events {
                    switch event {
                    case .start(let session):
                        guard openFasts.isEmpty, knownStarts.insert(session.start).inserted else { continue }
                        let fast = FoodFast(start: session.start, targetHours: session.targetHours)
                        context.insert(fast)
                        openFasts.append(fast)
                    case .end(let start, let end):
                        guard let index = openFasts.firstIndex(where: { $0.start == start }) else { continue }
                        let fast = openFasts.remove(at: index)
                        fast.end = max(start, end)
                    }
                }
            }
        }
        return openFasts.first.map { FastingAttributes(start: $0.start, targetHours: $0.targetHours) }
    }
}
