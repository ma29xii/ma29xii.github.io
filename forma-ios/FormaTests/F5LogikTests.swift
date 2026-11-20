import XCTest
@testable import Forma

final class F5LogikTests: XCTestCase {
    func testWeekStartFollowsProfileSetting() {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: Calendar.weekStartKey) }
        defaults.removeObject(forKey: Calendar.weekStartKey)
        XCTAssertEqual(Calendar.forma.firstWeekday, 2)
        defaults.set(1, forKey: Calendar.weekStartKey)
        XCTAssertEqual(Calendar.forma.firstWeekday, 1)
        defaults.set(5, forKey: Calendar.weekStartKey)
        XCTAssertEqual(Calendar.forma.firstWeekday, 2)
    }

    // F5-04: Google liefert HRV und Ruhepuls nur pro Tag – der Stress Monitor braucht keine Stundenwerte dafür.
    func testStressFromDailyVitalsWithoutHours() {
        let start = Date.now.startOfDay
        let history = (1...14).map { DayMetrics(date: start.adding(days: -$0), hrv: 50 + Double($0 % 3), restingHR: 55 + Double($0 % 2)) }
        let today = DayMetrics(date: start, hrv: 42, restingHR: 61)
        let signals = DaySignals(day: today, hours: [], history: history)
        XCTAssertNotNil(signals.stress)
        XCTAssertNil(DaySignals(day: DayMetrics(date: start), hours: [], history: history).stress)
    }

    func testHourlyStressUsesDailyVitalsWhenHourHasNone() throws {
        let start = Date.now.startOfDay
        let history = (1...14).map { DayMetrics(date: start.adding(days: -$0), hrv: 50 + Double($0 % 3), restingHR: 55 + Double($0 % 2)) }
        let hours = [HourlyMetrics(start: start.adding(minutes: 480), end: start.adding(minutes: 540), activeEnergy: 30)]
        let result = HourlyEstimate.timeline(hours: hours, today: DayMetrics(date: start, hrv: 42, restingHR: 61), history: history)
        XCTAssertNotNil(try XCTUnwrap(result.first).stress)
    }
}
