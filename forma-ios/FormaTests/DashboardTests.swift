import XCTest
@testable import Forma

final class DashboardTests: XCTestCase {
    func testEmptyDaysHaveNoRingValues() {
        let date = Date.now.startOfDay
        let day = DashboardDay(day: DayMetrics(date: date), history: [])
        XCTAssertNil(day.sleepScore)
        XCTAssertNil(day.recovery)
        XCTAssertNil(day.strain)
    }

    func testMeasuredZeroEnergyIsAnAvailableStrainValue() {
        let day = DashboardDay(day: DayMetrics(date: .now, activeEnergy: 0), history: [])
        XCTAssertEqual(day.strain, 0)
    }

    func testDailyBaselineExcludesSelectedDayAndOlderValues() throws {
        let date = Date.now.startOfDay
        let history = (-31...0).map { DayMetrics(date: date.adding(days: $0), steps: Double(-$0)) }
        let day = DashboardDay(day: DayMetrics(date: date, steps: 900), history: history)
        let baseline = try XCTUnwrap(day.baseline { $0.steps })
        XCTAssertEqual(baseline.mean, 15.5, accuracy: 0.001)
    }

    func testStressZonesUseOnlyMeasuredTimeAndCountPartialHours() {
        let start = Date.now.startOfDay
        let slots = [
            StressSlot(start: start, end: start.addingTimeInterval(3600), value: 0.9),
            StressSlot(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200), value: nil),
            StressSlot(start: start.addingTimeInterval(7200), end: start.addingTimeInterval(9000), value: 2)
        ]
        XCTAssertEqual(StressZone.low.duration(in: slots), 3600)
        XCTAssertEqual(StressZone.medium.duration(in: slots), 0)
        XCTAssertEqual(StressZone.high.duration(in: slots), 1800)
    }

    func testPaceUsesElapsedTimeBetweenEstimates() throws {
        let previous = Date(timeIntervalSinceReferenceDate: 0)
        let recent = previous.addingTimeInterval(30 * 86_400)
        let normalAging = recent.timeIntervalSince(previous) / (365.2425 * 86_400)
        let before = BodyAge.Estimate(date: previous, bodyAge: 30, age: 30)
        let after = BodyAge.Estimate(date: recent, bodyAge: 30 + normalAging, age: 30 + normalAging)
        let pace = try XCTUnwrap(BodyAge.agingPace(previous: before, recent: after))
        XCTAssertEqual(pace, 1, accuracy: 0.0001)
        XCTAssertNil(BodyAge.agingPace(previous: nil, recent: after))
        XCTAssertNil(BodyAge.agingPace(previous: after, recent: before))
    }

    func testAgeComparisonRequiresHealthDataInBothWindows() {
        let date = Date.now.startOfDay
        let days = (1...60).reversed().map { offset in
            DayMetrics(date: date.adding(days: -offset), restingHR: offset <= 30 ? 60 : nil, steps: 8_000)
        }
        let person = PersonInfo(birthDate: date.adding(days: -30 * 365), sex: .unknown, origin: .manual)
        let strength = BodyAge.StrengthMinutes(perWeek: 0, recentPerWeek: 0, hasRecord: false)
        guard case .ready(let result) = BodyAge.evaluate(days: days, person: person, strength: strength, now: date) else {
            return XCTFail("Ein Langzeitwert sollte verfügbar sein")
        }
        XCTAssertNil(result.pace)
    }
}
