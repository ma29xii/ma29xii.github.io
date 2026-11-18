import CryptoKit
import Foundation
import Security

struct BundledKeys: Decodable {
    static let anthropicAccount = "anthropic.key"
    static let openAIAccount = "openai.key"
    private static let importedHashKey = "forma.coach.importedBundleHash"
    private static let maxFileBytes = 8192

    let anthropic: String?
    let openai: String?

    private enum CodingKeys: String, CodingKey { case anthropic, openai }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func key(_ name: CodingKeys) throws -> String? {
            guard let raw = try container.decodeIfPresent(String.self, forKey: name) else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            guard value.utf8.count <= 2048, value.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw DecodingError.dataCorruptedError(forKey: name, in: container, debugDescription: "Ungültiges Schlüsselformat.")
            }
            return value
        }
        anthropic = try key(.anthropic)
        openai = try key(.openai)
    }

    static func parse(_ data: Data) throws -> BundledKeys {
        try JSONDecoder().decode(Self.self, from: data)
    }

    @MainActor
    static func installIfNeeded() {
        guard let url = Bundle.main.url(forResource: "coach-keys", withExtension: "json"),
              let file = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: maxFileBytes + 1), data.count <= maxFileBytes else { return }

        let digest = Data(SHA256.hash(data: data))
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: importedHashKey) != digest, let keys = try? parse(data) else { return }
        var stored = true
        if let key = keys.anthropic {
            stored = Keychain.set(key, for: anthropicAccount) == errSecSuccess
        }
        if let key = keys.openai {
            let status = Keychain.set(key, for: openAIAccount)
            stored = stored && status == errSecSuccess
        }
        // Bei einem Fehler beim nächsten Start wieder versuchen. Vorhandene Werte werden aktualisiert.
        if stored { defaults.set(digest, forKey: importedHashKey) }
    }
}
