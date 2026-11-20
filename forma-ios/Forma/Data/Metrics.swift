import Foundation

/// Messwerte eines Tages, unabhängig von der Quelle.
struct DayMetrics: Equatable, Sendable, Identifiable, Codable {
    var date: Date                 // Tagesbeginn
    var hrv: Double? = nil         // ms (Fitbit-RMSSD)
    var restingHR: Double? = nil   // bpm
    var respiratoryRate: Double? = nil // Atemzüge/min
    var spo2: Double? = nil        // %
    var vo2max: Double? = nil      // ml/kg/min
    var steps: Double? = nil
    var activeEnergy: Double? = nil // kcal
    var sleep: SleepNight? = nil
    var workouts: [WorkoutSummary] = []
    var skinTemperature: Double? = nil // nächtliche Hauttemperatur in °C
    var origins: [MetricSeries: [GoogleMetricOrigin]]? = nil
    var civilDay: CivilDay? = nil      // stabil beim Wechsel der Anzeigezeitzone

    var id: Date { date }

    func onCivilDay(in calendar: Calendar, legacyCalendar: Calendar? = nil) -> Self? {
        var day = self
        let key = civilDay ?? CivilDay(date, in: legacyCalendar ?? calendar)
        guard let start = key.start(in: calendar) else { return nil }
        day.civilDay = key
        day.date = start
        return day
    }

    mutating func setOrigins(_ values: [GoogleMetricOrigin], for series: MetricSeries) {
        if origins == nil { origins = [:] }
        origins?[series] = values.isEmpty ? nil : Array(Set(values)).sorted {
            if $0.family != $1.family { return $0.family.rawValue < $1.family.rawValue }
            return ($0.device ?? "") < ($1.device ?? "")
        }
    }

    func hasMeasurement(for series: MetricSeries) -> Bool {
        switch series {
        case .hrv: hrv != nil
        case .restingHR: restingHR != nil
        case .respiratoryRate: respiratoryRate != nil
        case .spo2: spo2 != nil
        case .vo2max: vo2max != nil
        case .steps: steps != nil
        case .activeEnergy: activeEnergy != nil
        case .sleep: (sleep?.asleep ?? 0) > 0
        case .workouts: !workouts.isEmpty
        case .skinTemperature: skinTemperature != nil
        }
    }

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
        d.skinTemperature = keep(skinTemperature, 20...45)
        if let night = sleep {
            let segments = night.segments.filter { $0.end > $0.start && $0.duration <= 12 * 3600 }
            let reported = keep(night.reportedAsleep, 1...max(1, night.inBed))
            d.sleep = (night.end > night.start && night.inBed <= 24 * 3600 && (!segments.isEmpty || reported != nil))
                ? SleepNight(start: night.start, end: night.end, segments: segments, reportedAsleep: reported)
                    .resolvingStages() : nil
        }
        d.workouts = workouts.filter { $0.duration.isFinite && $0.duration > 0 && $0.duration <= 24 * 3600 }
            .map { w in var w = w; if let e = w.energy, !e.isFinite || e < 0 || e > 10_000 { w.energy = nil }; return w }
        return d
    }
}

/// Einzelne Messreihen eines Imports (für Teil-Erfolge, Codex R-02-01).
enum MetricSeries: String, CaseIterable, Codable, Sendable {
    case hrv, restingHR, respiratoryRate, spo2, vo2max, steps, activeEnergy, sleep, workouts, skinTemperature

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
        case .skinTemperature: "Hauttemperatur"
        }
    }
}

struct SleepNight: Equatable, Sendable, Codable {
    enum Stage: String, Sendable, CaseIterable, Codable {
        case awake, rem, core, deep, unspecified
        var title: String {
            switch self {
            case .awake: "Wach"
            case .rem: "REM"
            case .core: "Kern"
            case .deep: "Tief"
            case .unspecified: "Ohne Phasenangabe"
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
    var reportedAsleep: TimeInterval? = nil

    var inBed: TimeInterval { end.timeIntervalSince(start) }
    func total(_ stage: Stage) -> TimeInterval { SleepNight.unionLength(segments.filter { $0.stage == stage }) }
    /// Schlafzeit als Vereinigung der Intervalle: Überlappungen zählen nur einmal.
    var asleep: TimeInterval {
        let measured = SleepNight.unionLength(segments.filter { $0.stage != .awake })
        return measured > 0 ? measured : (reportedAsleep ?? 0)
    }
    var efficiency: Double { inBed > 0 ? min(1, asleep / inBed) : 0 }
    /// Hat die Nacht echte Phasen (Tief/REM)? Sonst ist nur „geschlafen“ bekannt.
    var hasStages: Bool { segments.contains { $0.stage == .deep || $0.stage == .rem } }
    var hasCompleteStages: Bool { hasStages && total(.unspecified) == 0 }

    var recordedStages: [Stage] {
        Stage.allCases.filter { stage in segments.contains { $0.stage == stage } }
    }

    /// Lässt identische Phasen zusammenfallen und bewahrt widersprüchliche Schlafzeit ohne Phasenzuordnung.
    func resolvingStages() -> Self {
        var events: [Date: [Stage: Int]] = [:]
        for segment in segments {
            let lower = max(start, segment.start)
            let upper = min(end, segment.end)
            guard lower < upper else { continue }
            events[lower, default: [:]][segment.stage, default: 0] += 1
            events[upper, default: [:]][segment.stage, default: 0] -= 1
        }
        var active: [Stage: Int] = [:]
        var result: [Segment] = []
        var previous = start
        for time in events.keys.sorted() {
            let stages = active.filter { $0.value > 0 }.keys
            let specific = stages.filter { $0 != .unspecified }
            let stage: Stage? = if stages.isEmpty { nil }
                else if specific.count == 1, specific.first != .awake || !stages.contains(.unspecified) { specific.first }
                else { .unspecified }
            if let stage, previous < time {
                if let last = result.last, last.stage == stage, last.end == previous {
                    result[result.count - 1].end = time
                } else {
                    result.append(.init(stage: stage, start: previous, end: time))
                }
            }
            for (stage, change) in events[time] ?? [:] { active[stage, default: 0] += change }
            previous = time
        }
        var night = self
        night.segments = result
        return night
    }

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
    var activityType: String? = nil

    var end: Date { start.addingTimeInterval(duration) }

    func isDuplicate(of other: Self) -> Bool {
        if id == other.id { return true }
        let sameType = isStrength && other.isStrength
            || (!isStrength && !other.isStrength && (activityType != nil && activityType == other.activityType
                || activityType == nil && other.activityType == nil && name == other.name && name != "Training"))
        guard sameType, duration > 0, other.duration > 0 else { return false }
        let overlap = min(end, other.end).timeIntervalSince(max(start, other.start))
        return overlap >= max(duration, other.duration) * 0.8
            && abs(start.timeIntervalSince(other.start)) <= 5 * 60
            && abs(end.timeIntervalSince(other.end)) <= 5 * 60
    }

    static func totalDuration(_ workouts: [Self], from lower: Date = .distantPast,
                              until upper: Date = .distantFuture) -> TimeInterval {
        SleepNight.unionLength(workouts.compactMap {
            let start = max($0.start, lower)
            let end = min($0.end, upper)
            return start < end ? .init(stage: .unspecified, start: start, end: end) : nil
        })
    }
}

/// Ein Kalendertag ohne Zeitzone. Erst für die Anzeige wird daraus ein lokaler Tagesbeginn.
struct CivilDay: Hashable, Codable, Sendable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 0
        month = parts.month ?? 0
        day = parts.day ?? 0
    }

    func start(in calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              Self(date, in: calendar) == self else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

enum DataSourceKind: String, Sendable, CaseIterable, Identifiable {
    case google, sample
    var id: String { rawValue }
    var title: String {
        switch self {
        case .google: "Google Health"
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
    /// Wochenstart aus dem Profil: 2 = Montag (Standard), 1 = Sonntag.
    nonisolated static let weekStartKey = "forma.weekStart"
    nonisolated static let defaultWeekStart = 2

    static var forma: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = .german
        let start = UserDefaults.standard.object(forKey: weekStartKey) as? Int ?? defaultWeekStart
        c.firstWeekday = [1, 2].contains(start) ? start : defaultWeekStart
        c.timeZone = .current
        return c
    }

    func startOfDay(offsetBy days: Int, from date: Date) -> Date? {
        self.date(byAdding: .day, value: days, to: date).map { startOfDay(for: $0) }
    }
}

extension Date {
    var startOfDay: Date { Calendar.forma.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.forma.date(byAdding: .day, value: days, to: self) ?? self }
    func adding(minutes: Double) -> Date { addingTimeInterval(minutes * 60) }
}
