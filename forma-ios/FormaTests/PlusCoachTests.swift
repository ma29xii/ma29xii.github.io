import XCTest
import UIKit
@testable import Forma

final class PlusCoachTests: XCTestCase {
    // MARK: Plus-Menü

    func testPlusActionsHaveUniqueIdentifiersAndTexts() {
        let ids = PlusAction.allCases.map(\.accessibilityID)
        XCTAssertEqual(ids, ["plus.scan", "plus.photo", "plus.search", "plus.food", "plus.plan", "plus.water",
                             "plus.fasting", "plus.weight", "plus.training"])
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(PlusAction.allCases.map(\.title),
                       ["Mahlzeit scannen", "Essen fotografieren", "Essen suchen", "Ernährung heute", "Essen planen", "Wasser",
                        "Fasten", "Gewicht", "Training starten"])
        XCTAssertEqual(PlusAction.groups.flatMap(\.actions), PlusAction.allCases, "Jede Aktion steht in genau einer Gruppe")
        XCTAssertTrue(PlusAction.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    func testNextRoutinePrefersNeverUsedThenOldest() {
        let old = Date(timeIntervalSinceReferenceDate: 100)
        let recent = Date(timeIntervalSinceReferenceDate: 900)
        XCTAssertNil(PlusLogic.nextRoutineIndex(lastUsed: []))
        XCTAssertEqual(PlusLogic.nextRoutineIndex(lastUsed: [recent, nil, old]), 1)
        XCTAssertEqual(PlusLogic.nextRoutineIndex(lastUsed: [recent, old, recent]), 1)
        XCTAssertEqual(PlusLogic.nextRoutineIndex(lastUsed: [nil, nil]), 0, "Bei Gleichstand gewinnt die erste")
    }

    // MARK: Hintergrund-Plan im Profil

    func testBackgroundPlanTextShowsErrorWithTimeAndPlannedTime() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        XCTAssertNil(ProfileText.backgroundPlan(planned: nil, error: nil, attempt: nil, now: now))
        XCTAssertNil(ProfileText.backgroundPlan(planned: nil, error: "", attempt: now, now: now))
        let ok = ProfileText.backgroundPlan(planned: now.addingTimeInterval(2700), error: nil, attempt: now, now: now)
        XCTAssertEqual(ok?.isProblem, false)
        XCTAssertTrue(ok?.text.hasPrefix("Nächster Hintergrund-Abruf frühestens heute") == true)
        let failed = ProfileText.backgroundPlan(planned: now, error: "Hintergrundaktualisierung ist für Health aus.", attempt: now, now: now)
        XCTAssertEqual(failed?.isProblem, true)
        XCTAssertTrue(failed?.text.contains("nicht geplant (heute") == true)
    }

    // MARK: Maskottchen

    // MARK: Pause

    @MainActor
    func testExtendRestStopsAtLimit() {
        let workout = LiveWorkout(title: "Test", exercises: [])
        workout.isDemo = true   // keine Systemaufrufe
        XCTAssertTrue(workout.canExtendRest)
        for _ in 0..<80 { workout.extendRest(by: 15) }
        XCTAssertLessThanOrEqual(workout.restEndsAt?.timeIntervalSinceNow ?? 0, LiveWorkout.maxRestSeconds + 1)
        XCTAssertEqual(workout.restTotal, Int(LiveWorkout.maxRestSeconds))
        XCTAssertFalse(workout.canExtendRest)
    }

    func testMascotTintFollowsRecovery() {
        XCTAssertEqual(CoachMascotLogic.tint(recovery: 90), Theme.recoveryHigh)
        XCTAssertEqual(CoachMascotLogic.tint(recovery: 50), Theme.recoveryMid)
        XCTAssertEqual(CoachMascotLogic.tint(recovery: 10), Theme.recoveryLow)
        XCTAssertNotEqual(CoachMascotLogic.tint(recovery: nil), Theme.recoveryHigh, "Ohne Wert kein Grün vortäuschen")
    }

    func testMascotMoodPriority() {
        XCTAssertEqual(CoachMascotLogic.mood(thinking: true, justReplied: true, hasSuggestion: true), .thinking)
        XCTAssertEqual(CoachMascotLogic.mood(thinking: false, justReplied: true, hasSuggestion: true), .happy)
        XCTAssertEqual(CoachMascotLogic.mood(thinking: false, justReplied: false, hasSuggestion: true), .hint)
        XCTAssertEqual(CoachMascotLogic.mood(thinking: false, justReplied: false, hasSuggestion: false), .calm)
    }

    func testHopIsZeroOutsideTheWindowAndBounded() {
        XCTAssertEqual(CoachMascotLogic.hopHeight(elapsed: -1), 0)
        XCTAssertEqual(CoachMascotLogic.hopHeight(elapsed: 0.9), 0)
        XCTAssertEqual(CoachMascotLogic.hopHeight(elapsed: 5), 0)
        XCTAssertEqual(CoachMascotLogic.hopHeight(elapsed: 0), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(CoachMascotLogic.hopHeight(elapsed: 0.9 / 4), 0.5, "Erster Sprung erreicht die Spitze")
        for step in 0..<90 {
            let h = CoachMascotLogic.hopHeight(elapsed: Double(step) / 100)
            XCTAssertTrue((0...1).contains(h))
        }
    }

    func testEveryMoodHasText() {
        for mood in MascotMood.allCases { XCTAssertFalse(mood.accessibilityText.isEmpty) }
    }
}

final class CoachPhotoTests: XCTestCase {
    private func jpeg(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            for y in stride(from: 0, to: height, by: 8) {
                UIColor(hue: CGFloat(y % 360) / 360, saturation: 1, brightness: 1, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: y, width: width, height: 8))
            }
        }
        return image.jpegData(compressionQuality: 1)!
    }

    func testLargePhotoIsShrunkBelowEdgeAndSizeLimit() throws {
        let photo = try XCTUnwrap(CoachPhoto.prepare(jpeg(width: 3000, height: 2000)))
        let sent = try XCTUnwrap(UIImage(data: photo.jpeg))
        XCTAssertLessThanOrEqual(max(sent.size.width, sent.size.height) * sent.scale, CGFloat(CoachPhoto.maxEdge))
        XCTAssertLessThanOrEqual(photo.jpeg.count, CoachPhoto.maxBytes)
        XCTAssertLessThanOrEqual(max(photo.image.size.width, photo.image.size.height) * photo.image.scale, CGFloat(CoachPhoto.previewEdge))
    }

    func testNoImageDataGivesNil() {
        XCTAssertNil(CoachPhoto.prepare(Data("kein Bild".utf8)))
        XCTAssertNil(CoachPhoto.prepare(Data()))
    }

    func testChatCopyKeepsNoSendData() throws {
        let photo = try XCTUnwrap(CoachPhoto.prepare(jpeg(width: 800, height: 600)))
        XCTAssertFalse(photo.jpeg.isEmpty)
        XCTAssertTrue(photo.forChat.jpeg.isEmpty)
    }
}
