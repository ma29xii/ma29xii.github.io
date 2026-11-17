import Foundation
import SwiftData
import Testing
@testable import Stetig

/// Wochen- und Jahresrückblick: Zählweise für Aufbauen und Abgewöhnen.
@MainActor
struct ReviewTests {
    // Montag, 16. November 2026 – Donnerstag ist „heute“.
    private let monday = Day(year: 2026, month: 11, day: 16)
    private var today: Day { monday.adding(3) }

    private func makeHabits(in context: ModelContext) -> [Habit] {
        let read = Habit(name: "Lesen")
        read.createdAt = today.adding(-60).date()
        context.insert(read)
        for offset in [0, 2, 3] {
            read.setAmount(1, on: monday.adding(offset), in: context)
        }

        let smoke = Habit(name: "Nicht rauchen")
        smoke.kind = .quit
        smoke.dailyTarget = 0
        smoke.createdAt = today.adding(-60).date()
        context.insert(smoke)
        smoke.setAmount(1, on: monday.adding(1), in: context)   // Rückfall am Dienstag
        return [read, smoke]
    }

    @Test func weekCountsDoneAndMissedDays() {
        let context = ModelContext(Store.make(inMemory: true))
        let habits = makeHabits(in: context)
        #expect(monday.weekdayIndex == 0)

        let review = Review(scope: .week, offset: 0, habits: habits, today: today, weekStart: 0)
        #expect(review.start == monday)
        #expect(review.end == monday.adding(6))
        #expect(review.days.count == 4)                // Mo–Do, Zukunft zählt nicht
        #expect(review.done == 6)
        #expect(review.due == 8)
        #expect(review.rate == 0.75)
        #expect(review.perfectDays == 3)               // nur Dienstag war nicht perfekt
        #expect(review.bestDay?.rate == 1)
        #expect(review.lines.count == 2)
        #expect(review.lines.allSatisfy { $0.done == 3 && $0.due == 4 })
        #expect(review.title == "KW 47")
    }

    @Test func todayCountsOnlyWhenDone() {
        let context = ModelContext(Store.make(inMemory: true))
        let habit = Habit(name: "Wasser")
        habit.createdAt = today.adding(-10).date()
        context.insert(habit)
        let review = Review(scope: .week, offset: 0, habits: [habit], today: today, weekStart: 0)
        // Mo–Mi verpasst, Donnerstag (heute) noch offen → zählt nicht als verpasst.
        #expect(review.due == 3)
        #expect(review.done == 0)
    }

    @Test func yearGroupsByMonth() {
        let context = ModelContext(Store.make(inMemory: true))
        let habits = makeHabits(in: context)
        let review = Review(scope: .year, offset: 0, habits: habits, today: today, weekStart: 0)
        #expect(review.start == Day(year: 2026, month: 1, day: 1))
        #expect(review.end == Day(year: 2026, month: 12, day: 31))
        #expect(review.title == "2026")
        let months = review.monthRates
        #expect(months.count == 12)
        #expect(months[0] == nil)                      // vor dem Start
        #expect(months[10] != nil)                     // November
        #expect(months[11] == nil)                     // Zukunft
        #expect(review.done <= review.due)

        let previous = Review(scope: .year, offset: -1, habits: habits, today: today, weekStart: 0)
        #expect(previous.rate == nil)
        #expect(previous.lines.isEmpty)
    }

    @Test func weeklyTargetHabitsAreNotPenalisedForFreeDays() {
        var rule = HabitRule(firstDay: monday.adding(-30))
        rule.frequency = .perWeek
        rule.timesPerPeriod = 3
        let snapshot = HabitSnapshot(
            rule: rule,
            records: [monday.ordinal: DayRecord(amount: 1)],
            today: today
        )
        let freeDay = snapshot.dayTally(monday.adding(1))
        #expect(freeDay.done == 0 && freeDay.due == 0)
        let week = snapshot.tally(from: monday.adding(-7), through: monday.adding(-1))
        #expect(week.due == 3)
        #expect(week.done == 0)
    }
}
