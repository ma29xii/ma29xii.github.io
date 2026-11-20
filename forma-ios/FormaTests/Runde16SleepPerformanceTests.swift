import XCTest
@testable import Forma

final class Runde16SleepPerformanceTests: XCTestCase {
    func testSleepConsistencyPreparesOnlyItsFourteenCalendarDays() throws {
        let now = try XCTUnwrap(Calendar.forma.date(from: DateComponents(year: 2026, month: 11, day: 20)))
        var days = SampleData.days(count: 90, endingAt: now)
        let end = try XCTUnwrap(days.dropLast(3).last?.date)
        let first = end.adding(days: -13)
        let firstIndex = try XCTUnwrap(days.firstIndex { $0.date == first })
        // InsightHistory ordnet Messwerte auch abseits von Mitternacht ihrem Kalendertag zu.
        days[firstIndex].date = first.addingTimeInterval(3600)
        days[firstIndex + 1].sleep = nil
        days.reverse()

        let relevant = RingSleepConsistency.relevantDays(endingAt: end, history: days)
        XCTAssertEqual(relevant.count, 14)

        let full = SleepConsistency(endingAt: end, history: InsightHistory(days))
        let limited = SleepConsistency(endingAt: end, history: InsightHistory(relevant))
        XCTAssertEqual(limited.measured, 13)
        XCTAssertEqual(limited.percent, full.percent)
        XCTAssertEqual(limited.nights.map(\.date), full.nights.map(\.date))
        XCTAssertEqual(limited.nights.map { $0.value?.start }, full.nights.map { $0.value?.start })
        XCTAssertEqual(limited.nights.map { $0.value?.end }, full.nights.map { $0.value?.end })
    }
}
