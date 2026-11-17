import Foundation
import SwiftData
import Testing
@testable import Stetig

@MainActor
struct OverviewTests {
    private func makeContext() -> ModelContext {
        ModelContext(Store.make(inMemory: true))
    }

    @Test func dayFractionCountsOnlyDueHabits() {
        let context = makeContext()
        let today = Day.today
        let daily = Habit(name: "Täglich")
        daily.createdAt = today.adding(-10).date()
        let weekly = Habit(name: "Wöchentlich")
        weekly.frequency = .perWeek
        weekly.timesPerPeriod = 2
        weekly.createdAt = today.adding(-10).date()
        context.insert(daily)
        context.insert(weekly)
        try? context.save()

        let yesterday = today.adding(-1)
        // Nur die tägliche Gewohnheit ist fällig, x-mal-pro-Woche zählt nur, wenn erledigt.
        #expect(Overview(habits: [daily, weekly], today: today, weekStart: 0).dayFraction(yesterday) == 0)

        daily.setAmount(1, on: yesterday, in: context)
        #expect(Overview(habits: [daily, weekly], today: today, weekStart: 0).dayFraction(yesterday) == 1)

        weekly.setAmount(1, on: yesterday, in: context)
        #expect(Overview(habits: [daily, weekly], today: today, weekStart: 0).dayFraction(yesterday) == 1)

        daily.setAmount(0, on: yesterday, in: context)
        #expect(Overview(habits: [daily, weekly], today: today, weekStart: 0).dayFraction(yesterday) == 0.5)
    }

    @Test func skippedHabitIsIgnored() {
        let context = makeContext()
        let today = Day.today
        let habit = Habit(name: "A")
        habit.createdAt = today.adding(-5).date()
        context.insert(habit)
        habit.setSkipped(true, on: today.adding(-1), in: context)
        #expect(Overview(habits: [habit], today: today, weekStart: 0).dayFraction(today.adding(-1)) == nil)
    }

    @Test func perfectDays() {
        let context = makeContext()
        let today = Day.today
        let habit = Habit(name: "A")
        habit.createdAt = today.adding(-9).date()
        context.insert(habit)
        for offset in [1, 2, 3, 6, 7] {
            habit.setAmount(1, on: today.adding(-offset), in: context)
        }
        let perfect = Overview(habits: [habit], today: today, weekStart: 0).perfectDays(lookback: 30)
        #expect(perfect.count == 5)
        #expect(perfect.bestRun == 3)
    }

    @Test func achievementsProgress() {
        let context = makeContext()
        let today = Day.today
        let habit = Habit(name: "A")
        habit.createdAt = today.adding(-20).date()
        context.insert(habit)
        for offset in 1...7 {
            habit.setAmount(1, on: today.adding(-offset), in: context)
        }
        let list = Achievements.evaluate(Overview(habits: [habit], today: today, weekStart: 0))
        #expect(list.first { $0.id == "first" }?.unlocked == true)
        #expect(list.first { $0.id == "streak7" }?.unlocked == true)
        #expect(list.first { $0.id == "streak30" }?.unlocked == false)
        let progress = list.first { $0.id == "streak30" }?.progress ?? 0
        #expect(abs(progress - 7.0 / 30.0) < 0.0001)
    }
}
