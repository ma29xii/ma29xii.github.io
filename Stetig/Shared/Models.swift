import Foundation
import SwiftData

@Model
final class HabitCategory {
    var uuid: UUID = UUID()
    var name: String = ""
    var symbol: String = "folder"
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Habit.category)
    var habits: [Habit] = []

    init(name: String, symbol: String = "folder", sortOrder: Int = 0) {
        self.uuid = UUID()
        self.name = name
        self.symbol = symbol
        self.sortOrder = sortOrder
    }
}

@Model
final class Habit {
    var uuid: UUID = UUID()
    var name: String = ""
    var details: String = ""
    /// SF-Symbol-Name oder ein Emoji.
    var symbol: String = "checkmark"
    var colorID: String = "indigo"
    var createdAt: Date = Date()
    var sortOrder: Int = 0
    var isArchived: Bool = false

    var kindRaw: String = HabitKind.build.rawValue
    var frequencyRaw: String = HabitFrequency.daily.rawValue
    /// Bit 0 = Montag … Bit 6 = Sonntag.
    var weekdayMask: Int = 0b111_1111
    var timesPerPeriod: Int = 3
    /// Aufbauen: Tagesziel. Abgewöhnen: Tageslimit.
    var dailyTarget: Double = 1
    var unit: String = ""
    /// Schrittweite beim schnellen Eintragen.
    var step: Double = 1

    var reminderEnabled: Bool = false
    /// Minuten seit Mitternacht.
    var reminderMinutes: Int = 20 * 60

    /// Optionaler Zeitraum als `yyyymmdd` (0 = nicht gesetzt).
    var startDay: Int = 0
    var endDay: Int = 0
    /// Seit wann pausiert, als `yyyymmdd` (0 = aktiv).
    var pausedSinceDay: Int = 0

    var category: HabitCategory?

    @Relationship(deleteRule: .cascade, inverse: \HabitEntry.habit)
    var entries: [HabitEntry] = []

    init(name: String, symbol: String = "checkmark", colorID: String = "indigo") {
        self.uuid = UUID()
        self.name = name
        self.symbol = symbol
        self.colorID = colorID
        self.createdAt = Date()
    }
}

@Model
final class HabitEntry {
    /// Tag als `yyyymmdd`.
    var day: Int = 0
    var amount: Double = 0
    var skipped: Bool = false
    var note: String = ""
    var updatedAt: Date = Date()
    var habit: Habit?

    init(day: Int, amount: Double = 0, skipped: Bool = false, note: String = "") {
        self.day = day
        self.amount = amount
        self.skipped = skipped
        self.note = note
        self.updatedAt = Date()
    }
}

// MARK: - Abgeleitete Werte

extension Habit {
    var kind: HabitKind {
        get { HabitKind(rawValue: kindRaw) ?? .build }
        set { kindRaw = newValue.rawValue }
    }

    var frequency: HabitFrequency {
        get { HabitFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    var isPaused: Bool { pausedSinceDay > 0 }

    /// Zählt die Gewohnheit Mengen (z. B. 8 Gläser) statt nur „erledigt“?
    var isCounter: Bool { kind == .build && dailyTarget > 1 }

    var createdDay: Day { Day(date: createdAt) }

    func entry(on day: Day) -> HabitEntry? {
        let key = day.key
        return entries.first { $0.day == key }
    }

    func snapshot(today: Day = .today, weekStart: Int = AppGroup.weekStart) -> HabitSnapshot {
        var first = startDay > 0 ? Day(key: startDay) : createdDay
        var records: [Int: DayRecord] = [:]
        records.reserveCapacity(entries.count)
        let isBuild = kind == .build
        for entry in entries {
            let day = Day(key: entry.day)
            records[day.ordinal] = DayRecord(amount: entry.amount, skipped: entry.skipped)
            if isBuild, entry.amount > 0, day < first { first = day }
        }
        let rule = HabitRule(
            kind: kind,
            frequency: frequency,
            weekdayMask: weekdayMask,
            timesPerPeriod: max(1, timesPerPeriod),
            dailyTarget: isBuild ? max(dailyTarget, 0.0001) : max(dailyTarget, 0),
            firstDay: first,
            lastDay: endDay > 0 ? Day(key: endDay) : nil,
            weekStart: weekStart
        )
        return HabitSnapshot(
            rule: rule,
            records: records,
            today: today,
            pausedSince: pausedSinceDay > 0 ? Day(key: pausedSinceDay) : nil
        )
    }

    /// Kurze Beschreibung des Ziels, z. B. „3× pro Woche“ oder „8 Gläser täglich“.
    var goalDescription: String {
        if kind == .quit {
            return dailyTarget > 0 ? "Höchstens \(Format.amount(dailyTarget, unit: unit)) pro Tag" : "Jeden Tag ohne"
        }
        let amountPart = isCounter || !unit.isEmpty ? Format.amount(dailyTarget, unit: unit) + " · " : ""
        switch frequency {
        case .daily:
            return amountPart + "Jeden Tag"
        case .weekdays:
            let days = (0..<7).filter { weekdayMask & (1 << $0) != 0 }.map { Day.weekdaySymbolsShort[$0] }
            return amountPart + (days.isEmpty ? "Keine Tage" : days.joined(separator: " "))
        case .perWeek:
            return amountPart + "\(timesPerPeriod)× pro Woche"
        case .perMonth:
            return amountPart + "\(timesPerPeriod)× pro Monat"
        }
    }
}

enum Format {
    /// 1 → „1“, 1.5 → „1,5“.
    static func number(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func amount(_ value: Double, unit: String) -> String {
        unit.isEmpty ? "\(number(value))×" : "\(number(value)) \(unit)"
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }
}
