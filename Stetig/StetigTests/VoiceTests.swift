import Foundation
import SwiftData
import Testing
@testable import Stetig

/// Siris Antworten und Verhalten – ohne Siri, direkt über die Sprachlogik.
@MainActor
struct VoiceTests {
    private func makeContext() -> ModelContext {
        ModelContext(Store.make(inMemory: true))
    }

    private func makeHabit(_ name: String, in context: ModelContext, configure: (Habit) -> Void = { _ in }) -> Habit {
        let habit = Habit(name: name)
        habit.createdAt = Day.today.adding(-10).date()
        configure(habit)
        context.insert(habit)
        try? context.save()
        return habit
    }

    @Test func completeMarksDoneAndNeverToggles() {
        let context = makeContext()
        let habit = makeHabit("Lesen", in: context)
        let today = Day.today
        habit.setAmount(1, on: today.adding(-1), in: context)
        habit.setAmount(1, on: today.adding(-2), in: context)

        let first = HabitVoice.complete(habit, today: today, in: context)
        #expect(habit.snapshot(today: today).isDone(today))
        #expect(first == "Lesen für heute abgehakt. Serie: 3 Tage.")

        // Zweites „gemacht“ darf den Haken nicht wieder entfernen.
        let second = HabitVoice.complete(habit, today: today, in: context)
        #expect(habit.snapshot(today: today).isDone(today))
        #expect(second.hasPrefix("Lesen ist heute schon erledigt."))
    }

    @Test func completeWithAmountAddsUp() {
        let context = makeContext()
        let habit = makeHabit("Wasser", in: context) {
            $0.dailyTarget = 8
            $0.unit = "Gläser"
        }
        let today = Day.today
        let partial = HabitVoice.complete(habit, amount: 3, today: today, in: context)
        #expect(partial == "3 Gläser von 8 Gläser bei Wasser.")
        #expect(!habit.snapshot(today: today).isDone(today))

        let done = HabitVoice.complete(habit, amount: 5, today: today, in: context)
        #expect(done.hasPrefix("Wasser für heute abgehakt."))
        #expect(habit.entry(on: today)?.amount == 8)
    }

    @Test func completeWithoutAmountFillsCounter() {
        let context = makeContext()
        let habit = makeHabit("Wasser", in: context) { $0.dailyTarget = 8 }
        _ = HabitVoice.complete(habit, in: context)
        #expect(habit.entry(on: .today)?.amount == 8)
    }

    @Test func completeQuitHabitClearsSlip() {
        let context = makeContext()
        let habit = makeHabit("Nicht rauchen", in: context) {
            $0.kind = .quit
            $0.dailyTarget = 0
        }
        habit.setAmount(1, on: .today, in: context)
        let answer = HabitVoice.complete(habit, in: context)
        #expect(habit.snapshot().isDone(.today))
        #expect(answer.hasPrefix("Nicht rauchen: heute ohne Rückfall."))
    }

    @Test func statusSentences() {
        let context = makeContext()
        let today = Day.today
        let habit = makeHabit("Lesen", in: context)
        #expect(HabitVoice.status(habit, today: today) == "Lesen ist heute noch offen. Aktuelle Serie: 0 Tage, Rekord: 0.")
        habit.setAmount(1, on: today, in: context)
        #expect(HabitVoice.status(habit, today: today) == "Lesen ist heute erledigt. Aktuelle Serie: 1 Tag, Rekord: 1.")

        let weekly = makeHabit("Laufen", in: context) {
            $0.frequency = .perWeek
            $0.timesPerPeriod = 3
        }
        #expect(HabitVoice.status(weekly, today: today).hasPrefix("Laufen: 0 von 3 diese Woche."))

        habit.setPaused(true, today: today, in: context)
        #expect(HabitVoice.status(habit, today: today) == "Lesen ist gerade pausiert.")
    }

    @Test func todaySentence() {
        let context = makeContext()
        #expect(HabitVoice.today([]) == "Du hast noch keine Gewohnheiten angelegt.")
        let a = makeHabit("Lesen", in: context)
        let b = makeHabit("Wasser", in: context)
        let c = makeHabit("Yoga", in: context)
        #expect(HabitVoice.today([a, b, c]) == "Noch 3 offen: Lesen, Wasser und Yoga.")
        _ = HabitVoice.complete(a, in: context)
        _ = HabitVoice.complete(c, in: context)
        #expect(HabitVoice.today([a, b, c]) == "Noch offen: Wasser.")
        _ = HabitVoice.complete(b, in: context)
        #expect(HabitVoice.today([a, b, c]) == "Alles erledigt für heute. Stark!")
    }

    @Test func nameMatching() {
        let habits = [
            HabitEntity(id: "1", name: "Lesen", symbol: "book.fill"),
            HabitEntity(id: "2", name: "Wasser trinken", symbol: "drop.fill"),
            HabitEntity(id: "3", name: "Früh schlafen", symbol: "bed.double.fill"),
        ]
        #expect(HabitVoice.match("lesen", in: habits).map(\.id) == ["1"])
        #expect(HabitVoice.match("Wasser", in: habits).map(\.id) == ["2"])
        #expect(HabitVoice.match("fruh schlafen", in: habits).map(\.id) == ["3"])
        #expect(HabitVoice.match("schlafen", in: habits).map(\.id) == ["3"])
        #expect(HabitVoice.match("Yoga", in: habits).isEmpty)
        #expect(HabitVoice.list(["A", "B", "C"]) == "A, B und C")
        #expect(HabitVoice.list(["A"]) == "A")
    }

    @Test func entityTitleIsPlainName() {
        let emoji = HabitEntity(id: "1", name: "Gitarre", symbol: "🎸")
        #expect(String(localized: emoji.displayRepresentation.title) == "Gitarre")
    }

    @Test func widgetSummaryCountsDueHabits() {
        let context = makeContext()
        let a = makeHabit("A", in: context)
        let b = makeHabit("B", in: context)
        _ = HabitVoice.complete(a, in: context)
        let summary = TodaySummary(habits: WidgetLoader.habits(from: [a, b]))
        #expect(summary.total == 2)
        #expect(summary.done == 1)
        #expect(summary.ordered.first?.name == "B")
    }
}
