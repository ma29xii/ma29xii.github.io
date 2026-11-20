import Foundation

enum BiologicalSex: String, CaseIterable, Identifiable, Sendable {
    case unknown, male, female
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unknown: "Nicht angegeben"
        case .male: "Männlich"
        case .female: "Weiblich"
        }
    }
}

/// Angaben zur Person, die das Körperalter braucht.
struct PersonInfo: Equatable, Sendable {
    enum Origin: Sendable { case manual, assumed, missing }
    var birthDate: Date?
    var sex: BiologicalSex
    var origin: Origin
    var birthYear: Int? = nil
    var ageIsApproximate: Bool { birthDate == nil && birthYear != nil }

    func age(at date: Date = .now) -> Double? {
        if let birthDate { return date.timeIntervalSince(birthDate) / (365.2425 * 86_400) }
        let calendar = Calendar.forma
        guard let birthYear, let year = calendar.dateInterval(of: .year, for: date) else { return nil }
        let fraction = date.timeIntervalSince(year.start) / year.duration
        return Double(calendar.component(.year, from: date) - birthYear) + fraction - 0.5
    }
}

/// Körperalter: wie alt dein Körper nach deinen Messwerten wirkt.
///
/// Methode (transparent, keine Blackbox):
/// 1. Für jeden Faktor nehmen wir das relative Sterberisiko aus großen Meta-Analysen
///    und vergleichen deinen Wert mit einem typischen Referenzwert.
/// 2. Das Risiko wird über das Gompertz-Gesetz in Jahre umgerechnet: Bei Erwachsenen
///    verdoppelt sich das Sterberisiko etwa alle 8 Jahre, also gilt Jahre = ln(Risiko) · 8 / ln 2.
/// 3. Weil die Faktoren zusammenhängen (wer viel geht, hat oft auch eine höhere VO₂max),
///    wird die Summe auf 70 % gedämpft. Das ist eine eigene, offen benannte Annahme.
///
/// Das Ergebnis ist eine Schätzung für die Motivation, keine medizinische Diagnose.
enum BodyAge {
    struct Factor: Identifiable, Sendable {
        let id: String
        let title: String
        let systemImage: String
        let valueText: String
        let referenceText: String
        let value: Double
        let displayRange: ClosedRange<Double>
        let referenceRange: ClosedRange<Double>
        /// Datengrundlage, z. B. „164 von 180 Tagen“ oder „4 Messungen, zuletzt am 14.11.“
        let coverage: String
        let years: Double
        let explanation: String
        let source: String
    }

    /// Wie gut die Daten das Zeitfenster abdecken – sagt nichts über die Genauigkeit der Methode (Codex R-01-01).
    enum Confidence: Sendable {
        case low, medium, high
        var title: String {
            switch self {
            case .low: "Gering"
            case .medium: "Mittel"
            case .high: "Gut"
            }
        }
    }

    struct Result: Sendable {
        let age: Double
        let bodyAge: Double
        let recent: Estimate?
        let previous: Estimate?
        let factors: [Factor]
        let missing: [String]
        let daysWithData: Int
        let windowDays: Int
        let confidence: Confidence
        var ageIsApproximate = false
        var pace: Double? = nil
        var paceOutsideScale: Bool { pace.map { !(-1...3).contains($0) } ?? false }
        var difference: Double { bodyAge - age }
        var trend: Double? {
            guard let recent, let previous else { return nil }
            return recent.bodyAge - previous.bodyAge
        }
    }

    struct Estimate: Sendable, Identifiable {
        let date: Date
        let bodyAge: Double
        let age: Double
        var id: Date { date }
    }

    /// Geschätzte Altersjahre pro verstrichenem Kalenderjahr zwischen den Fenstermitten.
    static func agingPace(previous: Estimate?, recent: Estimate?) -> Double? {
        guard let previous, let recent else { return nil }
        let elapsedYears = recent.date.timeIntervalSince(previous.date) / (365.2425 * 86_400)
        guard elapsedYears > 0 else { return nil }
        let pace = (recent.bodyAge - previous.bodyAge) / elapsedYears
        return pace.isFinite ? pace : nil
    }

    enum Outcome: Sendable {
        case needsProfile
        case needsData(have: Int, need: Int)
        /// Rechnung wäre nicht belastbar (Alter außerhalb, nur Schritte …) – mit Begründung (Codex R-02-10).
        case insufficient(String)
        case ready(Result)
    }

    struct StrengthMinutes: Sendable {
        var perWeek: Double
        var recentPerWeek: Double
        var previousPerWeek: Double = 0
        /// Gibt es überhaupt aufgezeichnetes Krafttraining? Sonst kein Faktor statt „0 Minuten“ (Codex R-02-10).
        var hasRecord: Bool = true
        var recentHasRecord: Bool? = nil
        var previousHasRecord: Bool? = nil
        var trainingWeeks: Int? = nil
    }

    static let minimumDays = 21
    static let overlapDamping = 0.7
    /// Gompertz: Verdopplung des Sterberisikos etwa alle 8 Jahre.
    static let yearsPerLogHazard = 8 / log(2.0)

    static func evaluate(days: [DayMetrics], person: PersonInfo, strength: StrengthMinutes, now: Date = .now) -> Outcome {
        guard let age = person.age(at: now) else { return .needsProfile }
        let withData = days.filter(hasData)
        guard withData.count >= minimumDays else { return .needsData(have: withData.count, need: minimumDays) }
        guard (0...90).contains(age) else {
            return .insufficient("Health Age ist bis 90 Jahre verfügbar.")
        }

        let long = factors(days: days, age: age, sex: person.sex, strengthPerWeek: strength.perWeek, hasStrengthRecord: strength.hasRecord)
        guard long.factors.contains(where: { ["rhr", "sleep", "vo2"].contains($0.id) }) else {
            return .insufficient("Für Health Age fehlen Ruhepuls, Schlaf oder VO₂max.")
        }
        let end = now.startOfDay
        let comparison = comparableWindows(days, ending: end, length: 30, minimumDaily: 21, minimumVO2: 3, person: person)
        let longer = comparableWindows(days, ending: end, length: 90, minimumDaily: 60, minimumVO2: 6, person: person)

        let bodyAge = combine(age: age, sum: long.sum)
        let confidence: Confidence
        let weeks = strength.trainingWeeks ?? trainingWeeks(days.flatMap(\.workouts).filter(\.isStrength), calendar: .forma)
        func hasCoverage(daily: Int, vo2: Int, training: Int) -> Bool {
            long.factors.allSatisfy { factor in
                if factor.id == "strength" { return weeks >= training }
                return observations(for: factor.id, in: days).count >= (factor.id == "vo2" ? vo2 : daily)
            }
        }
        if long.factors.count == 5 && hasCoverage(daily: 120, vo2: 3, training: 12) { confidence = .high }
        else if long.factors.count >= 4 && hasCoverage(daily: 45, vo2: 2, training: 4) { confidence = .medium }
        else { confidence = .low }

        return .ready(Result(
            age: age, bodyAge: bodyAge,
            recent: comparison?.recent,
            previous: comparison?.previous,
            factors: long.factors.sorted { abs($0.years) > abs($1.years) },
            missing: long.missing,
            daysWithData: withData.count, windowDays: days.count,
            confidence: confidence, ageIsApproximate: person.ageIsApproximate,
            pace: agingPace(previous: longer?.previous, recent: longer?.recent)))
    }

    private static func comparableWindows(
        _ days: [DayMetrics], ending end: Date, length: Int, minimumDaily: Int, minimumVO2: Int,
        person: PersonInfo
    ) -> (previous: Estimate, recent: Estimate)? {
        let split = end.adding(days: -length)
        let start = split.adding(days: -length)
        let recentDays = days.filter { $0.date >= split && $0.date < end }
        let previousDays = days.filter { $0.date >= start && $0.date < split }
        guard recentDays.filter(hasData).count >= minimumDaily, previousDays.filter(hasData).count >= minimumDaily else { return nil }
        let recentMid = split.adding(days: length / 2)
        let previousMid = start.adding(days: length / 2)
        guard let recentAge = person.age(at: recentMid), let previousAge = person.age(at: previousMid),
              (0...90).contains(recentAge), (0...90).contains(previousAge) else { return nil }
        // Lokale Einheiten haben keine bekannte Geräteabdeckung für einen Zeitvergleich.
        let r = factors(days: recentDays, age: recentAge, sex: person.sex, strengthPerWeek: 0, hasStrengthRecord: false)
        let p = factors(days: previousDays, age: previousAge, sex: person.sex, strengthPerWeek: 0, hasStrengthRecord: false)
        let ids = Set(r.factors.map(\.id))
        guard ids == Set(p.factors.map(\.id)), !ids.isDisjoint(with: ["rhr", "sleep", "vo2"]) else { return nil }
        for id in ids {
            let minimum = id == "vo2" ? minimumVO2 : minimumDaily
            let recent = observations(for: id, in: recentDays)
            let previous = observations(for: id, in: previousDays)
            guard recent.count >= minimum, previous.count >= minimum,
                  sameMeasurementSource(for: id, recent: recent, previous: previous,
                                        allowExampleData: person.origin == .assumed) else { return nil }
        }
        return (Estimate(date: previousMid, bodyAge: combine(age: previousAge, sum: p.sum), age: previousAge),
                Estimate(date: recentMid, bodyAge: combine(age: recentAge, sum: r.sum), age: recentAge))
    }

    private static func observations(for factor: String, in days: [DayMetrics]) -> [DayMetrics] {
        switch factor {
        case "vo2": Array(days.suffix(90).filter { $0.vo2max != nil }.suffix(10))
        case "rhr": days.filter { $0.restingHR != nil }
        case "steps": days.filter { ($0.steps ?? 0) > 500 }
        case "sleep": days.filter { ($0.sleep?.asleep ?? 0) > 3 * 3600 }
        default: []
        }
    }

    private static func sameMeasurementSource(for factor: String, recent: [DayMetrics], previous: [DayMetrics],
                                              allowExampleData: Bool) -> Bool {
        let series: MetricSeries
        switch factor {
        case "vo2": series = .vo2max
        case "rhr": series = .restingHR
        case "steps": series = .steps
        case "sleep": series = .sleep
        default: return false
        }
        let measurements = (recent + previous).map { $0.origins?[series] ?? [] }
        if allowExampleData, measurements.allSatisfy(\.isEmpty) { return true }
        guard let origin = measurements.first?.first, origin.device != nil else { return false }
        return measurements.allSatisfy { $0 == [origin] }
    }

    private static func combine(age: Double, sum: Double) -> Double {
        let shift = min(15, max(-15, sum * overlapDamping))
        return age + shift
    }

    private static func hasData(_ d: DayMetrics) -> Bool {
        (d.steps ?? 0) > 500 || d.sleep != nil || d.restingHR != nil
    }

    // MARK: Faktoren

    private static func factors(days: [DayMetrics], age: Double, sex: BiologicalSex, strengthPerWeek: Double,
                                hasStrengthRecord: Bool = true) -> (factors: [Factor], missing: [String], sum: Double) {
        var result: [Factor] = []
        var missing: [String] = []

        // 1. VO₂max gegen den Median deiner Alters- und Geschlechtsgruppe.
        let vo2Days = days.suffix(90).filter { $0.vo2max != nil }
        let vo2Values = vo2Days.compactMap(\.vo2max).suffix(10)
        if let vo2 = mean(Array(vo2Values)), sex != .unknown, (20...79).contains(age) {
            let reference = vo2Reference(age: age, sex: sex)
            let deltaMET = (vo2 - reference) / 3.5
            let years = clamp(yearsPerLogHazard * log(0.87) * deltaMET, 6)
            result.append(Factor(
                id: "vo2", title: "VO₂max", systemImage: "lungs",
                valueText: "\(Format.number(vo2, decimals: 1)) ml/kg/min",
                referenceText: "Median deiner Alters- und Geschlechtsgruppe (US-Laufbandtests): \(Format.number(reference, decimals: 1))",
                value: vo2, displayRange: 15...75, referenceRange: reference...reference,
                coverage: "\(vo2Values.count) Messung\(vo2Values.count == 1 ? "" : "en")" + (vo2Days.last.map { ", zuletzt am \(Format.shortDate($0.date))" } ?? ""),
                years: years,
                explanation: "In Studien war je 1 MET (3,5 ml/kg/min) mehr Fitness mit etwa 13 % geringerem Sterberisiko verbunden. Annahmen von Health: lineare Umrechnung zwischen den Altersgruppen, Begrenzung auf ±6 Jahre. Die VO₂max der Uhr ist eine Schätzung und liegt oft anders als ein Labortest.",
                source: "Kodama et al., JAMA 2009 · Referenz: FRIEND-Register (Kaminsky et al., 2015)"))
        } else if !vo2Values.isEmpty && !(20...79).contains(age) {
            missing.append("VO₂max-Vergleich – die Referenzwerte gibt es nur für 20 bis 79 Jahre")
        } else if vo2Values.isEmpty {
            missing.append("VO₂max der letzten 90 Tage – entsteht bei Läufen oder zügigen Spaziergängen im Freien mit der Apple Watch")
        } else {
            missing.append("Geschlecht im Profil – nötig für den VO₂max-Vergleich")
        }

        // 2. Ruhepuls.
        let rhrValues = days.compactMap(\.restingHR)
        if rhrValues.count >= 7, let rhr = mean(rhrValues) {
            let years = clamp(yearsPerLogHazard * log(1.09) * (rhr - 65) / 10, 4)
            result.append(Factor(
                id: "rhr", title: "Ruhepuls", systemImage: "heart",
                valueText: "\(Format.number(rhr)) bpm im Mittel", referenceText: "Vergleichswert: 65 bpm (Annahme von Health)",
                value: rhr, displayRange: 35...105, referenceRange: 65...65,
                coverage: "\(rhrValues.count) von \(days.count) Tagen",
                years: years,
                explanation: "In großen Studien war je 10 Schläge pro Minute mehr Ruhepuls mit etwa 9 % höherem Sterberisiko verbunden. Annahmen von Health: 65 bpm als Vergleichswert und ein linearer Verlauf, begrenzt auf ±4 Jahre.",
                source: "Zhang et al., CMAJ 2016 · Referenz 65 bpm ist eine Annahme für Erwachsene"))
        } else {
            missing.append("Ruhepuls – mindestens 7 Tage")
        }

        // 3. Schritte (Tage unter 500 Schritten gelten als „Uhr nicht getragen“).
        let stepValues = days.compactMap(\.steps).filter { $0 > 500 }
        if stepValues.count >= 7, let steps = mean(stepValues) {
            let years = clamp(yearsPerLogHazard * (stepsLogHazard(steps) - stepsLogHazard(7000)), 4)
            result.append(Factor(
                id: "steps", title: "Schritte", systemImage: "figure.walk",
                valueText: "\(Format.number(steps)) pro Tag", referenceText: "Vergleichswert: 7.000 pro Tag (Annahme von Health)",
                value: steps, displayRange: 0...15_000, referenceRange: 7_000...7_000,
                coverage: "\(stepValues.count) von \(days.count) Tagen",
                years: years,
                explanation: "In Studien ging mehr Gehen mit geringerem Risiko einher, mit abflachendem Nutzen: unter 60 Jahren bei etwa 8.000 bis 10.000 Schritten. Annahmen von Health: gemittelte Kurve über alle Altersgruppen, Tage unter 500 Schritten gelten als „Uhr nicht getragen“, Begrenzung auf ±4 Jahre.",
                source: "Paluch et al., Lancet Public Health 2022 · Referenz 7.000 ist eine Annahme"))
        } else {
            missing.append("Schritte – mindestens 7 Tage")
        }

        // 4. Schlafdauer (Nächte unter 3 Stunden gelten als unvollständig gemessen).
        let sleepHours = days.compactMap { $0.sleep?.asleep }.filter { $0 > 3 * 3600 }.map { $0 / 3600 }
        if sleepHours.count >= 7, let hours = mean(sleepHours) {
            let logHazard: Double
            if hours < 7 { logHazard = log(1.12) * min(1, 7 - hours) }
            else if hours > 8 { logHazard = log(1.30) * min(1, hours - 8) }
            else { logHazard = 0 }
            result.append(Factor(
                id: "sleep", title: "Schlafdauer", systemImage: "moon",
                valueText: "\(Format.duration(hours * 3600)) im Mittel", referenceText: "Vergleichsbereich: 7–8 h (Annahme von Health)",
                value: hours, displayRange: 4...11, referenceRange: 7...8,
                coverage: "\(sleepHours.count) von \(days.count) Nächten",
                years: clamp(yearsPerLogHazard * logHazard, 4),
                explanation: "In Studien war kurzer Schlaf mit etwa 12 % und sehr langer Schlaf mit etwa 30 % höherem Risiko verbunden. Beim langen Schlaf kann eine Erkrankung die Ursache sein, nicht der Schlaf selbst. Annahme von Health: gleitender Übergang zwischen 6 und 7 h bzw. 8 und 9 h.",
                source: "Cappuccio et al., Sleep 2010"))
        } else {
            missing.append("Schlaf – mindestens 7 Nächte")
        }

        // 5. Krafttraining pro Woche (Forma-Trainings und Krafttrainings aus Google Health).
        let strengthLogHazard = log(0.86) * min(1, strengthPerWeek / 30)
        if !hasStrengthRecord {
            missing.append("Krafttraining – noch nichts aufgezeichnet (Training in dieser App oder in Google Health)")
        } else {
            result.append(Factor(
                id: "strength", title: "Krafttraining", systemImage: "dumbbell",
                valueText: "\(Format.number(strengthPerWeek)) min pro Woche", referenceText: "Vergleich: kein Krafttraining",
                value: strengthPerWeek, displayRange: 0...120, referenceRange: 0...0,
                coverage: "Trainings aus dieser App und aus Google Health",
                years: clamp(yearsPerLogHazard * strengthLogHazard, 4),
                explanation: "In Studien gingen 30 bis 60 Minuten Krafttraining pro Woche mit 10 bis 17 % geringerem Risiko einher. Annahmen von Health: 14 % ab 30 min/Woche. Health wertet deine erfassten Trainingsminuten aus.",
                source: "Momma et al., Br J Sports Med 2022"))
        }

        let sum = result.reduce(0) { $0 + $1.years }
        return (result, missing, sum)
    }

    /// Medianwerte der VO₂max (Laufband) nach Alter und Geschlecht, Mitte jedes Jahrzehnts.
    static func vo2Reference(age: Double, sex: BiologicalSex) -> Double {
        let mids: [Double] = [25, 35, 45, 55, 65, 75]
        let values: [Double] = sex == .female
            ? [37.6, 30.2, 26.7, 23.4, 20.0, 18.3]
            : [48.0, 42.4, 37.8, 32.6, 28.2, 24.4]
        return interpolate(age, xs: mids, ys: values)
    }

    /// Logarithmiertes relatives Risiko nach Schritten (Quartile aus Paluch 2022, linear verbunden).
    static func stepsLogHazard(_ steps: Double) -> Double {
        interpolate(steps, xs: [3553, 5801, 7842, 10901], ys: [0, log(0.60), log(0.55), log(0.47)])
    }

    private static func interpolate(_ x: Double, xs: [Double], ys: [Double]) -> Double {
        guard let first = xs.first, let last = xs.last else { return 0 }
        if x <= first { return ys[0] }
        if x >= last { return ys[ys.count - 1] }
        for i in 1..<xs.count where x <= xs[i] {
            let t = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
            return ys[i - 1] + t * (ys[i] - ys[i - 1])
        }
        return ys[ys.count - 1]
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func clamp(_ x: Double, _ limit: Double) -> Double { min(limit, max(-limit, x)) }

    /// Quellen für die Erklärseite.
    static let sources: [(title: String, url: String)] = [
        ("Kodama et al. (2009): Fitness und Sterblichkeit, JAMA", "https://pubmed.ncbi.nlm.nih.gov/19454641/"),
        ("Kaminsky et al. (2015): FRIEND-Referenzwerte VO₂max, Tabelle 2", "https://www.mayoclinicproceedings.org/article/S0025619615006424/pdf"),
        ("Zhang et al. (2016): Ruhepuls und Sterblichkeit, CMAJ", "https://pmc.ncbi.nlm.nih.gov/articles/PMC4754196/"),
        ("Paluch et al. (2022): Schritte und Sterblichkeit, Lancet Public Health", "https://doi.org/10.1016/S2468-2667(21)00302-9"),
        ("Cappuccio et al. (2010): Schlafdauer und Sterblichkeit, Sleep", "https://pmc.ncbi.nlm.nih.gov/articles/PMC2864873/"),
        ("Momma et al. (2022): Krafttraining und Sterblichkeit, BJSM", "https://pmc.ncbi.nlm.nih.gov/articles/PMC9209691/"),
        ("Gompertz-Modell der Sterblichkeit (Überblick)", "https://en.wikipedia.org/wiki/Gompertz%E2%80%93Makeham_law_of_mortality"),
        ("Gurven et al.: Unterschiede der Verdopplungszeit zwischen Bevölkerungen", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6121812/")
    ]

    /// Krafttraining pro Woche aus beiden Quellen. Überlappende Minuten zählen einmal.
    static func strengthMinutes(days: [DayMetrics], formaSessions: [(start: Date, minutes: Double)], now: Date = .now) -> StrengthMinutes {
        let calendar = Calendar.forma
        let imported = days.flatMap(\.workouts).filter(\.isStrength)
        let local = formaSessions.filter { $0.minutes.isFinite && (0...1440).contains($0.minutes) && $0.minutes > 0 }.map {
            WorkoutSummary(name: "Krafttraining", start: $0.start, duration: $0.minutes * 60, energy: nil, isStrength: true)
        }
        let workouts = imported + local
        func perWeek(from start: Date, until end: Date) -> (minutes: Double, hasRecord: Bool) {
            let numberOfDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            guard numberOfDays > 0 else { return (0, false) }
            let total = WorkoutSummary.totalDuration(workouts, from: start, until: end) / 60
            return (total / (Double(numberOfDays) / 7), total > 0)
        }
        let end = now.startOfDay
        let split = end.adding(days: -30)
        let long = days.first.map { perWeek(from: $0.date, until: end.adding(days: 1)) } ?? (minutes: 0, hasRecord: false)
        let recorded = workouts.filter { $0.start >= (days.first?.date ?? end) && $0.start <= now }
        let recent = perWeek(from: split, until: end)
        let previous = perWeek(from: end.adding(days: -60), until: split)
        return StrengthMinutes(perWeek: long.minutes, recentPerWeek: recent.minutes, previousPerWeek: previous.minutes,
                               hasRecord: long.hasRecord, recentHasRecord: recent.hasRecord, previousHasRecord: previous.hasRecord,
                               trainingWeeks: trainingWeeks(recorded, calendar: calendar))
    }

    private static func trainingWeeks(_ workouts: [WorkoutSummary], calendar: Calendar) -> Int {
        Set(workouts.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.start)?.start }).count
    }
}
