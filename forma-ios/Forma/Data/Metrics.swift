import Foundation

/// Messwerte eines Tages, unabhängig von der Quelle.
struct DayMetrics: Equatable, Sendable, Identifiable, Codable {
    var date: Date                 // Tagesbeginn
    var hrv: Double? = nil         // ms (SDNN bei Apple, RMSSD bei Fitbit)
    var restingHR: Double? = nil   // bpm
    var respiratoryRate: Double? = nil // Atemzüge/min
    var spo2: Double? = nil        // %
    var vo2max: Double? = nil      // ml/kg/min
    var steps: Double? = nil
    var activeEnergy: Double? = nil // kcal
    var sleep: SleepNight? = nil
    var workouts: [WorkoutSummary] = []

    var id: Date { date }

    /// Verwirft unplausible Messwerte (NaN, negativ, physiologisch unmöglich), damit
    /// keine Berechnung abstürzt oder Unsinn zeigt.
    func sanitized() -> DayMetrics {
        func keep(_ v: Double?, _ range: ClosedRange<Double>) -> Double? {
            guard let v, v.isFinite, range.contains(v) else { return nil }
            return v
        }
        var d = self
        d.hrv = keep(hrv, 1...400)
        d.restingHR = keep(restingHR, 25...150)
        d.respiratoryRate = keep(respiratoryRate, 4...40)
        d.spo2 = keep(spo2, 50...100)
        d.vo2max = keep(vo2max, 10...95)
        d.steps = keep(steps, 0...150_000)
        d.activeEnergy = keep(activeEnergy, 0...12_000)
        if let night = sleep {
            let segments = night.segments.filter { $0.end > $0.start && $0.duration <= 12 * 3600 }
            d.sleep = (night.end > night.start && night.inBed <= 24 * 3600 && !segments.isEmpty)
                ? SleepNight(start: night.start, end: night.end, segments: segments) : nil
        }
        d.workouts = workouts.filter { $0.duration.isFinite && $0.duration > 0 && $0.duration <= 24 * 3600 }
            .map { w in var w = w; if let e = w.energy, !e.isFinite || e < 0 || e > 10_000 { w.energy = nil }; return w }
        return d
    }
}

/// Einzelne Messreihen eines Imports (für Teil-Erfolge, Codex R-02-01).
enum MetricSeries: String, CaseIterable, Codable, Sendable {
    case hrv, restingHR, respiratoryRate, spo2, vo2max, steps, activeEnergy, sleep, workouts

    var title: String {
        switch self {
        case .hrv: "HRV"
        case .restingHR: "Ruhepuls"
        case .respiratoryRate: "Atemfrequenz"
        case .spo2: "Sauerstoffsättigung"
        case .vo2max: "VO₂max"
        case .steps: "Schritte"
        case .activeEnergy: "Aktive Energie"
        case .sleep: "Schlaf"
        case .workouts: "Trainings"
        }
    }
}

struct SleepNight: Equatable, Sendable, Codable {
    enum Stage: String, Sendable, CaseIterable, Codable {
        case awake, rem, core, deep
        var title: String {
            switch self {
            case .awake: "Wach"
            case .rem: "REM"
            case .core: "Kern"
            case .deep: "Tief"
            }
        }
        /// 0 = oben (wach), 3 = unten (tief)
        var level: Int {
            switch self {
            case .awake: 0
            case .rem: 1
            case .core: 2
            case .deep: 3
            }
        }
    }

    struct Segment: Equatable, Sendable, Identifiable, Codable {
        var stage: Stage
        var start: Date
        var end: Date
        var id: Date { start }
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    var start: Date
    var end: Date
    var segments: [Segment]

    var inBed: TimeInterval { end.timeIntervalSince(start) }
    func total(_ stage: Stage) -> TimeInterval { SleepNight.unionLength(segments.filter { $0.stage == stage }) }
    /// Schlafzeit als Vereinigung der Intervalle: Überlappungen zählen nur einmal.
    var asleep: TimeInterval { SleepNight.unionLength(segments.filter { $0.stage != .awake }) }
    var efficiency: Double { inBed > 0 ? min(1, asleep / inBed) : 0 }
    /// Hat die Nacht echte Phasen (Tief/REM)? Sonst ist nur „geschlafen“ bekannt.
    var hasStages: Bool { segments.contains { $0.stage == .deep || $0.stage == .rem } }

    static func unionLength(_ segments: [Segment]) -> TimeInterval {
        let sorted = segments.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for s in sorted {
            if let c = current, s.start <= c.end {
                current = (c.start, max(c.end, s.end))
            } else {
                if let c = current { total += c.end.timeIntervalSince(c.start) }
                current = (s.start, s.end)
            }
        }
        if let c = current { total += c.end.timeIntervalSince(c.start) }
        return total
    }

    /// Wählt pro Aufwachtag die Hauptnacht aus Phasen mehrerer Quellen.
    static func mainNights(bySource: [String: [Segment]], gap: TimeInterval = 90 * 60) -> [Date: SleepNight] {
        var best: [Date: SleepNight] = [:]
        for (_, segments) in bySource {
            let sorted = segments.sorted { $0.start < $1.start }
            var blocks: [[Segment]] = []
            var blockEnd: Date?
            for s in sorted {
                if let end = blockEnd, s.start.timeIntervalSince(end) <= gap {
                    blocks[blocks.count - 1].append(s)
                    blockEnd = max(end, s.end)
                } else {
                    blocks.append([s])
                    blockEnd = s.end
                }
            }
            for block in blocks {
                guard let first = block.first, let last = block.max(by: { $0.end < $1.end }) else { continue }
                let night = SleepNight(start: first.start, end: last.end, segments: block)
                guard night.asleep >= 20 * 60 else { continue }
                let wakeDay = last.end.addingTimeInterval(6 * 3600).startOfDay
                if let current = best[wakeDay] {
                    let better = night.asleep > current.asleep + 15 * 60
                        || (abs(night.asleep - current.asleep) <= 15 * 60 && night.hasStages && !current.hasStages)
                    if better { best[wakeDay] = night }
                } else {
                    best[wakeDay] = night
                }
            }
        }
        return best
    }
}

struct WorkoutSummary: Equatable, Sendable, Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var start: Date
    var duration: TimeInterval
    var energy: Double?   // kcal
    var isStrength: Bool = false
}

enum DataSourceKind: String, Sendable, CaseIterable, Identifiable {
    case automatic, health, fitbit, sample
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatisch"
        case .health: "Apple Health"
        case .fitbit: "Fitbit"
        case .sample: "Beispieldaten"
        }
    }
}

/// Berechnete Tageswerte.
struct DayScores: Equatable, Sendable {
    var recovery: Int
    var sleep: Int
    var strain: Int
    var target: ClosedRange<Int>
    var energy: Int
    var stress: Double      // 0–3, geschätzt
    var sleepNeed: TimeInterval
    var sleepDebt: TimeInterval
}

extension Calendar {
    static var forma: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = .german
        c.firstWeekday = 2
        c.timeZone = .current
        return c
    }
}

extension Date {
    var startOfDay: Date { Calendar.forma.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.forma.date(byAdding: .day, value: days, to: self) ?? self }
    func adding(minutes: Double) -> Date { addingTimeInterval(minutes * 60) }
}
