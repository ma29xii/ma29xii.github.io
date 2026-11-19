import XCTest
@testable import Forma

/// Runde 11: Muskelfigur und Sätze löschen.
@MainActor
final class Runde11TrainingTests: XCTestCase {
    private func workout() -> LiveWorkout {
        let sets = (0..<3).map { _ in LiveSet(weight: 40, reps: 10, isWarmup: false) }
        let w = LiveWorkout(title: "Test", exercises: [
            LiveExercise(name: "Bankdrücken", muscle: "Brust", restSeconds: 60, sets: sets),
            LiveExercise(name: "Rudern", muscle: "Rücken", restSeconds: 60, sets: sets)
        ])
        w.isDemo = true
        return w
    }

    func testRemoveSetKeepsSelectionOnSameSet() {
        let w = workout()
        w.select(exercise: 0, set: 2)
        let selected = w.currentSet?.id
        w.removeSet(exercise: 0, set: 0)
        XCTAssertEqual(w.exercises[0].sets.count, 2)
        XCTAssertEqual(w.currentSet?.id, selected, "Auswahl rutscht mit")
    }

    func testRemovingSelectedSetMovesToNextOpen() {
        let w = workout()
        w.completeCurrentSet()   // Satz 1 erledigt, Auswahl jetzt Satz 2
        w.select(exercise: 0, set: 2)
        w.removeSet(exercise: 0, set: 2)
        XCTAssertEqual(w.exerciseIndex, 0)
        XCTAssertEqual(w.setIndex, 1, "nächster offener Satz")
        XCTAssertFalse(w.currentSet?.done ?? true)
        w.removeSet(exercise: 9, set: 0)   // ungültig: nichts passiert
        XCTAssertEqual(w.exercises.map(\.sets.count), [2, 3])
    }

    func testFigureCoversEveryMuscleAndHitsTopmost() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 440)
        for muscle in Muscle.allCases {
            XCTAssertTrue(MuscleArt.polygons(muscle, .front) != nil || MuscleArt.polygons(muscle, .back) != nil, muscle.name)
        }
        // Seitliche Schulter liegt über der vorderen: Tippen auf den äußeren Rand trifft sie.
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 157, y: 104), side: .front, in: rect), .sideDelts)
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 120, y: 100), side: .front, in: rect), .chest)
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 120, y: 250), side: .back, in: rect), .glutes)
    }
}
