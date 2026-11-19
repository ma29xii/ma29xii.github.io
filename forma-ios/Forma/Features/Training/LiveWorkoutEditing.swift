import Foundation

extension LiveWorkout {
    /// Satz entfernen (langes Drücken). Die Auswahl folgt der Satz-ID: Bleibt der gewählte Satz, bleibt die Auswahl;
    /// sonst springt sie auf den nächsten offenen Satz und die Reserve wird zurückgesetzt.
    func removeSet(exercise: Int, set: Int) {
        guard exercises.indices.contains(exercise), exercises[exercise].sets.indices.contains(set) else { return }
        let selectedID = currentSet?.id
        let selectedExercise = exerciseIndex
        exercises[exercise].sets.remove(at: set)
        if let selectedID, exercises.indices.contains(selectedExercise),
           let s = exercises[selectedExercise].sets.firstIndex(where: { $0.id == selectedID && !$0.done }) {
            setIndex = s
        } else if let e = exercises.indices.first(where: { i in exercises[i].sets.contains { !$0.done } }),
                  let s = exercises[e].sets.firstIndex(where: { !$0.done }) {
            exerciseIndex = e
            setIndex = s
            currentRIR = nil   // die Reserve gehörte zum gelöschten Satz
        }
        // Kein offener Satz mehr: Pause und Mitteilung enden wie beim Abschluss des letzten Satzes.
        if !exercises.contains(where: { ex in ex.sets.contains { !$0.done } }) {
            currentRIR = nil
            skipRest()
            return
        }
        persist()
        LiveTrainingActivity.update(workout: self)
    }
}
