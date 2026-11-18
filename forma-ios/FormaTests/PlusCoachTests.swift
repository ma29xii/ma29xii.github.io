import XCTest
@testable import Forma

final class PlusCoachTests: XCTestCase {
    // MARK: Plus-Menü

    func testPlusActionsHaveUniqueIdentifiersAndTexts() {
        let ids = PlusAction.allCases.map(\.accessibilityID)
        XCTAssertEqual(ids, ["plus.scan", "plus.search", "plus.food", "plus.training"])
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(PlusAction.allCases.map(\.title),
                       ["Mahlzeit scannen", "Essen suchen", "Ernährung heute", "Training starten"])
        XCTAssertTrue(PlusAction.allCases.allSatisfy { !$0.subtitle.isEmpty && !$0.systemImage.isEmpty })
    }

    func testNextRoutinePrefersNeverUsedThenOldest() {
        let old = Date(timeIntervalSinceReferenceDate: 100)
        let recent = Date(timeIntervalSinceReferenceDate: 900)
        XCTAssertNil(PlusLogic.nextRoutineIndex(lastUsed: []))
        XCTAssertEqual(PlusLogic.nextRoutineIndex(lastUsed: [recent, nil, old]), 1)
        XCTAssertEqual(PlusLogic.nextRoutineIndex(lastUsed: [recent, old, recent]), 1)
        XCTAssertEqual(PlusLogic.nextRoutineIndex(lastUsed: [nil, nil]), 0, "Bei Gleichstand gewinnt die erste")
    }

    // MARK: Maskottchen

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
