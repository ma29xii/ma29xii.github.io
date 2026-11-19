import XCTest
@testable import Forma

/// Runde 11: Muskelfigur und Sätze löschen.
@MainActor
final class Runde11TrainingTests: XCTestCase {
    private func sets(_ n: Int = 3) -> [LiveSet] { (0..<n).map { _ in LiveSet(weight: 40, reps: 10, isWarmup: false) } }

    private func workout() -> LiveWorkout {
        let w = LiveWorkout(title: "Test", exercises: [
            LiveExercise(name: "Bankdrücken", muscle: "Brust", restSeconds: 60, sets: sets()),
            LiveExercise(name: "Rudern", muscle: "Rücken", restSeconds: 60, sets: sets())
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

    // Runde 12 (Gegenprüfung 05 #4)

    func testRemovingSelectedSetResetsReserve() {
        let w = workout()
        w.select(exercise: 0, set: 1)
        w.currentRIR = 2
        w.removeSet(exercise: 0, set: 1)
        XCTAssertEqual([w.exerciseIndex, w.setIndex], [0, 0], "nächster offener Satz")
        XCTAssertNil(w.currentRIR, "Reserve gehörte zum gelöschten Satz")
    }

    func testRemovingLastOpenSetDuringRestEndsRest() {
        let w = LiveWorkout(title: "Test", exercises: [LiveExercise(name: "Bankdrücken", muscle: "Brust", restSeconds: 90, sets: sets(2))])
        w.isDemo = true
        w.completeCurrentSet()
        XCTAssertTrue(w.isResting)
        w.removeSet(exercise: 0, set: 1)
        XCTAssertNil(w.restEndsAt, "keine Pause ohne offenen Satz")
        XCTAssertTrue(w.allDone)
    }

    func testFigureCoversEveryMuscleAndHitsTopmost() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 440)
        for muscle in Muscle.allCases {
            XCTAssertTrue(MuscleArt.polygons(muscle, .front) != nil || MuscleArt.polygons(muscle, .back) != nil, muscle.name)
        }
        // Seitliche Schulter liegt über der vorderen: Tippen auf den äußeren Rand trifft sie.
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 157, y: 104), side: .front, in: rect), .sideDelts)
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 120, y: 100), side: .front, in: rect), .chest)
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 80, y: 100), side: .front, in: rect), .chest)
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 120, y: 250), side: .back, in: rect), .glutes)
        XCTAssertNil(MuscleArt.muscle(at: CGPoint(x: 12, y: 100), side: .front, in: rect))
    }
}
