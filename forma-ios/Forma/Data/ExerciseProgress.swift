import Foundation

// Reine Rechenlogik für Bestwerte, Verlauf, Muskel-Erholung und Trainingskalender (ohne SwiftData, testbar).

// MARK: - Bestwerte

enum PersonalRecord {
    /// Neuer Bestwert, wenn das geschätzte Maximum den bisherigen Bestwert übertrifft.
    /// Das erste Mal einer Übung zählt nicht – sonst wäre jeder Anfang ein „Rekord“.
    static func isNew(weight: Double, reps: Int, previousBest: Double) -> Bool {
        previousBest > 0 && OneRepMax.epley(weight: weight, reps: reps) > previousBest + 0.05
    }
}

/// Ein Arbeitssatz einer Übung, wie ihn Verlauf und Bestwerte brauchen.
typealias LiftSet = (weight: Double, reps: Int)

struct ExerciseRecords: Equatable, Sendable {
    var bestOneRepMax: Double = 0
    var bestOneRepMaxDate: Date?
    var heaviest: Double = 0
    var heaviestReps = 0
    var mostReps = 0
    var bestSessionVolume: Double = 0

    /// Bestwerte über alle Trainings. nil, solange es keinen gültigen Arbeitssatz gibt.
    static func from(_ sessions: [(date: Date, sets: [LiftSet])]) -> ExerciseRecords? {
        var r = ExerciseRecords()
        var any = false
        for session in sessions {
            var volume = 0.0
            for set in session.sets where set.weight >= 0 && set.reps > 0 && set.weight.isFinite {
                any = true
                volume += set.weight * Double(set.reps)
                let orm = OneRepMax.epley(weight: set.weight, reps: set.reps)
                if orm > r.bestOneRepMax { r.bestOneRepMax = orm; r.bestOneRepMaxDate = session.date }
                if set.weight > r.heaviest || (set.weight == r.heaviest && set.reps > r.heaviestReps) {
                    r.heaviest = set.weight; r.heaviestReps = set.reps
                }
                r.mostReps = max(r.mostReps, set.reps)
            }
            r.bestSessionVolume = max(r.bestSessionVolume, volume)
        }
        return any ? r : nil
    }
}

struct ExerciseProgressPoint: Equatable, Sendable, Identifiable {
    let date: Date
    let oneRepMax: Double
    let volume: Double
    var id: Date { date }

    /// Ein Punkt je Training mit mindestens einem Arbeitssatz, zeitlich sortiert.
    static func series(_ sessions: [(date: Date, sets: [LiftSet])]) -> [ExerciseProgressPoint] {
        sessions.compactMap { s -> ExerciseProgressPoint? in
            let valid = s.sets.filter { $0.reps > 0 && $0.weight >= 0 && $0.weight.isFinite }
            guard !valid.isEmpty else { return nil }
            return ExerciseProgressPoint(date: s.date,
                                         oneRepMax: valid.map { OneRepMax.epley(weight: $0.weight, reps: $0.reps) }.max() ?? 0,
                                         volume: valid.reduce(0) { $0 + $1.weight * Double($1.reps) })
        }
        .sorted { $0.date < $1.date }
    }
}

// MARK: - Muskel-Erholung

enum RecoveryState: Int, Comparable, Sendable, CaseIterable {
    case fresh, recovering, loaded

    var title: String {
        switch self {
        case .fresh: "Frisch"
        case .recovering: "Erholt sich"
        case .loaded: "Belastet"
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

enum MuscleRecovery {
    static let window: TimeInterval = 72 * 3600

    /// Restbelastung je Muskel aus den Sätzen der letzten 72 h: Hauptmuskel 1, mithelfend ½,
    /// linear abklingend bis null nach 72 h.
    static func load(_ sets: [(exercise: String, date: Date)], groups: [String: String] = [:], now: Date = .now) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for set in sets {
            let age = now.timeIntervalSince(set.date)
            guard age >= 0, age < window else { continue }
            let decay = 1 - age / window
            let muscles = ExerciseCatalog.muscles(for: set.exercise, group: groups[set.exercise])
            for m in muscles.primary { result[m, default: 0] += decay }
            for m in muscles.secondary where !muscles.primary.contains(m) { result[m, default: 0] += 0.5 * decay }
        }
        return result
    }

    static func state(_ load: Double) -> RecoveryState {
        load < 1 ? .fresh : (load < 4 ? .recovering : .loaded)
    }

    /// Leuchtstärke auf der Karte: frische Muskeln bleiben dunkel.
    static func level(_ load: Double) -> Double {
        load < 1 ? 0 : min(1, 0.3 + load / 8)
    }
}

// MARK: - Trainingskalender

enum TrainingCalendar {
    static func days(_ dates: [Date], calendar: Calendar = .forma) -> Set<Date> {
        Set(dates.map { calendar.startOfDay(for: $0) })
    }

    /// Monatsraster ab Montag: führende Lücken (nil), dann jeder Tag des Monats.
    static func grid(for month: Date, calendar: Calendar = .forma) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: lead) + days.map { Optional($0) }
    }

    /// Wochen in Folge mit mindestens einem Training. Die laufende Woche bricht die Serie nicht, solange sie offen ist.
    static func weekStreak(_ dates: [Date], now: Date = .now, calendar: Calendar = .forma) -> Int {
        let weeks = Set(dates.filter { $0 <= now }.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(week) {
            guard let last = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { return 0 }
            week = last
        }
        var streak = 0
        while weeks.contains(week) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return streak
    }
}
