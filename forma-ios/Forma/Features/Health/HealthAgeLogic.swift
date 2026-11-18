import SwiftUI

/// Health Age heute und im Verlauf – beides mit derselben Rechnung aus `BodyAge`.
enum HealthAgeTrend {
    typealias Session = (start: Date, minutes: Double)

    static func outcome(days: [DayMetrics], person: PersonInfo, sessions: [Session], now: Date) -> BodyAge.Outcome {
        let strength = BodyAge.strengthMinutes(days: days, formaSessions: sessions, now: now)
        return BodyAge.evaluate(days: days, person: person, strength: strength, now: now)
    }

    /// Wöchentliche Schätzungen, jede nur mit den Daten bis zu ihrem Tag.
    /// Der letzte Punkt ist genau der Wert oben im Health-Tab.
    static func points(days: [DayMetrics], person: PersonInfo, sessions: [Session],
                       now: Date = .now, step: Int = 7, maxDays: Int = 180) -> [BodyAge.Estimate] {
        guard step > 0 else { return [] }
        var result: [BodyAge.Estimate] = []
        for offset in stride(from: 0, through: maxDays, by: step) {
            let cut = offset == 0 ? now : now.startOfDay.adding(days: -offset)
            let slice = offset == 0 ? days : days.filter { $0.date <= cut }
            // Weniger Tage als nötig: ältere Stichtage haben noch weniger, also abbrechen.
            guard slice.count >= BodyAge.minimumDays else { break }
            if case .ready(let r) = outcome(days: slice, person: person, sessions: sessions, now: cut) {
                result.append(BodyAge.Estimate(date: cut, bodyAge: r.bodyAge, age: r.age))
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}

/// Darstellung des Alterungstempos auf der Skala −1,0× bis 3,0×.
enum AgingPace {
    static let scale: ClosedRange<Double> = -1...3

    enum Band: Equatable {
        case slow, clock, fast

        var title: String {
            switch self {
            case .slow: "Langsam"
            case .clock: "Wie die Uhr"
            case .fast: "Schnell"
            }
        }

        var color: Color {
            switch self {
            case .slow: Theme.younger
            case .clock: Theme.textSecondary
            case .fast: Theme.older
            }
        }
    }

    /// Lage auf der Skala von 0 (−1,0×) bis 1 (3,0×); Werte außerhalb sitzen am Rand.
    static func fraction(_ pace: Double) -> Double {
        let clamped = min(scale.upperBound, max(scale.lowerBound, pace))
        return (clamped - scale.lowerBound) / (scale.upperBound - scale.lowerBound)
    }

    static func band(_ pace: Double) -> Band {
        if pace < 0.8 { return .slow }
        if pace > 1.2 { return .fast }
        return .clock
    }

    static func text(_ pace: Double) -> String {
        let rounded = (pace * 10).rounded() / 10
        let sign = rounded < 0 ? "−" : ""
        return sign + Format.number(abs(rounded), decimals: 1) + "×"
    }
}

/// Bereichsbalken eines Health-Age-Faktors: Skala, Lage des Werts und der Abstand zum Vergleich.
enum FactorScale {
    static func domain(value: Double, display: ClosedRange<Double>) -> ClosedRange<Double> {
        min(value, display.lowerBound)...max(value, display.upperBound)
    }

    static func fraction(_ x: Double, in domain: ClosedRange<Double>) -> Double {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, x.isFinite else { return 0.5 }
        return min(1, max(0, (x - domain.lowerBound) / span))
    }

    /// Strecke zwischen Vergleichsbereich und Wert (als Anteile); nil, wenn der Wert im Bereich liegt.
    static func gap(value: Double, reference: ClosedRange<Double>, in domain: ClosedRange<Double>) -> ClosedRange<Double>? {
        let v = fraction(value, in: domain)
        let low = fraction(reference.lowerBound, in: domain)
        let high = fraction(reference.upperBound, in: domain)
        if v < low { return v...low }
        if v > high { return high...v }
        return nil
    }

    /// Kurzer Wert über dem Marker.
    static func compact(_ value: Double, id: String) -> String {
        switch id {
        case "sleep": Format.duration(value * 3600)
        case "vo2": Format.number(value, decimals: 1)
        case "rhr": Format.number(value) + " bpm"
        case "strength": Format.number(value) + " min"
        default: Format.number(value)
        }
    }

    /// Beschriftung an den Enden der Skala.
    static func end(_ value: Double, id: String) -> String {
        id == "sleep" ? Format.number(value) + " h" : Format.number(value)
    }
}

/// Zustandswort eines Biomarkers: letzter Wert gegen den persönlichen Bereich.
enum BiomarkerStatus: Equatable {
    case none
    case stale(Date)
    case noBaseline
    case normal
    case higher
    case lower

    static func evaluate(latest: (date: Date, value: Double)?, baseline: ScoreEngine.Baseline?,
                         today: Date = .now) -> Self {
        guard let latest else { return .none }
        guard Calendar.forma.isDate(latest.date, inSameDayAs: today) else { return .stale(latest.date) }
        guard let baseline else { return .noBaseline }
        let z = baseline.z(latest.value)
        if z > 1 { return .higher }
        if z < -1 { return .lower }
        return .normal
    }

    var title: String {
        switch self {
        case .none: "Keine Messung"
        case .stale(let date): "Stand \(Format.shortDate(date))"
        case .noBaseline: "Noch kein Vergleich"
        case .normal: "Normal"
        case .higher: "Erhöht"
        case .lower: "Niedrig"
        }
    }

    /// Grün, wenn die Abweichung in die gute Richtung geht, sonst Orange.
    func color(for kind: MetricKind) -> Color {
        switch self {
        case .normal: Theme.younger
        case .higher: kind.higherIsBetter ? Theme.younger : Theme.warning
        case .lower: kind.higherIsBetter ? Theme.warning : Theme.younger
        case .none, .stale, .noBaseline: Theme.textSecondary
        }
    }
}
