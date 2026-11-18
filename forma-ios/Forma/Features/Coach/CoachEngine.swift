import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, coach }
    var id = UUID()
    var role: Role
    var text: String
}

/// Lokaler Coach: knapp, freundlich, du-Form. Optional mit Claude, wenn ein API-Schlüssel hinterlegt ist.
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
    }

    /// Ein Satz für die Startseite. Morgens Ausblick, nach dem Training Rückblick, abends Schlaf.
    static func dailyLine(_ c: Context) -> String {
        let s = c.scores
        if c.trainedToday {
            let remaining = s.target.upperBound - s.strain
            if remaining > 0 { return "Gut trainiert. Bis zum Zielbereich fehlen noch \(remaining) Punkte – ein lockerer Spaziergang reicht." }
            return "Gut trainiert. Dein Ziel für heute ist erreicht, jetzt zählt die Erholung: ins Bett gegen \(bedtime(s))."
        }
        if c.hour >= 20 {
            return "Für morgen zählt jetzt der Schlaf: ins Bett gegen \(bedtime(s)), dann holst du \(Format.duration(s.sleepNeed)) Schlaf."
        }
        let hrvPart: String
        if let d = c.hrvDelta, abs(d) >= 2 {
            hrvPart = d > 0 ? "Deine HRV liegt \(Int(d.rounded())) ms über deinem Normalwert" : "Deine HRV liegt \(Int((-d).rounded())) ms unter deinem Normalwert"
        } else {
            hrvPart = "Deine HRV liegt im Normalbereich"
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

    static func bedtime(_ s: DayScores, wake: DateComponents = DateComponents(hour: 6, minute: 55)) -> String {
        let cal = Calendar.forma
        let tomorrow = Date.now.startOfDay.adding(days: 1)
        let wakeDate = cal.date(bySettingHour: wake.hour ?? 7, minute: wake.minute ?? 0, second: 0, of: tomorrow) ?? tomorrow
        return Format.clock(wakeDate.addingTimeInterval(-s.sleepNeed - 10 * 60))
    }

    /// Vorschlag zur Trainingsanpassung (Maxi muss bestätigen).
    static func suggestion(_ c: Context) -> TrainingAdjustment? {
        guard c.plannedRoutine != nil, !c.trainedToday else { return nil }
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
        if q.contains("hrv") || q.contains("erhol") {
            var parts: [String] = []
            if let d = c.hrvDelta { parts.append("HRV \(d >= 0 ? "+" : "")\(Int(d.rounded())) ms zum Normalwert") }
            if let d = c.rhrDelta { parts.append("Ruhepuls \(d >= 0 ? "+" : "")\(Int(d.rounded())) bpm") }
            parts.append("Schlafwert \(s.sleep)")
            return "Deine Erholung liegt bei \(s.recovery). Grundlage: \(parts.joined(separator: ", ")). HRV zählt am stärksten, danach Ruhepuls und Schlaf."
        }
        if q.contains("bett") || q.contains("schlaf") {
            return "Geh gegen \(bedtime(s)) ins Bett. Dein Bedarf heute Nacht: \(Format.duration(s.sleepNeed)), inklusive \(Format.duration(s.sleepDebt)) Schlafschuld, die du nach und nach abbaust."
        }
        if q.contains("train") || q.contains("heute") || q.contains("push") || q.contains("pull") || q.contains("bein") {
            let plan = c.plannedRoutine ?? "dein nächstes Training"
            switch s.recovery {
            case 67...: return "\(plan) wie geplant. Dein Belastungsziel liegt bei \(s.target.lowerBound) bis \(s.target.upperBound)."
            case 34..<67: return "\(plan) ja, aber bleib bei 2 Wiederholungen in Reserve. Ziel: \(s.target.lowerBound) bis \(s.target.upperBound)."
            default: return "Heute lieber leicht: \(plan) mit einem Satz weniger pro Übung oder nur ein Spaziergang. Ich kann dir das als Anpassung vorschlagen."
            }
        }
        if q.contains("belast") || q.contains("ziel") {
            return "Belastung bisher \(s.strain), dein Zielbereich heute ist \(s.target.lowerBound) bis \(s.target.upperBound). Er richtet sich nach deiner Erholung."
        }
        if q.contains("stress") || q.contains("energie") {
            return "Energie \(s.energy) von 100, Stress etwa \(Format.number(s.stress, decimals: 1)) von 3 (geschätzt aus Ruhepuls und HRV)."
        }
        return "Ich habe dazu noch keine passende Auswertung. Frag mich nach Erholung, Schlaf, Training oder Belastung – oder hinterlege in den Einstellungen einen API-Schlüssel für freie Fragen."
    }

    static func contextSummary(_ c: Context) -> String {
        let s = c.scores
        var lines = [
            "Erholung \(s.recovery)/100, Schlaf \(s.sleep)/100, Belastung \(s.strain)/100 (Ziel \(s.target.lowerBound)–\(s.target.upperBound)).",
            "Energie \(s.energy)/100, Stress \(Format.number(s.stress, decimals: 1))/3 geschätzt.",
            "Schlafbedarf heute Nacht \(Format.duration(s.sleepNeed)), Schlafschuld \(Format.duration(s.sleepDebt))."
        ]
        if let hrv = c.today.hrv { lines.append("HRV \(Int(hrv)) ms" + (c.hrvDelta.map { " (\($0 >= 0 ? "+" : "")\(Int($0.rounded())) zum Normalwert)" } ?? "")) }
        if let rhr = c.today.restingHR { lines.append("Ruhepuls \(Int(rhr)) bpm") }
        if let sleep = c.today.sleep { lines.append("Letzte Nacht \(Format.duration(sleep.asleep)) geschlafen") }
        if let p = c.plannedRoutine { lines.append("Geplantes Training: \(p)") }
        if c.isSample { lines.append("Hinweis: Es sind Beispieldaten, keine echten Messwerte.") }
        return lines.joined(separator: "\n")
    }
}

/// Optionaler Zugang zu Claude über die Anthropic-API.
enum ClaudeClient {
    struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    static let model = "claude-sonnet-5-5"

    static func reply(apiKey: String, context: String, history: [ChatMessage]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let system = """
        Du bist der Coach in der App Forma. Antworte auf Deutsch, in der du-Form, knapp (höchstens 3 Sätze), freundlich und konkret. \
        Stütze dich nur auf die Daten unten. Du darfst Trainingsänderungen nur vorschlagen; Maxi entscheidet. Keine medizinischen Diagnosen.
        Daten von heute:
        \(context)
        """
        let messages: [[String: String]] = history.suffix(12).map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.text] }
        let body: [String: Any] = ["model": model, "max_tokens": 400, "system": system, "messages": messages]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw NSError(domain: "Forma.Claude", code: status, userInfo: [NSLocalizedDescriptionKey: "Claude antwortet mit Fehler \(status)."])
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.content.compactMap(\.text).joined(separator: "\n")
    }
}
