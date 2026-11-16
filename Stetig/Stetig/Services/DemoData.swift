import Foundation
import SwiftData

/// Beispieldaten – zum Ausprobieren (Einstellungen › Daten) und für die UI-Tests.
enum DemoData {
    /// Einfacher, reproduzierbarer Zufallsgenerator.
    struct Generator {
        var state: UInt64

        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) % 10_000) / 10_000
        }
    }

    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedDemo") else { return }
        let context = ModelContext(Store.shared)
        guard Store.activeHabits(in: context).isEmpty else { return }
        insert(into: context)
    }

    static func insert(into context: ModelContext, today: Day = .today) {
        var random = Generator(state: 42)
        let history = 300
        let created = today.adding(-history).date()
        var order = HabitAdmin.nextSortOrder(in: context)

        let health = HabitCategory(name: "Gesundheit", symbol: "heart.fill", sortOrder: 0)
        let mind = HabitCategory(name: "Geist", symbol: "brain.head.profile", sortOrder: 1)
        let fitness = HabitCategory(name: "Fitness", symbol: "figure.run", sortOrder: 2)
        [health, mind, fitness].forEach { context.insert($0) }

        func habit(_ name: String, _ symbol: String, _ color: String, _ category: HabitCategory?, configure: (Habit) -> Void = { _ in }) -> Habit {
            let habit = Habit(name: name, symbol: symbol, colorID: color)
            habit.createdAt = created
            habit.sortOrder = order
            order += 1
            configure(habit)
            context.insert(habit)
            habit.category = category
            return habit
        }

        /// Wahrscheinlichkeit steigt über die Zeit leicht an – wie bei echten Gewohnheiten.
        func chance(_ base: Double, offset: Int) -> Double {
            base + 0.25 * (1 - Double(offset) / Double(history))
        }

        // Lesen – Minuten zählen.
        let reading = habit("Lesen", "book.fill", "amber", mind) {
            $0.dailyTarget = 20
            $0.unit = "min"
            $0.step = 5
            $0.details = "Jeden Abend ein paar Seiten"
        }
        for offset in 1..<history {
            let roll = random.next()
            let day = today.adding(-offset)
            if roll < chance(0.5, offset: offset) {
                reading.entries.append(HabitEntry(day: day.key, amount: 20 + Double(Int(random.next() * 4)) * 5))
            } else if roll < chance(0.65, offset: offset) {
                reading.entries.append(HabitEntry(day: day.key, amount: 10))
            }
        }
        if let entry = reading.entry(on: today.adding(-3)) {
            entry.note = "Endlich das Kapitel beendet – sehr spannend."
        }
        if let entry = reading.entry(on: today.adding(-9)) {
            entry.note = "Nur kurz gelesen, war müde."
        }

        // Wasser – Gläser zählen.
        let water = habit("Wasser trinken", "drop.fill", "blue", health) {
            $0.dailyTarget = 8
            $0.unit = "Gläser"
        }
        for offset in 1..<history {
            let roll = random.next()
            let amount: Double = roll < chance(0.45, offset: offset) ? 8 : Double(Int(roll * 8))
            if amount > 0 {
                water.entries.append(HabitEntry(day: today.adding(-offset).key, amount: amount))
            }
        }
        water.entries.append(HabitEntry(day: today.key, amount: 5))

        // Laufen – dreimal pro Woche.
        let running = habit("Laufen", "figure.run", "coral", fitness) {
            $0.frequency = .perWeek
            $0.timesPerPeriod = 3
        }
        for offset in 1..<history where random.next() < chance(0.25, offset: offset) {
            running.entries.append(HabitEntry(day: today.adding(-offset).key, amount: 1))
        }

        // Krafttraining – Montag, Mittwoch, Freitag.
        let strength = habit("Krafttraining", "dumbbell.fill", "red", fitness) {
            $0.frequency = .weekdays
            $0.weekdayMask = 0b001_0101
        }
        for offset in 1..<history {
            let day = today.adding(-offset)
            let roll = random.next()
            if strength.weekdayMask & (1 << day.weekdayIndex) != 0, roll < chance(0.6, offset: offset) {
                strength.entries.append(HabitEntry(day: day.key, amount: 1))
            }
        }

        // Meditieren – einfaches Abhaken, heute schon erledigt.
        let meditation = habit("Meditieren", "figure.mind.and.body", "violet", mind)
        for offset in 1..<history where random.next() < chance(0.55, offset: offset) || offset < 12 {
            meditation.entries.append(HabitEntry(day: today.adding(-offset).key, amount: 1))
        }
        meditation.entries.append(HabitEntry(day: today.key, amount: 1, note: "10 Minuten Atemübung"))

        // Abgewöhnen – seit 80 Tagen, mit zwei Rückfällen.
        let smoking = habit("Nicht rauchen", "nosign", "green", health) {
            $0.kind = .quit
            $0.dailyTarget = 0
            $0.startDay = today.adding(-80).key
        }
        smoking.entries.append(HabitEntry(day: today.adding(-61).key, amount: 1, note: "Stressiger Tag."))
        smoking.entries.append(HabitEntry(day: today.adding(-34).key, amount: 1))

        // Tagebuch – mit ein paar übersprungenen Tagen.
        let journal = habit("Tagebuch", "pencil", "teal", mind)
        for offset in 1..<history {
            let roll = random.next()
            let day = today.adding(-offset)
            if (20...24).contains(offset) {
                journal.entries.append(HabitEntry(day: day.key, skipped: true, note: offset == 24 ? "Urlaub" : ""))
            } else if roll < chance(0.4, offset: offset) {
                journal.entries.append(HabitEntry(day: day.key, amount: 1))
            }
        }

        Store.commit(context)
    }
}
