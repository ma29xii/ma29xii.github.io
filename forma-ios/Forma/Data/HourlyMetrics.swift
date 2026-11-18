import Foundation

struct HourlyMetrics: Identifiable, Equatable, Codable, Sendable {
    let start: Date
    let end: Date
    var steps: Double? = nil
    var activeEnergy: Double? = nil
    var hrv: Double? = nil
    var restingHR: Double? = nil
    var heartRate: Double? = nil
    var stepOrigin: GoogleMetricOrigin? = nil
    var energyOrigin: GoogleMetricOrigin? = nil
    var heartRateOrigin: GoogleMetricOrigin? = nil

    var id: Date { start }

    static func samples(for day: DayMetrics) -> [Self] {
        let fractions = [0.03, 0.03, 0.1, 0.06, 0.05, 0.32, 0.14, 0.05, 0.22]
        return fractions.enumerated().map { offset, fraction in
            let start = day.date.adding(minutes: Double(8 + offset) * 60)
            return Self(start: start, end: start.addingTimeInterval(3600),
                        steps: day.steps.map { ($0 * fraction).rounded() },
                        activeEnergy: day.activeEnergy.map { $0 * fraction },
                        hrv: day.hrv.map { $0 + sin(Double(offset) * 1.6) * 7 },
                        restingHR: day.restingHR)
        }
    }
}

struct HourlyEstimate: Identifiable, Sendable {
    let at: Date
    let strain: Int?
    let stress: Double?
    let energy: Int?

    var id: Date { at }

    static func timeline(hours: [HourlyMetrics], today: DayMetrics, history: [DayMetrics]) -> [Self] {
        let hasHRVBaseline = ScoreEngine.baseline(history.compactMap(\.hrv)) != nil
        let hasRestingHRBaseline = ScoreEngine.baseline(history.compactMap(\.restingHR)) != nil
        var accumulatedEnergy: Double?
        return hours.map { hour in
            if let kcal = hour.activeEnergy {
                accumulatedEnergy = (accumulatedEnergy ?? 0) + kcal
            }
            let finishedWorkouts = today.workouts.filter { $0.start.addingTimeInterval($0.duration) <= hour.end }
            let completedSleep = today.sleep.flatMap { $0.end <= hour.end ? $0 : nil }
            let snapshot = DayMetrics(date: today.date, hrv: hour.hrv, restingHR: hour.restingHR,
                                      activeEnergy: accumulatedEnergy, sleep: completedSleep, workouts: finishedWorkouts)
            let hasActivity = accumulatedEnergy != nil || !finishedWorkouts.isEmpty
            let hasHeartBasis = (hour.hrv != nil && hasHRVBaseline) || (hour.restingHR != nil && hasRestingHRBaseline)
            let scores = ScoreEngine.scores(today: snapshot, history: history, now: hour.end)
            return Self(at: hour.end, strain: hasActivity ? scores.strain : nil,
                        stress: hasHeartBasis ? scores.stress : nil,
                        energy: hasHeartBasis && hasActivity && completedSleep != nil ? scores.energy : nil)
        }
    }
}
