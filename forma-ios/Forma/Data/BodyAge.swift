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
        let years: Double
        let explanation: String
        let source: String
    }

    enum Confidence: Sendable {
        case low, medium, high
        var title: String {
            switch self {
            case .low: "Niedrig"
            case .medium: "Mittel"
            case .high: "Hoch"
            }
        }
    }

    struct Result: Sendable {
        let age: Double
        let bodyAge: Double
        /// Gleiche Rechnung nur mit den letzten 30 Tagen: zeigt, wohin du dich gerade bewegst.
        let recentBodyAge: Double?
        let factors: [Factor]
        let missing: [String]
        let daysWithData: Int
        let windowDays: Int
        let confidence: Confidence
        var difference: Double { bodyAge - age }
        var trend: Double? { recentBodyAge.map { $0 - bodyAge } }
    }

    enum Outcome: Sendable {
        case needsProfile
        case needsData(have: Int, need: Int)
        case ready(Result)
    }

    struct StrengthMinutes: Sendable {
        var perWeek: Double
        var recentPerWeek: Double
    }

    static let minimumDays = 21
    static let overlapDamping = 0.7
    /// Gompertz: Verdopplung des Sterberisikos etwa alle 8 Jahre.
    static let yearsPerLogHazard = 8 / log(2.0)

    static func evaluate(days: [DayMetrics], person: PersonInfo, strength: StrengthMinutes, now: Date = .now) -> Outcome {
        guard let age = person.age(at: now) else { return .needsProfile }
        let withData = days.filter(hasData)
        guard withData.count >= minimumDays else { return .needsData(have: withData.count, need: minimumDays) }

        let long = factors(days: days, age: age, sex: person.sex, strengthPerWeek: strength.perWeek)
        let recentDays = Array(days.suffix(30))
        let recent: Double? = recentDays.filter(hasData).count >= minimumDays
            ? factors(days: recentDays, age: age, sex: person.sex, strengthPerWeek: strength.recentPerWeek).sum
            : nil

        let bodyAge = combine(age: age, sum: long.sum)
        let confidence: Confidence
        let hasVO2 = long.factors.contains { $0.id == "vo2" }
        if withData.count >= 90 && long.factors.count >= 4 && hasVO2 { confidence = .high }
        else if withData.count >= 45 && long.factors.count >= 3 { confidence = .medium }
        else { confidence = .low }

        return .ready(Result(
            age: age, bodyAge: bodyAge,
            recentBodyAge: recent.map { combine(age: age, sum: $0) },
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

    private static func factors(days: [DayMetrics], age: Double, sex: BiologicalSex, strengthPerWeek: Double) -> (factors: [Factor], missing: [String], sum: Double) {
        var result: [Factor] = []
        var missing: [String] = []

        // 1. VO₂max gegen den Median deiner Alters- und Geschlechtsgruppe.
        let vo2Values = days.compactMap(\.vo2max).suffix(30)
        if let vo2 = mean(Array(vo2Values)), sex != .unknown {
            let reference = vo2Reference(age: age, sex: sex)
            let deltaMET = (vo2 - reference) / 3.5
            let years = clamp(yearsPerLogHazard * log(0.87) * deltaMET, 6)
            result.append(Factor(
                id: "vo2", title: "VO₂max", systemImage: "lungs",
                valueText: "\(Format.number(vo2, decimals: 1)) ml/kg/min",
                referenceText: "Mittel deiner Altersgruppe: \(Format.number(reference, decimals: 1))",
                years: years,
                explanation: "Ausdauer ist einer der stärksten Einzelfaktoren für ein langes Leben. Je 1 MET (3,5 ml/kg/min) mehr ist das Sterberisiko im Mittel etwa 13 % niedriger. Die Werte der Uhr sind Schätzungen, Labormessungen liegen oft anders.",
                source: "Kodama et al., JAMA 2009 · Referenz: FRIEND-Register (Kaminsky et al., 2015)"))
        } else if vo2Values.isEmpty {
            missing.append("VO₂max – entsteht bei Läufen oder zügigen Spaziergängen im Freien mit der Apple Watch")
        } else {
            missing.append("Geschlecht im Profil – nötig für den VO₂max-Vergleich")
        }

        // 2. Ruhepuls.
        let rhrValues = days.compactMap(\.restingHR)
        if rhrValues.count >= 7, let rhr = mean(rhrValues) {
            let years = clamp(yearsPerLogHazard * log(1.09) * (rhr - 65) / 10, 4)
            result.append(Factor(
                id: "rhr", title: "Ruhepuls", systemImage: "heart",
                valueText: "\(Format.number(rhr)) bpm", referenceText: "Referenz: 65 bpm",
                years: years,
                explanation: "Je 10 Schläge pro Minute mehr Ruhepuls ist das Sterberisiko in großen Studien etwa 9 % höher. Ein niedriger Ruhepuls spricht meist für ein gut trainiertes Herz.",
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
                valueText: "\(Format.number(steps)) pro Tag", referenceText: "Referenz: 7.000 pro Tag",
                years: years,
                explanation: "Mehr Schritte senken das Risiko deutlich – bis zu einer Grenze: bei unter 60-Jährigen etwa 8.000 bis 10.000 Schritte, darüber bringt es kaum noch mehr.",
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
                valueText: "\(Format.duration(hours * 3600)) im Mittel", referenceText: "Bereich: 7–8 h",
                years: clamp(yearsPerLogHazard * logHazard, 4),
                explanation: "Kurzer Schlaf (6 h oder weniger) geht mit etwa 12 % höherem Risiko einher, sehr langer Schlaf mit etwa 30 % – dort ist die Ursache oft eine Krankheit, nicht der Schlaf selbst.",
                source: "Cappuccio et al., Sleep 2010"))
        } else {
            missing.append("Schlaf – mindestens 7 Nächte")
        }

        // 5. Krafttraining pro Woche (Forma-Trainings und Krafttrainings aus Apple Health).
        let strengthLogHazard = log(0.86) * min(1, strengthPerWeek / 30)
        result.append(Factor(
            id: "strength", title: "Krafttraining", systemImage: "dumbbell",
            valueText: "\(Format.number(strengthPerWeek)) min pro Woche", referenceText: "Bereich: 30–60 min",
            years: clamp(yearsPerLogHazard * strengthLogHazard, 4),
            explanation: "Schon 30 bis 60 Minuten Krafttraining pro Woche gehen mit 10 bis 17 % geringerem Risiko einher. Ob deutlich mehr noch mehr bringt, ist nicht geklärt – deshalb zählen wir über 30 Minuten nicht weiter hoch.",
            source: "Momma et al., Br J Sports Med 2022"))

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
        ("Kaminsky et al. (2015): FRIEND-Referenzwerte VO₂max", "https://pubmed.ncbi.nlm.nih.gov/?term=Kaminsky+2015+FRIEND+treadmill+reference+standards"),
        ("Zhang et al. (2016): Ruhepuls und Sterblichkeit, CMAJ", "https://pubmed.ncbi.nlm.nih.gov/26598376/"),
        ("Paluch et al. (2022): Schritte und Sterblichkeit, Lancet Public Health", "https://doi.org/10.1016/S2468-2667(21)00302-9"),
        ("Cappuccio et al. (2010): Schlafdauer und Sterblichkeit, Sleep", "https://pubmed.ncbi.nlm.nih.gov/20469800/"),
        ("Momma et al. (2022): Krafttraining und Sterblichkeit, BJSM", "https://doi.org/10.1136/bjsports-2021-105061"),
        ("Gompertz-Gesetz der Sterblichkeit", "https://en.wikipedia.org/wiki/Gompertz%E2%80%93Makeham_law_of_mortality")
    ]

    /// Krafttraining pro Woche: je Tag das Maximum aus Forma-Trainings und Apple-Health-Krafttrainings.
    static func strengthMinutes(days: [DayMetrics], formaSessions: [(start: Date, minutes: Double)]) -> StrengthMinutes {
        func perWeek(_ window: [DayMetrics]) -> Double {
            guard !window.isEmpty else { return 0 }
            var total = 0.0
            for day in window {
                let fromHealth = day.workouts.filter(\.isStrength).reduce(0) { $0 + $1.duration / 60 }
                let fromForma = formaSessions.filter { $0.start.startOfDay == day.date }.reduce(0) { $0 + $1.minutes }
                total += max(fromHealth, fromForma)
            }
            return total / (Double(window.count) / 7)
        }
        return StrengthMinutes(perWeek: perWeek(days), recentPerWeek: perWeek(Array(days.suffix(30))))
    }
}
