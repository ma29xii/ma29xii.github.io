import Foundation
import XCTest
@testable import Forma

final class CoachProvidersTests: XCTestCase {
    func testModelSelectionUsesQuestionType() {
        XCTAssertEqual(CoachProviders.anthropicModel(for: "Was ist mein Tagessatz?"), .haiku)
        XCTAssertEqual(CoachProviders.anthropicModel(for: "Soll ich heute trainieren?"), .haiku)
        XCTAssertEqual(CoachProviders.anthropicModel(for: "Wann soll ich ins Bett?"), .haiku)
        XCTAssertEqual(CoachProviders.anthropicModel(for: "Warum ist mein Schlaf schlecht?"), .sonnet)
        XCTAssertEqual(CoachProviders.anthropicModel(for: "Soll ich heute trainieren und wie sieht die nächste Woche aus?"), .sonnet)
        XCTAssertEqual(CoachProviders.anthropicModel(for: "Erstelle mir einen Trainingsplan für die nächsten vier Wochen."), .sonnet)
    }

    func testFallbackAfterTimeoutSendsOnlyExternalHistory() async throws {
        let calls = ProviderCalls()
        let result = try await CoachProviders.reply(
            context: "Schlaf: 7 h", history: [
                ChatMessage(role: .user, text: "NUR LOKAL", localOnly: true),
                ChatMessage(role: .coach, text: "AUCH LOKAL", localOnly: true),
                ChatMessage(role: .user, text: "Wann soll ich ins Bett?")
            ], anthropicKey: "fixture-a", openAIKey: "fixture-o", maySend: { true }
        ) { request in
            let host = try XCTUnwrap(request.url?.host)
            await calls.record(host)
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap((json["messages"] ?? json["input"]) as? [[String: String]])
            XCTAssertEqual(messages.map { $0["content"] }, ["Wann soll ich ins Bett?"])
            if host == "api.anthropic.com" {
                XCTAssertEqual(json["model"] as? String, CoachProviders.AnthropicModel.haiku.rawValue)
                throw URLError(.timedOut)
            }
            XCTAssertEqual(json["model"] as? String, CoachProviders.openAIModel)
            XCTAssertEqual(json["store"] as? Bool, false)
            return Data(#"{"status":"completed","output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"Geh um 22 Uhr ins Bett. Stell den Wecker auf 7 Uhr. Dieser Satz bleibt draußen."}]}]}"#.utf8)
        }
        let hosts = await calls.hosts
        XCTAssertEqual(hosts, ["api.anthropic.com", "api.openai.com"])
        XCTAssertEqual(result, "Geh um 22 Uhr ins Bett. Stell den Wecker auf 7 Uhr.")
    }

    func testObsoleteSourceInProviderReplyIsRejected() async throws {
        let result = try await CoachProviders.reply(
            context: "", history: [ChatMessage(role: .user, text: "Warum fehlen meine Schlafwerte?")],
            anthropicKey: "fixture-a", openAIKey: "fixture-o", maySend: { true }
        ) { request in
            if request.url?.host == "api.anthropic.com" {
                return Data(#"{"content":[{"type":"text","text":"Schau in Apple Health nach."}]}"#.utf8)
            }
            return Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Schau in Google Health nach."}]}]}"#.utf8)
        }
        XCTAssertEqual(result, "Schau in Google Health nach.")
    }

    func testTruncatedAnthropicReplyFallsBackWithTheSameSelectedFields() async throws {
        let calls = ProviderCalls()
        let context = CoachEngine.Context(
            scores: DayScores(recovery: 78, sleep: 82, strain: 38, target: 35...55,
                              energy: 68, stress: 1.4, sleepNeed: 8 * 3600, sleepDebt: 0),
            today: DayMetrics(date: .now, hrv: 45, restingHR: 60), hrvDelta: 3, rhrDelta: nil,
            plannedRoutine: "Privater Trainingsname", trainedToday: false, isSample: false, hour: 9
        )
        let result = try await CoachProviders.reply(
            context: CoachEngine.contextSummary(context),
            history: [ChatMessage(role: .user, text: "Wie ist meine HRV?")],
            anthropicKey: "fixture-a", openAIKey: "fixture-o", maySend: { true }
        ) { request in
            let host = try XCTUnwrap(request.url?.host)
            await calls.record(host)
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let prompt = try XCTUnwrap((json["system"] ?? json["instructions"]) as? String)
            XCTAssertEqual(prompt.components(separatedBy: "Daten von heute:\n").last, "HRV: 45 ms")
            if host == "api.anthropic.com" {
                return Data(#"{"stop_reason":"max_tokens","content":[{"type":"text","text":"Unvollständige Antwort."}]}"#.utf8)
            }
            XCTAssertEqual(json["store"] as? Bool, false)
            return Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Deine HRV liegt bei 45 ms."}]}]}"#.utf8)
        }
        let hosts = await calls.hosts
        XCTAssertEqual(hosts, ["api.anthropic.com", "api.openai.com"])
        XCTAssertEqual(result, "Deine HRV liegt bei 45 ms.")
        XCTAssertEqual(CoachEngine.transmittedFields(for: "Wie ist meine HRV?", context), ["HRV"])
    }

    func testTruncatedAnthropicReplyWithoutFallbackThrows() async {
        do {
            _ = try await CoachProviders.reply(
                context: "", history: [ChatMessage(role: .user, text: "Wann soll ich ins Bett?")],
                anthropicKey: "fixture-a", openAIKey: nil, maySend: { true }
            ) { _ in
                Data(#"{"stop_reason":"max_tokens","content":[{"type":"text","text":"Unvollständige Antwort."}]}"#.utf8)
            }
            XCTFail("Eine abgeschnittene Antwort darf nicht angezeigt werden.")
        } catch {
            XCTAssertEqual(error as? CoachProviders.ReplyError, .invalidResponse)
        }
    }

    func testRevokedConsentStopsFallback() async {
        let consent = LockedConsent()
        do {
            _ = try await CoachProviders.reply(
                context: "", history: [ChatMessage(role: .user, text: "Hallo")],
                anthropicKey: "fixture-a", openAIKey: "fixture-o", maySend: { consent.allowed }
            ) { request in
                XCTAssertEqual(request.url?.host, "api.anthropic.com")
                consent.revoke()
                throw URLError(.networkConnectionLost)
            }
            XCTFail("Widerruf muss die Anfrage abbrechen")
        } catch is CancellationError {
        } catch {
            XCTFail("Erwartet wurde CancellationError")
        }
    }

    func testCurrentLocalMessageNeverTriggersAnOlderExternalMessage() async {
        do {
            _ = try await CoachProviders.reply(
                context: "", history: [
                    ChatMessage(role: .user, text: "Alt"),
                    ChatMessage(role: .user, text: "Lokal", localOnly: true)
                ], anthropicKey: "fixture-a", openAIKey: "fixture-o", maySend: { true }
            ) { _ in
                XCTFail("Hier darf keine Anfrage ausgelöst werden")
                return Data()
            }
            XCTFail("Keine externe Antwort erwartet")
        } catch {
            XCTAssertEqual(error as? CoachProviders.ReplyError, .missingQuestion)
        }
    }

    func testParserAcceptsOptionalNonemptyKeys() throws {
        let keys = try BundledKeys.parse(Data(#"{"anthropic":" fixture-a ","openai":"fixture-o"}"#.utf8))
        XCTAssertEqual(keys.anthropic, .set("fixture-a"))
        XCTAssertEqual(keys.openai, .set("fixture-o"))
        let openAIOnly = try BundledKeys.parse(Data(#"{"openai":"fixture-o"}"#.utf8))
        XCTAssertEqual(openAIOnly.anthropic, .keep)
        XCTAssertEqual(openAIOnly.openai, .set("fixture-o"))
    }

    func testParserHandlesEmptyAndInvalidBundles() throws {
        let empty = try BundledKeys.parse(Data(#"{"openai":null,"anthropic":"  "}"#.utf8))
        XCTAssertEqual(empty.anthropic, .keep)
        XCTAssertEqual(empty.openai, .remove)
        XCTAssertNoThrow(try BundledKeys.parse(Data("{}".utf8)))
        XCTAssertThrowsError(try BundledKeys.parse(Data()))
        XCTAssertThrowsError(try BundledKeys.parse(Data(#"{"anthropic":12}"#.utf8)))
        XCTAssertThrowsError(try BundledKeys.parse(Data(#"{"anthropic": "#.utf8)))
    }

    func testBundleKeepsOmittedAccountAndDeletesExplicitNull() throws {
        let keys = try BundledKeys.parse(Data(#"{"openai":null}"#.utf8))
        let anthropic = BundledKeys.anthropicAccount
        let openAI = BundledKeys.openAIAccount
        var stored = [anthropic: "fixture-a", openAI: "fixture-o"]
        var touched: [String] = []

        XCTAssertTrue(keys.apply { value, account in
            touched.append(account)
            stored[account] = value
            return true
        })
        XCTAssertEqual(touched, [openAI])
        XCTAssertEqual(stored, [anthropic: "fixture-a"])
    }
}

private actor ProviderCalls {
    private(set) var hosts: [String] = []

    func record(_ host: String) {
        hosts.append(host)
    }
}

private final class LockedConsent: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true

    var allowed: Bool { lock.withLock { value } }

    func revoke() {
        lock.withLock { value = false }
    }
}
