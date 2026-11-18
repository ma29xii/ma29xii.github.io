import Foundation

struct InsightHistory {
    private let days: [Date: DayMetrics]
    let calendar: Calendar

    init(_ days: [DayMetrics], calendar: Calendar = .forma) {
        self.calendar = calendar
        self.days = Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0.sanitized()) },
                               uniquingKeysWith: { _, later in later })
    }

    subscript(_ date: Date) -> DayMetrics? { days[calendar.startOfDay(for: date)] }

    func dates(endingAt end: Date, count: Int) -> [Date] {
        let end = calendar.startOfDay(for: end)
        return (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: end) }
    }

    func prior(to date: Date) -> [DayMetrics] {
        dates(endingAt: date, count: 31).dropLast().compactMap { days[$0] }
    }

    static func lastCompletedDay(for selected: Date, now: Date = .now) -> Date {
        min(selected.startOfDay, now.startOfDay.adding(days: -1))
    }
}

struct InsightDay<Value>: Identifiable {
    let date: Date
    let value: Value?
    var id: Date { date }
}

struct InsightAverage {
    let mean: Double
    let count: Int

    init?(_ values: [Double], minimum: Int = 1) {
        guard values.count >= minimum, !values.isEmpty else { return nil }
        mean = values.reduce(0, +) / Double(values.count)
        count = values.count
    }
}

struct StrainInsight {
    enum State: Equatable {
        case hold, build, tooMuch

        var title: String {
            switch self {
            case .hold: "Halten"
            case .build: "Aufbau"
            case .tooMuch: "Zu viel"
            }
        }
    }

    let short: InsightAverage
    let long: InsightAverage
    var state: State { Self.state(short: short.mean, long: long.mean) }

    static func state(short: Double, long: Double) -> State {
        if short > long * 1.25 { return .tooMuch }
        if short > long * 1.10 { return .build }
        return .hold
    }

    static func path(endingAt end: Date, history: InsightHistory) -> [InsightDay<Self>] {
        let dates = history.dates(endingAt: end, count: 55)
        let scores = dates.map { history[$0].flatMap(score) }
        return dates.indices.dropFirst(27).map { index in
            let result: Self?
            if scores[index] != nil,
               let short = InsightAverage(scores[(index - 6)...index].compactMap { $0 }, minimum: 5),
               let long = InsightAverage(scores[(index - 27)...index].compactMap { $0 }, minimum: 20) {
                result = Self(short: short, long: long)
            } else {
                result = nil
            }
            return InsightDay(date: dates[index], value: result)
        }
    }

    static func score(_ day: DayMetrics) -> Double? {
        guard day.activeEnergy != nil || !day.workouts.isEmpty else { return nil }
        return Double(ScoreEngine.strain(day))
    }
}

struct SleepConsistency {
    struct Times {
        let start: Date
        let end: Date
        let bedtime: Int
        let wake: Int

        init(night: SleepNight, calendar: Calendar) {
            start = night.start
            end = night.end
            func minutes(_ date: Date) -> Int {
                calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            }
            bedtime = minutes(start)
            wake = minutes(end)
        }

        /// Größere der beiden zirkulären Uhrzeit-Abweichungen in Minuten.
        func deviation(from other: Self) -> Int {
            func distance(_ a: Int, _ b: Int) -> Int { min(abs(a - b), 1440 - abs(a - b)) }
            return max(distance(bedtime, other.bedtime), distance(wake, other.wake))
        }
    }

    let nights: [InsightDay<Times>]
    let measured: Int
    let percent: Int?

    init(endingAt end: Date, history: InsightHistory) {
        nights = history.dates(endingAt: end, count: 14).map { date in
            let night = history[date]?.sleep.flatMap { $0.asleep > 0 ? $0 : nil }
            return InsightDay(date: date, value: night.map { Times(night: $0, calendar: history.calendar) })
        }
        let times = nights.compactMap(\.value)
        measured = times.count
        // Als Bezug dient die gemessene Nacht, zu der die meisten anderen passen.
        let matches = times.map { reference in times.filter { $0.deviation(from: reference) <= 60 }.count }
        percent = times.count >= 4 ? matches.max().map { Int((100 * Double($0) / Double(times.count)).rounded()) } : nil
    }
}

enum WeeklyInsight {
    struct Period: Equatable {
        let currentStart: Date
        let previousStart: Date
        let dayCount: Int
    }

    enum Metric: String, CaseIterable {
        case sleep, recovery, strain, steps, hrv
    }

    struct Row: Identifiable {
        let metric: Metric
        let current: InsightAverage?
        let previous: InsightAverage?
        var id: Metric { metric }
    }

    static func period(at date: Date, calendar: Calendar = .forma) -> Period? {
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let sundayEvening = weekday == 1 && hour >= 18
        guard sundayEvening || (weekday == 2 && hour < 12) else { return nil }
        let today = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: sundayEvening ? -6 : -7, to: today),
              let previous = calendar.date(byAdding: .day, value: -7, to: start) else { return nil }
        return Period(currentStart: start, previousStart: previous, dayCount: sundayEvening ? 6 : 7)
    }

    static func rows(period: Period, history: InsightHistory) -> [Row] {
        func readings(from start: Date) -> [DayMetrics] {
            (0..<period.dayCount).compactMap { offset in
                history.calendar.date(byAdding: .day, value: offset, to: start).flatMap { history[$0] }
            }
        }
        let current = readings(from: period.currentStart)
        let previous = readings(from: period.previousStart)
        let hrvReference = current.last { $0.hrv != nil } ?? previous.last { $0.hrv != nil }
        func value(_ metric: Metric, _ day: DayMetrics) -> Double? {
            switch metric {
            case .sleep: day.sleep.flatMap { $0.asleep > 0 ? $0.asleep : nil }
            case .recovery: DashboardDay(day: day, history: history.prior(to: day.date)).recovery.map(Double.init)
            case .strain: StrainInsight.score(day)
            case .steps: day.steps
            case .hrv:
                if let hrvReference, hrvReference.date == day.date
                    || ScoreEngine.sameBaselineSource(for: .hrv, today: hrvReference, previous: day) {
                    day.hrv
                } else {
                    nil
                }
            }
        }
        return Metric.allCases.map { metric in
            Row(metric: metric, current: InsightAverage(current.compactMap { value(metric, $0) }),
                previous: InsightAverage(previous.compactMap { value(metric, $0) }))
        }
    }
}

enum StressInsight {
    static func trend(endingAt end: Date, history: InsightHistory) -> [InsightDay<InsightAverage>] {
        let dates = history.dates(endingAt: end, count: 36)
        let stress = dates.map { date -> Double? in
            guard var day = history[date] else { return nil }
            let prior = history.prior(to: date)
            let hasHRV = day.hrv != nil && ScoreEngine.baseline(for: \.hrv, today: day, history: prior) != nil
            let hasRestingHR = day.restingHR != nil && ScoreEngine.baseline(for: \.restingHR, today: day, history: prior) != nil
            guard hasHRV || hasRestingHR else { return nil }
            day.activeEnergy = nil
            day.workouts = []
            return ScoreEngine.scores(today: day, history: prior, now: date).stress
        }
        return dates.indices.dropFirst(6).map { index in
            let average = stress[index].flatMap { _ in
                InsightAverage(stress[(index - 6)...index].compactMap { $0 }, minimum: 4)
            }
            return InsightDay(date: dates[index], value: average)
        }
    }
}
