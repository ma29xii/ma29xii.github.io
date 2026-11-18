import Foundation

/// Messwerte eines Tages, unabhängig von der Quelle.
struct DayMetrics: Equatable, Sendable, Identifiable {
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
}

struct SleepNight: Equatable, Sendable {
    enum Stage: String, Sendable, CaseIterable {
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

    struct Segment: Equatable, Sendable, Identifiable {
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
    func total(_ stage: Stage) -> TimeInterval { segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration } }
    var asleep: TimeInterval { total(.rem) + total(.core) + total(.deep) }
    var efficiency: Double { inBed > 0 ? asleep / inBed : 0 }
}

struct WorkoutSummary: Equatable, Sendable, Identifiable {
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
