import Foundation

enum HabitKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case build
    case quit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .build: "Aufbauen"
        case .quit: "Abgewöhnen"
        }
    }
}

enum HabitFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekdays
    case perWeek
    case perMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Jeden Tag"
        case .weekdays: "Bestimmte Wochentage"
        case .perWeek: "Mehrmals pro Woche"
        case .perMonth: "Mehrmals pro Monat"
        }
    }
}

/// Was an einem Tag eingetragen wurde.
struct DayRecord: Equatable, Sendable {
    var amount: Double = 0
    var skipped: Bool = false
}

/// Die Regeln einer Gewohnheit – ohne Datenbank, damit die Logik testbar bleibt.
struct HabitRule: Equatable, Sendable {
    var kind: HabitKind = .build
    var frequency: HabitFrequency = .daily
    /// Bit 0 = Montag … Bit 6 = Sonntag.
    var weekdayMask: Int = 0b111_1111
    var timesPerPeriod: Int = 3
    /// Aufbauen: Menge, ab der ein Tag als erledigt zählt.
    /// Abgewöhnen: erlaubtes Tageslimit (0 = gar nicht).
    var dailyTarget: Double = 1
    var firstDay: Day
    var lastDay: Day?
    /// Wochentag-Index des Wochenbeginns (0 = Montag, 6 = Sonntag).
    var weekStart: Int = 0
}

/// Farbe/Zustand einer Kachel im Raster.
struct HeatCell: Equatable, Sendable {
    var level: Double = 0
    var skipped: Bool = false
    var slipped: Bool = false
}

enum DayState: Equatable, Sendable {
    case done
    case pending
    case skipped
    case slipped
    case notDue
}

/// Momentaufnahme einer Gewohnheit: Regeln + Einträge. Alle Auswertungen
/// (Serien, Quoten, Kachelstufen) werden hier berechnet.
struct HabitSnapshot: Sendable {
    var rule: HabitRule
    /// Einträge nach `Day.ordinal`.
    var records: [Int: DayRecord]
    var today: Day
    /// Seit wann die Gewohnheit pausiert ist (Tage ab hier gelten als übersprungen).
    var pausedSince: Day?

    init(rule: HabitRule, records: [Int: DayRecord] = [:], today: Day, pausedSince: Day? = nil) {
        self.rule = rule
        self.records = records
        self.today = today
        self.pausedSince = pausedSince
    }

    // MARK: Einzelne Tage

    func amount(_ day: Day) -> Double { records[day.ordinal]?.amount ?? 0 }

    func isSkipped(_ day: Day) -> Bool {
        if let pausedSince, day >= pausedSince { return true }
        return records[day.ordinal]?.skipped ?? false
    }

    func inRange(_ day: Day) -> Bool {
        guard day >= rule.firstDay, day <= today else { return false }
        if let last = rule.lastDay, day > last { return false }
        return true
    }

    func isDone(_ day: Day) -> Bool {
        switch rule.kind {
        case .build:
            let value = amount(day)
            return value > 0 && value >= rule.dailyTarget
        case .quit:
            return inRange(day) && !isSkipped(day) && amount(day) <= rule.dailyTarget
        }
    }

    /// Rückfall bei „Abgewöhnen“.
    func isSlip(_ day: Day) -> Bool {
        rule.kind == .quit && inRange(day) && amount(day) > rule.dailyTarget
    }

    var effectiveFrequency: HabitFrequency {
        rule.kind == .quit ? .daily : rule.frequency
    }

    func isDue(_ day: Day) -> Bool {
        guard inRange(day) else { return false }
        if effectiveFrequency == .weekdays {
            return rule.weekdayMask & (1 << day.weekdayIndex) != 0
        }
        return true
    }

    /// Anteil des Tagesziels (0…1), nur für „Aufbauen“ sinnvoll.
    func fraction(_ day: Day) -> Double {
        guard rule.dailyTarget > 0 else { return amount(day) > 0 ? 1 : 0 }
        return min(1, max(0, amount(day) / rule.dailyTarget))
    }

    func cell(_ day: Day) -> HeatCell {
        guard day <= today else { return HeatCell() }
        switch rule.kind {
        case .build:
            let value = amount(day)
            if value <= 0 {
                return HeatCell(level: 0, skipped: isSkipped(day) && inRange(day))
            }
            let f = fraction(day)
            return HeatCell(level: f >= 1 ? 1 : 0.25 + 0.45 * f)
        case .quit:
            guard inRange(day) else { return HeatCell() }
            if isSlip(day) { return HeatCell(level: 0, slipped: true) }
            if isSkipped(day) { return HeatCell(level: 0, skipped: true) }
            return HeatCell(level: amount(day) <= 0 ? 1 : 0.55)
        }
    }

    func state(_ day: Day) -> DayState {
        if isDone(day) { return .done }
        if isSlip(day) { return .slipped }
        if !inRange(day) { return .notDue }
        if isSkipped(day) { return .skipped }
        return isPending(day) ? .pending : .notDue
    }

    /// Steht an diesem Tag noch etwas aus?
    func isPending(_ day: Day) -> Bool {
        guard rule.kind == .build, inRange(day), !isDone(day), !isSkipped(day) else { return false }
        switch effectiveFrequency {
        case .daily, .weekdays:
            return isDue(day)
        case .perWeek, .perMonth:
            let (start, end) = periodBounds(containing: day)
            return doneCount(from: start, through: min(end, today)) < rule.timesPerPeriod
        }
    }

    // MARK: Zeiträume

    func weekStart(of day: Day) -> Day { day.startOfWeek(weekStart: rule.weekStart) }

    func periodBounds(containing day: Day) -> (start: Day, end: Day) {
        if effectiveFrequency == .perMonth {
            let start = day.startOfMonth
            return (start, start.adding(day.daysInMonth - 1))
        }
        let start = weekStart(of: day)
        return (start, start.adding(6))
    }

    func doneCount(from start: Day, through end: Day) -> Int {
        guard start <= end else { return 0 }
        var count = 0
        var day = start
        while day <= end {
            if isDone(day) { count += 1 }
            day = day.adding(1)
        }
        return count
    }

    /// Fortschritt im laufenden Zeitraum (nur bei „x-mal pro Woche/Monat“).
    var periodProgress: (done: Int, target: Int)? {
        guard effectiveFrequency == .perWeek || effectiveFrequency == .perMonth else { return nil }
        let (start, end) = periodBounds(containing: today)
        return (doneCount(from: start, through: min(end, today)), rule.timesPerPeriod)
    }

    // MARK: Serien

    enum UnitStatus: Equatable, Sendable {
        case met
        case neutral
        case missed
    }

    /// Chronologische Bewertung jeder Einheit (Tag, Woche oder Monat).
    func unitStatuses() -> [UnitStatus] {
        guard rule.firstDay <= today else { return [] }
        var result: [UnitStatus] = []
        switch effectiveFrequency {
        case .daily, .weekdays:
            result.reserveCapacity(rule.firstDay.days(until: today) + 1)
            var day = rule.firstDay
            while day <= today {
                if isDone(day) {
                    result.append(.met)
                } else if isSkipped(day) || !isDue(day) || day == today {
                    result.append(.neutral)
                } else {
                    result.append(.missed)
                }
                day = day.adding(1)
            }
        case .perWeek, .perMonth:
            var (start, end) = periodBounds(containing: rule.firstDay)
            while start <= today {
                let lower = max(start, rule.firstDay)
                let upper = min(end, today)
                var done = 0
                var skipped = false
                var day = lower
                while day <= upper {
                    if isDone(day) {
                        done += 1
                    } else if isSkipped(day) {
                        skipped = true
                    }
                    day = day.adding(1)
                }
                let afterEnd = rule.lastDay.map { start > $0 } ?? false
                if done >= rule.timesPerPeriod {
                    result.append(.met)
                } else if skipped || end >= today || afterEnd {
                    result.append(.neutral)
                } else {
                    result.append(.missed)
                }
                (start, end) = periodBounds(containing: end.adding(1))
            }
        }
        return result
    }

    static func currentRun(_ statuses: [UnitStatus]) -> Int {
        var count = 0
        for status in statuses.reversed() {
            switch status {
            case .met: count += 1
            case .neutral: continue
            case .missed: return count
            }
        }
        return count
    }

    static func bestRun(_ statuses: [UnitStatus]) -> Int {
        var best = 0
        var run = 0
        for status in statuses {
            switch status {
            case .met:
                run += 1
                best = max(best, run)
            case .neutral:
                continue
            case .missed:
                run = 0
            }
        }
        return best
    }

    var currentStreak: Int { Self.currentRun(unitStatuses()) }
    var bestStreak: Int { Self.bestRun(unitStatuses()) }

    func streakUnit(_ count: Int) -> String {
        switch effectiveFrequency {
        case .daily, .weekdays: count == 1 ? "Tag" : "Tage"
        case .perWeek: count == 1 ? "Woche" : "Wochen"
        case .perMonth: count == 1 ? "Monat" : "Monate"
        }
    }

    // MARK: Statistik

    /// Anzahl erledigter Tage insgesamt.
    var totalDone: Int {
        switch rule.kind {
        case .build:
            return records.values.reduce(0) { $0 + (($1.amount > 0 && $1.amount >= rule.dailyTarget) ? 1 : 0) }
        case .quit:
            return doneCount(from: rule.firstDay, through: today)
        }
    }

    var totalAmount: Double {
        records.values.reduce(0) { $0 + $1.amount }
    }

    /// Erfolgsquote der letzten `days` Tage (0…1).
    func rate(days: Int) -> Double {
        let start = max(rule.firstDay, today.adding(-(days - 1)))
        guard start <= today else { return 0 }
        switch effectiveFrequency {
        case .daily, .weekdays:
            var due = 0
            var done = 0
            var day = start
            while day <= today {
                if isDone(day) {
                    done += 1
                    due += 1
                } else if isDue(day), !isSkipped(day), day != today {
                    due += 1
                }
                day = day.adding(1)
            }
            return due == 0 ? 0 : Double(done) / Double(due)
        case .perWeek, .perMonth:
            let span = Double(start.days(until: today) + 1)
            let periodLength = effectiveFrequency == .perWeek ? 7.0 : 30.0
            let expected = Double(rule.timesPerPeriod) * span / periodLength
            guard expected > 0 else { return 0 }
            return min(1, Double(doneCount(from: start, through: today)) / expected)
        }
    }

    /// Erledigt und fällig in einem Zeitraum – Grundlage für Wochen- und Jahresrückblick.
    /// Heute zählt nur mit, wenn es schon erledigt ist (sonst ist der Tag ja nicht verpasst).
    func tally(from start: Day, through end: Day) -> (done: Int, due: Int) {
        let lower = max(start, rule.firstDay)
        let upper = min(end, today, rule.lastDay ?? end)
        guard lower <= upper else { return (0, 0) }
        switch effectiveFrequency {
        case .daily, .weekdays:
            var done = 0
            var due = 0
            var day = lower
            while day <= upper {
                let entry = dayTally(day)
                done += entry.done
                due += entry.due
                day = day.adding(1)
            }
            return (done, due)
        case .perWeek, .perMonth:
            let span = Double(lower.days(until: upper) + 1)
            let periodLength = effectiveFrequency == .perWeek ? 7.0 : 30.0
            let expected = max(1, Int((Double(rule.timesPerPeriod) * span / periodLength).rounded()))
            return (min(doneCount(from: lower, through: upper), expected), expected)
        }
    }

    /// Ein einzelner Tag: (1, 1) erledigt, (0, 1) verpasst, (0, 0) zählt nicht.
    /// „x-mal pro Woche“ zählt nur an erledigten Tagen – ein freier Tag ist kein Fehler.
    func dayTally(_ day: Day) -> (done: Int, due: Int) {
        guard inRange(day) else { return (0, 0) }
        if isDone(day) { return (1, 1) }
        switch effectiveFrequency {
        case .daily, .weekdays:
            return isDue(day) && !isSkipped(day) && day != today ? (0, 1) : (0, 0)
        case .perWeek, .perMonth:
            return (0, 0)
        }
    }

    /// Erledigte Tage je Wochentag (Index 0 = Montag).
    func weekdayCounts() -> [Int] {
        var counts = Array(repeating: 0, count: 7)
        switch rule.kind {
        case .build:
            for (ordinal, record) in records where record.amount > 0 && record.amount >= rule.dailyTarget {
                counts[Day(ordinal: ordinal).weekdayIndex] += 1
            }
        case .quit:
            var day = rule.firstDay
            while day <= today {
                if isDone(day) { counts[day.weekdayIndex] += 1 }
                day = day.adding(1)
            }
        }
        return counts
    }

    /// Erledigte Tage je Woche für die letzten `weeks` Wochen (älteste zuerst).
    func weeklyCounts(weeks: Int) -> [(start: Day, count: Int)] {
        let current = weekStart(of: today)
        return (0..<weeks).reversed().map { offset in
            let start = current.adding(-offset * 7)
            return (start, doneCount(from: start, through: min(start.adding(6), today)))
        }
    }
}
