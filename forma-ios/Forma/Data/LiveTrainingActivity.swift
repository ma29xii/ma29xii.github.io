import ActivityKit
import Foundation

/// Spiegel des echten Trainings für den Sperrbildschirm. Der Entwurf bleibt in `LiveWorkout`.
@MainActor
enum LiveTrainingActivity {
    private typealias Training = Activity<LiveTrainingAttributes>
    private static var tail: Task<Void, Never>?

    static func start(workout: LiveWorkout) {
        guard !workout.isDemo else { return }
        let id = workout.draftID
        let state = state(for: workout)
        enqueue {
            for activity in Training.activities where activity.attributes.workoutID != id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            if let activity = current(workoutID: id) {
                await apply(state, to: activity)
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                _ = try? Training.request(attributes: LiveTrainingAttributes(workoutID: id),
                                          content: content(for: state), pushType: nil)
            }
        }
    }

    static func update(workout: LiveWorkout) {
        guard !workout.isDemo else { return }
        let id = workout.draftID
        let state = state(for: workout)
        enqueue {
            guard let activity = current(workoutID: id) else { return }
            await apply(state, to: activity)
        }
    }

    static func end(workoutID: UUID) {
        enqueue {
            for activity in Training.activities where activity.attributes.workoutID == workoutID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Nach dem Laden eines echten App-Zustands ohne wiederherstellbaren Entwurf aufrufen.
    static func endOrphans() {
        enqueue {
            for activity in Training.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private static func current(workoutID: UUID) -> Training? {
        Training.activities.first {
            $0.attributes.workoutID == workoutID && ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    private static func state(for workout: LiveWorkout) -> LiveTrainingAttributes.ContentState {
        let set = workout.currentSet.flatMap { $0.done ? nil : $0 }
        let setNumber: Int?
        if let set, !set.isWarmup {
            setNumber = workout.workSetNumber(exercise: workout.exerciseIndex, set: workout.setIndex)
        } else {
            setNumber = nil
        }
        let pauseEnd = workout.restEndsAt.flatMap { $0 > .now ? $0 : nil }
        return .init(exerciseName: set == nil ? nil : workout.currentExercise?.name,
                     setNumber: setNumber, isWarmup: set?.isWarmup == true, pauseEndsAt: pauseEnd)
    }

    private static func content(for state: LiveTrainingAttributes.ContentState) -> ActivityContent<LiveTrainingAttributes.ContentState> {
        ActivityContent(state: state, staleDate: state.pauseEndsAt)
    }

    private static func apply(_ state: LiveTrainingAttributes.ContentState, to activity: Training) async {
        guard activity.content.state != state else { return }
        await activity.update(content(for: state))
    }
}
