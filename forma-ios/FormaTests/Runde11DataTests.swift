import XCTest
@testable import Forma

final class Runde11DataTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_800_000_000).startOfDay

    func testStepGoalNeedsSevenDistinctDaysWithValidMeasurements() {
        let validDays = stepDays(6, steps: 8_000)
        let history = validDays + [validDays[0], day(7, steps: nil), day(8, steps: .nan),
                                   day(9, steps: -1), day(10, steps: .infinity), day(11, steps: 150_001)]
        XCTAssertNil(StepGoal.target(on: today, history: history))

        // A measured zero is a valid day and contributes to the average.
        XCTAssertEqual(StepGoal.target(on: today, history: history + [day(12, steps: 0)]), 6_850)
    }

    func testStepGoalUsesThe28CompletedCalendarDaysAndRoundsTo50() {
        let history = stepDays(6, steps: 8_530) + [day(28, steps: 8_530), day(29, steps: 15_000),
                                                  day(0, steps: 2_000), day(-1, steps: 15_000)]
        XCTAssertEqual(StepGoal.target(on: today, history: history), 8_550)
    }

    func testStepGoalRisesWithHighRecoveryAndGoodSleep() {
        let history = stepDays(7, steps: 8_000)
        XCTAssertEqual(StepGoal.target(on: today, history: history, recovery: 80, sleepScore: 90), 8_800)
        XCTAssertEqual(StepGoal.target(on: today, history: history, recovery: 80, sleepScore: 70), 8_000)
        XCTAssertEqual(StepGoal.target(on: today, history: history, sleepScore: 90), 8_000)
    }

    func testStepGoalFallsWithLowRecoverySleepDebtOrHighStrainTarget() {
        let history = stepDays(7, steps: 8_000)
        XCTAssertEqual(StepGoal.target(on: today, history: history, recovery: 20), 7_200)
        XCTAssertEqual(StepGoal.target(on: today, history: history, recovery: 80, sleepScore: 90,
                                      sleepDebt: 3_600), 7_200)
        XCTAssertEqual(StepGoal.target(on: today, history: history, strainTarget: 35...55), 7_600)
        XCTAssertEqual(StepGoal.target(on: today, history: history, recovery: 80, sleepScore: 90,
                                      strainTarget: 35...55), 8_400)
    }

    func testStepGoalStaysWithinLimits() {
        XCTAssertEqual(StepGoal.target(on: today, history: stepDays(7, steps: 2_500)), 4_000)
        XCTAssertEqual(StepGoal.target(on: today, history: stepDays(7, steps: 20_000)), 16_000)
    }

    func testFoodGoalsUseWeightAndTotalCalorieTarget() {
        let goal = FoodGoal(weightKg: 80, heightCm: 180, age: 30, sex: .male, activeEnergy: 300)
        XCTAssertEqual(goal.proteinGrams, 144, accuracy: 0.001)
        XCTAssertEqual(goal.carbGrams, 220, accuracy: 0.001)
        XCTAssertEqual(goal.fiberGrams, 29.12, accuracy: 0.001)
    }

    func testMissingWeightFallsBackTo120GramsOfProtein() {
        for weight in [0.0, -1, .nan, .infinity] {
            let goal = FoodGoal(weightKg: weight, heightCm: 180, age: 30, sex: .male, activeEnergy: nil)
            XCTAssertEqual(goal.proteinGrams, 120)
            XCTAssertEqual(goal.carbGrams, 230, accuracy: 0.001)
            XCTAssertEqual(goal.fiberGrams, 28, accuracy: 0.001)
        }
    }

    func testKnownWeightIsUsedWithoutOtherProfileData() {
        let goal = FoodGoal(weightKg: 70, heightCm: 0, age: nil, sex: .unknown, activeEnergy: nil)
        XCTAssertEqual(goal.proteinGrams, 126, accuracy: 0.001)
    }

    func testCarbohydrateGoalDoesNotGoBelowZero() {
        let goal = FoodGoal(weightKg: 250, heightCm: 0, age: nil, sex: .unknown, activeEnergy: nil)
        XCTAssertEqual(goal.carbGrams, 0)
    }

    func testCoachAnswersStepGoalQuestionsWithTheGermanFormattedTarget() {
        let context = coachContext(history: stepDays(7, steps: 8_530))
        XCTAssertEqual(CoachEngine.localAnswer(to: "Wie viele Schritte soll ich heute gehen?", context),
                       "Heute passen etwa 8.550 Schritte.")
    }

    func testCoachExplainsMissingStepHistory() {
        let answer = CoachEngine.localAnswer(to: "Was ist mein Schrittziel?", coachContext(history: []))
        XCTAssertTrue(answer.contains("mindestens sieben Tagen"))
    }

    func testOnlineCoachOnlyIncludesStepGoalForRelevantQuestions() {
        let context = coachContext(history: stepDays(7, steps: 8_530))
        XCTAssertEqual(CoachEngine.transmittedFields(for: "Was ist mein Schrittziel?", context), ["Schrittziel"])
        XCTAssertEqual(CoachEngine.contextSummary(context, for: "Was ist mein Schrittziel?"),
                       "Schrittziel: 8.550 Schritte")
        XCTAssertFalse(CoachEngine.transmittedFields(for: "Wie ist meine Erholung?", context).contains("Schrittziel"))
        XCTAssertTrue(CoachEngine.transmittedFields(for: "Wie viele Schritte habe ich heute gemacht?", context).isEmpty)
        var sample = context
        sample.isSample = true
        XCTAssertTrue(CoachEngine.transmittedFields(for: "Was ist mein Schrittziel?", sample).isEmpty)
    }

    @MainActor
    func testSampleDataHubAndCoachShareTheStepGoal() throws {
        let suite = "Forma.Runde11Data.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = today
        let hub = DataHub(googleService: UnconfiguredGoogle(), defaults: defaults, cacheURL: nil,
                          now: { now }, isUITest: true)
        let goal = try XCTUnwrap(hub.stepGoalToday)
        XCTAssertTrue((4_000...16_000).contains(goal))
        XCTAssertEqual(goal % 50, 0)
        let context = CoachEngine.Context(scores: hub.scores, today: hub.today, hrvDelta: nil, rhrDelta: nil,
                                          plannedRoutine: nil, trainedToday: false, isSample: true, hour: 12,
                                          recoveryAvailable: hub.availability.recovery, history: hub.history)
        XCTAssertEqual(context.stepGoalToday, goal)
    }

    private func day(_ daysAgo: Int, steps: Double?) -> DayMetrics {
        DayMetrics(date: today.adding(days: -daysAgo), steps: steps)
    }

    private func stepDays(_ count: Int, steps: Double) -> [DayMetrics] {
        (1...count).reversed().map { day($0, steps: steps) }
    }

    private func coachContext(history: [DayMetrics]) -> CoachEngine.Context {
        CoachEngine.Context(scores: DayScores(recovery: 55, sleep: 0, strain: 0, target: 25...40,
                                              energy: 50, stress: 1, sleepNeed: 28_000, sleepDebt: 0),
                            today: DayMetrics(date: today), hrvDelta: nil, rhrDelta: nil, plannedRoutine: nil,
                            trainedToday: false, isSample: false, hour: 12, history: history)
    }
}

@MainActor
private struct UnconfiguredGoogle: GoogleHealthImporting {
    let isConfigured = false
    let accountID: String? = nil

    func restore() throws {}
    func connect() async throws { throw GoogleHealthError.invalidResponse }
    func disconnect() throws -> Task<GoogleRevocation, Never>? { nil }
    func load(from: Date, until: Date, calendar: Calendar, includePulse: Bool) async throws -> GoogleHealthService.Import {
        throw GoogleHealthError.invalidResponse
    }
    func loadPulse(from: Date, until: Date, calendar: Calendar) async throws -> [HourlyMetrics] {
        throw GoogleHealthError.invalidResponse
    }
}
