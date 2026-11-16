import Foundation

/// Ein Kalendertag ohne Uhrzeit und Zeitzone – gespeichert als fortlaufende
/// Tagesnummer seit dem 1.1.1970. Rechnen mit Tagen ist damit reine
/// Ganzzahl-Arithmetik (keine Sommerzeit-Fallen) und vollständig testbar.
struct Day: Hashable, Comparable, Sendable {
    let ordinal: Int

    init(ordinal: Int) {
        self.ordinal = ordinal
    }

    init(year: Int, month: Int, day: Int) {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        self.ordinal = era * 146_097 + doe - 719_468
    }

    /// Aus einem Schlüssel der Form `yyyymmdd`, z. B. 20261116.
    init(key: Int) {
        self.init(year: key / 10_000, month: (key / 100) % 100, day: key % 100)
    }

    init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    static var today: Day { Day(date: Date()) }

    static func < (lhs: Day, rhs: Day) -> Bool { lhs.ordinal < rhs.ordinal }

    // MARK: Komponenten

    var components: (year: Int, month: Int, day: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    var year: Int { components.year }
    var month: Int { components.month }
    var dayOfMonth: Int { components.day }

    /// `yyyymmdd` – stabil, lesbar, sortierbar.
    var key: Int {
        let c = components
        return c.year * 10_000 + c.month * 100 + c.day
    }

    /// 0 = Montag … 6 = Sonntag.
    var weekdayIndex: Int {
        (((ordinal % 7) + 7) % 7 + 3) % 7
    }

    // MARK: Rechnen

    func adding(_ days: Int) -> Day { Day(ordinal: ordinal + days) }

    func days(until other: Day) -> Int { other.ordinal - ordinal }

    var startOfMonth: Day {
        let c = components
        return Day(year: c.year, month: c.month, day: 1)
    }

    var daysInMonth: Int {
        startOfMonth.addingMonths(1).ordinal - startOfMonth.ordinal
    }

    /// Erster Tag des Monats, der `months` Monate entfernt liegt.
    func addingMonths(_ months: Int) -> Day {
        let c = components
        let index = c.year * 12 + (c.month - 1) + months
        let y = index >= 0 ? index / 12 : (index - 11) / 12
        let m = index - y * 12
        return Day(year: y, month: m + 1, day: 1)
    }

    /// Erster Tag der Woche, in der dieser Tag liegt.
    /// - Parameter weekStart: Wochentag-Index des Wochenbeginns (0 = Montag, 6 = Sonntag).
    func startOfWeek(weekStart: Int) -> Day {
        adding(-((weekdayIndex - weekStart + 7) % 7))
    }

    func date(calendar: Calendar = .current) -> Date {
        let c = components
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) ?? Date()
    }
}

extension Day {
    static let weekdaySymbolsShort = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let weekdaySymbolsLong = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
    static let monthSymbolsShort = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
    static let monthSymbolsLong = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]

    var weekdayShort: String { Day.weekdaySymbolsShort[weekdayIndex] }
    var weekdayLong: String { Day.weekdaySymbolsLong[weekdayIndex] }
    var monthShort: String { Day.monthSymbolsShort[month - 1] }
    var monthLong: String { Day.monthSymbolsLong[month - 1] }

    /// z. B. „Montag, 16. November“.
    var longTitle: String { "\(weekdayLong), \(dayOfMonth). \(monthLong)" }

    /// z. B. „16.11.2026“.
    var shortTitle: String {
        let c = components
        return "\(c.day).\(c.month).\(c.year)"
    }
}
