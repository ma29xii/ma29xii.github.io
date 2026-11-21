import XCTest
@testable import Forma

final class R23MorningBriefingTests: XCTestCase {
    func testAutomaticBriefingOpensOnlyInTheMorningAndOncePerLocalDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute)))
        }

        let morning = try date(29, 5)
        let shown = MorningBriefing.dayKey(at: morning, calendar: calendar)
        XCTAssertFalse(MorningBriefing.shouldOpen(at: try date(29, 4, 59), shownDay: "", calendar: calendar))
        XCTAssertTrue(MorningBriefing.shouldOpen(at: morning, shownDay: "", calendar: calendar))
        XCTAssertTrue(MorningBriefing.shouldOpen(at: try date(29, 10, 59), shownDay: "", calendar: calendar))
        XCTAssertFalse(MorningBriefing.shouldOpen(at: try date(29, 11), shownDay: "", calendar: calendar))
        XCTAssertFalse(MorningBriefing.shouldOpen(at: try date(29, 8), shownDay: shown, calendar: calendar))
        XCTAssertTrue(MorningBriefing.shouldOpen(at: try date(30, 5), shownDay: shown, calendar: calendar))
    }
}
