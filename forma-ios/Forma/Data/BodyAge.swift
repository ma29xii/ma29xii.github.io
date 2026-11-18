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
    enum Origin: Sendable { case manual, health, assumed, missing }
    var birthDate: Date?
    var sex: BiologicalSex
    var origin: Origin

    func age(at date: Date = .now) -> Double? {
        guard let birthDate else { return nil }
        return date.timeIntervalSince(birthDate) / (365.2425 * 86_400)
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
        var difference: Double { bodyAge - age }
        var trend: Double? {
            guard let recent, let previous else { return nil }
            return recent.bodyAge - previous.bodyAge
        }
        var pace: Double? { BodyAge.agingPace(previous: previous, recent: recent) }
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
    }

    static let minimumDays = 21
    static let overlapDamping = 0.7
    /// Gompertz: Verdopplung des Sterberisikos etwa alle 8 Jahre.
    static let yearsPerLogHazard = 8 / log(2.0)

    static func evaluate(days: [DayMetrics], person: PersonInfo, strength: StrengthMinutes, now: Date = .now) -> Outcome {
        guard let age = person.age(at: now) else { return .needsProfile }
        let withData = days.filter(hasData)
        guard withData.count >= minimumDays else { return .needsData(have: withData.count, need: minimumDays) }
        guard (18...90).contains(age) else {
            return .insufficient("Health Age ist für 18 bis 90 Jahre verfügbar.")
        }

        let long = factors(days: days, age: age, sex: person.sex, strengthPerWeek: strength.perWeek, hasStrengthRecord: strength.hasRecord)
        guard long.factors.contains(where: { ["rhr", "sleep", "vo2"].contains($0.id) }) else {
            return .insufficient("Für Health Age fehlen Ruhepuls, Schlaf oder VO₂max.")
        }
        // Vergleich nur zwischen gleich langen, nicht überlappenden Fenstern mit denselben Faktoren (Codex R-01-09).
        let end = now.startOfDay
        let split = end.adding(days: -30)
        let start = end.adding(days: -60)
        let recentDays = days.filter { $0.date >= split && $0.date < end }
        let previousDays = days.filter { $0.date >= start && $0.date < split }
        var recent: Estimate?, previous: Estimate?
        if recentDays.filter(hasData).count >= minimumDays, previousDays.filter(hasData).count >= minimumDays {
            let recentMid = split.adding(days: 15)
            let previousMid = start.adding(days: 15)
            if let recentAge = person.age(at: recentMid), let previousAge = person.age(at: previousMid),
               (18...90).contains(recentAge), (18...90).contains(previousAge) {
                let r = factors(days: recentDays, age: recentAge, sex: person.sex, strengthPerWeek: strength.recentPerWeek,
                                hasStrengthRecord: strength.recentHasRecord ?? strength.hasRecord)
                let p = factors(days: previousDays, age: previousAge, sex: person.sex, strengthPerWeek: strength.previousPerWeek,
                                hasStrengthRecord: strength.previousHasRecord ?? strength.hasRecord)
                if Set(r.factors.map(\.id)) == Set(p.factors.map(\.id)),
                   r.factors.contains(where: { ["rhr", "sleep", "vo2"].contains($0.id) }) {
                    recent = Estimate(date: recentMid, bodyAge: combine(age: recentAge, sum: r.sum), age: recentAge)
                    previous = Estimate(date: previousMid, bodyAge: combine(age: previousAge, sum: p.sum), age: previousAge)
                }
            }
        }

        let bodyAge = combine(age: age, sum: long.sum)
        let confidence: Confidence
        let vo2Count = days.suffix(90).compactMap(\.vo2max).count
        if withData.count >= 120 && long.factors.count == 5 && vo2Count >= 3 { confidence = .high }
        else if withData.count >= 45 && long.factors.count >= 4 { confidence = .medium }
        else { confidence = .low }

        return .ready(Result(
            age: age, bodyAge: bodyAge,
            recent: recent,
            previous: previous,
            factors: long.factors.sorted { abs($0.years) > abs($1.years) },
            missing: long.missing,
            daysWithData: withData.count, windowDays: days.count,
            confidence: confidence))
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

        // 5. Krafttraining pro Woche (Forma-Trainings und Krafttrainings aus Apple Health).
        let strengthLogHazard = log(0.86) * min(1, strengthPerWeek / 30)
        if !hasStrengthRecord {
            missing.append("Krafttraining – noch nichts aufgezeichnet (Training in dieser App oder Krafttraining in Apple Health)")
        } else {
            result.append(Factor(
                id: "strength", title: "Krafttraining", systemImage: "dumbbell",
                valueText: "\(Format.number(strengthPerWeek)) min pro Woche", referenceText: "Vergleich: kein Krafttraining",
                value: strengthPerWeek, displayRange: 0...120, referenceRange: 0...0,
                coverage: "Trainings aus dieser App und Krafttrainings aus Apple Health",
                years: clamp(yearsPerLogHazard * strengthLogHazard, 4),
                explanation: "In Studien gingen 30 bis 60 Minuten Krafttraining pro Woche mit 10 bis 17 % geringerem Risiko einher. Ob mehr noch mehr bringt, ist nicht geklärt. Annahmen von Health: 14 % ab 30 min/Woche, darüber kein weiterer Bonus. Nicht aufgezeichnetes Training zählt als 0.",
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

    /// Krafttraining pro Woche: Forma-Trainings plus Krafttrainings aus Apple Health,
    /// die sich zeitlich nicht mit einem Forma-Training überschneiden (keine Doppelzählung, Codex R-01-08).
    static func strengthMinutes(days: [DayMetrics], formaSessions: [(start: Date, minutes: Double)], now: Date = .now) -> StrengthMinutes {
        func perWeek(from start: Date, until end: Date) -> (minutes: Double, hasRecord: Bool) {
            let numberOfDays = Calendar.forma.dateComponents([.day], from: start, to: end).day ?? 0
            guard numberOfDays > 0 else { return (0, false) }
            let window = days.filter { $0.date >= start && $0.date < end }
            var total = formaSessions.filter { $0.start >= start && $0.start < end && $0.minutes.isFinite }
                .reduce(0) { $0 + max(0, $1.minutes) }
            for day in window {
                for w in day.workouts where w.isStrength {
                    let wEnd = w.start.addingTimeInterval(w.duration)
                    let overlaps = formaSessions.contains { s in
                        let sEnd = s.start.addingTimeInterval(s.minutes * 60)
                        return s.start < wEnd && w.start < sEnd
                    }
                    if !overlaps { total += w.duration / 60 }
                }
            }
            return (total / (Double(numberOfDays) / 7), total > 0)
        }
        let end = now.startOfDay
        let split = end.adding(days: -30)
        let long = days.first.map { perWeek(from: $0.date, until: end.adding(days: 1)) } ?? (minutes: 0, hasRecord: false)
        let recent = perWeek(from: split, until: end)
        let previous = perWeek(from: end.adding(days: -60), until: split)
        return StrengthMinutes(perWeek: long.minutes, recentPerWeek: recent.minutes, previousPerWeek: previous.minutes,
                               hasRecord: long.hasRecord, recentHasRecord: recent.hasRecord, previousHasRecord: previous.hasRecord)
    }
}
