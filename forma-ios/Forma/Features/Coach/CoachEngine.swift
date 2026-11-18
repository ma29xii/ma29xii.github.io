import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, coach }
    var id = UUID()
    var role: Role
    var text: String
    /// Nur lokal beantwortet – geht nie an Claude, auch nicht später im Verlauf (Codex R-02-15/A-22).
    var localOnly: Bool = false
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
        /// Gibt es heute eine Messgrundlage? Ohne sie keine Empfehlungen aus Ersatzwerten (Codex R-02-03).
        var recoveryAvailable: Bool = true
        var strainAvailable: Bool = true
    }

    /// Ein Satz für die Startseite. Morgens Ausblick, nach dem Training Rückblick, abends Schlaf.
    static func dailyLine(_ c: Context) -> String {
        let s = c.scores
        if c.trainedToday && !c.strainAvailable {
            return "Gut trainiert. Für eine Belastungszahl fehlen heute Messwerte von Uhr oder Apple Health."
        }
        if !c.recoveryAvailable && !c.trainedToday && c.hour < 20 {
            return "Für heute fehlen Herzwerte mit Vergleich. Ich gebe dir erst eine Empfehlung, wenn Messwerte da sind – trag deine Uhr auch nachts."
        }
        if c.trainedToday {
            // Gleiche Logik wie der Zielbogen am Belastungsring (Codex R-01-05).
            if s.strain < s.target.lowerBound {
                return "Gut trainiert. Bis zur Untergrenze deines Zielbereichs fehlen noch \(s.target.lowerBound - s.strain) Punkte – etwas lockere Bewegung reicht."
            }
            if s.strain <= s.target.upperBound {
                return "Gut trainiert – du bist in deinem Zielbereich (\(s.target.lowerBound)–\(s.target.upperBound)). Jetzt zählt die Erholung: ins Bett gegen \(bedtime(s))."
            }
            return "Heute warst du über deinem Zielbereich. Mach morgen eher locker und geh gegen \(bedtime(s)) ins Bett."
        }
        if c.hour >= 20 {
            return "Für morgen zählt jetzt der Schlaf: ins Bett gegen \(bedtime(s)), dann holst du \(Format.duration(s.sleepNeed)) Schlaf."
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

    /// Gleiche Berechnung wie die Erinnerung (Codex R-02-08), Weckzeit aus dem Profil.
    static func bedtime(_ s: DayScores, now: Date = .now) -> String {
        guard let plan = CoachNotifier.bedtimePlan(sleepNeed: s.sleepNeed, now: now) else { return "–" }
        return Format.clock(plan.bed)
    }

    static func wakeTime(now: Date = .now) -> String {
        let m = CoachNotifier.wakeMinutes
        return String(format: "%d:%02d", m / 60, m % 60)
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
        if q.contains("hrv") || q.contains("erhol") {
            guard c.recoveryAvailable else {
                return "Für heute fehlen HRV oder Ruhepuls mit Vergleichswerten. Ohne Messung rechne ich keine Erholung aus – sobald deine Uhr Daten liefert, erkläre ich sie dir."
            }
            var parts: [String] = []
            if let d = c.hrvDelta { parts.append("HRV \(d >= 0 ? "+" : "")\(Int(d.rounded())) ms zum Normalwert") }
            if let d = c.rhrDelta { parts.append("Ruhepuls \(d >= 0 ? "+" : "")\(Int(d.rounded())) bpm") }
            parts.append("Schlafwert \(s.sleep)")
            return "Deine Erholung liegt bei \(s.recovery). Grundlage: \(parts.joined(separator: ", ")). HRV zählt am stärksten, danach Ruhepuls und Schlaf."
        }
        if q.contains("bett") || q.contains("schlaf") || q.contains("nacht") {
            return "Geschätzter Bedarf heute Nacht: \(Format.duration(s.sleepNeed)) (inklusive Schlafschuld). Bei Wecker \(wakeTime()) heißt das: gegen \(bedtime(s)) ins Bett. Die Weckzeit stellst du im Profil ein."
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
        if q.contains("belast") || q.contains("ziel") {
            guard c.recoveryAvailable else {
                return "Dein Zielbereich richtet sich nach der Erholung – und dafür fehlen heute Messwerte."
            }
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
            c.recoveryAvailable ? "Erholung \(s.recovery)/100." : "Erholung: heute keine Messgrundlage (nicht raten).",
            c.today.sleep != nil ? "Schlaf \(s.sleep)/100." : "Schlaf: keine Nacht gespeichert.",
            c.strainAvailable ? "Belastung \(s.strain)/100 (Ziel \(s.target.lowerBound)–\(s.target.upperBound))." : "Belastung: keine Messgrundlage.",
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
        // Lokale Nachrichten nie senden, jede Nachricht begrenzen (Codex R-02-15/A-22/A-23).
        let messages: [[String: String]] = history.filter { !$0.localOnly }.suffix(12)
            .map { ["role": $0.role == .user ? "user" : "assistant", "content": String($0.text.prefix(2000))] }
        guard messages.last?["role"] == "user" else { throw NSError(domain: "Forma.Claude", code: 400) }
        let body: [String: Any] = ["model": model, "max_tokens": 400, "system": system, "messages": messages]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        // Einmal erneut versuchen bei Überlastung, Serverfehler oder Zeitüberschreitung.
        var lastError: Error = NSError(domain: "Forma.Claude", code: 0)
        for attempt in 0..<2 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    let decoded = try JSONDecoder().decode(Response.self, from: data)
                    let text = decoded.content.compactMap(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { throw NSError(domain: "Forma.Claude", code: 204) }
                    return String(text.prefix(4000))
                }
                lastError = NSError(domain: "Forma.Claude", code: status, userInfo: [NSLocalizedDescriptionKey: "Claude antwortet mit Fehler \(status)."])
                guard status == 429 || status >= 500, attempt == 0 else { throw lastError }
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
                lastError = error
                guard attempt == 0 else { throw error }
            }
            try Task.checkCancellation()   // Widerruf stoppt auch den zweiten Versuch
            try await Task.sleep(for: .seconds(2))
            try Task.checkCancellation()
        }
        throw lastError
    }
}
