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

    // MARK: #16 Tippflächen der Muskelkarte

    func testMuscleHitAreasAreGenerous() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 440)
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 120, y: 108), side: .front, in: rect), .chest)
        // Knapp neben der schmalen seitlichen Schulter: zählt trotzdem.
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 176, y: 106), side: .front, in: rect), .sideDelts)
        XCTAssertEqual(MuscleArt.muscle(at: CGPoint(x: 24, y: 106), side: .front, in: rect), .sideDelts, "gespiegelt")
        XCTAssertNil(MuscleArt.muscle(at: CGPoint(x: 2, y: 2), side: .front, in: rect))
        // Hinten gibt es keine Brust.
        XCTAssertNotEqual(MuscleArt.muscle(at: CGPoint(x: 120, y: 108), side: .back, in: rect), .chest)
    }
}

private actor RequestCounter {
    private(set) var count = 0
    func hit() { count += 1 }
}
