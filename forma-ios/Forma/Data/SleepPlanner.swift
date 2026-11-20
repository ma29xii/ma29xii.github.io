import Foundation

struct SleepPlanner: Codable, Equatable, Sendable {
    enum Weekday: Int, CaseIterable, Codable, Hashable, Sendable, Identifiable {
        // Calendar zählt Sonntag als 1. Die Auswahl beginnt unabhängig davon am Montag.
        case monday = 2, tuesday, wednesday, thursday, friday, saturday
        case sunday = 1

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .monday: "Montag"
            case .tuesday: "Dienstag"
            case .wednesday: "Mittwoch"
            case .thursday: "Donnerstag"
            case .friday: "Freitag"
            case .saturday: "Samstag"
            case .sunday: "Sonntag"
            }
        }

        var shortTitle: String { String(title.prefix(2)) }
    }

    struct Window: Equatable, Sendable {
        let bed: Date
        let wake: Date
        var reminder: Date { bed.addingTimeInterval(-30 * 60) }

        /// Gemeinsame 24-Stunden-Achse ab 18 Uhr, damit Mitternacht in einem Balken liegt.
        func timelineSegments(calendar: Calendar) -> [Range<Double>] {
            func position(of date: Date) -> Double {
                let minute = SleepPlanner.minuteOfDay(date, calendar: calendar)
                return Double((minute + 6 * 60) % SleepPlanner.minutesPerDay) / Double(SleepPlanner.minutesPerDay)
            }
            let start = position(of: bed)
            let end = position(of: wake)
            if start <= end { return [start..<end] }
            return [0..<end, start..<1].filter { !$0.isEmpty }
        }
    }

    static let storageKey = "forma.sleepPlan"
    static let legacyWakeKey = "forma.wakeMinutes"
    static let defaultWorkdayWake = 6 * 60 + 55
    private static let minutesPerDay = 24 * 60

    private(set) var workdayWake: Int
    private(set) var freeDayWake: Int
    var workdays: Set<Weekday>

    init(workdayWake: Int = SleepPlanner.defaultWorkdayWake, freeDayWake: Int = 8 * 60,
         workdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]) {
        self.workdayWake = Self.validWake(workdayWake) ? workdayWake : Self.defaultWorkdayWake
        self.freeDayWake = Self.validWake(freeDayWake) ? freeDayWake : 8 * 60
        self.workdays = workdays
    }

    func wakeMinutes(for day: Weekday) -> Int {
        workdays.contains(day) ? workdayWake : freeDayWake
    }

    mutating func setWakeMinutes(_ minutes: Int, for day: Weekday) {
        guard Self.validWake(minutes) else { return }
        if workdays.contains(day) {
            workdayWake = minutes
        } else {
            freeDayWake = minutes
        }
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func restore(_ data: Data, fallback: Self) -> Self {
        guard let plan = try? JSONDecoder().decode(Self.self, from: data),
              validWake(plan.workdayWake), validWake(plan.freeDayWake) else { return fallback }
        return plan
    }

    static func legacyWakeMinutes(in store: UserDefaults) -> Int? {
        guard let minutes = store.object(forKey: legacyWakeKey) as? Int, validWake(minutes) else { return nil }
        return minutes
    }

    static func fallback(in store: UserDefaults) -> Self {
        guard let minutes = legacyWakeMinutes(in: store) else { return Self() }
        return Self(workdayWake: minutes, freeDayWake: minutes)
    }

    static func load(in store: UserDefaults) -> Self {
        restore(store.data(forKey: storageKey) ?? Data(), fallback: fallback(in: store))
    }

    private static func validWake(_ minutes: Int) -> Bool { (0..<minutesPerDay).contains(minutes) }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return (time.hour ?? 0) * 60 + (time.minute ?? 0)
    }

    /// Der Wochentag gehört zum Aufwachen. Die Dauer wird auch an Zeitumstellungen real abgezogen.
    func window(wakingOn date: Date, sleepNeed: TimeInterval?, calendar: Calendar = .forma) -> Window? {
        makeWindow(wake: wakeDate(wakingOn: date, calendar: calendar), sleepNeed: sleepNeed)
    }

    func nextWindow(after now: Date, sleepNeed: TimeInterval?, calendar: Calendar = .forma) -> Window? {
        makeWindow(wake: nextWake(after: now, calendar: calendar), sleepNeed: sleepNeed)
    }

    private func makeWindow(wake: Date?, sleepNeed: TimeInterval?) -> Window? {
        guard let wake, let sleepNeed, sleepNeed.isFinite, sleepNeed > 0, sleepNeed < 14 * 3600 else { return nil }
        return Window(bed: wake.addingTimeInterval(-sleepNeed), wake: wake)
    }

    func wakeDate(wakingOn date: Date, calendar: Calendar = .forma) -> Date? {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)) else { return nil }
        let day = calendar.startOfDay(for: date)
        let minutes = wakeMinutes(for: weekday)
        guard let wake = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day,
                                       matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              calendar.isDate(wake, inSameDayAs: day) else { return nil }
        return wake
    }

    func nextWake(after now: Date, calendar: Calendar = .forma) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...2 {
            guard let day = calendar.startOfDay(offsetBy: offset, from: today),
                  let wake = wakeDate(wakingOn: day, calendar: calendar), wake > now else { continue }
            return wake
        }
        return nil
    }

    static func week(containing date: Date, calendar: Calendar = .forma) -> [Date] {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = Weekday.monday.rawValue
        guard let monday = mondayFirst.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { mondayFirst.startOfDay(offsetBy: $0, from: monday) }
    }
}
