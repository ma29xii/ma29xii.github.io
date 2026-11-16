import Foundation
import SwiftData
import Testing
@testable import Stetig

/// Tests gegen eine echte (flüchtige) SwiftData-Datenbank.
@MainActor
struct StoreTests {
    private func makeContext() -> ModelContext {
        ModelContext(Store.make(inMemory: true))
    }

    private func makeHabit(_ name: String = "Test", in context: ModelContext, configure: (Habit) -> Void = { _ in }) -> Habit {
        let habit = Habit(name: name)
        configure(habit)
        context.insert(habit)
        try? context.save()
        return habit
    }

    @Test func simpleHabitToggles() {
        let context = makeContext()
        let habit = makeHabit(in: context)
        let today = Day.today

        habit.advance(on: today, in: context)
        #expect(habit.snapshot(today: today).isDone(today))
        #expect(habit.entries.count == 1)

        habit.advance(on: today, in: context)
        #expect(!habit.snapshot(today: today).isDone(today))
        #expect(habit.entries.count == 1)
    }

    @Test func counterStepsUpAndResets() {
        let context = makeContext()
        let habit = makeHabit(in: context) {
            $0.dailyTarget = 3
            $0.step = 1
        }
        let today = Day.today

        habit.advance(on: today, in: context)
        habit.advance(on: today, in: context)
        #expect(habit.entry(on: today)?.amount == 2)
        #expect(!habit.snapshot(today: today).isDone(today))

        habit.advance(on: today, in: context)
        #expect(habit.snapshot(today: today).isDone(today))

        habit.advance(on: today, in: context)
        #expect(habit.entry(on: today)?.amount == 0)
    }

    @Test func quitHabitLogsSlip() {
        let context = makeContext()
        let habit = makeHabit(in: context) {
            $0.kind = .quit
            $0.dailyTarget = 0
        }
        let today = Day.today
        #expect(habit.snapshot(today: today).isDone(today))

        habit.advance(on: today, in: context)
        #expect(habit.snapshot(today: today).isSlip(today))

        habit.advance(on: today, in: context)
        #expect(habit.snapshot(today: today).isDone(today))
    }

    @Test func skippingClearsAmountAndKeepsStreak() {
        let context = makeContext()
        let habit = makeHabit(in: context)
        let today = Day.today
        habit.createdAt = today.adding(-10).date()

        habit.setAmount(1, on: today.adding(-2), in: context)
        habit.setAmount(1, on: today.adding(-1), in: context)
        habit.setSkipped(true, on: today.adding(-1), in: context)
        habit.setAmount(1, on: today, in: context)

        let snapshot = habit.snapshot(today: today)
        #expect(habit.entry(on: today.adding(-1))?.amount == 0)
        #expect(snapshot.currentStreak == 2)

        habit.setAmount(1, on: today.adding(-1), in: context)
        #expect(habit.entry(on: today.adding(-1))?.skipped == false)
        #expect(habit.snapshot(today: today).currentStreak == 3)
    }

    @Test func pauseAndResumeFreezesStreak() {
        let context = makeContext()
        let habit = makeHabit(in: context)
        let today = Day.today
        habit.createdAt = today.adding(-20).date()
        for offset in 6...9 {
            habit.setAmount(1, on: today.adding(-offset), in: context)
        }

        habit.setPaused(true, today: today.adding(-5), in: context)
        #expect(habit.isPaused)
        #expect(habit.snapshot(today: today).currentStreak == 4)

        habit.setPaused(false, today: today, in: context)
        #expect(!habit.isPaused)
        #expect(habit.entry(on: today.adding(-3))?.skipped == true)
        #expect(habit.snapshot(today: today).currentStreak == 4)
    }

    @Test func notesSurviveClearingAmount() {
        let context = makeContext()
        let habit = makeHabit(in: context)
        let today = Day.today
        habit.setNote("  Guter Tag  ", on: today, in: context)
        habit.advance(on: today, in: context)
        habit.advance(on: today, in: context)
        #expect(habit.entry(on: today)?.note == "Guter Tag")
        habit.clear(on: today, in: context)
        #expect(habit.entry(on: today)?.note == "")
    }

    @Test func earlierEntriesExtendHistory() {
        let context = makeContext()
        let habit = makeHabit(in: context)
        let today = Day.today
        // Eintrag vor dem Erstellungsdatum nachtragen.
        for offset in 0...4 {
            habit.setAmount(1, on: today.adding(-offset), in: context)
        }
        let snapshot = habit.snapshot(today: today)
        #expect(snapshot.rule.firstDay == today.adding(-4))
        #expect(snapshot.currentStreak == 5)
    }

    @Test func backupRoundTrip() throws {
        let source = makeContext()
        DemoData.insert(into: source)
        let original = Backup.snapshot(of: source)
        #expect(original.habits.count == 7)
        #expect(original.categories.count == 3)

        let data = try Backup.encode(original)
        let decoded = try Backup.decode(data)
        #expect(decoded.habits == original.habits)

        let target = makeContext()
        let summary = Backup.restore(decoded, into: target)
        #expect(summary.habits == 7)
        let restored = Backup.snapshot(of: target)
        #expect(restored.habits == original.habits)
        #expect(restored.categories == original.categories)

        // Zweiter Import darf nichts verdoppeln.
        Backup.restore(decoded, into: target)
        #expect(Backup.snapshot(of: target).habits == original.habits)
    }

    @Test func backupRejectsForeignFiles() {
        #expect(throws: (any Error).self) {
            _ = try Backup.decode(Data("{\"hello\": 1}".utf8))
        }
    }

    @Test func csvExportHasHeaderAndRows() {
        let context = makeContext()
        let habit = makeHabit("Lesen; \"viel\"", in: context)
        habit.setAmount(1, on: Day(key: 20_261_116), in: context)
        let text = String(decoding: Backup.exportCSV(from: context), as: UTF8.self)
        #expect(text.contains("Gewohnheit;Datum;Menge;Einheit;Übersprungen;Notiz"))
        #expect(text.contains("\"Lesen; \"\"viel\"\"\";2026-11-16;1;\"\";nein;\"\""))
    }

    @Test func demoDataIsPlausible() {
        let context = makeContext()
        DemoData.insert(into: context)
        let habits = Store.activeHabits(in: context)
        #expect(habits.count == 7)
        for habit in habits {
            let days = habit.entries.map(\.day)
            #expect(Set(days).count == days.count, "Doppelte Tage bei \(habit.name)")
            let snapshot = habit.snapshot()
            #expect(snapshot.bestStreak >= snapshot.currentStreak)
            #expect((0...1).contains(snapshot.rate(days: 30)))
        }
        let overview = Overview(habits: habits, weekStart: 0)
        #expect(overview.totalDone > 100)
        #expect(Achievements.evaluate(overview).contains { $0.unlocked })
    }

    @Test func deleteEverything() {
        let context = makeContext()
        DemoData.insert(into: context)
        Backup.deleteEverything(in: context)
        #expect(Store.activeHabits(in: context).isEmpty)
        #expect(Backup.snapshot(of: context).categories.isEmpty)
    }

    @Test func draftAppliesAllFields() {
        let context = makeContext()
        var draft = HabitTemplates.make("Lesen", "book.fill", "amber", target: 20, unit: "min", step: 5)
        draft.frequency = .weekdays
        draft.weekdayMask = 0b000_0011
        draft.reminderEnabled = true
        draft.reminderMinutes = 7 * 60 + 30
        #expect(draft.isValid)

        let habit = makeHabit(in: context)
        draft.apply(to: habit, categories: [])
        #expect(habit.name == "Lesen")
        #expect(habit.isCounter)
        #expect(habit.frequency == .weekdays)
        #expect(Reminders.reminderWeekdays(for: habit) == [0, 1])
        #expect(HabitDraft(habit: habit).dailyTarget == 20)

        draft.weekdayMask = 0
        #expect(!draft.isValid)
        draft.frequency = .daily
        draft.name = "   "
        #expect(!draft.isValid)
    }
}
