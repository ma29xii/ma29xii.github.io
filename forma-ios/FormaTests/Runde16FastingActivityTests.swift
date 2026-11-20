import Foundation
import XCTest
@testable import Forma

final class Runde16FastingActivityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testAttributesAndBothContentStatesRoundTrip() throws {
        let attributes = FastingAttributes(start: start, targetHours: 16.5)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(FastingAttributes.self, from: encoder.encode(attributes)), attributes)

        let end = start.addingTimeInterval(14 * 3_600)
        for state in [FastingAttributes.ContentState(end: nil), .init(end: end)] {
            XCTAssertEqual(try decoder.decode(FastingAttributes.ContentState.self, from: encoder.encode(state)),
                           state)
        }
    }

    func testRemainingTimeAndRingProgressUseTheOriginalStart() {
        let attributes = FastingAttributes(start: start, targetHours: 16)
        let goal = start.addingTimeInterval(16 * 3_600)
        let beforeStart = attributes.progress(at: start.addingTimeInterval(-60), state: .init(end: nil))
        let halfway = attributes.progress(at: start.addingTimeInterval(8 * 3_600), state: .init(end: nil))

        XCTAssertEqual(attributes.timerInterval, start...goal)
        XCTAssertEqual(beforeStart.fraction, 0)
        XCTAssertEqual(beforeStart.remaining, 16 * 3_600)
        XCTAssertEqual(halfway.fraction, 0.5)
        XCTAssertEqual(halfway.remaining, 8 * 3_600)
        XCTAssertFalse(halfway.reached)
    }

    func testRingFillsAtTheGoalAndElapsedTimeKeepsCounting() {
        let attributes = FastingAttributes(start: start, targetHours: 16)
        let atGoal = attributes.progress(at: attributes.timerInterval.upperBound, state: .init(end: nil))
        let afterGoal = attributes.progress(at: start.addingTimeInterval(18 * 3_600), state: .init(end: nil))

        XCTAssertTrue(atGoal.reached)
        XCTAssertEqual(atGoal.fraction, 1)
        XCTAssertEqual(atGoal.remaining, 0)
        XCTAssertEqual(afterGoal.fraction, 1)
        XCTAssertEqual(afterGoal.elapsed, 18 * 3_600)
    }

    func testEndingEarlyFreezesProgressAndDoesNotReachTheGoalLater() {
        let attributes = FastingAttributes(start: start, targetHours: 16)
        let end = start.addingTimeInterval(4 * 3_600)
        let progress = attributes.progress(at: start.addingTimeInterval(24 * 3_600), state: .init(end: end))

        XCTAssertEqual(progress.elapsed, 4 * 3_600)
        XCTAssertEqual(progress.fraction, 0.25)
        XCTAssertEqual(progress.remaining, 12 * 3_600)
        XCTAssertFalse(progress.reached)
    }
}
