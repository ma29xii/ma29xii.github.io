import Foundation

/// Frühwarnung (F6-04): vergleicht die letzte Nacht mit dem persönlichen Bereich der 30 Tage davor.
/// Auffällig sind Hauttemperatur, Ruhepuls und Atemfrequenz zu hoch sowie HRV zu niedrig.
/// Ohne genug Vergleichswerte gibt es kein Ergebnis (nil) – es wird nichts geschätzt.
struct IllnessSignal: Sendable {
    enum Kind: CaseIterable, Sendable {
        case skinTemperature, restingHR, hrv, respiratoryRate

        var series: MetricSeries {
            switch self {
            case .skinTemperature: .skinTemperature
            case .restingHR: .restingHR
            case .hrv: .hrv
            case .respiratoryRate: .respiratoryRate
            }
        }
        var title: String { series.title }
        var unit: String {
            switch self {
            case .skinTemperature: "°C"
            case .restingHR: "bpm"
            case .hrv: "ms"
            case .respiratoryRate: "/min"
            }
        }
        var decimals: Int { self == .skinTemperature || self == .respiratoryRate ? 1 : 0 }
        /// Bei HRV ist ein *niedriger* Wert das Warnzeichen, bei den anderen ein hoher.
        var warnsWhenLow: Bool { self == .hrv }
        var symbol: String {
            switch self {
            case .skinTemperature: "thermometer.medium"
            case .restingHR: "heart"
            case .hrv: "waveform.path.ecg"
            case .respiratoryRate: "lungs"
            }
        }
    }

    enum Level: Int, Comparable, Sendable {
        case normal, watch, fighting

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .normal: "Unauffällig"
            case .watch: "Beobachten"
            case .fighting: "Dein Körper kämpft"
            }
        }
    }

    struct Reading: Sendable {
        let kind: Kind
        let value: Double
        let baseline: ScoreEngine.Baseline
        /// Abweichung in Standardabweichungen; positiv = in Warnrichtung (HRV: darunter).
        let deviation: Double

        var isFlagged: Bool { deviation >= IllnessSignal.flagThreshold }
        var isStrong: Bool { deviation >= IllnessSignal.strongThreshold }
        /// Pfeil zeigt die tatsächliche Richtung des Werts gegenüber deinem Normalwert.
        var isAboveNormal: Bool { value > baseline.mean }
        var range: ClosedRange<Double>? {
            NightVitals.range(for: kind.series.rawValue, baseline: baseline)
        }
    }

    static let flagThreshold = 1.5
    static let strongThreshold = 2.5
    /// Mindestens so viele der vier Werte brauchen Messung *und* Vergleichsbereich.
    static let minimumReadings = 3

    let readings: [Reading]
    let level: Level
    var flagged: [Reading] { readings.filter(\.isFlagged) }

    static func evaluate(day: DayMetrics, history: [DayMetrics], calendar: Calendar = .forma) -> IllnessSignal? {
        let vitals = NightVitals(day: day, history: history, calendar: calendar)
        guard vitals.hasNight else { return nil }
        let readings: [Reading] = Kind.allCases.compactMap { kind in
            guard let reading = vitals.readings.first(where: { $0.series == kind.series }),
                  let value = reading.value, value.isFinite, let baseline = reading.baseline else { return nil }
            let z = baseline.z(value)
            return Reading(kind: kind, value: value, baseline: baseline, deviation: kind.warnsWhenLow ? -z : z)
        }
        guard readings.count >= minimumReadings else { return nil }
        return IllnessSignal(readings: readings, level: level(for: readings))
    }

    static func level(for readings: [Reading]) -> Level {
        let flagged = readings.filter(\.isFlagged)
        let skinStrong = flagged.contains { $0.kind == .skinTemperature && $0.isStrong }
        if flagged.count >= 3 || (skinStrong && flagged.count >= 2) { return .fighting }
        if flagged.count == 2 { return .watch }
        return .normal
    }

    /// Verlauf der letzten `days` Tage bis einschließlich `day`; Tage ohne genug Daten bleiben nil.
    static func trail(endingAt day: Date, days: Int = 14, history: [DayMetrics],
                      calendar: Calendar = .forma) -> [(date: Date, signal: IllnessSignal?)] {
        let end = calendar.startOfDay(for: day)
        let byDay = Dictionary(history.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { _, later in later })
        return (0..<days).reversed().compactMap { offset -> (date: Date, signal: IllnessSignal?)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            guard let current = byDay[date] else { return (date, nil) }
            let prior = history.filter { $0.date < date }
            return (date, evaluate(day: current, history: prior, calendar: calendar))
        }
    }
}
