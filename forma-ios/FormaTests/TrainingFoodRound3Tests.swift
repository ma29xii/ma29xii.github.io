import AVFoundation
import Foundation
import XCTest
@testable import Forma

/// Runde 3: Nährwert-Lücken, getrennte Vorschau, Kamera-Zustände, abbrechbares Essensfoto, Tippflächen der Muskelkarte.
final class TrainingFoodRound3Tests: XCTestCase {

    // MARK: #14 fehlende Nährwerte

    func testMissingValuesAreNotZero() {
        let full = FoodSum([300, 200])
        XCTAssertEqual(full.known, 500)
        XCTAssertTrue(full.complete)
        XCTAssertEqual(full.remaining(of: 2_000), 1_500)

        let gap = FoodSum([300, nil, 200])
        XCTAssertEqual(gap.known, 500)
        XCTAssertFalse(gap.complete)
        XCTAssertNil(gap.remaining(of: 2_000), "Restbudget bleibt offen, solange ein Wert fehlt")

        XCTAssertFalse(FoodSum([.nan]).complete)
        XCTAssertNil(FoodSum([100]).remaining(of: 0), "ohne Ziel kein Rest")
        XCTAssertTrue(FoodSum([]).complete)
    }

    // MARK: #4 Vorschau überschreibt nie das Profil

    func testPreviewStoreIsSeparate() {
        let key = FoodSettings.bodyWeightKey
        let before = UserDefaults.standard.object(forKey: key) as? Double
        FoodSettings.store(isSample: true).set(120.0, forKey: key)
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Double, before)
        XCTAssertEqual(FoodSettings.previewDefaults.double(forKey: key), 120)
        XCTAssertTrue(FoodSettings.store(isSample: false) === UserDefaults.standard)
    }

    // MARK: #6 eigene Foto-Freigabe

    func testFoodPhotoConsentIsSeparateFromCoach() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "forma.test.photoConsent"))
        defaults.removePersistentDomain(forName: "forma.test.photoConsent")
        defaults.set(true, forKey: "forma.coach.photoConsent.v1")
        XCTAssertFalse(FoodSettings.photoAnalysisAllowed(defaults))
        defaults.set(true, forKey: FoodSettings.photoConsentKey)
        XCTAssertTrue(FoodSettings.photoAnalysisAllowed(defaults))
    }

    // MARK: #15 Kamera

    func testCameraStates() {
        XCTAssertEqual(CameraAccess.state(hasCamera: false, status: .authorized), .unavailable)
        XCTAssertEqual(CameraAccess.state(hasCamera: true, status: .authorized), .ready)
        XCTAssertEqual(CameraAccess.state(hasCamera: true, status: .notDetermined), .needsRequest)
        XCTAssertEqual(CameraAccess.state(hasCamera: true, status: .denied), .denied)
        XCTAssertEqual(CameraAccess.state(hasCamera: true, status: .restricted), .denied)
    }

    // MARK: #2 Schließen während des Ladens → null Anfragen

    func testClosingWhileLoadingSendsNothing() async {
        let counter = RequestCounter()
        let task = Task {
            try await FoodPhotoFlow.run(
                // Laden, das den Abbruch ignoriert (wie ein langsamer Foto-Import).
                load: { try? await Task.sleep(for: .milliseconds(300)); return Data([0xFF, 0xD8]) },
                anthropicKey: "test", openAIKey: nil, allowed: { true },
                send: { _ in await counter.hit(); return Data() }
            )
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = try? await task.value
        let count = await counter.count
        XCTAssertEqual(count, 0)
    }

    func testWithoutConsentSendsNothing() async {
        let counter = RequestCounter()
        do {
            _ = try await FoodPhotoFlow.run(
                load: { Data([0xFF, 0xD8]) }, anthropicKey: "test", openAIKey: nil, allowed: { false },
                send: { _ in await counter.hit(); return Data() }
            )
            XCTFail("ohne Freigabe muss die Schätzung abbrechen")
        } catch {}
        let count = await counter.count
        XCTAssertEqual(count, 0)
    }

    func testLoadFailureIsReported() async {
        do {
            _ = try await FoodPhotoFlow.run(load: { nil }, anthropicKey: "test", openAIKey: nil, allowed: { true })
            XCTFail("leeres Foto muss scheitern")
        } catch FoodPhotoFlow.FlowError.loadFailed {
        } catch {
            XCTFail("falscher Fehler: \(error)")
        }
    }

    // MARK: #12 Entwürfe ab der 31. Übung

    @MainActor
    func testDraftWith31ExercisesSurvivesRestart() throws {
        defer { LiveWorkout.clearSaved() }
        let exercises = (1...31).map { i in
            LiveExercise(name: "Übung \(i)", muscle: "Brust", restSeconds: 90, sets: [LiveSet(weight: 50, reps: 8, isWarmup: false)])
        }
        let w = LiveWorkout(title: "Groß", exercises: exercises)
        w.select(exercise: 30, set: 0)
        w.completeCurrentSet()
        let restored = try XCTUnwrap(LiveWorkout.restore())
        XCTAssertEqual(restored.exercises.count, 31)
        XCTAssertEqual(restored.exercises[30].name, "Übung 31")
        XCTAssertEqual(restored.exercises[30].sets[0].done, true)
    }

    @MainActor
    func testAddingStopsAtLimit() {
        defer { LiveWorkout.clearSaved() }
        let w = LiveWorkout.empty()
        for i in 0..<(LiveWorkout.maxExercises + 3) { w.addExercise(name: "Ü\(i)", muscle: "Arme") }
        XCTAssertEqual(w.exercises.count, LiveWorkout.maxExercises)
    }

    // MARK: #13 Texte ohne Einheit

    func testProgressionNoteHasNoUnit() throws {
        let plan = Progression.plan(targetReps: 8, routineWeight: 60, lastWorkSets: [(70, 8, 2), (70, 8, 3)])
        XCTAssertEqual(plan.weight, 70 + Progression.step)
        let note = try XCTUnwrap(plan.note)
        XCTAssertFalse(note.contains("kg"))
        XCTAssertEqual(Format.weight(77.5, unit: .lb), "170,9")
        XCTAssertEqual(Format.weight(Progression.step, unit: .lb), "5,5")
    }

    // MARK: #16 Tippflächen der Muskelkarte

    func testMuscleHitAreasAreGenerous() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 440)
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 120, y: 108), side: .front, in: rect), .chest)
        // Knapp neben der schmalen seitlichen Schulter: zählt trotzdem.
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 170, y: 100), side: .front, in: rect), .sideDelts)
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 30, y: 100), side: .front, in: rect), .sideDelts, "gespiegelt")
        XCTAssertNil(MuscleArt.muscle(at: CGPoint(x: 2, y: 2), side: .front, in: rect))
        // Hinten gibt es keine Brust.
        XCTAssertNotEqual(MuscleArt.muscle(at: CGPoint(x: 120, y: 108), side: .back, in: rect), .chest)
    }
}

private actor RequestCounter {
    private(set) var count = 0
    func hit() { count += 1 }
}
