import Foundation

enum Achievement: String, CaseIterable, Identifiable, Sendable {
    case sleep, steps, firstRecord, tracked, healthAge

    var id: String { rawValue }
}

struct AchievementWorkout: Equatable, Sendable {
    let start: Date
    let end: Date
    let bests: [String: Double]
}

enum AchievementEngine {
    static let streakLength = 7
    static let stepGoal = 8_000
    static let trackedDays = 30
    static let ageDecrease = 0.5

    static func health(days: [DayMetrics], ageTrend: (previous: BodyAge.Estimate, recent: BodyAge.Estimate)?,
                       now: Date, calendar: Calendar = .forma) -> [Achievement: Date] {
        let today = calendar.startOfDay(for: now)
        let normalized = days.compactMap { raw -> DayMetrics? in
            guard raw.date.timeIntervalSinceReferenceDate.isFinite,
                  var day = raw.sanitized().onCivilDay(in: calendar), day.date <= today else { return nil }
            if let night = day.sleep, night.end > now { day.sleep = nil }
            day.workouts.removeAll { !($0.end <= now) }
            return day
        }
        let byDate = Dictionary(grouping: normalized, by: \.date).compactMapValues { rows -> DayMetrics? in
            guard let first = rows.first, rows.dropFirst().allSatisfy({ $0 == first }) else { return nil }
            return first
        }
        let dates = byDate.keys.sorted()
        var earned: [Achievement: Date] = [:]
        var steps = 0
        var sleep = 0
        var tracked = 0
        var lastDate: Date?

        for date in dates {
            guard let day = byDate[date] else { continue }
            let yesterday = calendar.startOfDay(offsetBy: -1, from: date)
            if lastDate != yesterday {
                steps = 0
                sleep = 0
            }
            lastDate = date

            steps = (day.steps ?? 0) >= Double(stepGoal) ? steps + 1 : 0
            if steps == streakLength, earned[.steps] == nil { earned[.steps] = date }

            sleep = meetsSleepNeed(day, days: byDate, calendar: calendar) ? sleep + 1 : 0
            if sleep == streakLength, earned[.sleep] == nil { earned[.sleep] = date }

            if MetricSeries.allCases.contains(where: { day.hasMeasurement(for: $0) }) {
                tracked += 1
                if tracked == trackedDays { earned[.tracked] = date }
            }
        }

        if let (previous, recent) = ageTrend, previous.date < recent.date, recent.date <= now {
            let difference = previous.bodyAge - recent.bodyAge
            if difference.isFinite, difference >= ageDecrease { earned[.healthAge] = now }
        }
        return earned
    }

    private static func meetsSleepNeed(_ day: DayMetrics, days: [Date: DayMetrics], calendar: Calendar) -> Bool {
        guard let night = day.sleep, night.asleep > 0,
              let previousDate = calendar.startOfDay(offsetBy: -1, from: day.date),
              let previous = days[previousDate], previous.activeEnergy != nil || !previous.workouts.isEmpty else { return false }
        // Dieselbe Basis wie in ScoreEngine, über die Kalendertage des Imports aufgelöst.
        let basis = (-8 ... -1).compactMap { offset in
            calendar.startOfDay(offsetBy: offset, from: day.date).flatMap { days[$0] }
        }
        return ScoreEngine.hasSleepHistory(Array(basis.dropLast()))
            && night.asleep > ScoreEngine.sleepNeedForLastNight(history: basis)
    }

    static func firstRecord(in workouts: [AchievementWorkout], now: Date) -> Date? {
        let finished = workouts.filter { $0.start <= $0.end && $0.end <= now }
        let byStart = Dictionary(grouping: finished, by: \.start)
        var bests: [String: Double] = [:]
        for start in byStart.keys.sorted() {
            guard let sessions = byStart[start] else { continue }
            let improved = sessions.filter { session in
                session.bests.contains { name, best in
                    best.isFinite && PersonalRecord.isNew(weight: best, reps: 1, previousBest: bests[name, default: 0])
                }
            }
            if let end = improved.map(\.end).min() { return end }
            for session in sessions {
                for (name, best) in session.bests where best.isFinite && best > bests[name, default: 0] {
                    bests[name] = best
                }
            }
        }
        return nil
    }
}
