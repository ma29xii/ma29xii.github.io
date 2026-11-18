import Foundation
import CryptoKit

/// Fitbit Web API mit OAuth 2.0 (Authorization Code + PKCE).
/// Die Anmeldung selbst läuft über ASWebAuthenticationSession (siehe ProfileView).
@MainActor
@Observable
final class FitbitService {
    struct Tokens: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String?
    }

    enum FitbitError: LocalizedError {
        case notConfigured, invalidCallback, http(Int), noTokens, rateLimited(Date)
        var errorDescription: String? {
            switch self {
            case .rateLimited(let until): "Fitbit-Limit erreicht. Neuer Versuch ab \(Format.clock(until))."
            case .notConfigured: "Fitbit ist noch nicht eingerichtet: Client-ID fehlt (siehe README)."
            case .invalidCallback: "Die Anmeldung bei Fitbit wurde abgebrochen."
            case .http(let code): "Fitbit antwortet mit Fehler \(code)."
            case .noTokens: "Nicht mit Fitbit verbunden."
            }
        }
    }

    private(set) var tokens: Tokens?
    private var pendingVerifier: String?
    private var pendingState: String?
    /// Nach Fehler 429 keine weiteren Anfragen bis zu diesem Zeitpunkt.
    private(set) var rateLimitedUntil: Date?
    /// Anmeldung abgelaufen (Refresh-Token ungültig): Nutzer muss neu verbinden.
    private(set) var needsReconnect = false

    var isConnected: Bool { tokens != nil }

    let clientID: String = (Bundle.main.object(forInfoDictionaryKey: "FitbitClientID") as? String) ?? ""
    let redirectScheme: String = (Bundle.main.object(forInfoDictionaryKey: "FitbitRedirectScheme") as? String) ?? "forma"
    var redirectURI: String { "\(redirectScheme)://fitbit" }
    var isConfigured: Bool { !clientID.isEmpty && !clientID.hasPrefix("DEINE") && !clientID.contains("$(") }

    private static let scopes = ["sleep", "heartrate", "activity", "oxygen_saturation", "respiratory_rate", "profile"]

    init() {
        if let json = Keychain.get("fitbit.tokens"), let data = json.data(using: .utf8) {
            tokens = try? JSONDecoder().decode(Tokens.self, from: data)
        }
    }

    // MARK: Anmeldung

    func authorizationURL() throws -> URL {
        guard isConfigured else { throw FitbitError.notConfigured }
        let verifier = Self.randomString(length: 64)
        let state = Self.randomString(length: 24)
        pendingVerifier = verifier
        pendingState = state
        var c = URLComponents(string: "https://www.fitbit.com/oauth2/authorize")!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: Self.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ]
        return c.url!
    }

    func handleCallback(_ url: URL) async throws {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value,
              items.first(where: { $0.name == "state" })?.value == pendingState,
              let verifier = pendingVerifier else { throw FitbitError.invalidCallback }
        try await requestToken(form: [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI
        ])
        pendingVerifier = nil
        pendingState = nil
    }

    func disconnect() {
        tokens = nil
        Keychain.set(nil, for: "fitbit.tokens")
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user_id: String?
    }

    private func requestToken(form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://api.fitbit.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // 400/401 beim Erneuern: Refresh-Token verbraucht oder widerrufen → nicht endlos wiederholen.
            if form["grant_type"] == "refresh_token" && (status == 400 || status == 401) {
                needsReconnect = true
                tokens = nil
                Keychain.set(nil, for: "fitbit.tokens")
            }
            throw FitbitError.http(status)
        }
        let r = try JSONDecoder().decode(TokenResponse.self, from: data)
        let t = Tokens(accessToken: r.access_token, refreshToken: r.refresh_token,
                       expiresAt: .now.addingTimeInterval(r.expires_in - 60), userID: r.user_id)
        tokens = t
        needsReconnect = false
        if let data = try? JSONEncoder().encode(t) { Keychain.set(String(data: data, encoding: .utf8), for: "fitbit.tokens") }
    }

    private func validAccessToken() async throws -> String {
        guard let t = tokens else { throw FitbitError.noTokens }
        if t.expiresAt > .now { return t.accessToken }
        try await requestToken(form: ["client_id": clientID, "grant_type": "refresh_token", "refresh_token": t.refreshToken])
        guard let fresh = tokens else { throw FitbitError.noTokens }
        return fresh.accessToken
    }

    private func get(_ path: String) async throws -> Data {
        if let until = rateLimitedUntil, until > .now { throw FitbitError.rateLimited(until) }
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://api.fitbit.com" + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("de_DE", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 429 {
            let wait = Self.retryAfter(http?.value(forHTTPHeaderField: "Retry-After"))
                ?? Self.retryAfter(http?.value(forHTTPHeaderField: "fitbit-rate-limit-reset"))
                ?? 3600
            let until = Date.now.addingTimeInterval(wait)
            rateLimitedUntil = until
            throw FitbitError.rateLimited(until)
        }
        if status == 410 {
            // Endpunkt abgeschaltet (Google, 2.11.2026): dauerhaft, nicht wiederholen.
            needsReconnect = true
            rateLimitedUntil = .distantFuture
        }
        guard status == 200 else { throw FitbitError.http(status) }
        return data
    }

    nonisolated static func retryAfter(_ header: String?) -> TimeInterval? {
        guard let header, let seconds = Double(header.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, 3 * 3600)
    }

    var isRateLimited: Bool { (rateLimitedUntil ?? .distantPast) > .now }

    // MARK: Daten

    /// Lädt einen Tag. Fehlende Teile bleiben leer.
    func loadDay(_ date: Date) async -> DayMetrics {
        var day = DayMetrics(date: date.startOfDay)
        let d = Self.dayString(date)
        if let data = try? await get("/1.2/user/-/sleep/date/\(d).json"),
           let r = try? JSONDecoder().decode(SleepResponse.self, from: data),
           let main = r.sleep.first(where: { $0.isMainSleep ?? false }) ?? r.sleep.first {
            day.sleep = main.night()
        }
        if let data = try? await get("/1/user/-/hrv/date/\(d).json"),
           let r = try? JSONDecoder().decode(HRVResponse.self, from: data) {
            day.hrv = r.hrv.first?.value.dailyRmssd
        }
        if let data = try? await get("/1/user/-/activities/heart/date/\(d)/1d.json"),
           let r = try? JSONDecoder().decode(HeartResponse.self, from: data) {
            day.restingHR = r.activitiesHeart.first?.value.restingHeartRate
        }
        if let data = try? await get("/1/user/-/activities/date/\(d).json"),
           let r = try? JSONDecoder().decode(ActivityResponse.self, from: data) {
            day.steps = r.summary.steps
            day.activeEnergy = r.summary.activityCalories
        }
        if let data = try? await get("/1/user/-/spo2/date/\(d).json"),
           let r = try? JSONDecoder().decode(SpO2Response.self, from: data) {
            day.spo2 = r.value?.avg
        }
        if let data = try? await get("/1/user/-/br/date/\(d).json"),
           let r = try? JSONDecoder().decode(BreathingResponse.self, from: data) {
            day.respiratoryRate = r.br.first?.value.breathingRate
        }
        return day
    }

    // MARK: Hilfen

    nonisolated static func dayString(_ date: Date) -> String {
        let c = Calendar.forma.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    nonisolated static func randomString(length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    nonisolated static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

// MARK: - Fitbit-Antworten (nur benötigte Felder)

private struct SleepResponse: Decodable {
    struct Entry: Decodable {
        struct Levels: Decodable {
            struct Item: Decodable { let dateTime: String; let level: String; let seconds: Double }
            let data: [Item]
            let shortData: [Item]?
        }
        let startTime: String
        let endTime: String
        let isMainSleep: Bool?
        let levels: Levels?

        func night() -> SleepNight? {
            guard let start = Self.parse(startTime), let end = Self.parse(endTime) else { return nil }
            guard end > start, end.timeIntervalSince(start) < 24 * 3600 else { return nil }
            let segments: [SleepNight.Segment] = (levels?.data ?? []).compactMap { item in
                // Unplausible Werte verwerfen (negativ, länger als 12 h, keine Zahl).
                guard let s = Self.parse(item.dateTime), item.seconds.isFinite, item.seconds > 0, item.seconds <= 12 * 3600 else { return nil }
                let stage: SleepNight.Stage
                switch item.level {
                case "deep": stage = .deep
                case "rem": stage = .rem
                case "light", "asleep": stage = .core
                case "wake", "awake", "restless": stage = .awake
                default: return nil
                }
                return SleepNight.Segment(stage: stage, start: s, end: s.addingTimeInterval(item.seconds))
            }
            return SleepNight(start: start, end: end, segments: segments)
        }

        static func parse(_ s: String) -> Date? { FitbitTime.parse(s) }
    }
    let sleep: [Entry]
}

/// Zeitangaben von Fitbit: lokale Zeit ohne Zeitzone, z. B. 2026-11-17T23:10:30.000.
/// Robust gegen kaputte Eingaben (kein Absturz, sondern nil).
enum FitbitTime {
    static func parse(_ s: String) -> Date? {
            let parts = s.split(separator: "T")
            guard parts.count == 2, let timePart = parts[1].split(separator: ".").first else { return nil }
            let d = parts[0].split(separator: "-").compactMap { Int($0) }
            let t = timePart.split(separator: ":").compactMap { Int($0) }
            guard d.count == 3, t.count >= 2, t.count <= 3,
                  (1...12).contains(d[1]), (1...31).contains(d[2]), (0...23).contains(t[0]), (0...59).contains(t[1]),
                  t.count < 3 || (0...60).contains(t[2]) else { return nil }
            var c = DateComponents()
            c.year = d[0]; c.month = d[1]; c.day = d[2]; c.hour = t[0]; c.minute = t[1]; c.second = t.count > 2 ? t[2] : 0
            return Calendar.forma.date(from: c)
    }
}

private struct HRVResponse: Decodable {
    struct Entry: Decodable { struct Value: Decodable { let dailyRmssd: Double? }; let value: Value }
    let hrv: [Entry]
}

private struct HeartResponse: Decodable {
    struct Entry: Decodable { struct Value: Decodable { let restingHeartRate: Double? }; let value: Value }
    let activitiesHeart: [Entry]
    enum CodingKeys: String, CodingKey { case activitiesHeart = "activities-heart" }
}

private struct ActivityResponse: Decodable {
    struct Summary: Decodable { let steps: Double?; let activityCalories: Double? }
    let summary: Summary
}

private struct SpO2Response: Decodable {
    struct Value: Decodable { let avg: Double? }
    let value: Value?
}

private struct BreathingResponse: Decodable {
    struct Entry: Decodable { struct Value: Decodable { let breathingRate: Double? }; let value: Value }
    let br: [Entry]
}
