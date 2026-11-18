import SwiftUI

/// Kennzahlen mit Einheit, Nachkommastellen und Quelle.
enum MetricKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case hrv, restingHR, respiratoryRate, spo2, vo2max, sleepDuration, steps, activeEnergy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv: "HRV"
        case .restingHR: "Ruhepuls"
        case .respiratoryRate: "Atemfrequenz"
        case .spo2: "Sauerstoffsättigung"
        case .vo2max: "VO₂max"
        case .sleepDuration: "Schlafdauer"
        case .steps: "Schritte"
        case .activeEnergy: "Aktive Energie"
        }
    }

    var unit: String {
        switch self {
        case .hrv: "ms"
        case .restingHR: "bpm"
        case .respiratoryRate: "/min"
        case .spo2: "%"
        case .vo2max: "ml/kg/min"
        case .sleepDuration: "h"
        case .steps: ""
        case .activeEnergy: "kcal"
        }
    }

    var decimals: Int {
        switch self {
        case .respiratoryRate, .vo2max, .sleepDuration: 1
        default: 0
        }
    }

    /// Höher ist besser? (für die Farbe der Abweichung)
    var higherIsBetter: Bool {
        switch self {
        case .restingHR, .respiratoryRate: false
        default: true
        }
    }

    var explanation: String {
        switch self {
        case .hrv: "Herzfrequenzvariabilität: Schwankung zwischen Herzschlägen. Höher als dein Normalwert heißt meist: gut erholt. Apple misst SDNN, Fitbit RMSSD – die Werte sind nicht direkt vergleichbar."
        case .restingHR: "Ruhepuls: dein niedrigster stabiler Puls. Ein Anstieg über mehrere Tage kann auf Belastung, Stress oder eine beginnende Erkrankung hinweisen."
        case .respiratoryRate: "Atemzüge pro Minute im Schlaf. Sehr stabil – schon kleine Abweichungen sind auffällig."
        case .spo2: "Sauerstoffsättigung im Blut, gemessen im Schlaf. Werte zwischen 95 und 100 % gelten als normal."
        case .vo2max: "Geschätzte maximale Sauerstoffaufnahme – ein Maß für deine Ausdauer. Ändert sich langsam über Wochen."
        case .sleepDuration: "Tatsächlich geschlafene Zeit ohne Wachphasen."
        case .steps: "Schritte über den ganzen Tag."
        case .activeEnergy: "Kalorien, die du durch Bewegung über dem Grundumsatz verbrauchst."
        }
    }

    func value(_ day: DayMetrics) -> Double? {
        switch self {
        case .hrv: day.hrv
        case .restingHR: day.restingHR
        case .respiratoryRate: day.respiratoryRate
        case .spo2: day.spo2
        case .vo2max: day.vo2max
        case .sleepDuration: day.sleep.map { $0.asleep / 3600 }
        case .steps: day.steps
        case .activeEnergy: day.activeEnergy
        }
    }

    /// Kurzform für Bereiche, z. B. 7:02 bei Schlafdauer.
    func formattedShort(_ value: Double) -> String {
        guard self == .sleepDuration else { return formatted(value) }
        let minutes = Int((value * 60).rounded())
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    func formatted(_ value: Double) -> String {
        if self == .sleepDuration { return Format.duration(value * 3600) }
        return Format.number(value, decimals: decimals)
    }
}

/// Zeile mit aktuellem Wert und Normalbereich (Mittel ± 1 Standardabweichung der letzten 30 Tage).
struct MetricSummaryRow: View {
    @Environment(DataHub.self) private var hub
    let kind: MetricKind

    var body: some View {
        let values = hub.days.compactMap { kind.value($0) }
        let history = hub.history.compactMap { kind.value($0) }
        let current = kind.value(hub.today) ?? values.last
        let base = ScoreEngine.baseline(history)
        let low = base.map { $0.mean - $0.sd }, high = base.map { $0.mean + $0.sd }
        let outside: Bool = {
            guard let c = current, let low, let high else { return false }
            return c < low - (high - low) * 0.25 || c > high + (high - low) * 0.25
        }()
        MetricRow(
            title: kind.title,
            subtitle: (low != nil && high != nil) ? "Normal \(kind.formattedShort(low!))–\(kind.formattedShort(high!))\(kind.unit.isEmpty ? "" : " " + kind.unit)" : "noch kein Normalwert",
            value: current.map { kind == .sleepDuration ? kind.formatted($0) : kind.formatted($0) },
            unit: kind == .sleepDuration ? nil : kind.unit,
            valueColor: outside ? Theme.warning : Theme.textPrimary,
            showsChevron: true
        ) {
            if let c = current, let low, let high {
                let span = Swift.max(high - low, 0.001)
                RangeBar(low: low, high: high, value: c, minimum: low - span * 1.2, maximum: high + span * 1.2,
                         dotColor: outside ? Theme.warning : Theme.textPrimary)
            }
        }
    }
}
