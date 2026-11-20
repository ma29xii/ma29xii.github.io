import XCTest
import UIKit
@testable import Forma

final class PlusCoachTests: XCTestCase {
    // MARK: Plus-Menü

    func testPlusActionsHaveUniqueIdentifiersAndTexts() {
        let ids = PlusAction.allCases.map(\.accessibilityID)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(PlusAction.tiles.map(\.accessibilityID),
                       ["plus.track", "plus.water", "plus.weight", "plus.mood", "plus.caffeine",
                        "plus.training", "plus.fasting", "plus.plan", "plus.breathe", "plus.sleepPlan", "plus.askCoach"])
        XCTAssertEqual(PlusAction.tiles.map(\.title),
                       ["Nährwerte tracken", "Wasser", "Gewicht", "Stimmung", "Koffein",
                        "Fitness", "Fasten", "Essen planen", "Atmen", "Schlafplan", "Coach fragen"])
        XCTAssertFalse(PlusAction.tiles.contains(.scan), "Scanner und Schnellstart sind nur intern")
        XCTAssertFalse(PlusAction.tiles.contains(.quickTraining))
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

    @MainActor
    func testPlusTogglesOverCurrentTabAndClosesWhenSelectingFood() {
        let app = AppState(isDemo: true)
        app.selectTab(.add)
        XCTAssertEqual(app.selectedTab, .today)
        XCTAssertTrue(app.showPlus)

        app.selectTab(.food)
        XCTAssertEqual(app.selectedTab, .food)
        XCTAssertFalse(app.showPlus)

        app.selectTab(.add)
        XCTAssertEqual(app.selectedTab, .food)
        XCTAssertTrue(app.showPlus)
        app.selectTab(.add)
        XCTAssertFalse(app.showPlus)
    }

    @MainActor
    func testOpeningCoachClosesPlus() {
        let app = AppState(isDemo: true)
        app.selectTab(.add)
        app.openCoach(with: "Schlaf")
        XCTAssertEqual(app.selectedTab, .coach)
        XCTAssertEqual(app.coachPrompt, "Schlaf")
        XCTAssertFalse(app.showPlus)
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
