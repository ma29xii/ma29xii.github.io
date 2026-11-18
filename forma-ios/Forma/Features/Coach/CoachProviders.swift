import Foundation
import NaturalLanguage

enum CoachProviders {
    enum AnthropicModel: String {
        case sonnet = "claude-sonnet-5-5"
        case haiku = "claude-haiku-5-5"
    }

    enum ReplyError: Error, Equatable {
        case missingQuestion
        case missingCredentials
        case invalidResponse
        case httpStatus(Int)
    }

    typealias Transport = @Sendable (URLRequest) async throws -> Data

    // https://developers.openai.com/api/docs/models/gpt-6-luna
    static let openAIModel = "gpt-6-luna"
    static let consentKey = "forma.coach.externalConsent.v1"
    // Vorbereitet für eine spätere Freigabe. Kein Schlüssel, Endpunkt oder Routing für Gemini.
    private static let geminiEnabled = false

    private static let singleProviderTimeout: TimeInterval = 30
    private static let primaryTimeoutWithFallback: TimeInterval = 18
    private static let maxResponseBytes = 64 * 1024

    @MainActor
    static var hasConfiguredKey: Bool {
        BundledKeys.installIfNeeded()
        return [BundledKeys.anthropicAccount, BundledKeys.openAIAccount].contains {
            Keychain.get($0)?.isEmpty == false
        }
    }

    /// Aufrufer zeigen zuerst die Einwilligung für beide Anbieter und brechen beim Widerruf den Task ab.
    @MainActor
    static func reply(context: String, history: [ChatMessage]) async throws -> String {
        guard UserDefaults.standard.bool(forKey: consentKey) else { throw CancellationError() }
        BundledKeys.installIfNeeded()
        return try await reply(
            context: context, history: history,
            anthropicKey: Keychain.get(BundledKeys.anthropicAccount),
            openAIKey: Keychain.get(BundledKeys.openAIAccount),
            maySend: { UserDefaults.standard.bool(forKey: consentKey) }
        )
    }

    static func anthropicModel(for question: String) -> AnthropicModel {
        let text = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 240 else { return .sonnet }

        let explicitBrevity = #"\b(?:in (?:[12]|einem|zwei) s(?:atz|ätzen)|ja oder nein)\b|^(?:bitte )?kurz\s*:"#
        if text.range(of: explicitBrevity, options: .regularExpression) != nil { return .haiku }

        // Fragen mit mehreren Anliegen und Begründungsfragen bleiben beim Hauptmodell.
        let complex = #"\b(?:und|oder|warum|wieso|weshalb|erkläre|begründe|vergleich\w*|analysier\w*|pl(?:an|än)\w*|strategie)\b|[;:\n]|[.!?].+\S"#
        guard text.range(of: complex, options: .regularExpression) == nil else { return .sonnet }
        let quick = #"\btagessatz\b|^(?:(?:ein|einen|mein) satz (?:für|zu) heute|heute in einem satz|(?:soll|kann|darf|muss) ich|lohnt|passt|reicht|ist|wann soll ich ins bett|wie viel (?:schlaf|belastung))\b"#
        return text.range(of: quick, options: .regularExpression) != nil ? .haiku : .sonnet
    }

    static func reply(
        context: String, history: [ChatMessage], anthropicKey: String?, openAIKey: String?,
        maySend: @Sendable () -> Bool, send: Transport = fetch
    ) async throws -> String {
        try checkConsent(maySend)
        // Die aktuelle Frage muss selbst extern sein. Sonst könnte die letzte ältere Frage erneut rausgehen.
        guard let question = history.last, question.role == .user, !question.localOnly,
              !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReplyError.missingQuestion
        }
        let messages = history.filter { !$0.localOnly }.suffix(12).drop(while: { $0.role != .user })
            .map { ["role": $0.role == .user ? "user" : "assistant",
                    "content": limited($0.text, characters: 2000, bytes: 8000)] }
        let model = anthropicModel(for: limited(question.text, characters: 2000, bytes: 8000))
        let short = model == .haiku
        let system = """
        Du bist der Coach in der App Health. Antworte auf Deutsch, in der du-Form, freundlich und konkret. \
        Verwende höchstens \(short ? 2 : 3) Sätze. Stütze dich auf die Daten unten und sage klar, wenn Werte fehlen. \
        Die einzige Datenquelle für Messwerte in dieser App heißt Google Health. \
        Nenne keine anderen Gesundheitsdienste als Quelle und wiederhole deren Namen auch auf Nachfrage nicht. \
        Du darfst Trainingsänderungen nur vorschlagen. Stelle keine medizinischen Diagnosen.
        Daten von heute:
        \(limited(context, characters: 4000, bytes: 16000))
        """
        let primaryKey = anthropicKey.flatMap { $0.isEmpty ? nil : $0 }
        let fallbackKey = openAIKey.flatMap { $0.isEmpty ? nil : $0 }
        if let primaryKey {
            do {
                let request = try anthropicRequest(
                    key: primaryKey, model: model, system: system, messages: messages,
                    timeout: fallbackKey == nil ? singleProviderTimeout : primaryTimeoutWithFallback
                )
                try checkConsent(maySend)
                let data = try await send(request)
                try checkConsent(maySend)
                let blocks = try JSONDecoder().decode(AnthropicResponse.self, from: data).content
                return try checkedAnswer(blocks.filter { $0.type == "text" }.compactMap(\.text), short: short)
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                guard fallbackKey != nil else { throw error }
                try checkConsent(maySend)
            }
        }

        guard let fallbackKey else { throw ReplyError.missingCredentials }
        let timeout = primaryKey == nil ? singleProviderTimeout : singleProviderTimeout - primaryTimeoutWithFallback
        let request = try openAIRequest(key: fallbackKey, system: system, messages: messages, short: short, timeout: timeout)
        try checkConsent(maySend)
        let data: Data
        do {
            data = try await send(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
        try checkConsent(maySend)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard response.status == "completed" else { throw ReplyError.invalidResponse }
        let blocks = response.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        return try checkedAnswer(blocks.filter { $0.type == "output_text" }.compactMap(\.text), short: short)
    }

    private static func checkConsent(_ maySend: () -> Bool) throws {
        try Task.checkCancellation()
        guard maySend() else { throw CancellationError() }
    }

    private static func anthropicRequest(
        key: String, model: AnthropicModel, system: String, messages: [[String: String]], timeout: TimeInterval
    ) throws -> URLRequest {
        let short = model == .haiku
        var request = try post(
            to: URL(string: "https://api.anthropic.com/v1/messages")!, timeout: timeout,
            body: ["model": model.rawValue, "system": system, "messages": messages,
                   "max_tokens": short ? 180 : 400,
                   "thinking": ["type": short ? "disabled" : "between_tools"],
                   "output_config": ["effort": short ? "low" : "medium"]]
        )
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return request
    }

    private static func openAIRequest(
        key: String, system: String, messages: [[String: String]], short: Bool, timeout: TimeInterval
    ) throws -> URLRequest {
        var request = try post(
            to: URL(string: "https://api.openai.com/v1/responses")!, timeout: timeout,
            body: ["model": openAIModel, "instructions": system, "input": messages,
                   "max_output_tokens": short ? 180 : 400, "reasoning": ["effort": "none"], "store": false]
        )
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func post(to url: URL, timeout: TimeInterval, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func fetch(_ request: URLRequest) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = request.timeoutInterval
        config.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ReplyError.invalidResponse }
        guard status == 200 else { throw ReplyError.httpStatus(status) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maxResponseBytes else { throw ReplyError.invalidResponse }
            data.append(byte)
        }
        return data
    }

    private static func limited(_ text: String, characters: Int, bytes: Int) -> String {
        let bounded = String(decoding: text.utf8.prefix(bytes), as: UTF8.self)
        return String(bounded.prefix(characters))
    }

    private static func checkedAnswer(_ blocks: [String], short: Bool) throws -> String {
        let text = limited(blocks.joined(separator: "\n"), characters: 4000, bytes: 16000)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let obsoleteSource = #"apple[\s\-]*health(?:[\s\-]*kit)?|health[\s\-]*kit|apple[\s\-]+gesundheit"#
        guard !text.isEmpty, text.range(of: obsoleteSource, options: [.regularExpression, .caseInsensitive]) == nil else {
            throw ReplyError.invalidResponse
        }
        guard short else { return text }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(.german)
        tokenizer.string = text
        var sentenceCount = 0
        var end = text.endIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentenceCount += 1
            if sentenceCount == 2 { end = range.upperBound }
            return sentenceCount < 2
        }
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct TextBlock: Decodable {
        let type: String
        let text: String?
    }

    private struct AnthropicResponse: Decodable {
        let content: [TextBlock]
    }

    private struct OpenAIResponse: Decodable {
        struct Output: Decodable {
            let type: String
            let content: [TextBlock]?
        }
        let status: String
        let output: [Output]
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
