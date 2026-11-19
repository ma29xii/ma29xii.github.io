import Foundation

extension LiveWorkout {
    /// Satz entfernen (langes Drücken). Die Auswahl bleibt auf demselben Satz oder springt auf den nächsten offenen.
    func removeSet(exercise: Int, set: Int) {
        guard exercises.indices.contains(exercise), exercises[exercise].sets.indices.contains(set) else { return }
        exercises[exercise].sets.remove(at: set)
        if exercise == exerciseIndex, set < setIndex { setIndex -= 1 }
        if currentSet == nil || currentSet?.done == true,
           let e = exercises.indices.first(where: { i in exercises[i].sets.contains { !$0.done } }),
           let s = exercises[e].sets.firstIndex(where: { !$0.done }) {
            select(exercise: e, set: s)
        } else {
            persist()
            LiveTrainingActivity.update(workout: self)
        }
    }
}
