import CryptoKit
import Foundation
import Security

struct BundledKeys: Decodable {
    static let anthropicAccount = "anthropic.key"
    static let openAIAccount = "openai.key"
    private static let importedHashKey = "forma.coach.importedBundleHash"
    private static let maxFileBytes = 8192

    enum Update: Equatable {
        case keep
        case remove
        case set(String)
    }

    let anthropic: Update
    let openai: Update

    private enum CodingKeys: String, CodingKey { case anthropic, openai }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func update(_ name: CodingKeys) throws -> Update {
            guard container.contains(name) else { return .keep }
            guard let raw = try container.decodeIfPresent(String.self, forKey: name) else { return .remove }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return .keep }
            guard value.utf8.count <= 2048, value.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw DecodingError.dataCorruptedError(forKey: name, in: container, debugDescription: "Ungültiges Schlüsselformat.")
            }
            return .set(value)
        }
        anthropic = try update(.anthropic)
        openai = try update(.openai)
    }

    static func parse(_ data: Data) throws -> BundledKeys {
        try JSONDecoder().decode(Self.self, from: data)
    }

    func apply(using store: (String?, String) -> Bool) -> Bool {
        func apply(_ update: Update, to account: String) -> Bool {
            switch update {
            case .keep: return true
            case .remove: return store(nil, account)
            case .set(let value): return store(value, account)
            }
        }
        let anthropicStored = apply(anthropic, to: Self.anthropicAccount)
        let openAIStored = apply(openai, to: Self.openAIAccount)
        return anthropicStored && openAIStored
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
        let stored = keys.apply { value, account in
            Keychain.set(value, for: account) == errSecSuccess
        }
        // Bei einem Fehler beim nächsten Start die Änderungen erneut anwenden.
        if stored { defaults.set(digest, forKey: importedHashKey) }
    }
}
