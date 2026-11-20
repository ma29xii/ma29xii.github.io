import XCTest
@testable import Forma

final class Runde12SleepPlanTests: XCTestCase {
    func testSleepNeedIncludesTodaysStrainAndRecentSleepDebt() {
        let today = DayMetrics(date: date(11, 20), activeEnergy: 1100)
        let history = (16...19).map { day in
            DayMetrics(date: date(11, day),
                       sleep: SleepNight(start: date(11, day - 1, 23), end: date(11, day, 5),
                                         segments: [], reportedAsleep: 6 * 3600))
        }

        let scores = ScoreEngine.scores(today: today, history: history)
        XCTAssertEqual(CoachEngine.measuredSleepNeed(scores, strainAvailable: true, history: history), 30834)
        XCTAssertNil(CoachEngine.measuredSleepNeed(scores, strainAvailable: false, history: history))
    }

    func testWorkdayAssignmentUsesTheDayOfTheWakeTime() throws {
        let plan = SleepPlanner(workdayWake: 7 * 60, freeDayWake: 9 * 60, workdays: [.saturday])
        let saturday = try XCTUnwrap(plan.window(wakingOn: date(11, 21), sleepNeed: 8 * 3600, calendar: calendar))
        let monday = try XCTUnwrap(plan.window(wakingOn: date(11, 23), sleepNeed: 8 * 3600, calendar: calendar))

        XCTAssertEqual(saturday.bed, date(11, 20, 23))
        XCTAssertEqual(saturday.wake, date(11, 21, 7))
        XCTAssertEqual(monday.bed, date(11, 23, 1))
        XCTAssertEqual(monday.wake, date(11, 23, 9))
    }

    func testEditingOneDayMovesTheWholeGroupByTheSameAmount() throws {
        var plan = SleepPlanner(workdayWake: 7 * 60, freeDayWake: 9 * 60)
        let friday = date(11, 20)
        let first = try XCTUnwrap(plan.window(wakingOn: friday, sleepNeed: 8 * 3600, calendar: calendar))

        plan.setWakeMinutes(7 * 60 + 45, for: .monday)
        let moved = try XCTUnwrap(plan.window(wakingOn: friday, sleepNeed: 8 * 3600, calendar: calendar))

        XCTAssertEqual(moved.bed.timeIntervalSince(first.bed), 45 * 60)
        XCTAssertEqual(moved.wake.timeIntervalSince(first.wake), 45 * 60)
        XCTAssertEqual(plan.wakeMinutes(for: .saturday), 9 * 60)
    }

    func testTonightMovesFromFridayToSaturdayAtWakeTime() throws {
        let plan = SleepPlanner(workdayWake: 7 * 60, freeDayWake: 9 * 60)
        let fridayMorning = try XCTUnwrap(plan.nextWindow(after: date(11, 20, 6), sleepNeed: 8 * 3600, calendar: calendar))
        let saturdayMorning = try XCTUnwrap(plan.nextWindow(after: date(11, 20, 7), sleepNeed: 8 * 3600, calendar: calendar))

        XCTAssertEqual(fridayMorning.wake, date(11, 20, 7))
        XCTAssertEqual(saturdayMorning.wake, date(11, 21, 9))
    }

    func testEarlyScheduleKeepsMondayThroughSundayOrder() {
        let days = SleepPlanner.week(containing: date(11, 22), calendar: calendar)
        XCTAssertEqual(days, (16...22).map { date(11, $0) })
    }

    func testSpringChangeKeepsElapsedSleepDuration() throws {
        var berlin = calendar
        berlin.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let sunday = try XCTUnwrap(berlin.date(from: DateComponents(year: 2026, month: 3, day: 29)))
        let plan = SleepPlanner(freeDayWake: 2 * 60 + 30)
        let night = try XCTUnwrap(plan.window(wakingOn: sunday, sleepNeed: 8 * 3600, calendar: berlin))

        XCTAssertEqual(berlin.component(.hour, from: night.wake), 3)
        XCTAssertEqual(berlin.component(.minute, from: night.wake), 0)
        XCTAssertEqual(night.wake.timeIntervalSince(night.bed), 8 * 3600)
        XCTAssertEqual(berlin.component(.day, from: night.bed), 28)
        XCTAssertEqual(berlin.component(.hour, from: night.bed), 18)
    }

    func testAutumnChangeUsesTheFirstOccurrenceOfAnAmbiguousWakeTime() throws {
        var berlin = calendar
        berlin.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let sunday = try XCTUnwrap(berlin.date(from: DateComponents(year: 2026, month: 10, day: 25)))
        let plan = SleepPlanner(freeDayWake: 2 * 60 + 30)
        let night = try XCTUnwrap(plan.window(wakingOn: sunday, sleepNeed: 8 * 3600, calendar: berlin))

        XCTAssertEqual(night.wake, date(10, 25, 0, 30))
        XCTAssertEqual(night.wake.timeIntervalSince(night.bed), 8 * 3600)
    }

    func testTimelineWrapsIntervalsThatCrossTheEveningBoundary() throws {
        let plan = SleepPlanner(workdayWake: 22 * 60)
        let night = try XCTUnwrap(plan.window(wakingOn: date(11, 20), sleepNeed: 8 * 3600, calendar: calendar))

        XCTAssertEqual(night.timelineSegments(calendar: calendar), [0..<(4.0 / 24), (20.0 / 24)..<1])
    }

    func testInvalidNeedAndClockInputAreRejected() {
        var plan = SleepPlanner(workdayWake: 7 * 60)
        XCTAssertNil(plan.window(wakingOn: date(11, 20), sleepNeed: .nan, calendar: calendar))
        XCTAssertNil(plan.window(wakingOn: date(11, 20), sleepNeed: 0, calendar: calendar))
        XCTAssertNil(plan.window(wakingOn: date(11, 20), sleepNeed: 14 * 3600, calendar: calendar))

        plan.setWakeMinutes(1440, for: .monday)
        XCTAssertEqual(plan.wakeMinutes(for: .monday), 7 * 60)
    }

    func testJSONRoundTripAndFallbackForCorruptSettings() throws {
        let plan = SleepPlanner(workdayWake: 7 * 60, freeDayWake: 9 * 60, workdays: [])
        let fallback = SleepPlanner(workdayWake: 6 * 60 + 55)
        let encoded = try XCTUnwrap(plan.encoded())

        XCTAssertEqual(SleepPlanner.restore(encoded, fallback: fallback), plan)
        XCTAssertEqual(SleepPlanner.restore(Data("veraltet".utf8), fallback: fallback), fallback)
        let outOfRange = Data(#"{"workdayWake":1500,"freeDayWake":480,"workdays":[2]}"#.utf8)
        XCTAssertEqual(SleepPlanner.restore(outOfRange, fallback: fallback), fallback)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testStoredScheduleUsesWakeDayForReminder() throws {
        let suite = "SleepPlannerTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = SleepPlanner(workdayWake: 7 * 60, freeDayWake: 9 * 60)
        defaults.set(try XCTUnwrap(plan.encoded()), forKey: SleepPlanner.storageKey)
        let stored = SleepPlanner.load(in: defaults)
        let friday = date(11, 20, 22)
        let sunday = date(11, 22, 22)
        let weekend = try XCTUnwrap(stored.nextWindow(after: friday, sleepNeed: 8 * 3600, calendar: calendar))
        let weekday = try XCTUnwrap(stored.nextWindow(after: sunday, sleepNeed: 8 * 3600, calendar: calendar))
        XCTAssertEqual(weekend.wake, date(11, 21, 9))
        XCTAssertEqual(weekend.reminder, date(11, 21, 0, 30))
        XCTAssertEqual(weekday.wake, date(11, 23, 7))
        XCTAssertEqual(weekday.reminder, date(11, 22, 22, 30))
        XCTAssertEqual(stored.nextWake(after: friday, calendar: calendar), weekend.wake)
    }

    func testNextReminderSkipsTheOngoingNightAfterMidnight() throws {
        let plan = SleepPlanner(workdayWake: 7 * 60)
        let now = date(11, 23, 1)
        let ongoing = try XCTUnwrap(plan.nextWindow(after: now, sleepNeed: 8 * 3600, calendar: calendar))
        let reminder = try XCTUnwrap(plan.nextReminderWindow(after: now, sleepNeed: 8 * 3600, calendar: calendar))

        XCTAssertEqual(ongoing.wake, date(11, 23, 7))
        XCTAssertEqual(reminder.wake, date(11, 24, 7))
        XCTAssertEqual(reminder.reminder, date(11, 23, 22, 30))
    }

    func testLegacyMidnightSurvivesOnWorkdaysAndDaysOff() throws {
        let suite = "SleepPlannerTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(SleepPlanner.load(in: defaults), SleepPlanner())
        defaults.set(0, forKey: CoachNotifier.wakeKey)
        let migrated = SleepPlanner.load(in: defaults)
        XCTAssertEqual(migrated.wakeMinutes(for: .monday), 0)
        XCTAssertEqual(migrated.wakeMinutes(for: .saturday), 0)
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }
}
