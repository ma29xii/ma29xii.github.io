import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum GoogleConnection: Equatable, Sendable {
    case notConfigured, disconnected, connecting, connected(lastSync: Date?), failed(String)
}

enum GoogleRevocation: Equatable, Sendable {
    case inProgress, confirmed, unconfirmed

    var notice: String {
        switch self {
        case .inProgress: "Die Freigabe bei Google wird widerrufen …"
        case .confirmed: "Die Freigabe bei Google wurde widerrufen."
        case .unconfirmed: "Google hat den Widerruf nicht bestätigt. Entferne Health in deinem Google-Konto unter Sicherheit → Verbindungen zu Drittanbietern."
        }
    }
}

enum GoogleHealthError: LocalizedError, Equatable, Sendable {
    case notConfigured, cancelled, invalidCallback, incompleteConsent, reauthorize
    case notLinked, noConnection, keychain(OSStatus), invalidResponse, http(Int), rateLimited(Date)
    case loginRevocationUnconfirmed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google Health ist noch nicht eingerichtet."
        case .cancelled: "Anmeldung abgebrochen."
        case .invalidCallback: "Die Google-Anmeldung konnte nicht abgeschlossen werden."
        case .incompleteConsent: "Erlaube beim Verbinden den Zugriff auf Schlaf, Aktivität und Vitalwerte."
        case .reauthorize: "Die Google-Freigabe ist abgelaufen. Verbinde Google Health erneut."
        case .notLinked: "Öffne zuerst die Google-Health-App und richte dort dein Google-Konto ein."
        case .noConnection: "Verbinde Google Health im Profil."
        case .keychain: "Der iPhone-Schlüsselbund ist gerade nicht verfügbar. Entsperre dein iPhone und versuche es erneut."
        case .invalidResponse: "Google Health hat unlesbare Daten geliefert."
        case .http(let status): "Google Health antwortet mit Fehler \(status)."
        case .rateLimited(let until): "Google Health begrenzt den Abruf. Neuer Versuch ab \(Format.clock(until))."
        case .loginRevocationUnconfirmed(let reason): "\(reason) \(GoogleRevocation.unconfirmed.notice)"
        }
    }
}

@MainActor
protocol GoogleHealthImporting {
    var isConfigured: Bool { get }
    var accountID: String? { get }
    func restore() throws
    func connect() async throws
    func disconnect() throws -> Task<GoogleRevocation, Never>?
    func load(from: Date, until: Date, calendar: Calendar, includePulse: Bool) async throws -> GoogleHealthService.Import
    func loadPulse(from: Date, until: Date, calendar: Calendar) async throws -> [HourlyMetrics]
}

struct GoogleOAuthTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scope: String? = nil
    var accountID: String? = nil
    var clientID: String? = nil

    private struct Response: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let token_type: String
        let scope: String?
    }

    private struct Rejection: Decodable { let error: String }

    static func decode(_ data: Data, status: Int, previous: Self?, now: Date) throws -> Self {
        guard (200..<300).contains(status) else {
            if previous != nil, status == 400,
               (try? JSONDecoder().decode(Rejection.self, from: data).error) == "invalid_grant" {
                throw GoogleHealthError.reauthorize
            }
            throw GoogleHealthError.http(status)
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              !response.access_token.isEmpty, response.token_type.lowercased() == "bearer",
              (1...86_400).contains(response.expires_in),
              let refresh = response.refresh_token ?? previous?.refreshToken, !refresh.isEmpty else {
            throw GoogleHealthError.invalidResponse
        }
        let lifetime = TimeInterval(response.expires_in - min(60, response.expires_in / 2))
        return Self(accessToken: response.access_token, refreshToken: refresh,
                    expiresAt: now.addingTimeInterval(lifetime), scope: response.scope ?? previous?.scope,
                    accountID: previous?.accountID, clientID: previous?.clientID)
    }
}

@MainActor
final class GoogleHealthService: GoogleHealthImporting {
    struct Import: Sendable {
        var days: [DayMetrics]
        var hours: [HourlyMetrics]?
        var pulses: [HourlyMetrics]?
        var failed: Set<MetricSeries>
    }

    private struct Configuration {
        let clientID: String
        let scheme: String
        var redirect: String { "\(scheme):/oauth2callback" }

        init?() {
            let bundle = Bundle.main
            guard let id = bundle.object(forInfoDictionaryKey: "GoogleHealthClientID") as? String,
                  id.hasSuffix(".apps.googleusercontent.com"),
                  id.range(of: #"^[A-Za-z0-9-]+\.apps\.googleusercontent\.com$"#,
                           options: .regularExpression) != nil else { return nil }
            let reversed = id.split(separator: ".").reversed().joined(separator: ".")
            let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
            guard types.contains(where: { ($0["CFBundleURLSchemes"] as? [String])?.contains(reversed) == true }) else { return nil }
            clientID = id
            scheme = reversed
        }
    }

    private static let scopes = [
        "activity_and_fitness", "sleep", "health_metrics_and_measurements"
    ].map { "https://www.googleapis.com/auth/googlehealth.\($0).readonly" }

    private let configuration = Configuration()
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 18
        config.urlCache = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: CoachProviders.NoRedirects(), delegateQueue: nil)
    }()
    private let browser = GoogleHealthBrowser()
    private var tokens: GoogleOAuthTokens?
    private var refreshTask: Task<GoogleOAuthTokens, any Error>?
    private var revocation: Task<GoogleRevocation, Never>?
    private var revocationID: UUID?
    private var generation = 0
    private let clock = ContinuousClock()
    private var nextRequest: ContinuousClock.Instant?
    private var limitedUntil: Date?

    var isConfigured: Bool { configuration != nil }
    var accountID: String? { tokens?.accountID }

    init() {
        try? restore()
    }

    func restore() throws {
        guard let configuration, tokens == nil,
              let stored = try GoogleCredentialStore.load(), stored.clientID == configuration.clientID,
              stored.accountID != nil else { return }
        tokens = stored
    }

    func connect() async throws {
        guard let configuration else { throw GoogleHealthError.notConfigured }
        let generation = self.generation
        _ = await revocation?.value
        try check(generation)
        let verifier = try Self.randomString()
        let state = try Self.randomString()
        let challenge = Self.challenge(for: verifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account")
        ]
        guard let url = components.url else { throw GoogleHealthError.notConfigured }
        let callback = try await browser.open(url, scheme: configuration.scheme)
        try check(generation)
        let code = try Self.authorizationCode(callback, scheme: configuration.scheme, state: state)
        var newTokens = try await requestToken([
            "client_id": configuration.clientID, "redirect_uri": configuration.redirect,
            "grant_type": "authorization_code", "code": code, "code_verifier": verifier
        ], previous: nil)
        do {
            try check(generation)
            try Self.requireScopes(newTokens)
            let identity = try await request(path: "identity", query: [], bearer: newTokens.accessToken, generation: generation)
            guard let account = try? JSONDecoder().decode(Identity.self, from: identity),
                  !account.healthUserId.isEmpty else { throw GoogleHealthError.invalidResponse }
            try check(generation)
            newTokens.accountID = account.healthUserId
            newTokens.clientID = configuration.clientID
            try GoogleCredentialStore.save(newTokens)
            tokens = newTokens
        } catch {
            // Eigener Task, damit auch eine abgebrochene Anmeldung die neue Freigabe zurücknehmen kann.
            let result = await beginRevocation(newTokens.refreshToken).value
            guard result == .confirmed else {
                let reason = (error as? GoogleHealthError)?.errorDescription ?? "Die Anmeldung wurde nicht abgeschlossen."
                throw GoogleHealthError.loginRevocationUnconfirmed(reason)
            }
            throw error
        }
    }

    func disconnect() throws -> Task<GoogleRevocation, Never>? {
        generation += 1
        browser.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        let old = try tokens ?? GoogleCredentialStore.load()
        try GoogleCredentialStore.delete()
        tokens = nil
        nextRequest = nil
        limitedUntil = nil
        return old.map { beginRevocation($0.refreshToken) } ?? revocation
    }

    private func beginRevocation(_ token: String) -> Task<GoogleRevocation, Never> {
        let previous = revocation
        let id = UUID()
        let task = Task { [session] in
            defer {
                if self.revocationID == id {
                    self.revocationID = nil
                    self.revocation = nil
                }
            }
            _ = await previous?.value
            return await Self.revoke(token) { request in
                let (_, response) = try await session.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode
            }
        }
        revocationID = id
        revocation = task
        return task
    }

    static func revoke(_ token: String, send: @Sendable (URLRequest) async throws -> Int?) async -> GoogleRevocation {
        let url = URL(string: "https://oauth2.googleapis.com/revoke")!
        let request = formRequest(url, fields: ["token": token])
        do {
            guard let status = try await send(request), (200..<300).contains(status) else { return .unconfirmed }
            return .confirmed
        } catch {
            return .unconfirmed
        }
    }

    func load(from: Date, until: Date, calendar: Calendar, includePulse: Bool) async throws -> Import {
        try restore()
        let generation = self.generation
        let kinds = GoogleHealthKind.dailyImport + (includePulse ? [.pulse] : [])
        let activityLookback = from.addingTimeInterval(-3600)
        let measuredUntil = min(until, .now)
        let imported = try await withThrowingTaskGroup(of: (GoogleHealthKind, [GoogleHealthPoint]?).self) { group in
            for kind in kinds {
                group.addTask { [self] in
                    let start = switch kind {
                    case .steps, .energy: activityLookback
                    case .pulse: max(from, calendar.startOfDay(for: .now))
                    default: from
                    }
                    let end = switch kind {
                    case .steps, .energy, .pulse, .sleep: measuredUntil
                    default: until
                    }
                    do {
                        return (kind, try await points(kind, from: start, until: end,
                                                       calendar: calendar, generation: generation))
                    } catch let error as GoogleHealthError {
                        switch error {
                        case .reauthorize, .incompleteConsent, .notLinked, .noConnection, .keychain: throw error
                        default: return (kind, nil)
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return (kind, nil)
                    }
                }
            }
            var values: [GoogleHealthKind: [GoogleHealthPoint]] = [:]
            for try await (kind, points) in group { values[kind] = points }
            return values
        }
        try check(generation)
        let failed = Set(kinds.compactMap { imported[$0] == nil ? $0.series : nil })
        if failed.count == MetricSeries.allCases.count, let limitedUntil, limitedUntil > .now {
            throw GoogleHealthError.rateLimited(limitedUntil)
        }
        let result = await Task.detached(priority: .utility) {
            let activity = GoogleHealthMerge.hours(steps: imported[.steps] ?? [], energy: imported[.energy] ?? [],
                                                   from: from, until: measuredUntil, calendar: calendar)
            let pulses = imported[.pulse].map {
                GoogleHealthMerge.hours(steps: [], energy: [], pulse: $0, from: from, until: measuredUntil, calendar: calendar)
            }
            return Import(days: GoogleHealthMerge.days(points: imported, from: from, until: until,
                                                       calendar: calendar, activity: activity),
                          hours: imported[.steps] == nil ? nil : activity,
                          pulses: pulses, failed: failed)
        }.value
        try check(generation)
        return result
    }

    func loadPulse(from: Date, until: Date, calendar: Calendar) async throws -> [HourlyMetrics] {
        let points = try await points(.pulse, from: from, until: until, calendar: calendar, generation: generation)
        return GoogleHealthMerge.hours(steps: [], energy: [], pulse: points, from: from, until: until, calendar: calendar)
    }

    private func points(_ kind: GoogleHealthKind, from: Date, until: Date, calendar: Calendar,
                        generation: Int) async throws -> [GoogleHealthPoint] {
        guard from < until else { return [] }
        let query = [
            URLQueryItem(name: "filter", value: kind.filter(from: from, until: until, calendar: calendar)),
            URLQueryItem(name: "pageSize", value: kind == .sleep || kind == .exercise ? "25" : "10000")
        ]
        var result: [GoogleHealthPoint] = []
        var pageToken: String?
        var seen: Set<String> = []
        repeat {
            let pageQuery = query + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            let path = "dataTypes/\(kind.rawValue)/dataPoints"
            let bearer = try await accessToken(generation: generation)
            let data: Data
            do {
                data = try await request(path: path, query: pageQuery, bearer: bearer, generation: generation)
            } catch GoogleHealthError.http(401) {
                let renewed = try await accessToken(generation: generation, rejected: bearer)
                do {
                    data = try await request(path: path, query: pageQuery, bearer: renewed, generation: generation)
                } catch GoogleHealthError.http(401) {
                    throw GoogleHealthError.reauthorize
                }
            }
            let page = try await Task.detached(priority: .utility) { try GoogleHealthPage.decode(data, kind: kind) }.value
            try check(generation)
            result.append(contentsOf: page.points)
            pageToken = page.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
            if let pageToken, !seen.insert(pageToken).inserted || seen.count >= 100 {
                throw GoogleHealthError.invalidResponse
            }
        } while pageToken != nil
        return result
    }

    private func accessToken(generation: Int, rejected: String? = nil) async throws -> String {
        try check(generation)
        guard let configuration, let old = tokens else { throw GoogleHealthError.noConnection }
        if old.expiresAt > .now, old.accessToken != rejected { return old.accessToken }
        if let refreshTask {
            let updated = try await refreshTask.value
            try check(generation)
            return updated.accessToken
        }
        let task = Task { @MainActor in
            defer { if generation == self.generation { self.refreshTask = nil } }
            do {
                let renewed = try await self.requestToken([
                    "client_id": configuration.clientID, "grant_type": "refresh_token", "refresh_token": old.refreshToken
                ], previous: old)
                try self.check(generation)
                try Self.requireScopes(renewed)
                try GoogleCredentialStore.save(renewed)
                self.tokens = renewed
                return renewed
            } catch GoogleHealthError.reauthorize {
                try self.check(generation)
                try GoogleCredentialStore.delete()
                self.tokens = nil
                throw GoogleHealthError.reauthorize
            }
        }
        refreshTask = task
        let updated = try await task.value
        try check(generation)
        return updated.accessToken
    }

    private func requestToken(_ fields: [String: String], previous: GoogleOAuthTokens?) async throws -> GoogleOAuthTokens {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        let (data, response) = try await session.data(for: Self.formRequest(url, fields: fields))
        guard let http = response as? HTTPURLResponse else { throw GoogleHealthError.invalidResponse }
        return try GoogleOAuthTokens.decode(data, status: http.statusCode, previous: previous, now: .now)
    }

    private static func requireScopes(_ tokens: GoogleOAuthTokens) throws {
        let granted = Set(tokens.scope?.split(separator: " ").map { String($0) } ?? [])
        guard Set(scopes).isSubset(of: granted) else { throw GoogleHealthError.incompleteConsent }
    }

    private func request(path: String, query: [URLQueryItem], bearer: String, generation: Int) async throws -> Data {
        var url = URLComponents(string: "https://health.googleapis.com/v4/users/me/\(path)")!
        url.queryItems = query.isEmpty ? nil : query
        guard let url = url.url else { throw GoogleHealthError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for attempt in 0...2 {
            try await waitForRequest(generation: generation)
            let (data, response) = try await session.data(for: request)
            try check(generation)
            guard let http = response as? HTTPURLResponse else { throw GoogleHealthError.invalidResponse }
            switch http.statusCode {
            case 200..<300:
                return data
            case 429:
                let now = Date.now
                let retry = Self.retryDate(http.value(forHTTPHeaderField: "Retry-After"), now: now)
                    ?? now.addingTimeInterval(Double(2 << attempt))
                let deadline = max(limitedUntil ?? now, retry)
                limitedUntil = deadline
                if attempt == 2 || deadline.timeIntervalSinceNow > 5 { throw GoogleHealthError.rateLimited(deadline) }
            case 504 where attempt < 2:
                try await Task.sleep(for: .seconds(1 << attempt))
            case 400 where Self.isUnlinked(data):
                throw GoogleHealthError.notLinked
            default:
                throw GoogleHealthError.http(http.statusCode)
            }
        }
        throw GoogleHealthError.invalidResponse
    }

    private func waitForRequest(generation: Int) async throws {
        while true {
            try check(generation)
            if let limitedUntil, limitedUntil > .now {
                let delay = limitedUntil.timeIntervalSinceNow
                guard delay <= 5 else { throw GoogleHealthError.rateLimited(limitedUntil) }
                try await Task.sleep(for: .seconds(delay))
            } else if let nextRequest, nextRequest > clock.now {
                try await clock.sleep(until: nextRequest)
            } else {
                // Die unverifizierte App darf pro Nutzer 2,5 Anfragen pro Sekunde starten.
                nextRequest = clock.now.advanced(by: .milliseconds(450))
                return
            }
        }
    }

    private func check(_ generation: Int) throws {
        try Task.checkCancellation()
        guard generation == self.generation else { throw CancellationError() }
    }

    private struct Identity: Decodable { let healthUserId: String }
    private struct APIError: Decodable {
        struct Body: Decodable {
            struct Detail: Decodable { let reason: String? }
            let details: [Detail]?
        }
        let error: Body
    }

    private static func isUnlinked(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(APIError.self, from: data).error.details)?
            .contains { $0.reason == "ACCOUNT_NOT_LINKED" } == true
    }

    nonisolated static func retryDate(_ value: String?, now: Date) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let seconds = Int(value), seconds >= 0 { return now.addingTimeInterval(min(10_800, Double(seconds))) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { min(now.addingTimeInterval(10_800), max(now, $0)) }
    }

    nonisolated static func authorizationCode(_ url: URL, scheme: String, state: String) throws -> String {
        guard let callback = URLComponents(url: url, resolvingAgainstBaseURL: false),
              callback.scheme == scheme, callback.host == nil, callback.path == "/oauth2callback",
              callback.fragment == nil else { throw GoogleHealthError.invalidCallback }
        let fields = callback.queryItems ?? []
        let states = fields.filter { $0.name == "state" }
        guard states.count == 1, states.first?.value == state else { throw GoogleHealthError.invalidCallback }
        if fields.contains(where: { $0.name == "error" && $0.value == "access_denied" }) {
            throw GoogleHealthError.cancelled
        }
        let codes = fields.filter { $0.name == "code" }
        guard !fields.contains(where: { $0.name == "error" }), codes.count == 1,
              let code = codes.first?.value, !code.isEmpty else { throw GoogleHealthError.invalidCallback }
        return code
    }

    nonisolated static func randomString() throws -> String {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            buffer.baseAddress.map { SecRandomCopyBytes(kSecRandomDefault, buffer.count, $0) } ?? errSecParam
        }
        guard status == errSecSuccess else { throw GoogleHealthError.invalidCallback }
        return base64URL(bytes)
    }

    nonisolated static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private nonisolated static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func formRequest(_ url: URL, fields: [String: String]) -> URLRequest {
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let body = fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")"
        }.joined(separator: "&")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        return request
    }
}

/// Eigener Eintrag mit atomarer Aktualisierung und geprüftem OSStatus.
private enum GoogleCredentialStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.ma29xii.forma",
         kSecAttrAccount as String: "google-health.tokens"]
    }

    static func load() throws -> GoogleOAuthTokens? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GoogleHealthError.keychain(status) }
        guard let data = item as? Data else { throw GoogleHealthError.invalidResponse }
        return try? JSONDecoder().decode(GoogleOAuthTokens.self, from: data)
    }

    static func save(_ value: GoogleOAuthTokens) throws {
        let bytes = try JSONEncoder().encode(value)
        let changes = [kSecValueData as String: bytes]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = bytes
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw GoogleHealthError.keychain(status) }
    }

    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GoogleHealthError.keychain(status) }
    }
}

@MainActor
private final class GoogleHealthBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, any Error>?
    private var anchor: ASPresentationAnchor?
    private var attempt: UUID?

    func open(_ url: URL, scheme: String) async throws -> URL {
        guard let anchor = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { throw GoogleHealthError.invalidCallback }
        self.anchor = anchor
        let id = UUID()
        attempt = id
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let web = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { [weak self] url, error in
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    Task { @MainActor in
                        if let url { self?.finish(.success(url), id: id) }
                        else { self?.finish(.failure(cancelled ? .cancelled : .invalidCallback), id: id) }
                    }
                }
                web.presentationContextProvider = self
                session = web
                if !web.start() { finish(.failure(.invalidCallback), id: id) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.attempt == id { self?.cancel() }
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }

    func cancel() {
        guard let attempt else { return }
        session?.cancel()
        finish(.failure(.cancelled), id: attempt)
    }

    private func finish(_ result: Result<URL, GoogleHealthError>, id: UUID) {
        guard attempt == id else { return }
        attempt = nil
        let continuation = self.continuation
        self.continuation = nil
        session = nil
        anchor = nil
        switch result {
        case .success(let url): continuation?.resume(returning: url)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }
}
