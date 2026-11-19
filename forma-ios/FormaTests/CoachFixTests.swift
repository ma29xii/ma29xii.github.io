import Foundation
import XCTest
@testable import Forma

final class CoachFixTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testMissingCoachMeasurementsHaveNoNumbersOrBedtime() {
        let context = makeContext(today: DayMetrics(date: date), history: [], recovery: false, strain: false)
        let summary = CoachEngine.contextSummary(context, for: "Energie, Stress, Schlafbedarf und Schlafschuld?")
        XCTAssertEqual(summary, """
        Energie: keine Messung
        Stress: keine Messung
        Schlafbedarf: keine Messung
        Schlafschuld: keine Messung
        """)
        XCTAssertEqual(CoachEngine.localAnswer(to: "Energie und Stress?", context),
                       "Energie: keine Messung. Stress: keine Messung.")
        XCTAssertEqual(CoachEngine.localAnswer(to: "Wann soll ich ins Bett?", context),
                       "Schlafbedarf: keine Messung.")
        XCTAssertEqual(CoachEngine.localAnswer(to: "Wie hoch ist meine Schlafschuld?", context),
                       "Schlafschuld: keine Messung.")
        XCTAssertEqual(CoachEngine.localAnswer(to: "Energie, Stress, Schlafbedarf und Schlafschuld?", context),
                       "Energie: keine Messung. Stress: keine Messung. Schlafbedarf: keine Messung. Schlafschuld: keine Messung.")
        XCTAssertTrue(CoachEngine.dailyLine(context).contains("Schlafbedarf: keine Messung."))
        XCTAssertFalse(CoachEngine.dailyLine(context).contains("ins Bett gegen"))
    }

    func testMeasuredZeroSleepDebtIsShownWithoutStrainAndNeedIsMissing() {
        let context = makeContext(today: DayMetrics(date: date), history: (1...4).reversed().map { measuredNight(daysAgo: $0) },
                                  recovery: false, strain: false)
        XCTAssertEqual(CoachEngine.contextSummary(context, for: "Schlafbedarf und Schlafschuld?"), """
        Schlafbedarf: keine Messung
        Schlafschuld: 0 min
        """)
    }

    func testMeasuredStrainAndSleepHistoryAllowBedtimeEstimate() {
        let context = makeContext(today: DayMetrics(date: date, activeEnergy: 0),
                                  history: (1...4).reversed().map { measuredNight(daysAgo: $0) },
                                  recovery: false, strain: true)
        XCTAssertEqual(CoachEngine.contextSummary(context, for: "Wie viel Schlaf brauche ich heute Nacht?"),
                       "Schlafbedarf: 8 h")
        XCTAssertTrue(CoachEngine.localAnswer(to: "Wann soll ich ins Bett?", context)
            .contains("Geschätzter Bedarf heute Nacht: 8 h"))
    }

    func testMeasuredEnergyAndStressAreGatedIndependently() {
        let today = DayMetrics(date: date, hrv: 45, restingHR: 60, activeEnergy: 0, sleep: measuredNight().sleep)
        var context = makeContext(today: today, history: [], recovery: true, strain: true)
        context.rhrDelta = nil
        let summary = CoachEngine.contextSummary(context, for: "Energie und Stress?")
        XCTAssertEqual(summary, "Energie: 68/100\nStress: keine Messung")
        context.rhrDelta = 0
        context.today.sleep = nil
        XCTAssertEqual(CoachEngine.contextSummary(context, for: "Energie und Stress?"),
                       "Energie: keine Messung\nStress: 1,4/3 (geschätzt)")
    }

    func testUnknownQuestionAndSampleDataSendNoDailyFields() {
        var context = makeContext(today: DayMetrics(date: date, hrv: 45), history: [], recovery: true, strain: true)
        XCTAssertTrue(CoachEngine.transmittedFields(for: "Hallo, kannst du mir helfen?", context).isEmpty)
        context.isSample = true
        XCTAssertTrue(CoachEngine.contextSummary(context, for: "Wie ist meine HRV?").isEmpty)
        XCTAssertTrue(CoachEngine.transmittedFields(for: "Wie ist meine HRV?", context).isEmpty)
    }

    func testTopicBeyondSentQuestionDoesNotSelectFields() {
        let context = makeContext(today: DayMetrics(date: date, hrv: 45), history: [], recovery: true, strain: true)
        let question = String(repeating: "a", count: 2_000) + " Wie ist meine HRV?"
        XCTAssertTrue(CoachEngine.transmittedFields(for: question, context).isEmpty)
    }

    @MainActor
    func testOverlappingMorningReportIsReservedBeforeEnqueueFinishes() async throws {
        let suite = "Forma.CoachFixTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let day = "2026-04-01"
        var enqueued = 0

        await CoachNotifier.enqueueMorningReportOnce(day: day, defaults: defaults) {
            enqueued += 1
            await CoachNotifier.enqueueMorningReportOnce(day: day, defaults: defaults) {
                enqueued += 1
            }
        }
        XCTAssertEqual(enqueued, 1)
    }

    @MainActor
    func testFailedMorningEnqueueCanRetryAndSuccessPersists() async throws {
        let suite = "Forma.CoachFixTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let day = "2026-04-02"
        var attempts = 0

        await CoachNotifier.enqueueMorningReportOnce(day: day, defaults: defaults) {
            attempts += 1
            throw URLError(.unknown)
        }
        await CoachNotifier.enqueueMorningReportOnce(day: day, defaults: defaults) { attempts += 1 }
        await CoachNotifier.enqueueMorningReportOnce(day: day, defaults: defaults) { attempts += 1 }
        XCTAssertEqual(attempts, 2)
    }

    private func makeContext(today: DayMetrics, history: [DayMetrics], recovery: Bool, strain: Bool) -> CoachEngine.Context {
        CoachEngine.Context(
            scores: DayScores(recovery: 78, sleep: 82, strain: 38, target: 35...55,
                              energy: 68, stress: 1.4, sleepNeed: 8 * 3600, sleepDebt: 0),
            today: today, hrvDelta: 0, rhrDelta: 0, plannedRoutine: nil, trainedToday: false,
            isSample: false, hour: 21, recoveryAvailable: recovery, strainAvailable: strain, history: history
        )
    }

    private func measuredNight(daysAgo: Int = 1) -> DayMetrics {
        let end = date.adding(days: -daysAgo)
        let start = end.addingTimeInterval(-8 * 3600)
        let sleep = SleepNight(start: start, end: end, segments: [.init(stage: .core, start: start, end: end)])
        return DayMetrics(date: end, sleep: sleep)
    }
}
