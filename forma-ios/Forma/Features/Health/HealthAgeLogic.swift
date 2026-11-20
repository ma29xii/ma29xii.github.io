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

    /// Ruhige Worte statt einer Grenzzahl, wenn das Tempo außerhalb der Skala liegt.
    static func outsideText(_ pace: Double) -> String? {
        if pace < scale.lowerBound { return "Langsamer, als die Skala zeigt" }
        if pace > scale.upperBound { return "Schneller, als die Skala zeigt" }
        return nil
    }

    static func text(_ pace: Double) -> String {
        // Außerhalb der Skala keine Scheingenauigkeit (K-03-38).
        if pace > scale.upperBound { return "über 3,0×" }
        if pace < scale.lowerBound { return "unter −1,0×" }
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

/// Zustandswort eines Biomarkers: letzter Wert gegen deinen üblichen Bereich – neutral, ohne „besser/schlechter“ (K-03-24).
enum BiomarkerStatus: Equatable {
    case none
    case stale(Date)
    case noBaseline
    case within
    case above
    case below

    static func evaluate(latest: (date: Date, value: Double)?, range: ClosedRange<Double>?,
                         today: Date = .now) -> Self {
        guard let latest else { return .none }
        guard Calendar.forma.isDate(latest.date, inSameDayAs: today) else { return .stale(latest.date) }
        guard let range else { return .noBaseline }
        if latest.value > range.upperBound { return .above }
        if latest.value < range.lowerBound { return .below }
        return .within
    }

    var title: String {
        switch self {
        case .none: "Keine Messung"
        case .stale(let date): "Stand \(Format.shortDate(date))"
        case .noBaseline: "Noch kein Vergleich"
        case .within: "In deinem Bereich"
        case .above: "Über deinem Bereich"
        case .below: "Unter deinem Bereich"
        }
    }

    /// Abweichungen heben sich nur durch Helligkeit und Pfeil ab, nicht durch Ampelfarben.
    var color: Color {
        switch self {
        case .above, .below: Theme.textPrimary
        case .within: Theme.textSecondary
        case .none, .stale, .noBaseline: Theme.textTertiary
        }
    }

    var symbol: String? {
        switch self {
        case .above: "arrow.up"
        case .below: "arrow.down"
        default: nil
        }
    }
}

/// Gleiche Vergleichsbasis wie der Health Monitor: die 30 Tage davor, nur Werte derselben Quelle,
/// mindestens sieben Werte, Bereich = Mittel ± 2 Standardabweichungen.
enum BiomarkerComparison {
    struct Evaluation {
        let latest: (date: Date, value: Double)?
        let range: ClosedRange<Double>?
        let status: BiomarkerStatus
    }

    static func series(for kind: MetricKind) -> MetricSeries? {
        kind == .sleepDuration ? .sleep : MetricSeries(rawValue: kind.rawValue)
    }

    static func range(for kind: MetricKind, day: DayMetrics, history: [DayMetrics]) -> ClosedRange<Double>? {
        let source = Self.series(for: kind)
        let values = InsightHistory(history).prior(to: day.date).compactMap { previous -> Double? in
            if let source, !ScoreEngine.sameBaselineSource(for: source, today: day, previous: previous) { return nil }
            return kind.value(previous)
        }
        guard values.count >= 7 else { return nil }
        let absoluteSpread = kind == .spo2 || kind == .skinTemperature
        var baseline = ScoreEngine.baseline(values, minimumRelativeSpread: absoluteSpread ? 0 : 0.04)
        if absoluteSpread, let spread = baseline?.sd { baseline?.sd = max(kind == .spo2 ? 1 : 0.2, spread) }
        return NightVitals.range(for: kind.rawValue, baseline: baseline)
    }

    static func evaluate(_ kind: MetricKind, days: [DayMetrics], today: Date = .now) -> Evaluation {
        guard let day = days.last(where: { kind.value($0) != nil }), let value = kind.value(day) else {
            return Evaluation(latest: nil, range: nil, status: .none)
        }
        let usual = Self.range(for: kind, day: day, history: days)
        let latest = (date: day.date, value: value)
        return Evaluation(latest: latest, range: usual,
                          status: BiomarkerStatus.evaluate(latest: latest, range: usual, today: today))
    }
}
