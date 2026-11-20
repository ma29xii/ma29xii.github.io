import Foundation
import SwiftData

/// Ein gespeichertes Gespräch mit dem Coach. Fotos bleiben nur im Speicher und werden nicht abgelegt.
@Model
final class CoachChat {
    var title: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \CoachChatMessage.chat) var messages: [CoachChatMessage]

    init(title: String, now: Date = .now) {
        self.title = title
        self.createdAt = now
        self.updatedAt = now
        self.messages = []
    }
}

@Model
final class CoachChatMessage {
    var messageID: UUID
    var order: Int
    var roleRaw: String
    var text: String
    /// Bleibt auch nach dem Öffnen eines alten Chats erhalten: Lokale Nachrichten gehen nie online.
    var localOnly: Bool
    var chat: CoachChat?

    init(messageID: UUID, order: Int, role: ChatMessage.Role, text: String, localOnly: Bool) {
        self.messageID = messageID
        self.order = order
        self.roleRaw = role.rawValue
        self.text = text
        self.localOnly = localOnly
    }
}

extension CoachChat {
    static let maxTitleLength = 60

    /// Titel = erste Frage, auf eine Zeile gekürzt.
    static func title(for question: String) -> String {
        let line = CoachMemory.oneLine(question)
        return line.isEmpty ? "Neuer Chat" : String(line.prefix(maxTitleLength))
    }

    /// Spiegelt die Nachrichten des Bildschirms in den Speicher. Ein Chat entsteht erst mit der ersten Frage.
    @discardableResult
    static func sync(_ messages: [ChatMessage], into chat: CoachChat?, in context: ModelContext,
                     now: Date = .now) -> CoachChat? {
        guard let first = messages.first(where: { $0.role == .user }) else { return chat }
        let target: CoachChat
        if let chat {
            target = chat
        } else {
            target = CoachChat(title: title(for: first.text), now: now)
            context.insert(target)
        }
        // Nur echte Änderungen schieben den Chat in der Liste nach oben (Öffnen allein nicht).
        var changed = chat == nil
        var stored = Dictionary(target.messages.map { ($0.messageID, $0) }, uniquingKeysWith: { a, _ in a })
        for (index, message) in messages.enumerated() {
            if let row = stored.removeValue(forKey: message.id) {
                if row.text != message.text || row.localOnly != message.localOnly { changed = true }
                row.order = index
                row.text = message.text
                row.localOnly = message.localOnly
            } else {
                let row = CoachChatMessage(messageID: message.id, order: index, role: message.role,
                                           text: message.text, localOnly: message.localOnly)
                context.insert(row)
                row.chat = target
                changed = true
            }
        }
        if changed { target.updatedAt = now }
        try? context.save()
        return target
    }

    /// Die Nachrichten für den Bildschirm. Sie gehören zum aktuellen Gespräch und bleiben so für Folgefragen gültig.
    var restoredMessages: [ChatMessage] {
        messages.sorted { $0.order < $1.order }.map {
            ChatMessage(id: $0.messageID, role: ChatMessage.Role(rawValue: $0.roleRaw) ?? .coach,
                        text: $0.text, localOnly: $0.localOnly)
        }
    }
}
