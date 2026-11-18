import Foundation

/// Lokale Berechnung der drei Ringe (0–100).
enum ScoreEngine {
    struct Baseline: Sendable {
        var mean: Double
        var sd: Double
        func z(_ value: Double) -> Double { sd > 0.0001 ? (value - mean) / sd : 0 }
    }

    static func baseline(_ raw: [Double]) -> Baseline? {
        let values = raw.filter(\.isFinite)
        guard values.count >= 4 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return Baseline(mean: mean, sd: max(sqrt(variance), mean * 0.04))
    }

    /// Schlafwert: Dauer gegen Bedarf (60 %), Effizienz (20 %), Tief- und REM-Anteil (20 %).
    static func sleepScore(_ night: SleepNight?, need: TimeInterval) -> Int {
        guard let night, night.asleep > 0 else { return 0 }
        let duration = min(1, night.asleep / max(need, 1)) * 60
        let efficiency = clamp((night.efficiency - 0.75) / 0.2) * 20
        // Ohne gemessene Phasen neutral werten statt mit 0 bestrafen (Codex R-01-06).
        // Tief und REM als *gemeinsame* Vereinigung: überlappende Phasen zählen nur einmal (Codex R-02-09).
        let restorativeTime = SleepNight.unionLength(night.segments.filter { $0.stage == .deep || $0.stage == .rem })
        let restorative = night.hasStages ? clamp((min(1, restorativeTime / night.asleep) - 0.25) / 0.2) * 20 : 10
        return Int((duration + efficiency + restorative).rounded()).clamped(1, 100)
    }

    /// Erholung: HRV und Ruhepuls gegen deinen 30-Tage-Normalwert, dazu Schlaf und Atemfrequenz.
    static func recovery(today: DayMetrics, history: [DayMetrics], sleepScore: Int) -> Int {
        var score = 58.0
        if let hrv = today.hrv, let b = baseline(history.compactMap(\.hrv)) { score += 10 * clampZ(b.z(hrv)) }
        if let rhr = today.restingHR, let b = baseline(history.compactMap(\.restingHR)) { score -= 7 * clampZ(b.z(rhr)) }
        if let resp = today.respiratoryRate, let b = baseline(history.compactMap(\.respiratoryRate)) { score -= 4 * clampZ(b.z(resp)) }
        if sleepScore > 0 { score += 0.25 * Double(sleepScore - 70) }
        return Int(score.rounded()).clamped(1, 99)
    }

    /// Belastung: aktive Energie und Trainingszeit, gesättigt gegen 100.
    static func strain(_ day: DayMetrics) -> Int {
        let kcal = day.activeEnergy ?? 0
        let workoutMinutes = day.workouts.reduce(0) { $0 + $1.duration / 60 }
        let load = kcal + workoutMinutes * 4
        return Int((100 * (1 - exp(-load / 1100))).rounded()).clamped(0, 100)
    }

    /// Empfohlener Belastungsbereich aus der Erholung.
    static func target(recovery: Int) -> ClosedRange<Int> {
        if recovery >= 67 { return 35...55 }
        if recovery >= 34 { return 25...40 }
        return 10...25
    }

    /// Schlafbedarf: Grundbedarf + Belastung von heute + Abbau der Schuld.
    static func sleepNeed(strain: Int, debt: TimeInterval, base: TimeInterval = 7.75 * 3600) -> TimeInterval {
        base + Double(strain) * 18 + min(debt, 2 * 3600) * 0.25
    }

    static func sleepDebt(history: [DayMetrics], base: TimeInterval = 7.75 * 3600) -> TimeInterval {
        let nights = history.suffix(7).compactMap { $0.sleep?.asleep }
        return nights.reduce(0) { $0 + max(0, base - $1) } / 3
    }

    /// Bedarf der vergangenen Nacht anhand der Daten vor dem Aufwachen.
    static func sleepNeedForLastNight(history: [DayMetrics]) -> TimeInterval {
        sleepNeed(strain: history.last.map { strain($0) } ?? 0,
                  debt: sleepDebt(history: Array(history.dropLast())))
    }

    static func scores(today: DayMetrics, history: [DayMetrics], now: Date = .now) -> DayScores {
        let debt = sleepDebt(history: history)
        let strainValue = strain(today)
        let need = sleepNeed(strain: strainValue, debt: debt)
        // Die vergangene Nacht wird am Bedarf von *gestern* gemessen – sonst ändert sich ihr Wert,
        // nur weil du heute trainierst (Codex R-02-09/A-13).
        let nightNeed = sleepNeedForLastNight(history: history)
        let sleepValue = sleepScore(today.sleep, need: nightNeed)
        let rec = recovery(today: today, history: history, sleepScore: sleepValue)
        let hour = Double(Calendar.forma.component(.hour, from: now))
        let dayFatigue = max(0, hour - 8) * 1.4
        let energy = Int((Double(rec) * 0.65 + Double(sleepValue) * 0.35 - Double(strainValue) * 0.3 - dayFatigue).rounded()).clamped(3, 100)
        var stress = 1.2 + Double(strainValue) / 120
        if let rhr = today.restingHR, let b = baseline(history.compactMap(\.restingHR)) { stress += 0.3 * clampZ(b.z(rhr)) }
        if let hrv = today.hrv, let b = baseline(history.compactMap(\.hrv)) { stress -= 0.2 * clampZ(b.z(hrv)) }
        return DayScores(recovery: rec, sleep: sleepValue, strain: strainValue, target: target(recovery: rec),
                         energy: energy, stress: min(3, max(0, stress)), sleepNeed: need, sleepDebt: debt)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func clampZ(_ z: Double) -> Double { min(2, max(-2, z)) }
}

extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(hi, Swift.max(lo, self)) }
}

/// Geschätztes Maximalgewicht (Epley).
enum OneRepMax {
    static func epley(weight: Double, reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }
}
