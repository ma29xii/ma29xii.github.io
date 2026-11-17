import Foundation
import SwiftData

/// Alle schreibenden Aktionen auf einer Gewohnheit. Jede Aktion speichert
/// sofort und aktualisiert die Widgets.
extension Habit {
    @discardableResult
    func ensureEntry(on day: Day) -> HabitEntry {
        if let existing = entry(on: day) { return existing }
        let entry = HabitEntry(day: day.key)
        entries.append(entry)
        return entry
    }

    func setAmount(_ value: Double, on day: Day, in context: ModelContext) {
        let entry = ensureEntry(on: day)
        entry.amount = max(0, value)
        if entry.amount > 0 { entry.skipped = false }
        entry.updatedAt = Date()
        Store.commit(context)
    }

    func add(_ delta: Double, on day: Day, in context: ModelContext) {
        setAmount((entry(on: day)?.amount ?? 0) + delta, on: day, in: context)
    }

    /// Der schnelle Tipp auf den Haken:
    /// - einfache Gewohnheit: an/aus
    /// - Zähler: einen Schritt weiter, nach Erreichen des Ziels zurück auf 0
    /// - Abgewöhnen: Rückfall eintragen bzw. wieder entfernen
    func advance(on day: Day, in context: ModelContext) {
        let current = entry(on: day)?.amount ?? 0
        switch kind {
        case .build:
            if current >= dailyTarget, current > 0 {
                setAmount(0, on: day, in: context)
            } else if isCounter {
                setAmount(min(dailyTarget, current + max(step, 0.1)), on: day, in: context)
            } else {
                setAmount(max(dailyTarget, 1), on: day, in: context)
            }
        case .quit:
            if dailyTarget <= 0 {
                // Ganz ohne: Tipp trägt einen Rückfall ein bzw. nimmt ihn zurück.
                setAmount(current > 0 ? 0 : 1, on: day, in: context)
            } else {
                // Mit Tageslimit: jeder Tipp zählt eins hoch.
                setAmount(current + max(step, 1), on: day, in: context)
            }
        }
    }

    func setSkipped(_ skipped: Bool, on day: Day, in context: ModelContext) {
        let entry = ensureEntry(on: day)
        entry.skipped = skipped
        if skipped { entry.amount = 0 }
        entry.updatedAt = Date()
        Store.commit(context)
    }

    func setNote(_ note: String, on day: Day, in context: ModelContext) {
        let entry = ensureEntry(on: day)
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.updatedAt = Date()
        Store.commit(context)
    }

    func clear(on day: Day, in context: ModelContext) {
        guard let entry = entry(on: day) else { return }
        entry.amount = 0
        entry.skipped = false
        entry.note = ""
        entry.updatedAt = Date()
        Store.commit(context)
    }

    /// Pausieren friert die Serie ein; beim Fortsetzen werden die pausierten Tage
    /// als „übersprungen“ festgeschrieben.
    func setPaused(_ paused: Bool, today: Day = .today, in context: ModelContext) {
        if paused {
            guard !isPaused else { return }
            pausedSinceDay = today.key
        } else {
            guard isPaused else { return }
            // Höchstens ein Jahr nachtragen – schützt vor kaputten Werten aus Backups.
            var day = max(Day(key: Sanitize.optionalDayKey(pausedSinceDay)), today.adding(-366))
            while day < today {
                let entry = ensureEntry(on: day)
                if entry.amount <= 0 { entry.skipped = true }
                day = day.adding(1)
            }
            pausedSinceDay = 0
        }
        Store.commit(context)
    }
}
