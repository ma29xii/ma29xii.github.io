import Foundation
import SwiftData
import XCTest
@testable import Forma

/// F7-02 persönlicher Kontext und gemerkte Fakten, F7-03 gespeicherter Verlauf.
final class F7CoachMemoryTests: XCTestCase {
    private func freshStore() -> UserDefaults {
        let name = "F7CoachMemoryTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    private func personal(facts: [String] = []) -> CoachMemory.Personal {
        CoachMemory.Personal(
            profile: CoachMemory.Profile(age: 31, sex: .male, weightKg: 78, heightCm: 180, baseKcal: 1_820,
                                         mealsPerDay: 1, workdayWake: 6 * 60 + 55, freeDayWake: 8 * 60),
            trends: CoachMemory.trends([
                .init(recovery: 70, sleep: 7 * 3600, strain: 40, steps: 8_000),
                .init(recovery: 50, sleep: 8 * 3600, strain: nil, steps: 10_000)
            ]),
            workouts: ["Push, gestern", "Pull, vor 3 Tagen"], facts: facts)
    }

    // MARK: Kontextblock

    func testContextBlockHasProfileGoalsAndTrends() {
        let block = personal(facts: ["Ich vertrage keine Laktose"]).contextBlock(isSample: false)
        XCTAssertTrue(block.contains("31 Jahre"), block)
        XCTAssertTrue(block.contains("78,0 kg"), block)
        XCTAssertTrue(block.contains("1 Mahlzeit pro Tag (One Meal a Day)"), block)
        XCTAssertTrue(block.contains("Weckzeit Werktage 6:55 Uhr, freie Tage 8:00 Uhr"), block)
        XCTAssertTrue(block.contains("Erholung 60/100"), block)
        XCTAssertTrue(block.contains("Schlaf 7 h 30 min"), block)
        XCTAssertTrue(block.contains("Belastung 40/100"), "Mittel nur über gemessene Tage")
        XCTAssertTrue(block.contains("Push, gestern"), block)
        XCTAssertTrue(block.contains("Ich vertrage keine Laktose"), block)
        XCTAssertLessThanOrEqual(block.count, CoachMemory.maxBlockCharacters)
    }

    func testSampleDataNeverProducesAContextBlock() {
        XCTAssertEqual(personal(facts: ["Geheim"]).contextBlock(isSample: true), "")
    }

    func testTrendsAverageOnlyMeasuredDaysAndNeedAtLeastOneValue() throws {
        XCTAssertNil(CoachMemory.trends([]))
        XCTAssertNil(CoachMemory.trends([.init(), .init()]))
        let trend = try XCTUnwrap(CoachMemory.trends([.init(recovery: 80), .init(), .init(recovery: 60)]))
        XCTAssertEqual(trend.recovery, 70)
        XCTAssertEqual(trend.days, 3)
        XCTAssertNil(trend.sleep)
    }

    func testProfileReadsSettingsAndKeepsDefaultCalorieGoalOut() {
        let store = freshStore()
        XCTAssertNil(CoachMemory.profile(from: store).baseKcal, "Ohne Angaben kein erfundenes Kalorienziel")
        store.set(1_994, forKey: "forma.birthYear")
        store.set(BiologicalSex.male.rawValue, forKey: "forma.sex")
        store.set(78.0, forKey: FoodSettings.bodyWeightKey)
        store.set(180.0, forKey: FoodGoal.heightKey)
        store.set(3, forKey: MealPlanSettings.mealsKey)
        let profile = CoachMemory.profile(from: store, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(profile.mealsPerDay, 3)
        XCTAssertEqual(profile.weightKg, 78)
        XCTAssertNotNil(profile.baseKcal)
        XCTAssertNotNil(profile.age)
    }

    func testWorkoutLinesAreNewestFirstAndLimited() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        let lines = CoachMemory.workoutLines([
            ("Alt", now - 9 * day), ("Heute", now), ("Gestern", now - day), ("Vorgestern", now - 2 * day)
        ], now: now)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Heute, heute")
        XCTAssertEqual(lines[1], "Gestern, gestern")
        XCTAssertEqual(lines[2], "Vorgestern, vor 2 Tagen")
    }

    // MARK: Gemerkte Fakten

    func testFactsCanBeAddedAndDeletedOneByOne() throws {
        let store = freshStore()
        XCTAssertEqual(CoachMemory.remember("Ich vertrage keine Laktose", in: store), "Ich vertrage keine Laktose")
        XCTAssertNil(CoachMemory.remember("ich vertrage keine laktose", in: store), "Doppelte werden nicht gespeichert")
        XCTAssertNil(CoachMemory.remember("   ", in: store))
        CoachMemory.remember("Ich esse nur abends", in: store)
        let facts = CoachMemory.facts(in: store)
        XCTAssertEqual(facts.map(\.text), ["Ich vertrage keine Laktose", "Ich esse nur abends"])

        CoachMemory.forget(try XCTUnwrap(facts.first).id, in: store)
        XCTAssertEqual(CoachMemory.facts(in: store).map(\.text), ["Ich esse nur abends"])
    }

    func testFactsAreLimitedInNumberAndLength() {
        let store = freshStore()
        for index in 0..<(CoachMemory.maxFacts + 5) { CoachMemory.remember("Fakt \(index)", in: store) }
        let facts = CoachMemory.facts(in: store)
        XCTAssertEqual(facts.count, CoachMemory.maxFacts)
        XCTAssertEqual(facts.last?.text, "Fakt \(CoachMemory.maxFacts + 4)")
        let long = CoachMemory.remember(String(repeating: "a", count: 500), in: freshStore())
        XCTAssertEqual(long?.count, CoachMemory.maxFactLength)
    }

    func testExplicitRequestStoresTheRest() {
        let found = CoachMemory.extractFacts(from: "Merk dir: ich vertrage keine Laktose.")
        XCTAssertTrue(found.explicit)
        XCTAssertEqual(found.facts, ["Ich vertrage keine Laktose"])
        let dass = CoachMemory.extractFacts(from: "Bitte merk dir, dass ich abends nur eine Mahlzeit esse")
        XCTAssertTrue(dass.explicit)
        XCTAssertEqual(dass.facts.count, 1)
        XCTAssertTrue(dass.facts[0].contains("eine Mahlzeit"))
    }

    func testStatementsAboutYouAreRememberedWithoutARequest() {
        let found = CoachMemory.extractFacts(from: "Ich vertrage keine Laktose. Was kann ich frühstücken?")
        XCTAssertFalse(found.explicit)
        XCTAssertEqual(found.facts, ["Ich vertrage keine Laktose"])
        XCTAssertTrue(CoachMemory.extractFacts(from: "Wie war mein Schlaf?").facts.isEmpty)
        XCTAssertTrue(CoachMemory.extractFacts(from: "Ich bin müde heute").facts.isEmpty, "Tagesform ist kein Fakt")
    }

    func testRememberFactsSavesDetectedStatements() {
        let store = freshStore()
        let result = CoachMemory.rememberFacts(in: "Ich bin allergisch gegen Nüsse", store: store)
        XCTAssertEqual(result.saved, ["Ich bin allergisch gegen Nüsse"])
        XCTAssertEqual(CoachMemory.facts(in: store).count, 1)
        XCTAssertTrue(CoachMemory.rememberFacts(in: "Ich bin allergisch gegen Nüsse", store: store).saved.isEmpty)
    }

    // MARK: Lokaler Coach

    func testLocalCoachUsesMealsPerDayAndFacts() {
        var context = CoachEngine.Context(
            scores: DayScores(recovery: 70, sleep: 80, strain: 30, target: 30...50, energy: 60, stress: 1,
                              sleepNeed: 8 * 3600, sleepDebt: 0),
            today: DayMetrics(date: .now), hrvDelta: nil, rhrDelta: nil, plannedRoutine: nil,
            trainedToday: false, isSample: false, hour: 12)
        context.personal = personal(facts: ["Ich vertrage keine Laktose"])
        let food = CoachEngine.localAnswer(to: "Was soll ich essen?", context)
        XCTAssertTrue(food.contains("eine Mahlzeit am Tag"), food)
        XCTAssertTrue(food.contains("Laktose"), food)
        let known = CoachEngine.localAnswer(to: "Was weißt du über mich?", context)
        XCTAssertTrue(known.contains("Laktose"), known)
    }

    // MARK: Versand

    func testPersonalContextReachesTheRequestOnlyWhenGiven() async throws {
        let systems = SystemPrompts()
        let answer = #"{"stop_reason":"end_turn","content":[{"type":"text","text":"Okay."}]}"#
        for block in ["", "Persönlicher Kontext:\n- Ich vertrage keine Laktose"] {
            _ = try await CoachProviders.reply(
                context: "", history: [ChatMessage(role: .user, text: "Was soll ich essen?")], personal: block,
                anthropicKey: "fixture-a", openAIKey: nil, maySend: { true }
            ) { request in
                let body = try XCTUnwrap(request.httpBody)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                await systems.record(try XCTUnwrap(json["system"] as? String))
                return Data(answer.utf8)
            }
        }
        let recorded = await systems.all
        XCTAssertEqual(recorded.count, 2)
        XCTAssertFalse(recorded[0].contains("Persönlicher Kontext"))
        XCTAssertTrue(recorded[1].contains("Ich vertrage keine Laktose"))
    }

    // MARK: Verlauf

    @MainActor
    func testChatsArePersistedWithTitleAndKeepOrderAndLocalFlag() throws {
        let container = try ModelContainer(for: CoachChat.self, CoachChatMessage.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let question = ChatMessage(role: .user, text: "  Wie war mein\n Schlaf?  ")
        let answer = ChatMessage(role: .coach, text: "Gut.", localOnly: true)

        XCTAssertNil(CoachChat.sync([ChatMessage(role: .coach, text: "Hallo", localOnly: true)], into: nil, in: context),
                     "Ohne Frage entsteht kein Chat")

        let chat = try XCTUnwrap(CoachChat.sync([question, answer], into: nil, in: context))
        XCTAssertEqual(chat.title, "Wie war mein Schlaf?")
        let followUp = ChatMessage(role: .user, text: "Und gestern?")
        let again = try XCTUnwrap(CoachChat.sync([question, answer, followUp], into: chat, in: context))
        XCTAssertTrue(again === chat)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CoachChat>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CoachChatMessage>()), 3)

        let restored = chat.restoredMessages
        XCTAssertEqual(restored.map(\.id), [question.id, answer.id, followUp.id])
        XCTAssertEqual(restored.map(\.localOnly), [false, true, false])
        XCTAssertEqual(restored.map(\.role), [.user, .coach, .user])
        XCTAssertTrue(restored.allSatisfy { $0.conversationID == CoachProviders.conversationID })
    }

    @MainActor
    func testDeletingAChatRemovesItsMessages() throws {
        let container = try ModelContainer(for: CoachChat.self, CoachChatMessage.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let chat = try XCTUnwrap(CoachChat.sync([ChatMessage(role: .user, text: "Hallo")], into: nil, in: context))
        context.delete(chat)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CoachChat>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CoachChatMessage>()), 0)
    }

    func testChatTitleIsOneShortLine() {
        XCTAssertEqual(CoachChat.title(for: ""), "Neuer Chat")
        XCTAssertEqual(CoachChat.title(for: String(repeating: "x", count: 200)).count, CoachChat.maxTitleLength)
    }
}

private actor SystemPrompts {
    private(set) var all: [String] = []

    func record(_ system: String) { all.append(system) }
}
