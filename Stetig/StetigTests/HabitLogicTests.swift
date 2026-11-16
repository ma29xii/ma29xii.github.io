import Foundation
import Testing
@testable import Stetig

/// Montag, 16. November 2026.
private let monday = Day(year: 2026, month: 11, day: 16)

private func snapshot(
    kind: HabitKind = .build,
    frequency: HabitFrequency = .daily,
    mask: Int = 0b111_1111,
    times: Int = 3,
    target: Double = 1,
    first: Day,
    last: Day? = nil,
    today: Day,
    done: [Day] = [],
    amounts: [Day: Double] = [:],
    skipped: [Day] = [],
    pausedSince: Day? = nil
) -> HabitSnapshot {
    var records: [Int: DayRecord] = [:]
    for day in done { records[day.ordinal] = DayRecord(amount: target) }
    for (day, amount) in amounts { records[day.ordinal] = DayRecord(amount: amount) }
    for day in skipped { records[day.ordinal] = DayRecord(amount: 0, skipped: true) }
    let rule = HabitRule(
        kind: kind,
        frequency: frequency,
        weekdayMask: mask,
        timesPerPeriod: times,
        dailyTarget: target,
        firstDay: first,
        lastDay: last,
        weekStart: 0
    )
    return HabitSnapshot(rule: rule, records: records, today: today, pausedSince: pausedSince)
}

struct DayTests {
    @Test func epochAndKnownOrdinals() {
        #expect(Day(year: 1970, month: 1, day: 1).ordinal == 0)
        #expect(Day(year: 2000, month: 3, day: 1).ordinal == 11_017)
        #expect(Day(year: 1969, month: 12, day: 31).ordinal == -1)
    }

    @Test func keyRoundTrip() {
        for key in [19_700_101, 20_000_229, 20_240_229, 20_261_116, 20_261_231, 20_270_101, 19_991_231] {
            #expect(Day(key: key).key == key)
        }
        var day = Day(year: 2023, month: 12, day: 25)
        for _ in 0..<800 {
            let c = day.components
            #expect(Day(year: c.year, month: c.month, day: c.day) == day)
            day = day.adding(1)
        }
    }

    @Test func weekdays() {
        #expect(monday.weekdayIndex == 0)
        #expect(monday.adding(6).weekdayIndex == 6)
        #expect(Day(year: 1970, month: 1, day: 1).weekdayIndex == 3)
        #expect(Day(year: 1969, month: 12, day: 28).weekdayIndex == 6)
    }

    @Test func months() {
        #expect(Day(year: 2024, month: 2, day: 10).daysInMonth == 29)
        #expect(Day(year: 2026, month: 2, day: 10).daysInMonth == 28)
        #expect(Day(year: 2026, month: 12, day: 31).daysInMonth == 31)
        #expect(Day(year: 2026, month: 11, day: 16).addingMonths(2) == Day(year: 2027, month: 1, day: 1))
        #expect(Day(year: 2026, month: 1, day: 16).addingMonths(-1) == Day(year: 2025, month: 12, day: 1))
        #expect(Day(year: 2026, month: 11, day: 16).startOfMonth.key == 20_261_101)
    }

    @Test func weekStart() {
        let wednesday = monday.adding(2)
        #expect(wednesday.startOfWeek(weekStart: 0) == monday)
        #expect(wednesday.startOfWeek(weekStart: 6) == monday.adding(-1))
        #expect(monday.startOfWeek(weekStart: 0) == monday)
        #expect(monday.adding(-1).startOfWeek(weekStart: 6) == monday.adding(-1))
    }

    @Test func calendarBridge() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 1, minute: 30))!
        let day = Day(date: date, calendar: calendar)
        #expect(day.key == 20_260_329)
        #expect(Day(date: day.date(calendar: calendar), calendar: calendar) == day)
    }
}

struct DailyStreakTests {
    @Test func countsConsecutiveDaysIncludingToday() {
        let today = monday.adding(10)
        let s = snapshot(first: monday, today: today, done: (0..<5).map { today.adding(-$0) })
        #expect(s.currentStreak == 5)
        #expect(s.bestStreak == 5)
    }

    @Test func todayNotDoneYetDoesNotBreak() {
        let today = monday.adding(10)
        let s = snapshot(first: monday, today: today, done: (1..<5).map { today.adding(-$0) })
        #expect(s.currentStreak == 4)
        #expect(s.isPending(today))
    }

    @Test func gapResetsCurrentButKeepsBest() {
        let today = monday.adding(20)
        // 6 Tage am Stück, dann 1 Lücke, dann 3 Tage bis heute.
        let old = (4..<10).map { today.adding(-$0) }
        let recent = (0..<3).map { today.adding(-$0) }
        let s = snapshot(first: monday, today: today, done: old + recent)
        #expect(s.currentStreak == 3)
        #expect(s.bestStreak == 6)
    }

    @Test func skippedDayIsNeutral() {
        let today = monday.adding(10)
        let done = [0, 1, 3, 4].map { today.adding(-$0) }
        let s = snapshot(first: monday, today: today, done: done, skipped: [today.adding(-2)])
        #expect(s.currentStreak == 4)
        #expect(s.state(today.adding(-2)) == .skipped)
    }

    @Test func emptyHabit() {
        let s = snapshot(first: monday, today: monday)
        #expect(s.currentStreak == 0)
        #expect(s.bestStreak == 0)
        #expect(s.totalDone == 0)
        #expect(s.rate(days: 30) == 0)
        #expect(s.isPending(monday))
    }

    @Test func futureStartDate() {
        let s = snapshot(first: monday.adding(5), today: monday)
        #expect(s.unitStatuses().isEmpty)
        #expect(s.currentStreak == 0)
        #expect(!s.isPending(monday))
        #expect(s.state(monday) == .notDue)
    }

    @Test func partialAmountIsNotDone() {
        let s = snapshot(target: 8, first: monday, today: monday.adding(1), amounts: [monday: 8, monday.adding(1): 3])
        #expect(s.isDone(monday))
        #expect(!s.isDone(monday.adding(1)))
        #expect(s.fraction(monday.adding(1)) == 3.0 / 8.0)
        #expect(s.cell(monday).level == 1)
        let partial = s.cell(monday.adding(1)).level
        #expect(partial > 0.25 && partial < 1)
        #expect(s.currentStreak == 1)
    }

    @Test func endDateStopsTracking() {
        let today = monday.adding(10)
        let s = snapshot(first: monday, last: monday.adding(4), today: today, done: (0...4).map { monday.adding($0) })
        #expect(s.currentStreak == 5)
        #expect(!s.isPending(today))
        #expect(s.rate(days: 30) == 1)
    }
}

struct WeekdayScheduleTests {
    /// Montag, Mittwoch, Freitag.
    private let mask = 0b001_0101

    @Test func nonDueDaysDoNotBreak() {
        let today = monday.adding(14) // Montag
        let done = [monday, monday.adding(2), monday.adding(4), monday.adding(7), monday.adding(9), monday.adding(11), today]
        let s = snapshot(frequency: .weekdays, mask: mask, first: monday, today: today, done: done)
        #expect(s.currentStreak == 7)
        #expect(!s.isDue(monday.adding(1)))
        #expect(s.isDue(monday.adding(2)))
        #expect(s.state(monday.adding(1)) == .notDue)
    }

    @Test func missedDueDayBreaks() {
        let today = monday.adding(14)
        let done = [monday, monday.adding(2), monday.adding(7), monday.adding(9), monday.adding(11), today]
        let s = snapshot(frequency: .weekdays, mask: mask, first: monday, today: today, done: done)
        // Freitag der ersten Woche fehlt.
        #expect(s.currentStreak == 4)
        #expect(s.bestStreak == 4)
    }

    @Test func rateIgnoresNonDueDays() {
        let today = monday.adding(13) // Sonntag
        let done = [monday, monday.adding(2), monday.adding(4), monday.adding(7)]
        let s = snapshot(frequency: .weekdays, mask: mask, first: monday, today: today, done: done)
        // 6 fällige Tage, 4 erledigt.
        #expect(abs(s.rate(days: 30) - 4.0 / 6.0) < 0.0001)
    }
}

struct PeriodStreakTests {
    @Test func weeksInARow() {
        let today = monday.adding(16) // Mittwoch der dritten Woche
        let done = [0, 1, 2, 7, 9, 11].map { monday.adding($0) }
        let s = snapshot(frequency: .perWeek, times: 3, first: monday, today: today, done: done)
        // Zwei volle Wochen erfüllt, laufende Woche noch offen.
        #expect(s.currentStreak == 2)
        #expect(s.streakUnit(2) == "Wochen")
        #expect(s.isPending(today))
        #expect(s.periodProgress?.done == 0)
        #expect(s.periodProgress?.target == 3)
    }

    @Test func currentWeekCountsOnceMet() {
        let today = monday.adding(16)
        let done = [0, 1, 2, 7, 9, 11, 14, 15, 16].map { monday.adding($0) }
        let s = snapshot(frequency: .perWeek, times: 3, first: monday, today: today, done: done)
        #expect(s.currentStreak == 3)
        #expect(!s.isPending(today))
    }

    @Test func missedWeekBreaks() {
        let today = monday.adding(23)
        let done = [0, 1, 2, 7, 14, 15, 16].map { monday.adding($0) }
        let s = snapshot(frequency: .perWeek, times: 3, first: monday, today: today, done: done)
        #expect(s.currentStreak == 1)
        #expect(s.bestStreak == 1)
    }

    @Test func monthly() {
        let first = Day(year: 2026, month: 9, day: 1)
        let today = Day(year: 2026, month: 11, day: 16)
        let done = [Day(year: 2026, month: 9, day: 3), Day(year: 2026, month: 9, day: 20),
                    Day(year: 2026, month: 10, day: 1), Day(year: 2026, month: 10, day: 31),
                    Day(year: 2026, month: 11, day: 2)]
        let s = snapshot(frequency: .perMonth, times: 2, first: first, today: today, done: done)
        #expect(s.currentStreak == 2)
        #expect(s.periodProgress?.done == 1)
        #expect(s.streakUnit(1) == "Monat")
    }
}

struct QuitHabitTests {
    @Test func cleanDaysCountFromStart() {
        let today = monday.adding(9)
        let s = snapshot(kind: .quit, target: 0, first: monday, today: today)
        #expect(s.currentStreak == 10)
        #expect(s.totalDone == 10)
        #expect(s.state(today) == .done)
        #expect(s.cell(today).level == 1)
        #expect(s.cell(monday.adding(-1)).level == 0)
    }

    @Test func slipResets() {
        let today = monday.adding(9)
        let s = snapshot(kind: .quit, target: 0, first: monday, today: today, amounts: [monday.adding(6): 1])
        #expect(s.currentStreak == 3)
        #expect(s.bestStreak == 6)
        #expect(s.isSlip(monday.adding(6)))
        #expect(s.state(monday.adding(6)) == .slipped)
        #expect(s.cell(monday.adding(6)).slipped)
    }

    @Test func limitAllowsSome() {
        let today = monday.adding(2)
        let s = snapshot(kind: .quit, target: 2, first: monday, today: today, amounts: [monday: 2, monday.adding(1): 3])
        #expect(s.isDone(monday))
        #expect(s.isSlip(monday.adding(1)))
        #expect(s.currentStreak == 1)
        #expect(s.cell(monday).level == 0.55)
    }
}

struct PauseTests {
    @Test func pausedDaysAreNeutral() {
        let today = monday.adding(10)
        let done = (0...4).map { monday.adding($0) }
        let s = snapshot(first: monday, today: today, done: done, pausedSince: monday.adding(5))
        #expect(s.currentStreak == 5)
        #expect(!s.isPending(today))
        #expect(s.state(today) == .skipped)
    }
}

struct StatisticsTests {
    @Test func rateAndTotals() {
        let today = monday.adding(9)
        let done = [0, 1, 2, 3, 4].map { monday.adding($0) }
        let s = snapshot(first: monday, today: today, done: done)
        // 9 abgeschlossene Tage (heute zählt noch nicht), 5 erledigt.
        #expect(abs(s.rate(days: 30) - 5.0 / 9.0) < 0.0001)
        #expect(s.totalDone == 5)
        #expect(s.weekdayCounts() == [1, 1, 1, 1, 1, 0, 0])
        let weeks = s.weeklyCounts(weeks: 2)
        #expect(weeks.count == 2)
        #expect(weeks[0].count == 5)
        #expect(weeks[1].count == 0)
    }

    @Test func runHelpers() {
        typealias U = HabitSnapshot.UnitStatus
        let statuses: [U] = [.met, .met, .missed, .met, .neutral, .met, .neutral]
        #expect(HabitSnapshot.currentRun(statuses) == 2)
        #expect(HabitSnapshot.bestRun(statuses) == 2)
        #expect(HabitSnapshot.currentRun([]) == 0)
        #expect(HabitSnapshot.bestRun([.missed, .neutral]) == 0)
    }

    @Test func formatting() {
        #expect(Format.number(3) == "3")
        #expect(Format.number(1.5) == "1,5")
        #expect(Format.amount(8, unit: "Gläser") == "8 Gläser")
        #expect(Format.amount(2, unit: "") == "2×")
        #expect(Format.percent(0.666) == "67 %")
    }
}
