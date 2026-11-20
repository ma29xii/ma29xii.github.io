import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, coach }
    var id = UUID()
    var role: Role
    var text: String
    /// Nur lokal beantwortet. Bleibt auch später aus dem externen Verlauf (Codex R-02-15/A-22).
    var localOnly: Bool = false
    var conversationID = CoachProviders.conversationID
}

/// Lokale Auswertung für den Coach.
enum CoachEngine {
    struct Context: Sendable {
        var scores: DayScores
        var today: DayMetrics
        var hrvDelta: Double?
        var rhrDelta: Double?
        var plannedRoutine: String?
        var trainedToday: Bool
        var isSample: Bool
        var hour: Int
        /// Gibt es heute eine Messgrundlage? Ohne sie keine Empfehlungen aus Ersatzwerten (Codex R-02-03).
        var recoveryAvailable: Bool = true
        var strainAvailable: Bool = true
        var history: [DayMetrics] = []
        /// Persönlicher Kontext (Profil, Ziele, gemerkte Fakten). Der lokale Coach nutzt dieselben Werte wie der Online-Coach.
        var personal = CoachMemory.Personal.empty

        var sleepDuration: TimeInterval? { CoachEngine.measuredSleep(in: today) }
        var sleepScore: Int? { sleepDuration != nil && scores.sleep > 0 ? scores.sleep : nil }

        var sleepDebt: TimeInterval? {
            CoachEngine.measuredSleepDebt(scores, history: history)
        }

        var sleepNeed: TimeInterval? {
            CoachEngine.measuredSleepNeed(scores, strainAvailable: strainAvailable, history: history)
        }

        func sleepWindow(sleepNeed: TimeInterval, now: Date = .now) -> SleepPlanner.Window? {
            let plan = SleepPlanner.load(in: FoodSettings.store(isSample: isSample))
            return plan.nextWindow(after: now, sleepNeed: sleepNeed)
        }

        var stepGoalToday: Int? {
            StepGoal.target(on: today.date, history: history, recovery: recoveryAvailable ? scores.recovery : nil,
                            sleepScore: sleepScore, sleepDebt: sleepDebt,
                            strainTarget: recoveryAvailable ? scores.target : nil)
        }

        var energy: Int? {
            recoveryAvailable && strainAvailable && sleepScore != nil ? scores.energy : nil
        }

        var stress: Double? {
            guard strainAvailable, today.hrv?.isFinite == true, today.restingHR?.isFinite == true,
                  hrvDelta?.isFinite == true, rhrDelta?.isFinite == true,
                  (0...3).contains(scores.stress) else { return nil }
            return scores.stress
        }
    }

    private static func measuredSleep(in day: DayMetrics) -> TimeInterval? {
        guard let duration = day.sleep?.asleep, duration > 0, duration <= 24 * 3600 else { return nil }
        return duration
    }

    private static func measuredSleepDebt(_ scores: DayScores, history: [DayMetrics]) -> TimeInterval? {
        guard ScoreEngine.hasSleepHistory(history),
              scores.sleepDebt >= 0, scores.sleepDebt <= 7 * 24 * 3600 else { return nil }
        return scores.sleepDebt
    }

    static func measuredSleepNeed(_ scores: DayScores, strainAvailable: Bool, history: [DayMetrics]) -> TimeInterval? {
        guard strainAvailable, measuredSleepDebt(scores, history: history) != nil,
              scores.sleepNeed > 0, scores.sleepNeed < 14 * 3600 else { return nil }
        return scores.sleepNeed
    }

    /// Ein Satz für die Startseite. Morgens Ausblick, nach dem Training Rückblick, abends Schlaf.
    static func dailyLine(_ c: Context) -> String {
        let s = c.scores
        if c.trainedToday && !c.strainAvailable {
            return "Gut trainiert. Für eine Belastungszahl fehlen heute Messwerte aus Google Health."
        }
        if c.trainedToday && !c.recoveryAvailable {
            return "Training abgeschlossen. Deine Belastung liegt bei \(s.strain). Für ein Ziel fehlen heute vergleichbare Herzwerte."
        }
        if !c.recoveryAvailable && !c.trainedToday && c.hour < 20 {
            return "Für heute fehlen Herzwerte mit Vergleich. Ich gebe dir erst eine Empfehlung, wenn Messwerte da sind – trag deine Uhr auch nachts."
        }
        if c.trainedToday {
            let sleepLine = c.sleepNeed.flatMap { c.sleepWindow(sleepNeed: $0) }
                .map { "Geh gegen \(Format.clock($0.bed)) ins Bett." } ?? "Schlafbedarf: keine Messung."
            // Gleiche Logik wie der Zielbogen am Belastungsring (Codex R-01-05).
            if s.strain < s.target.lowerBound {
                return "Gut trainiert. Bis zur Untergrenze deines Zielbereichs fehlen noch \(s.target.lowerBound - s.strain) Punkte – etwas lockere Bewegung reicht."
            }
            if s.strain <= s.target.upperBound {
                return "Gut trainiert – du bist in deinem Zielbereich (\(s.target.lowerBound)–\(s.target.upperBound)). \(sleepLine)"
            }
            return "Heute warst du über deinem Zielbereich. Mach morgen eher locker. \(sleepLine)"
        }
        if c.hour >= 20 {
            guard let need = c.sleepNeed, let window = c.sleepWindow(sleepNeed: need) else {
                return "Schlafbedarf: keine Messung."
            }
            return "Für morgen zählt jetzt der Schlaf: ins Bett gegen \(Format.clock(window.bed)), dann holst du \(Format.duration(need)) Schlaf."
        }
        let hrvPart: String
        if let d = c.hrvDelta, abs(d) >= 2 {
            hrvPart = d > 0 ? "Deine HRV liegt \(Int(d.rounded())) ms über deinem Normalwert" : "Deine HRV liegt \(Int((-d).rounded())) ms unter deinem Normalwert"
        } else if c.hrvDelta != nil {
            hrvPart = "Deine HRV liegt im Normalbereich"
        } else {
            hrvPart = "Für heute fehlt ein HRV-Wert"
        }
        let plan = c.plannedRoutine.map { " \($0) passt" } ?? ""
        switch s.recovery {
        case 67...:
            return "\(hrvPart). Du bist gut erholt –\(plan.isEmpty ? " ein intensiver Tag passt" : plan + " wie geplant")."
        case 34..<67:
            return "\(hrvPart). Mittlere Erholung – trainier normal, aber ohne neue Bestwerte zu erzwingen."
        default:
            return "\(hrvPart). Dein Körper braucht heute Ruhe – lieber locker bewegen und früh schlafen."
        }
    }

    /// Vorschlag zur Trainingsanpassung (Maxi muss bestätigen).
    static func suggestion(_ c: Context) -> TrainingAdjustment? {
        // Nur mit vollständigen, echten Daten von heute vorschlagen (Codex R-01-05, R-02-03/A-05).
        guard c.plannedRoutine != nil, !c.trainedToday, !c.isSample, c.recoveryAvailable,
              c.today.hrv != nil, c.today.sleep != nil else { return nil }
        if c.scores.recovery < 40 { return .minusOneSet }
        if c.scores.recovery >= 80 { return .plusWeight }
        return nil
    }

    static func suggestionReason(_ adjustment: TrainingAdjustment, _ c: Context) -> String {
        switch adjustment {
        case .minusOneSet: "Erholung \(c.scores.recovery): weniger Volumen schützt die nächsten Tage. Deine gespeicherte Routine bleibt unverändert."
        case .plusWeight: "Erholung \(c.scores.recovery): ein guter Tag für etwas mehr Gewicht. Deine gespeicherte Routine bleibt unverändert."
        }
    }

    /// Lokale Antworten auf typische Fragen.
    static func localAnswer(to question: String, _ c: Context) -> String {
        let q = question.lowercased()
        let s = c.scores
        let selected = selectedFields(for: question)
        let measurements: [ExternalField] = [.energy, .stress, .sleepNeed, .sleepDebt, .stepGoal]
        let requested = measurements.filter { selected.contains($0) }
        if requested == [.sleepNeed] { return sleepAdvice(c) }
        if !requested.isEmpty {
            return requested.map { field in
                let value = field.value(in: c)
                if field == .stepGoal {
                    return value.map { "Heute passen etwa \($0)." }
                        ?? "Für ein Schrittziel brauche ich Messwerte von mindestens sieben Tagen."
                }
                return "\(field.rawValue): \(value ?? "keine Messung")."
            }.joined(separator: " ")
        }
        if q.contains("hrv") || q.contains("erhol") {
            guard c.recoveryAvailable else {
                return "Für heute fehlen HRV oder Ruhepuls mit Vergleichswerten. Sobald Messwerte aus Google Health da sind, kann ich deine Erholung erklären."
            }
            var parts: [String] = []
            if let d = c.hrvDelta { parts.append("HRV \(d >= 0 ? "+" : "")\(Int(d.rounded())) ms zum Normalwert") }
            if let d = c.rhrDelta { parts.append("Ruhepuls \(d >= 0 ? "+" : "")\(Int(d.rounded())) bpm") }
            if let sleepScore = c.sleepScore { parts.append("Schlafwert \(sleepScore)") }
            return "Deine Erholung liegt bei \(s.recovery). Grundlage: \(parts.joined(separator: ", ")). HRV zählt am stärksten, danach Ruhepuls und Schlaf."
        }
        if q.contains("bett") || q.contains("schlaf") || q.contains("nacht") {
            if selected.contains(.sleepDuration), !selected.contains(.sleepNeed) {
                return c.sleepDuration.map { "Du hast \(Format.duration($0)) geschlafen." } ?? "Schlafdauer: keine Messung."
            }
            return sleepAdvice(c)
        }
        if q.contains("train") || q.contains("push") || q.contains("pull") || q.contains("bein") {
            let plan = c.plannedRoutine ?? "dein nächstes Training"
            guard c.recoveryAvailable else {
                return "Für heute fehlen Herzwerte, deshalb gebe ich keine Belastungsempfehlung. Trainier nach Gefühl und hör auf deinen Körper."
            }
            switch s.recovery {
            case 67...: return "\(plan) wie geplant. Dein Belastungsziel liegt bei \(s.target.lowerBound) bis \(s.target.upperBound)."
            case 34..<67: return "\(plan) ja, aber bleib bei 2 Wiederholungen in Reserve. Ziel: \(s.target.lowerBound) bis \(s.target.upperBound)."
            default: return "Heute lieber leicht: \(plan) mit einem Satz weniger pro Übung oder nur ein Spaziergang. Ich kann dir das als Anpassung vorschlagen."
            }
        }
        if !c.isSample {
            let words = Set(q.split(whereSeparator: { !$0.isLetter }).map(String.init))
            if !words.isDisjoint(with: ["essen", "mahlzeit", "mahlzeiten", "omad"])
                || ["kalorie", "ernähr", "abnehm"].contains(where: { q.contains($0) }) {
                var answer = c.personal.foodLine
                if !c.personal.facts.isEmpty { answer += " Ich beachte: " + c.personal.facts.joined(separator: "; ") + "." }
                return answer
            }
            if q.contains("über mich") || q.contains("merkst du dir") || q.contains("weißt du") {
                return c.personal.facts.isEmpty
                    ? "Ich habe mir noch nichts gemerkt. Schreib „Merk dir: …“, dann behalte ich es."
                    : "Das habe ich mir gemerkt: " + c.personal.facts.joined(separator: "; ") + "."
            }
        }
        if q.contains("belast") || q.contains("ziel") {
            let current = c.strainAvailable ? "Belastung bisher \(s.strain)." : "Belastung: keine Messung."
            let target = c.recoveryAvailable
                ? "Dein Zielbereich heute ist \(s.target.lowerBound) bis \(s.target.upperBound)."
                : "Für einen Zielbereich fehlen vergleichbare Herzwerte."
            return "\(current) \(target)"
        }
        return "Ich habe dazu noch keine passende Auswertung. Frag mich nach Erholung, Schlaf, Training, Belastung oder deinem Schrittziel."
    }

    private static func sleepAdvice(_ c: Context) -> String {
        guard let need = c.sleepNeed else {
            return c.sleepDuration.map { "Du hast \(Format.duration($0)) geschlafen. Für deinen Schlafbedarf fehlen Vergleichsdaten." }
                ?? "Schlafbedarf: keine Messung."
        }
        let summary = "Geschätzter Bedarf heute Nacht: \(Format.duration(need)) (inklusive Schlafschuld)."
        guard let window = c.sleepWindow(sleepNeed: need) else { return summary }
        return "\(summary) Bei Wecker \(Format.clock(window.wake)) geh gegen \(Format.clock(window.bed)) ins Bett. Die Weckzeit änderst du im Schlafplan."
    }

    /// Vollständiger lokaler Entwurf für bestehende Aufrufer. CoachProviders filtert vor dem Versand.
    static func contextSummary(_ c: Context) -> String {
        fields(in: c, selecting: Set(ExternalField.allCases)).map { $0.line }.joined(separator: "\n")
    }

    static func contextSummary(_ c: Context, for question: String) -> String {
        fields(in: c, selecting: selectedFields(for: question)).map { $0.line }.joined(separator: "\n")
    }

    /// Die Feldnamen für den Dialog, einschließlich übertragener Hinweise auf fehlende Messungen.
    static func transmittedFields(for question: String, _ c: Context) -> [String] {
        fields(in: c, selecting: selectedFields(for: question)).map { $0.name }
    }

    /// Dieselbe Positivliste gilt auch für Aufrufer, die noch den lokalen Entwurf übergeben.
    static func filteredContextSummary(_ summary: String, for question: String) -> String {
        let allowed = selectedFields(for: question)
        return summary.split(whereSeparator: \.isNewline).filter { line in
            guard let separator = line.firstIndex(of: ":"),
                  let field = ExternalField(rawValue: String(line[..<separator])) else { return false }
            return allowed.contains(field)
        }.joined(separator: "\n")
    }

    private enum ExternalField: String, CaseIterable {
        case recovery = "Erholung"
        case sleep = "Schlafwert"
        case sleepDuration = "Schlafdauer"
        case strain = "Belastung"
        case target = "Belastungsziel"
        case energy = "Energie"
        case stress = "Stress"
        case sleepNeed = "Schlafbedarf"
        case sleepDebt = "Schlafschuld"
        case stepGoal = "Schrittziel"
        case hrv = "HRV"
        case hrvDelta = "HRV-Abweichung"
        case restingHR = "Ruhepuls"
        case routine = "Geplantes Training"

        func value(in c: Context) -> String? {
            let s = c.scores
            switch self {
            case .recovery: return c.recoveryAvailable ? "\(s.recovery)/100" : nil
            case .sleep: return c.sleepScore.map { "\($0)/100" }
            case .sleepDuration: return c.sleepDuration.map(Format.duration)
            case .strain: return c.strainAvailable ? "\(s.strain)/100" : nil
            case .target: return c.recoveryAvailable ? "\(s.target.lowerBound)–\(s.target.upperBound)" : nil
            case .energy: return c.energy.map { "\($0)/100" }
            case .stress: return c.stress.map { "\(Format.number($0, decimals: 1))/3 (geschätzt)" }
            case .sleepNeed: return c.sleepNeed.map(Format.duration)
            case .sleepDebt: return c.sleepDebt.map(Format.duration)
            case .stepGoal: return c.stepGoalToday.map { "\(Format.number(Double($0))) Schritte" }
            case .hrv: return c.today.hrv.flatMap { $0.isFinite ? "\(Format.number($0)) ms" : nil }
            case .hrvDelta:
                return c.hrvDelta.flatMap { $0.isFinite ? "\($0 >= 0 ? "+" : "")\(Format.number($0)) ms zum Normalwert" : nil }
            case .restingHR: return c.today.restingHR.flatMap { $0.isFinite ? "\(Format.number($0)) bpm" : nil }
            case .routine:
                guard let name = c.plannedRoutine else { return nil }
                // Der Routinenname muss in einer Zeile bleiben, auch bei frei eingegebenen Namen.
                return String(decoding: name.utf8.prefix(800), as: UTF8.self)
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
        }
    }

    private static func fields(in c: Context, selecting selected: Set<ExternalField>) -> [(name: String, line: String)] {
        guard !c.isSample else { return [] }
        return ExternalField.allCases.filter { selected.contains($0) }.compactMap { field in
            let value = field.value(in: c)
            if field == .routine && (value == nil || value == "") { return nil }
            return (field.rawValue, "\(field.rawValue): \(value ?? "keine Messung")")
        }
    }

    private static func selectedFields(for question: String) -> Set<ExternalField> {
        let words = Set(CoachProviders.outgoingMessageText(question).lowercased().split(whereSeparator: { !$0.isLetter }))
        func has(_ options: String...) -> Bool { options.contains { words.contains(Substring($0)) } }

        var fields: Set<ExternalField> = []
        if has("erholung", "erholt", "recovery") {
            fields.formUnion([.recovery, .hrv, .hrvDelta, .restingHR, .sleep])
        }
        if has("hrv", "herzfrequenzvariabilität") {
            fields.insert(.hrv)
            if has("normal", "normalwert", "vergleich", "abweichung", "höher", "niedriger") { fields.insert(.hrvDelta) }
        }
        if has("ruhepuls", "ruheherzfrequenz") { fields.insert(.restingHR) }
        let asksForNeed = has("schlafbedarf", "bett", "bettzeit", "schlafenszeit", "schlafen") ||
            (has("schlaf", "sleep") && has("brauche", "bedarf", "braucht", "empfohlen"))
        let asksForDuration = has("schlafdauer", "geschlafen", "schlafzeit")
        if has("schlaf", "sleep", "nacht"), !asksForNeed, !asksForDuration { fields.formUnion([.sleep, .sleepDuration]) }
        if has("schlafwert", "schlafscore", "schlafqualität") { fields.insert(.sleep) }
        if asksForDuration { fields.insert(.sleepDuration) }
        if asksForNeed { fields.insert(.sleepNeed) }
        if has("schlafschuld", "schlafdefizit") { fields.insert(.sleepDebt) }
        if has("schrittziel") || (has("schritte", "schritten") &&
            has("soll", "sollte", "sollten", "ziel", "passen", "empfiehlst", "empfohlen", "sinnvoll")) {
            fields.insert(.stepGoal)
        }
        if has("trainieren", "training", "trainingsplan", "workout", "push", "pull", "beintraining") {
            fields.formUnion([.recovery, .strain, .target, .routine])
        }
        if has("belastung", "strain") {
            fields.insert(.strain)
            if has("gut", "soll", "ziel", "zielbereich", "empfohlen") { fields.insert(.target) }
        }
        if has("belastungsziel", "belastungsbereich") { fields.insert(.target) }
        if has("energie", "energy", "energielevel") { fields.insert(.energy) }
        if has("stress", "stresswert", "stresslevel") { fields.insert(.stress) }
        return fields
    }
}

/// Kompatibilität für den bestehenden Coach-Dialog, dessen Einwilligung allein Anthropic umfasst.
enum ClaudeClient {
    static let model = CoachProviders.AnthropicModel.sonnet.rawValue

    static func reply(apiKey: String, context: String, history: [ChatMessage]) async throws -> String {
        try await CoachProviders.reply(
            context: context, history: history, anthropicKey: apiKey, openAIKey: nil,
            maySend: { UserDefaults.standard.bool(forKey: "forma.claudeConsent") }
        )
    }
}
