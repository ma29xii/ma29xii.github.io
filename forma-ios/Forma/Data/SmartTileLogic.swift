import Foundation

/// Reine Logik hinter den schlauen Today-Kacheln (F6-03). Alles aus vorhandenen Messwerten, nichts geschätzt.

/// „Bereit für“: Empfehlung aus Erholung und Strain-Ziel.
struct ReadinessAdvice: Equatable, Sendable {
    enum Kind: Int, Sendable {
        case hard, normal, easy, rest

        var title: String {
            switch self {
            case .hard: "Hart"
            case .normal: "Normal"
            case .easy: "Locker"
            case .rest: "Ruhetag"
            }
        }
    }

    let kind: Kind
    /// Strain-Bereich der Empfehlung (Ruhetag: 0–10).
    let strain: ClosedRange<Int>

    var rangeText: String {
        kind == .rest ? "unter \(strain.upperBound)" : "\(strain.lowerBound)–\(strain.upperBound)"
    }

    /// `nil` ohne Erholung. Bei einer Warnung der Körpersignale („kämpft“) oder sehr niedriger Erholung: Ruhetag.
    static func make(recovery: Int?, illness: IllnessSignal.Level? = nil) -> ReadinessAdvice? {
        guard let recovery else { return nil }
        if illness == .fighting || recovery < 20 { return ReadinessAdvice(kind: .rest, strain: 0...10) }
        let target = ScoreEngine.target(recovery: recovery)
        if recovery >= 67 { return ReadinessAdvice(kind: .hard, strain: target) }
        if recovery >= 34 { return ReadinessAdvice(kind: .normal, strain: target) }
        return ReadinessAdvice(kind: .easy, strain: target)
    }
}

/// „Schlafschuld“: Schuld der letzten 7 Nächte und der Anteil, der heute Abend früher ins Bett verlegt wird.
struct SleepDebtInfo: Equatable, Sendable {
    let debt: TimeInterval
    /// Aufschlag auf den heutigen Schlafbedarf durch die Schuld (siehe `ScoreEngine.sleepNeed`).
    let extraTonight: TimeInterval

    var hasExtra: Bool { extraTonight >= 5 * 60 }

    /// `nil`, solange weniger als vier der letzten sieben Nächte gemessen sind.
    static func make(history: [DayMetrics]) -> SleepDebtInfo? {
        guard ScoreEngine.hasSleepHistory(history) else { return nil }
        let debt = ScoreEngine.sleepDebt(history: history)
        return SleepDebtInfo(debt: debt, extraTonight: min(debt, 2 * 3600) * 0.25)
    }
}

/// „Erholte Zeit“: gemessene Stunden pro Stresszone; Lücken zählen nicht mit.
struct CalmTimeInfo: Equatable, Sendable {
    let calm: TimeInterval
    let medium: TimeInterval
    let stressed: TimeInterval

    var measured: TimeInterval { calm + medium + stressed }

    static func make(slots: [StressSlot]) -> CalmTimeInfo? {
        let info = CalmTimeInfo(calm: StressZone.low.duration(in: slots),
                                medium: StressZone.medium.duration(in: slots),
                                stressed: StressZone.high.duration(in: slots))
        return info.measured > 0 ? info : nil
    }
}

/// „Serie“: Tage in Folge mit erreichtem Ziel (Schritte im Ziel oder Strain im Ziel).
enum GoalStreak {
    struct Result: Equatable, Sendable {
        /// Zusammenhängende Tage bis gestern (plus heute, falls schon erreicht).
        let days: Int
        let todayReached: Bool
    }

    static func reached(_ day: DayMetrics, history: [DayMetrics], calendar: Calendar = .forma) -> Bool {
        let snapshot = DashboardDay(day: day, history: history)
        if let steps = day.steps,
           let goal = StepGoal.target(on: day.date, history: snapshot.history, recovery: snapshot.recovery,
                                      sleepScore: snapshot.sleepScore,
                                      sleepDebt: ScoreEngine.sleepDebt(history: snapshot.history),
                                      strainTarget: snapshot.recovery.map { ScoreEngine.target(recovery: $0) },
                                      calendar: calendar),
           steps >= Double(goal) { return true }
        if let strain = snapshot.strain, let recovery = snapshot.recovery,
           strain >= ScoreEngine.target(recovery: recovery).lowerBound { return true }
        return false
    }

    /// `history` darf heute enthalten. Tage ohne Daten unterbrechen die Serie.
    static func current(endingAt today: Date, history: [DayMetrics], limit: Int = 60,
                        calendar: Calendar = .forma) -> Result {
        let end = calendar.startOfDay(for: today)
        let byDay = Dictionary(history.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { _, later in later })
        func reachedOn(_ date: Date) -> Bool {
            guard let day = byDay[date] else { return false }
            return reached(day, history: history.filter { $0.date < date }, calendar: calendar)
        }
        let todayReached = reachedOn(end)
        var count = todayReached ? 1 : 0
        for offset in 1..<max(2, limit) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end), reachedOn(date) else { break }
            count += 1
        }
        return Result(days: count, todayReached: todayReached)
    }
}
