import Foundation
import SwiftData

/// Stimmung und Energie, 1 (niedrig) bis 5 (hoch), mit kurzer Notiz. Nur lokal gespeichert.
@Model
final class MoodEntry {
    var date: Date
    var mood: Int
    var energy: Int
    var note: String

    init(date: Date = .now, mood: Int, energy: Int, note: String = "") {
        self.date = date
        self.mood = PlusLogic.clampLevel(mood)
        self.energy = PlusLogic.clampLevel(energy)
        self.note = note
    }
}

/// Eine Koffein-Aufnahme mit Uhrzeit. `kind` ist der Rohwert von `CaffeineKind`.
@Model
final class CaffeineEntry {
    var date: Date
    var kind: String
    var milligrams: Double

    init(date: Date = .now, kind: CaffeineKind) {
        self.date = date
        self.kind = kind.rawValue
        self.milligrams = kind.milligrams
    }
}

enum CaffeineKind: String, CaseIterable, Identifiable, Sendable {
    case cup, espresso

    var id: String { rawValue }
    var title: String { self == .cup ? "Tasse" : "Espresso" }
    var systemImage: String { self == .cup ? "cup.and.saucer" : "mug" }
    /// Grobe Richtwerte für eine Tasse Filterkaffee und einen Espresso.
    var milligrams: Double { self == .cup ? 95 : 63 }
}

extension PlusLogic {
    /// Stimmung und Energie bleiben zwischen 1 und 5.
    static func clampLevel(_ level: Int) -> Int { min(max(level, 1), 5) }

    /// Koffein-Summe (mg) des Kalendertags von `now`.
    static func caffeineToday(_ entries: [(date: Date, milligrams: Double)], now: Date = .now,
                              calendar: Calendar = .forma) -> Double {
        entries.filter { calendar.isDate($0.date, inSameDayAs: now) }.reduce(0) { $0 + $1.milligrams }
    }

    /// Was von den Aufnahmen zu `now` noch im Körper ist (Halbwertszeit ca. 5 Stunden; Zukunft zählt voll).
    static func caffeineRemaining(_ entries: [(date: Date, milligrams: Double)], now: Date = .now) -> Double {
        entries.reduce(0) { sum, e in
            let hours = max(0, now.timeIntervalSince(e.date) / 3600)
            return sum + e.milligrams * pow(0.5, hours / 5)
        }
    }
}
