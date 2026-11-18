import Foundation

/// Tagesansicht und Vergleich verwenden ausschließlich Daten bis zum gewählten Tag.
struct DashboardDay: Sendable {
    let day: DayMetrics
    let history: [DayMetrics]
    let sleepScore: Int?
    let recovery: Int?
    let strain: Int?

    init(day: DayMetrics, history: [DayMetrics]) {
        self.day = day
        let previous = day.date.adding(days: -30)
        let prior = history.filter { $0.date >= previous && $0.date < day.date }
        self.history = prior
        sleepScore = Self.sleepScore(day, history: prior)
        let hasHeartBasis = (day.hrv != nil && ScoreEngine.baseline(prior.compactMap(\.hrv)) != nil)
            || (day.restingHR != nil && ScoreEngine.baseline(prior.compactMap(\.restingHR)) != nil)
        recovery = hasHeartBasis ? ScoreEngine.recovery(today: day, history: prior, sleepScore: sleepScore ?? 0) : nil
        strain = day.activeEnergy != nil || !day.workouts.isEmpty ? ScoreEngine.strain(day) : nil
    }

    func baseline(_ value: (DayMetrics) -> Double?) -> ScoreEngine.Baseline? {
        ScoreEngine.baseline(history.compactMap(value))
    }

    /// Für historische Schlafwerte wird stets der Bedarf der jeweiligen Nacht zugrunde gelegt.
    static func sleepScore(_ day: DayMetrics, history: [DayMetrics]) -> Int? {
        guard let night = day.sleep, night.asleep > 0 else { return nil }
        return ScoreEngine.sleepScore(night, need: ScoreEngine.sleepNeedForLastNight(history: history))
    }

    var sleepNeed: TimeInterval? {
        guard sleepScore != nil else { return nil }
        return ScoreEngine.sleepNeedForLastNight(history: history)
    }

    /// Anteil der letzten erfassten Schlafstarts, die höchstens eine Stunde vom aktuellen Start abweichen.
    var sleepRegularity: Double? {
        guard let night = day.sleep, night.asleep > 0 else { return nil }
        return Self.sleepRegularity(night, history: history)
    }

    static func sleepRegularity(_ night: SleepNight, history: [DayMetrics]) -> Double? {
        let starts = history.suffix(7).compactMap { day in
            day.sleep.flatMap { $0.asleep > 0 ? $0.start : nil }
        }
        guard starts.count >= 4 else { return nil }
        func minuteOfDay(_ date: Date) -> Int {
            let parts = Calendar.forma.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        let minute = minuteOfDay(night.start)
        let similar = starts.filter {
            let difference = abs(minuteOfDay($0) - minute)
            return min(difference, 1440 - difference) <= 60
        }
        return Double(similar.count) / Double(starts.count)
    }

    static func restorativeFraction(_ night: SleepNight) -> Double? {
        guard night.hasStages, night.asleep > 0 else { return nil }
        let restorative = SleepNight.unionLength(night.segments.filter { $0.stage == .deep || $0.stage == .rem })
        return min(1, restorative / night.asleep)
    }

    static func workoutTime(_ day: DayMetrics, strengthOnly: Bool = false) -> Double? {
        let workouts = strengthOnly ? day.workouts.filter(\.isStrength) : day.workouts
        guard !workouts.isEmpty else { return nil }
        let intervals = workouts.map {
            SleepNight.Segment(stage: .unspecified, start: $0.start, end: $0.start.addingTimeInterval($0.duration))
        }
        return SleepNight.unionLength(intervals)
    }
}

struct StressSlot: Identifiable, Sendable {
    let start: Date
    let end: Date
    let value: Double?
    var id: Date { start }
}

enum StressZone: Int, CaseIterable, Identifiable, Sendable {
    case low, medium, high
    var id: Int { rawValue }

    init(value: Double) {
        if value < 1 { self = .low }
        else if value < 2 { self = .medium }
        else { self = .high }
    }

    var title: String {
        switch self {
        case .low: "Niedrig"
        case .medium: "Mittel"
        case .high: "Hoch"
        }
    }

    func duration(in slots: [StressSlot]) -> TimeInterval {
        slots.reduce(0) { total, slot in
            guard let value = slot.value, value.isFinite, Self(value: value) == self else { return total }
            return total + max(0, slot.end.timeIntervalSince(slot.start))
        }
    }
}
