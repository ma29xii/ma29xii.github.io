import Foundation
import XCTest
@testable import Forma

final class Runde18WaterReminderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func time(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day,
                                           hour: hour, minute: minute, second: second))!
    }

    private func next(at now: Date, goal: Double = 2_800, total: Double = 0,
                      history: [Date] = []) -> Date? {
        WaterReminder.nextDate(goal: goal, total: total, now: now, history: history, calendar: calendar)
    }

    func testTargetRisesLinearlyAndStopsAtTheGoal() {
        for (hour, expected) in [(6, 0.0), (7, 0), (10, 600), (14, 1_400), (21, 2_800), (22, 2_800)] {
            XCTAssertEqual(WaterReminder.target(goal: 2_800, at: time(hour), calendar: calendar),
                           expected, accuracy: 0.001)
        }
    }

    func testSchedulesTheFirstWholeSecondBeyondTheStrictThreshold() {
        XCTAssertEqual(next(at: time(8), total: 500), time(12, 0, 1))
        XCTAssertEqual(next(at: time(12), total: 500), time(12, 0, 1))
        // 625 / 2.800 eines 14-Stunden-Fensters sind 3:07:30 Stunden.
        XCTAssertEqual(next(at: time(7), total: 125), time(10, 7, 31))
    }

    func testOverdueReminderCanFireAtTheNextWholeSecond() {
        XCTAssertEqual(next(at: time(13), total: 500), time(13, 0, 1))
    }

    func testRestHoursAndEndOfDay() {
        XCTAssertEqual(next(at: time(5)), time(9, 30, 1))
        XCTAssertEqual(next(at: time(20, 59, 59)), time(21))
        XCTAssertNil(next(at: time(21)))
        XCTAssertNil(next(at: time(22)))
        XCTAssertNil(next(at: time(20), total: 2_300))
    }

    func testTwoHourSpacingUsesMostRecentReminder() {
        XCTAssertEqual(next(at: time(13), history: [time(12, 25), time(10)]), time(14, 25))
        XCTAssertNil(next(at: time(20), history: [time(19, 30)]))
    }

    func testDailyLimitResetsAtMidnight() {
        let reminders = [time(9, 31), time(11, 31), time(13, 31), time(15, 31)]
        XCTAssertEqual(next(at: time(18), history: Array(reminders.prefix(3))), time(18, 0, 1))
        XCTAssertNil(next(at: time(18), history: reminders))
        XCTAssertEqual(next(at: time(7, day: 21), history: reminders), time(9, 30, 1, day: 21))
    }

    func testGoalReachedAndSmallDeficitsSkipReminders() {
        XCTAssertNil(next(at: time(13), total: 2_800))
        XCTAssertNil(next(at: time(13), total: 3_000))
        XCTAssertNil(next(at: time(18), goal: 500))
    }

    func testReachedGoalPlansTomorrowWithFreshDailyTotal() {
        let plan = WaterReminder.plan(goal: 2_800, total: 2_800, now: time(13),
                                      history: [], calendar: calendar)
        XCTAssertEqual(plan?.date, time(9, 30, 1, day: 21))
        XCTAssertEqual(plan?.remainingMilliliters, 2_800)
    }

    func testClosedWindowAndDailyLimitBothPlanTheNextMorning() {
        let history = [time(10), time(12), time(14), time(16)]
        for (now, deliveries) in [(time(18), history), (time(21), [])] {
            let plan = WaterReminder.plan(goal: 2_800, total: 0, now: now,
                                          history: deliveries, calendar: calendar)
            XCTAssertEqual(plan?.date, time(9, 30, 1, day: 21))
        }
        XCTAssertNil(WaterReminder.plan(goal: 500, total: 0, now: time(21), history: [], calendar: calendar))
    }

    func testWidgetGlassUpdatesTodaysPlanBeforeSwiftDataImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WaterWidgetStore(directory: directory)
        try store.publish(milliliters: 500, goalMilliliters: 2_800, including: [], at: time(8), calendar: calendar)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }

        let now = time(9)
        try store.recordGlass(at: now)
        let progress = try store.progress(at: now, calendar: calendar)
        let plan = WaterReminder.plan(goal: progress.goalMilliliters, total: progress.milliliters,
                                      now: now, history: [], calendar: calendar)

        XCTAssertEqual(plan?.date, time(13, 15, 1))
        XCTAssertEqual(plan?.remainingMilliliters, 2_050)
    }
}
