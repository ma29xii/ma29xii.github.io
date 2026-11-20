import ActivityKit
import Foundation
import SwiftData

@MainActor
enum FastingActivity {
    private typealias Fasting = Activity<FastingAttributes>
    private static var tail: Task<Void, Never>?

    static func start(start: Date, targetHours: Double) {
        guard FoodSettings.fastRange.contains(targetHours),
              start.timeIntervalSinceReferenceDate.isFinite else { return }
        let attributes = FastingAttributes(start: start, targetHours: targetHours)
        enqueue {
            var keptMatchingActivity = false
            for activity in Fasting.activities {
                if !keptMatchingActivity, activity.attributes == attributes, activity.content.state.end == nil,
                   activity.activityState == .active || activity.activityState == .stale {
                    keptMatchingActivity = true
                } else {
                    await finish(activity, at: .now)
                }
            }
            guard !keptMatchingActivity, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            // isStale signalisiert dem Widget, dass der Countdown am Ziel umschalten soll.
            let goal = attributes.timerInterval.upperBound
            let content = ActivityContent(state: FastingAttributes.ContentState(end: nil),
                                          staleDate: goal > .now ? goal : nil)
            _ = try? Fasting.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    static func end(at date: Date) {
        enqueue {
            for activity in Fasting.activities {
                await finish(activity, at: date)
            }
        }
    }

    static func reconcile(in context: ModelContext) {
        var descriptor = FetchDescriptor<FoodFast>(predicate: #Predicate { $0.end == nil },
                                                   sortBy: [SortDescriptor(\.start, order: .reverse)])
        descriptor.fetchLimit = 1
        // Ein Lesefehler belegt nicht, dass das Fasten beendet wurde.
        guard let active = try? context.fetch(descriptor) else { return }
        if let fast = active.first {
            start(start: fast.start, targetHours: fast.targetHours)
        } else {
            end(at: .now)
        }
    }

    private static func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private static func finish(_ activity: Fasting, at date: Date) async {
        let content = ActivityContent(state: FastingAttributes.ContentState(end: date), staleDate: nil)
        // ActivityKit ist threadsicher, markiert Activity aber nicht als Sendable.
        nonisolated(unsafe) let target = activity
        await target.end(content, dismissalPolicy: .immediate)
    }
}
