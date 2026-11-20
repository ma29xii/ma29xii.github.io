import XCTest
@testable import Forma

final class RingTrendRangeTests: XCTestCase {
    func testAllRangesIncludeTodayAndUseCalendarBoundaries() {
        let anchor = Calendar.forma.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 16))!
        let midnight = Calendar.forma.startOfDay(for: anchor)
        let calendar = Calendar.forma

        XCTAssertEqual(RingTrendRange.week.domain(ending: anchor), midnight.adding(days: -6)...midnight)
        XCTAssertEqual(calendar.component(.month, from: RingTrendRange.month.domain(ending: anchor).lowerBound), 10)
        XCTAssertEqual(calendar.component(.month, from: RingTrendRange.halfYear.domain(ending: anchor).lowerBound), 5)
        XCTAssertEqual(RingTrendRange.halfYear.domain(ending: anchor).upperBound, midnight)
    }
}
