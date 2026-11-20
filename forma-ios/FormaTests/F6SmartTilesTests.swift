import XCTest
@testable import Forma

final class F6SmartTilesTests: XCTestCase {
    private let calendar = Calendar.forma
    private var today: Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 11, day: 20))!)
    }

    func testReadinessFollowsRecovery() {
        XCTAssertEqual(ReadinessAdvice.make(recovery: 80)?.kind, .hard)
        XCTAssertEqual(ReadinessAdvice.make(recovery: 80)?.strain, 35...55)
        XCTAssertEqual(ReadinessAdvice.make(recovery: 50)?.kind, .normal)
        XCTAssertEqual(ReadinessAdvice.make(recovery: 50)?.rangeText, "25–40")
        XCTAssertEqual(ReadinessAdvice.make(recovery: 25)?.kind, .easy)
        XCTAssertEqual(ReadinessAdvice.make(recovery: 10)?.kind, .rest)
        XCTAssertEqual(ReadinessAdvice.make(recovery: 10)?.rangeText, "unter 10")
        XCTAssertNil(ReadinessAdvice.make(recovery: nil))
    }

    func testFightingBodyMeansRestDay() {
        XCTAssertEqual(ReadinessAdvice.make(recovery: 85, illness: .fighting)?.kind, .rest)
        XCTAssertEqual(ReadinessAdvice.make(recovery: 85, illness: .watch)?.kind, .hard)
    }

    private func sleepDays(nights: Int, hours: Double) -> [DayMetrics] {
        (0..<nights).map { index in
            let date = today.adding(days: -(nights - index))
            return DayMetrics(date: date, sleep: SleepNight(start: date.addingTimeInterval(-hours * 3600 + 7 * 3600),
                                                            end: date.addingTimeInterval(7 * 3600),
                                                            segments: [], reportedAsleep: hours * 3600))
        }
    }

    func testSleepDebtNeedsFourNights() throws {
        XCTAssertNil(SleepDebtInfo.make(history: sleepDays(nights: 3, hours: 6)))
        let info = try XCTUnwrap(SleepDebtInfo.make(history: sleepDays(nights: 7, hours: 6)))
        XCTAssertEqual(info.debt, 7 * 1.75 * 3600 / 3, accuracy: 1)
        XCTAssertEqual(info.extraTonight, 1800, accuracy: 1)
        XCTAssertTrue(info.hasExtra)
    }

    func testNoDebtMeansNoEarlierBedtime() throws {
        let info = try XCTUnwrap(SleepDebtInfo.make(history: sleepDays(nights: 7, hours: 8)))
        XCTAssertEqual(info.debt, 0)
        XCTAssertFalse(info.hasExtra)
    }

    func testCalmTimeSkipsGaps() throws {
        let start = today
        func slot(_ hour: Int, _ value: Double?) -> StressSlot {
            StressSlot(start: start.addingTimeInterval(Double(hour) * 3600),
                       end: start.addingTimeInterval(Double(hour + 1) * 3600), value: value)
        }
        let slots = [slot(8, 0.4), slot(9, 0.6), slot(10, nil), slot(11, nil), slot(12, 1.5), slot(13, 2.5)]
        let info = try XCTUnwrap(CalmTimeInfo.make(slots: slots))
        XCTAssertEqual(info.calm, 7200)
        XCTAssertEqual(info.medium, 3600)
        XCTAssertEqual(info.stressed, 3600)
        XCTAssertEqual(info.measured, 14400)
        XCTAssertNil(CalmTimeInfo.make(slots: [slot(10, nil)]))
        XCTAssertNil(CalmTimeInfo.make(slots: []))
    }

    private func stepDays(todaySteps: Double) -> [DayMetrics] {
        (0...40).reversed().map { offset in
            let steps: Double
            switch offset {
            case 0: steps = todaySteps
            case 1...4: steps = 12_000
            case 5: steps = 5_000
            default: steps = 10_000
            }
            return DayMetrics(date: today.adding(days: -offset), steps: steps)
        }
    }

    func testStreakCountsDaysInARowIncludingToday() {
        let result = GoalStreak.current(endingAt: today, history: stepDays(todaySteps: 12_000))
        XCTAssertEqual(result.days, 5)
        XCTAssertTrue(result.todayReached)
    }

    func testStreakKeepsYesterdaysCountWhileTodayIsOpen() {
        let result = GoalStreak.current(endingAt: today, history: stepDays(todaySteps: 3_000))
        XCTAssertEqual(result.days, 4)
        XCTAssertFalse(result.todayReached)
    }

    func testStreakIsZeroWithoutData() {
        let result = GoalStreak.current(endingAt: today, history: [])
        XCTAssertEqual(result.days, 0)
        XCTAssertFalse(result.todayReached)
    }

    func testNewTilesAreRegisteredAndOnlyTwoStartVisible() {
        let standard = TileArrangement<TodayTile>.standard
        XCTAssertTrue(standard.visible.contains(.bodySignals))
        XCTAssertTrue(standard.visible.contains(.readiness))
        for kind in [TodayTile.sleepDebt, .calmTime, .streak] { XCTAssertTrue(standard.hidden.contains(kind)) }
        XCTAssertEqual(TodayTile.bodySignals.title, "Körpersignale")
        XCTAssertEqual(TodayTile.readiness.title, "Bereit für")
        XCTAssertEqual(Set(TodayTile.allCases.map(\.title)).count, TodayTile.allCases.count)
    }

    func testOldStoredArrangementGetsNewTilesAppended() {
        let old = TileArrangement<TodayTile>(storage: "coach,metrics|")
        XCTAssertTrue(old.order.contains(.streak))
        XCTAssertTrue(old.hidden.contains(.streak))
        XCTAssertTrue(old.visible.contains(.bodySignals))
    }
}
