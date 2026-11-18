import Foundation
import XCTest
@testable import Forma

/// Texte im Profil: Google-Status und Body-Zusammenfassung.
final class DesignRestTests: XCTestCase {
    private let now = Calendar.forma.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 9, minute: 30))!

    func testGoogleStatusWords() {
        XCTAssertEqual(GoogleStatus(.disconnected, now: now).title, "Nicht verbunden")
        XCTAssertEqual(GoogleStatus(.disconnected, now: now).tone, .off)
        XCTAssertTrue(GoogleStatus(.connecting, now: now).isBusy)
        XCTAssertNotNil(GoogleStatus(.notConfigured, now: now).detail)

        let failed = GoogleStatus(.failed("Freigabe abgelaufen"), now: now)
        XCTAssertEqual(failed.tone, .problem)
        XCTAssertEqual(failed.detail, "Freigabe abgelaufen")

        XCTAssertEqual(GoogleStatus(.connected(lastSync: nil), now: now).title, "Verbunden")
        let synced = GoogleStatus(.connected(lastSync: now.addingTimeInterval(-15 * 60)), now: now)
        XCTAssertEqual(synced.tone, .good)
        XCTAssertTrue(synced.title.hasPrefix("Verbunden · heute, "))
    }

    func testStampNamesTodayYesterdayOrDate() {
        XCTAssertTrue(ProfileText.stamp(now.addingTimeInterval(-3600), now: now).hasPrefix("heute, "))
        XCTAssertTrue(ProfileText.stamp(now.addingTimeInterval(-24 * 3600), now: now).hasPrefix("gestern, "))
        XCTAssertTrue(ProfileText.stamp(now.addingTimeInterval(-3 * 24 * 3600), now: now).hasPrefix("16.11"))
    }

    /// Gegenprüfung 01, Punkt 5: Eine abgebrochene Frage geht bei der nächsten Online-Frage nicht mit raus.
    func testCancelledQuestionStaysOutOfLaterOnlineRequest() async throws {
        let cancelled = ChatMessage(role: .user, text: "ABGEBROCHEN")
        var messages = [cancelled, ChatMessage(role: .coach, text: "Abgebrochen.", localOnly: true)]
        messages.markLocalOnly(cancelled.id)
        XCTAssertTrue(messages[0].localOnly)
        messages.append(ChatMessage(role: .user, text: "Wann soll ich ins Bett?"))

        let sent = SentBodies()
        _ = try? await CoachProviders.reply(
            context: "Schlaf: 7 h", history: messages,
            anthropicKey: "fixture-a", openAIKey: nil, maySend: { true }
        ) { request in
            await sent.add(String(decoding: request.httpBody ?? Data(), as: UTF8.self))
            throw URLError(.timedOut)
        }
        let bodies = await sent.all
        XCTAssertFalse(bodies.isEmpty)
        XCTAssertFalse(bodies.contains { $0.contains("ABGEBROCHEN") })
        XCTAssertTrue(bodies.allSatisfy { $0.contains("Wann soll ich ins Bett?") })
    }

    func testBodySummaryLeavesOutMissingValues() {
        XCTAssertNil(ProfileText.bodySummary(birthYear: 0, sex: .unknown, weightKg: 0, unit: .kg))
        XCTAssertEqual(ProfileText.bodySummary(birthYear: 1994, sex: .unknown, weightKg: 0, unit: .kg), "1994")
        XCTAssertEqual(ProfileText.bodySummary(birthYear: 1994, sex: .male, weightKg: 78.5, unit: .kg), "1994 · Männlich · 78,5 kg")
        XCTAssertEqual(ProfileText.bodySummary(birthYear: 0, sex: .female, weightKg: .nan, unit: .lb), "Weiblich")
    }
}

private actor SentBodies {
    private(set) var all: [String] = []
    func add(_ body: String) { all.append(body) }
}
