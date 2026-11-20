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
    var hasMeasurement: Bool {
        steps != nil || activeEnergy != nil || heartRate != nil || hrv != nil || restingHR != nil
    }

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
        // Der importierte Tagespuls ist kein Ruhepuls und liefert weder Stress noch Energie.
        // F5-04: Google liefert HRV und Ruhepuls nur pro Tag – ohne Stundenwert gilt der Tageswert,
        // verglichen mit Tagen derselben Quelle.
        let hasHRVBaseline = ScoreEngine.baseline(for: \.hrv, today: today, history: history) != nil
        let hasRestingHRBaseline = ScoreEngine.baseline(for: \.restingHR, today: today, history: history) != nil
        var accumulatedEnergy: Double?
        return hours.map { hour in
            if let kcal = hour.activeEnergy {
                accumulatedEnergy = (accumulatedEnergy ?? 0) + kcal
            }
            let finishedWorkouts = today.workouts.filter { $0.start.addingTimeInterval($0.duration) <= hour.end }
            let completedSleep = today.sleep.flatMap { $0.end <= hour.end ? $0 : nil }
            var snapshot = DayMetrics(date: today.date, hrv: hour.hrv ?? today.hrv, restingHR: hour.restingHR ?? today.restingHR,
                                      activeEnergy: accumulatedEnergy, sleep: completedSleep, workouts: finishedWorkouts)
            snapshot.origins = today.origins
            let hasActivity = accumulatedEnergy != nil || !finishedWorkouts.isEmpty
            let hasHeartBasis = (snapshot.hrv != nil && hasHRVBaseline) || (snapshot.restingHR != nil && hasRestingHRBaseline)
            let scores = ScoreEngine.scores(today: snapshot, history: history, now: hour.end)
            return Self(at: hour.end, strain: hasActivity ? scores.strain : nil,
                        stress: hasHeartBasis ? scores.stress : nil,
                        energy: hasHeartBasis && hasActivity && completedSleep != nil ? scores.energy : nil)
        }
    }

    /// Tagesstress aus HRV und Ruhepuls des Tages, wenn es keine Stundenwerte gibt (z. B. Google ohne Stundenaktivität).
    static func dailyStress(today: DayMetrics, history: [DayMetrics], now: Date = .now) -> Double? {
        let hasHRV = today.hrv != nil && ScoreEngine.baseline(for: \.hrv, today: today, history: history) != nil
        let hasRHR = today.restingHR != nil && ScoreEngine.baseline(for: \.restingHR, today: today, history: history) != nil
        guard hasHRV || hasRHR else { return nil }
        return ScoreEngine.scores(today: today, history: history, now: now).stress
    }
}
