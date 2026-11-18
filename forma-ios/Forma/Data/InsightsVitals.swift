import Foundation

struct NightVitals {
    struct Reading {
        let series: MetricSeries
        let value: Double?
        let baseline: ScoreEngine.Baseline?

        var isOutlier: Bool {
            guard let value, let range = NightVitals.range(for: series.rawValue, baseline: baseline) else { return false }
            return !range.contains(value)
        }
    }

    let readings: [Reading]
    let hasNight: Bool
    var outliers: [MetricSeries] { readings.filter(\.isOutlier).map(\.series) }
    var isMarked: Bool { hasNight && outliers.count >= 2 }

    init(day: DayMetrics, history: [DayMetrics], calendar: Calendar = .forma) {
        let current = day.sanitized()
        hasNight = current.sleep.map { $0.asleep > 0 } ?? false
        let prior = InsightHistory(history, calendar: calendar).prior(to: day.date)
        func reading(_ series: MetricSeries, _ key: KeyPath<DayMetrics, Double?>) -> Reading {
            let values = prior.compactMap { previous -> Double? in
                guard previous.sleep.map({ $0.asleep > 0 }) == true,
                      ScoreEngine.sameBaselineSource(for: series, today: current, previous: previous) else { return nil }
                return previous[keyPath: key]
            }
            let useAbsoluteSpread = series == .skinTemperature || series == .spo2
            var baseline = values.count >= 7
                ? ScoreEngine.baseline(values, minimumRelativeSpread: useAbsoluteSpread ? 0 : 0.04) : nil
            if useAbsoluteSpread, let spread = baseline?.sd {
                baseline?.sd = max(series == .skinTemperature ? 0.2 : 1, spread)
            }
            return Reading(series: series, value: current[keyPath: key], baseline: baseline)
        }
        readings = [reading(.respiratoryRate, \.respiratoryRate), reading(.spo2, \.spo2),
                    reading(.restingHR, \.restingHR), reading(.hrv, \.hrv), reading(.skinTemperature, \.skinTemperature)]
    }

    static func range(for id: String, baseline: ScoreEngine.Baseline?) -> ClosedRange<Double>? {
        baseline.map { base in
            let limit = id == MetricSeries.spo2.rawValue ? 100.0 : Double.infinity
            let lower = min(limit, max(0, base.mean - 2 * base.sd))
            let upper = min(limit, max(lower, base.mean + 2 * base.sd))
            return lower...upper
        }
    }
}
