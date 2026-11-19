import Foundation

/// Gewohnheit, deren Wirkung auf die folgende Nacht ein Experiment beobachtet.
enum ExperimentHabit: String, Codable, CaseIterable, Identifiable, Sendable {
    case lateCaffeine, alcohol, screens, magnesium, lateMeal, lateTraining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lateCaffeine: "Koffein am Nachmittag"
        case .alcohol: "Alkohol"
        case .screens: "Bildschirm im Bett"
        case .magnesium: "Magnesium"
        case .lateMeal: "Spätes Essen"
        case .lateTraining: "Training am Abend"
        }
    }

    var icon: String {
        switch self {
        case .lateCaffeine: "cup.and.saucer"
        case .alcohol: "wineglass"
        case .screens: "iphone"
        case .magnesium: "pills"
        case .lateMeal: "fork.knife"
        case .lateTraining: "figure.run"
        }
    }

    /// Frage am Morgen – sie bezieht sich auf den Abend vor der Nacht, deren Werte heute gelten.
    var question: String {
        switch self {
        case .lateCaffeine: "Gestern nach 14 Uhr Koffein?"
        case .alcohol: "Gestern Alkohol getrunken?"
        case .screens: "Gestern im Bett aufs Handy geschaut?"
        case .magnesium: "Gestern Abend Magnesium genommen?"
        case .lateMeal: "Gestern nach 21 Uhr gegessen?"
        case .lateTraining: "Gestern nach 19 Uhr trainiert?"
        }
    }
}

/// 14 Tage, an denen du morgens antippst, ob die Gewohnheit am Vorabend dabei war.
struct HabitExperiment: Codable, Identifiable, Equatable, Sendable {
    static let length = 14

    var id = UUID()
    let habit: ExperimentHabit
    /// Erster Morgen des Experiments (Tagesbeginn).
    let start: Date
    /// Antwort je Tag seit Beginn (0…13): true = mit Gewohnheit.
    var answers: [Int: Bool] = [:]
    var ended: Date?

    init(habit: ExperimentHabit, start: Date, calendar: Calendar = .forma) {
        self.habit = habit
        self.start = calendar.startOfDay(for: start)
    }

    func date(ofDay index: Int, calendar: Calendar = .forma) -> Date {
        calendar.date(byAdding: .day, value: index, to: start) ?? start
    }

    /// Tag im Experiment (0…13) für ein Datum, sonst nil.
    func dayIndex(of date: Date, calendar: Calendar = .forma) -> Int? {
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? -1
        return (0..<Self.length).contains(days) ? days : nil
    }

    /// Wie viele Tage schon begonnen haben (1…14), höchstens 14.
    func elapsedDays(now: Date = .now, calendar: Calendar = .forma) -> Int {
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0
        return min(Self.length, max(0, days + 1))
    }

    func isComplete(now: Date = .now, calendar: Calendar = .forma) -> Bool {
        ended != nil || (calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0) >= Self.length
    }

    var answeredCount: Int { answers.count }

    /// Antworten nach Datum, für den Vergleich.
    func answersByDate(calendar: Calendar = .forma) -> [Date: Bool] {
        Dictionary(uniqueKeysWithValues: answers.map { (date(ofDay: $0.key, calendar: calendar), $0.value) })
    }
}

/// Vergleich der Tage mit und ohne Gewohnheit – ehrlich: erst ab vier Tagen je Gruppe.
enum ExperimentComparison {
    static let minimumPerGroup = 4

    enum Metric: String, CaseIterable, Identifiable, Sendable {
        case recovery, hrv, sleep
        var id: String { rawValue }

        var title: String {
            switch self {
            case .recovery: "Recovery"
            case .hrv: "HRV"
            case .sleep: "Schlafdauer"
            }
        }

        func format(_ value: Double) -> String {
            switch self {
            case .recovery: Format.number(value) + " %"
            case .hrv: Format.number(value) + " ms"
            case .sleep: Format.duration(value * 3600)
            }
        }

        func formatDifference(_ value: Double) -> String {
            let sign = value > 0 ? "+" : (value < 0 ? "−" : "±")
            switch self {
            case .recovery: return sign + Format.number(abs(value)) + " %"
            case .hrv: return sign + Format.number(abs(value)) + " ms"
            case .sleep: return sign + Format.duration(abs(value) * 3600)
            }
        }
    }

    struct Result: Equatable, Sendable {
        let withMean: Double?
        let withoutMean: Double?
        let withCount: Int
        let withoutCount: Int

        var isConclusive: Bool { withMean != nil && withoutMean != nil }
        /// Mit minus ohne.
        var difference: Double? {
            guard let withMean, let withoutMean else { return nil }
            return withMean - withoutMean
        }
    }

    /// Nur Tage mit Antwort *und* Messwert zählen. Unter vier Tagen je Gruppe gibt es keinen Mittelwert.
    static func compare(answers: [Date: Bool], values: [Date: Double], calendar: Calendar = .forma) -> Result {
        let measured = Dictionary(values.compactMap { date, value in
            value.isFinite ? (calendar.startOfDay(for: date), value) : nil
        }, uniquingKeysWith: { first, _ in first })
        var with: [Double] = []
        var without: [Double] = []
        for (date, didIt) in answers {
            guard let value = measured[calendar.startOfDay(for: date)] else { continue }
            if didIt { with.append(value) } else { without.append(value) }
        }
        func mean(_ values: [Double]) -> Double? {
            values.count >= minimumPerGroup ? values.reduce(0, +) / Double(values.count) : nil
        }
        return Result(withMean: mean(with), withoutMean: mean(without), withCount: with.count, withoutCount: without.count)
    }

    /// Tageswerte je Kennzahl aus den vorhandenen Tagesdaten. Recovery wie auf Today (`DashboardDay`).
    static func values(for metric: Metric, dates: [Date], days: [DayMetrics], calendar: Calendar = .forma) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for date in dates {
            let key = calendar.startOfDay(for: date)
            guard let day = days.first(where: { calendar.isDate($0.date, inSameDayAs: key) }) else { continue }
            let value: Double? = switch metric {
            case .recovery: DashboardDay(day: day, history: days).recovery.map { Double($0) }
            case .hrv: day.hrv
            case .sleep: day.sleep.map { $0.asleep / 3600 }.flatMap { $0 > 0 ? $0 : nil }
            }
            if let value { result[key] = value }
        }
        return result
    }
}

/// Laufendes und abgeschlossene Experimente, als JSON in UserDefaults (eigener Schlüssel für die Vorschau).
struct ExperimentStore: Codable, Equatable, Sendable {
    var current: HabitExperiment?
    var past: [HabitExperiment] = []

    static func key(isSample: Bool) -> String {
        isSample ? "forma.health.experiments.sample.v1" : "forma.health.experiments.v1"
    }

    static func load(isSample: Bool, defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key(isSample: isSample)),
              let store = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return store
    }

    func save(isSample: Bool, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key(isSample: isSample))
    }

    /// Laufendes Experiment abschließen und oben in die Liste legen.
    mutating func finishCurrent(now: Date = .now) {
        guard var experiment = current else { return }
        experiment.ended = experiment.ended ?? now
        past.insert(experiment, at: 0)
        past = Array(past.prefix(12))
        current = nil
    }
}
