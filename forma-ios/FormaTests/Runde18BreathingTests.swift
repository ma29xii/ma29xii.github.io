import XCTest
@testable import Forma

final class Runde18BreathingTests: XCTestCase {
    func testFillFollowsInhaleAndExhale() {
        let half = BreathingSession.half
        XCTAssertEqual(BreathingSession.fill(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(BreathingSession.fill(at: half / 2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(BreathingSession.fill(at: half), 1, accuracy: 0.0001)
        XCTAssertEqual(BreathingSession.fill(at: half * 1.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(BreathingSession.fill(at: half * 2), 0, accuracy: 0.0001)
    }

    func testPhasesAlternate() {
        XCTAssertTrue(BreathingSession.isInhale(0))
        XCTAssertFalse(BreathingSession.isInhale(1))
        XCTAssertTrue(BreathingSession.isInhale(2))
    }
}
