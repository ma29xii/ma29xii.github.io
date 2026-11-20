import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import NaturalLanguage
import Synchronization
import UniformTypeIdentifiers

enum CoachProviders {
    enum AnthropicModel: String {
        case sonnet = "claude-sonnet-5-5"
        case haiku = "claude-haiku-5-5"
    }

    enum ReplyError: Error, Equatable {
        case missingQuestion
        case missingCredentials
        case tooManyImages
        case invalidImage
        case invalidResponse
        case httpStatus(Int)
    }

    typealias Transport = @Sendable (URLRequest) async throws -> Data

    // https://developers.openai.com/api/docs/models/gpt-6-luna
    static let openAIModel = "gpt-6-luna"
    static let consentKey = "forma.coach.externalConsent.v1"
    static let photoConsentKey = "forma.coach.photoConsent.v1"
    static let maxImagesPerMessage = 4
    private static let conversation = Mutex(UUID())
    private enum PhotoKind: Equatable, Sendable { case chat, food }

    private struct PhotoRequests: Sendable {
        var revision = UUID()
        var allowed = false
        var transports: [UUID: Task<Data, any Error>] = [:]

        mutating func revoke() -> [Task<Data, any Error>] {
            revision = UUID()
            let active = Array(transports.values)
            transports.removeAll()
            return active
        }
    }

    private struct PhotoAccess: Sendable {
        let kind: PhotoKind
        let revision: UUID

        init(_ kind: PhotoKind) {
            self.kind = kind
            revision = photoRequests.withLock { $0[kind].revision }
        }

        var isCurrent: Bool { photoRequests.withLock { $0[kind].revision == revision } }
    }

    private struct PhotoPermissions: Sendable {
        private var chat = PhotoRequests()
        private var food = PhotoRequests()

        subscript(kind: PhotoKind) -> PhotoRequests {
            get { kind == .chat ? chat : food }
            set {
                if kind == .chat { chat = newValue } else { food = newValue }
            }
        }
    }

    private static let photoRequests = Mutex(PhotoPermissions())
    @MainActor private static var activeReplies: [UUID: Task<String, any Error>] = [:]
    @MainActor private static var credentialSignature: [Data?]?
    @MainActor private static let consentObserver = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: nil
    ) { _ in
        CoachProviders.observeConsentChange()
    }

    static var conversationID: UUID { conversation.withLock { $0 } }

    @MainActor
    static func invalidateConversation() {
        conversation.withLock { $0 = UUID() }
        for task in activeReplies.values { task.cancel() }
        activeReplies.removeAll()
    }
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

    static func allowsExternalData() -> Bool {
        UserDefaults.standard.bool(forKey: consentKey)
    }

    static func allowsCoachReply(withPhotos: Bool, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: consentKey) && (!withPhotos || defaults.bool(forKey: photoConsentKey))
    }

    static func allowsFoodPhoto(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: consentKey) && FoodSettings.photoAnalysisAllowed(defaults)
    }

    static func revokeFoodPhotoConsent(defaults: UserDefaults = .standard) {
        revokePhotoRequests(.food)
        defaults.removeObject(forKey: FoodSettings.photoConsentKey)
    }

    @MainActor
    static func revokeChatConsent(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: consentKey)
        clearPhotoConsentIfChatIsOff(defaults: defaults)
        revokePhotoRequests(.chat)
        revokePhotoRequests(.food)
        invalidateConversation()
    }

    @MainActor
    static func monitorConsent() {
        _ = consentObserver
        observeConsentChange()
    }

    private static func observeConsentChange() {
        let chat = allowsCoachReply(withPhotos: true)
        let food = allowsFoodPhoto()
        let cancelled = photoRequests.withLock { requests in
            var cancelled: [Task<Data, any Error>] = []
            for (kind, allowed) in [(PhotoKind.chat, chat), (.food, food)] {
                if requests[kind].allowed && !allowed { cancelled += requests[kind].revoke() }
                requests[kind].allowed = allowed
            }
            return cancelled
        }
        for task in cancelled { task.cancel() }
        clearPhotoConsentIfChatIsOff(defaults: .standard)
    }

    private static func revokePhotoRequests(_ kind: PhotoKind) {
        let cancelled = photoRequests.withLock { $0[kind].revoke() }
        for task in cancelled { task.cancel() }
    }

    private static func clearPhotoConsentIfChatIsOff(defaults: UserDefaults) {
        guard !defaults.bool(forKey: consentKey) else { return }
        if defaults.bool(forKey: photoConsentKey) { defaults.removeObject(forKey: photoConsentKey) }
        if FoodSettings.photoAnalysisAllowed(defaults) { revokeFoodPhotoConsent(defaults: defaults) }
    }

    @MainActor
    static func externalCredentials() throws -> (anthropic: String?, openAI: String?) {
        try checkConsent(allowsExternalData)
        BundledKeys.installIfNeeded()
        let anthropic = Keychain.get(BundledKeys.anthropicAccount)
        let openAI = Keychain.get(BundledKeys.openAIAccount)
        guard anthropic?.isEmpty == false || openAI?.isEmpty == false else {
            throw ReplyError.missingCredentials
        }
        return (anthropic, openAI)
    }

    /// Bilder gehören zur letzten Nachricht und brauchen eine eigene Einwilligung.
    @MainActor
    static func reply(context: String, history: [ChatMessage], images: [Data] = [], personal: String = "") async throws -> String {
        let keys = try externalCredentials()
        let signature = signature(for: keys)
        if let credentialSignature, credentialSignature != signature { invalidateConversation() }
        credentialSignature = signature
        let needsPhotoConsent = !images.isEmpty
        return try await replyInCurrentConversation(
            context: context, history: history, images: images, personal: personal, anthropicKey: keys.anthropic,
            openAIKey: keys.openAI, maySend: {
                allowsCoachReply(withPhotos: needsPhotoConsent)
                    && signature == Self.signature(for: storedCredentials())
            }
        )
    }

    private static func storedCredentials() -> (anthropic: String?, openAI: String?) {
        (Keychain.get(BundledKeys.anthropicAccount), Keychain.get(BundledKeys.openAIAccount))
    }

    private static func signature(for keys: (anthropic: String?, openAI: String?)) -> [Data?] {
        [keys.anthropic, keys.openAI].map { $0.map { Data(SHA256.hash(data: Data($0.utf8))) } }
    }

    @MainActor
    static func replyInCurrentConversation(
        context: String, history: [ChatMessage], images: [Data] = [], personal: String = "",
        anthropicKey: String?, openAIKey: String?,
        maySend: @Sendable @escaping () -> Bool, send: @escaping Transport = fetch
    ) async throws -> String {
        let current = conversationID
        let photoAccess = images.isEmpty ? nil : PhotoAccess(.chat)
        let allowed: @Sendable () -> Bool = { conversationID == current && (photoAccess?.isCurrent ?? true) && maySend() }
        guard history.last?.conversationID == current else { throw CancellationError() }
        try checkConsent(allowed)
        let eligible = history.filter { $0.conversationID == current }
        let id = UUID()
        let task = Task {
            try await reply(
                context: context, history: eligible, images: images, personal: personal, anthropicKey: anthropicKey,
                openAIKey: openAIKey, maySend: allowed, send: send
            )
        }
        activeReplies[id] = task
        defer { activeReplies.removeValue(forKey: id) }
        let answer = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try checkConsent(allowed)
        return answer
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
        context: String, history: [ChatMessage], images: [Data] = [], personal: String = "",
        anthropicKey: String?, openAIKey: String?,
        maySend: @escaping @Sendable () -> Bool, send: @escaping Transport = fetch
    ) async throws -> String {
        let photoAccess = images.isEmpty ? nil : PhotoAccess(.chat)
        try checkConsent(maySend)
        guard images.count <= maxImagesPerMessage else { throw ReplyError.tooManyImages }
        // Die aktuelle Frage muss selbst extern sein. Sonst könnte die letzte ältere Frage erneut rausgehen.
        guard let question = history.last, question.role == .user, !question.localOnly else {
            throw ReplyError.missingQuestion
        }
        let hasText = !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText || !images.isEmpty else { throw ReplyError.missingQuestion }
        var messages = history.dropLast().filter {
            !$0.localOnly && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.suffix(11)
            .map { ["role": $0.role == .user ? "user" : "assistant",
                    "content": outgoingMessageText($0.text)] }
        let text = hasText ? outgoingMessageText(question.text) : "Was siehst du auf dem Bild?"
        messages.append(["role": "user", "content": text])
        let model = images.isEmpty ? anthropicModel(for: text) : .sonnet
        let short = model == .haiku
        let dailyContext = CoachEngine.filteredContextSummary(context, for: question.text)
        // Der Block kommt fertig aus CoachMemory (nie mit Beispieldaten); hier nur noch begrenzt und auf eine Zeilenform gebracht.
        let personalSection = personal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "" : "\n" + limited(personal, characters: CoachMemory.maxBlockCharacters, bytes: 8000)
        let system = """
        Du bist der Coach in der App Health. Antworte auf Deutsch, in der du-Form, freundlich und konkret. \
        Verwende höchstens \(short ? 2 : 3) Sätze. Stütze dich auf die Daten unten und sage klar, wenn Werte fehlen. \
        Erfinde keine persönlichen Messwerte. \
        Die einzige Datenquelle für Messwerte in dieser App heißt Google Health. \
        Nenne keine anderen Gesundheitsdienste als Quelle und wiederhole deren Namen auch auf Nachfrage nicht. \
        Du darfst Trainingsänderungen nur vorschlagen. Stelle keine medizinischen Diagnosen. \
        Nutze den persönlichen Kontext, ohne ihn aufzuzählen, und beachte gemerkte Angaben wie Unverträglichkeiten immer. \
        Isst die Person eine Mahlzeit am Tag, schlage keine zusätzlichen Mahlzeiten vor.
        Daten von heute:
        \(dailyContext.isEmpty ? "Keine Tageswerte für diese Frage." : limited(dailyContext, characters: 4000, bytes: 16000))
        \(personalSection)
        """
        let prompt = Prompt(
            system: system, messages: Array(messages.drop(while: { $0["role"] != "user" })),
            images: try images.map(prepareImage), model: model
        )
        return try await requestReply(
            prompt, anthropicKey: anthropicKey, openAIKey: openAIKey, photoAccess: photoAccess,
            maySend: maySend, send: send
        ) { try checkedAnswer($0, short: short) }
    }

    static func structuredImageReply<Result: Sendable>(
        photo: Data, system: String, schema: String, anthropicKey: String?, openAIKey: String?,
        maySend: @escaping @Sendable () -> Bool, send: @escaping Transport, parse: (String) throws -> Result
    ) async throws -> Result {
        let photoAccess = PhotoAccess(.food)
        try checkConsent(maySend)
        let prompt = Prompt(
            system: system, messages: [["role": "user", "content": "Schätze die sichtbare Portion auf dem Foto."]],
            images: [try prepareImage(photo)], model: .sonnet, jsonSchema: schema
        )
        return try await requestReply(
            prompt, anthropicKey: anthropicKey, openAIKey: openAIKey, photoAccess: photoAccess,
            maySend: maySend, send: send
        ) { blocks in
            guard blocks.count == 1, let json = blocks.first else { throw ReplyError.invalidResponse }
            return try parse(json)
        }
    }

    /// Strukturierte JSON-Antwort ohne Bild (zum Beispiel Essensplan). Gleiche Einwilligungsprüfung und Rückfallkette.
    static func structuredReply<Result: Sendable>(
        system: String, user: String, schema: String, anthropicKey: String?, openAIKey: String?,
        maySend: @escaping @Sendable () -> Bool, send: @escaping Transport, parse: (String) throws -> Result
    ) async throws -> Result {
        try checkConsent(maySend)
        let prompt = Prompt(system: system, messages: [["role": "user", "content": user]],
                            images: [], model: .sonnet, jsonSchema: schema)
        return try await requestReply(
            prompt, anthropicKey: anthropicKey, openAIKey: openAIKey, photoAccess: nil,
            maySend: maySend, send: send
        ) { blocks in
            guard blocks.count == 1, let json = blocks.first else { throw ReplyError.invalidResponse }
            return try parse(json)
        }
    }

    private struct Prompt {
        let system: String
        let messages: [[String: String]]
        let images: [Data]
        let model: AnthropicModel
        var jsonSchema: String? = nil

        var maxTokens: Int {
            if jsonSchema != nil { return 1_600 }
            return model == .haiku ? 180 : 400
        }

        func messagesWithImages(_ imageBlocks: [[String: Any]], textType: String) -> [[String: Any]] {
            var result: [[String: Any]] = messages.map { $0 }
            if !imageBlocks.isEmpty, let text = messages.last?["content"] {
                result[result.count - 1]["content"] = imageBlocks + [["type": textType, "text": text]]
            }
            return result
        }
    }

    private static func requestReply<Result: Sendable>(
        _ prompt: Prompt, anthropicKey: String?, openAIKey: String?, photoAccess: PhotoAccess?,
        maySend: @escaping @Sendable () -> Bool, send: @escaping Transport, parse: ([String]) throws -> Result
    ) async throws -> Result {
        let allowed: @Sendable () -> Bool = { (photoAccess?.isCurrent ?? true) && maySend() }
        try checkConsent(allowed)
        let primaryKey = anthropicKey.flatMap { $0.isEmpty ? nil : $0 }
        let fallbackKey = openAIKey.flatMap { $0.isEmpty ? nil : $0 }
        // Ein erstmalig verwendetes JSON-Schema braucht Zeit zur Kompilierung beim Anbieter.
        let totalTimeout = prompt.jsonSchema == nil ? singleProviderTimeout : 60
        let primaryTimeout = prompt.jsonSchema == nil ? primaryTimeoutWithFallback : 35
        if let primaryKey {
            do {
                let request = try anthropicRequest(
                    key: primaryKey, prompt: prompt, timeout: fallbackKey == nil ? totalTimeout : primaryTimeout
                )
                let data = try await sendRequest(request, photoAccess: photoAccess, allowed: allowed, send: send)
                try checkConsent(allowed)
                let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)
                if let reason = response.stopReason,
                   ["max_tokens", "model_context_window_exceeded", "refusal"].contains(reason) {
                    throw ReplyError.invalidResponse
                }
                return try parse(response.content.filter { $0.type == "text" }.compactMap(\.text))
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                try checkConsent(allowed)
                guard fallbackKey != nil else { throw error }
            }
        }

        guard let fallbackKey else { throw ReplyError.missingCredentials }
        let timeout = primaryKey == nil ? totalTimeout : totalTimeout - primaryTimeout
        let request = try openAIRequest(key: fallbackKey, prompt: prompt, timeout: timeout)
        let data: Data
        do {
            data = try await sendRequest(request, photoAccess: photoAccess, allowed: allowed, send: send)
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            try checkConsent(allowed)
            throw error
        }
        try checkConsent(allowed)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard response.status == "completed" else { throw ReplyError.invalidResponse }
        let blocks = response.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        guard !blocks.contains(where: { $0.type == "refusal" }) else { throw ReplyError.invalidResponse }
        return try parse(blocks.filter { $0.type == "output_text" }.compactMap(\.text))
    }

    private static func sendRequest(_ request: URLRequest, photoAccess: PhotoAccess?,
                                    allowed: @escaping @Sendable () -> Bool, send: @escaping Transport) async throws -> Data {
        try checkConsent(allowed)
        guard let photoAccess else { return try await send(request) }
        let id = UUID()
        // Registrierung und Widerruf verwenden dieselbe Sperre. Ein veralteter Auftrag kann nicht nachrücken.
        let task: Task<Data, any Error> = try photoRequests.withLock { requests in
            guard requests[photoAccess.kind].revision == photoAccess.revision else { throw CancellationError() }
            let task = Task {
                try checkConsent(allowed)
                return try await send(request)
            }
            requests[photoAccess.kind].transports[id] = task
            return task
        }
        defer { photoRequests.withLock { $0[photoAccess.kind].transports[id] = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func checkConsent(_ maySend: () -> Bool) throws {
        try Task.checkCancellation()
        guard maySend() else { throw CancellationError() }
    }

    private static func anthropicRequest(key: String, prompt: Prompt, timeout: TimeInterval) throws -> URLRequest {
        // https://platform.claude.com/docs/en/build-with-claude/vision
        let images: [[String: Any]] = prompt.images.map { image in
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]]
        }
        let short = prompt.model == .haiku
        var outputConfig: [String: Any] = ["effort": short ? "low" : "medium"]
        if let schema = prompt.jsonSchema {
            // https://platform.claude.com/docs/en/build-with-claude/structured-outputs
            let format: [String: Any] = [
                "type": "json_schema", "schema": try JSONSerialization.jsonObject(with: Data(schema.utf8))
            ]
            outputConfig["format"] = format
        }
        var request = try post(
            to: URL(string: "https://api.anthropic.com/v1/messages")!, timeout: timeout,
            body: ["model": prompt.model.rawValue, "system": prompt.system,
                   "messages": prompt.messagesWithImages(images, textType: "text"),
                   "max_tokens": prompt.maxTokens,
                   "thinking": ["type": short ? "disabled" : "between_tools"],
                   "output_config": outputConfig]
        )
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return request
    }

    private static func openAIRequest(key: String, prompt: Prompt, timeout: TimeInterval) throws -> URLRequest {
        // https://developers.openai.com/api/docs/guides/images-vision
        let images: [[String: Any]] = prompt.images.map { image in
            ["type": "input_image", "image_url": "data:image/jpeg;base64,\(image.base64EncodedString())", "detail": "auto"]
        }
        // store: false deaktiviert die Speicherung der Antwort für späteren API-Abruf.
        // https://developers.openai.com/api/reference/resources/responses/methods/create
        var body: [String: Any] = [
            "model": openAIModel, "instructions": prompt.system,
            "input": prompt.messagesWithImages(images, textType: "input_text"),
            "max_output_tokens": prompt.maxTokens, "reasoning": ["effort": "none"], "store": false
        ]
        if let schema = prompt.jsonSchema {
            // https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses
            let format: [String: Any] = [
                "type": "json_schema", "name": "food_estimate", "strict": true,
                "schema": try JSONSerialization.jsonObject(with: Data(schema.utf8))
            ]
            body["text"] = ["format": format]
        }
        var request = try post(
            to: URL(string: "https://api.openai.com/v1/responses")!, timeout: timeout, body: body
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

    static func fetch(_ request: URLRequest) async throws -> Data {
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

    /// Erzeugt ein JPEG aus den gedrehten Bildpixeln, ohne EXIF- oder GPS-Daten zu übernehmen.
    static func prepareImage(_ data: Data) throws -> Data {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            throw ReplyError.invalidImage
        }

        for pixels in [1_568, 1_176, 882, 662, 496] {
            try Task.checkCancellation()
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  max(image.width, image.height) <= pixels else {
                throw ReplyError.invalidImage
            }
            for quality in [0.88, 0.7, 0.5] {
                let bytes = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(
                    bytes as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
                ) else { throw ReplyError.invalidImage }
                CGImageDestinationAddImage(
                    destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
                )
                guard CGImageDestinationFinalize(destination), bytes.length > 0 else { throw ReplyError.invalidImage }
                if bytes.length <= 1_000_000 { return bytes as Data }
            }
        }
        throw ReplyError.invalidImage
    }

    static func outgoingMessageText(_ text: String) -> String {
        limited(text, characters: 2000, bytes: 8000)
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
        let stopReason: String?
        let content: [TextBlock]

        enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason"
            case content
        }
    }

    private struct OpenAIResponse: Decodable {
        struct Output: Decodable {
            let type: String
            let content: [TextBlock]?
        }
        let status: String
        let output: [Output]
    }

    final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
