import XCTest
@testable import Forma

/// Logik hinter Today (Overview, Ring-Details): Satz zum Tag, Vergleichspfeile, Reiter-Kennungen, Kapseln.
final class DesignTodayTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000).startOfDay

    private func history(_ make: (Int) -> DayMetrics) -> [DayMetrics] {
        (1...10).map { make($0) }
    }

    // MARK: Kopf

    func testRingKindsHaveDistinctNavigationIDs() {
        XCTAssertEqual(Set(RingKind.allCases.map(\.id)), ["recovery", "sleep", "strain"])
    }

    func testRecoveryArcRunsFromLowerLeftToLowerRight() {
        let start = RecoveryArc.endpoint(fraction: 0, radius: 100)
        let middle = RecoveryArc.endpoint(fraction: 0.5, radius: 100)
        let end = RecoveryArc.endpoint(fraction: 1, radius: 100)
        XCTAssertEqual(start.width, -70.71, accuracy: 0.01)
        XCTAssertEqual(start.height, 70.71, accuracy: 0.01)   // unten links (y zeigt nach unten)
        XCTAssertEqual(middle.width, 0, accuracy: 0.01)
        XCTAssertEqual(middle.height, -100, accuracy: 0.01)   // oben in der Mitte
        XCTAssertEqual(end.width, 70.71, accuracy: 0.01)
        XCTAssertEqual(end.height, 70.71, accuracy: 0.01)     // unten rechts
        XCTAssertEqual(RecoveryArc.endpoint(fraction: 3, radius: 100).width, end.width, accuracy: 0.01)
    }

    func testSleepDebtNoteOnlyFromFifteenMinutes() {
        XCTAssertNil(TodayView.debtNote(0))
        XCTAssertNil(TodayView.debtNote(14 * 60))
        XCTAssertEqual(TodayView.debtNote(79 * 60), "−1:19 h")
    }

    func testRecoveryArcFollowsAvailableWidth() {
        XCTAssertEqual(TodayView.recoverySize(width: 398), 184)   // 430er-Gerät: voll
        XCTAssertEqual(TodayView.recoverySize(width: 343), 183)   // 375er-Gerät
        XCTAssertEqual(TodayView.recoverySize(width: 300), 140)   // Zoom/Split: Kapseln behalten 80 pt
        XCTAssertEqual(TodayView.recoverySize(width: 200), 132)   // Untergrenze
    }

    func testHeaderStacksWhenCapsulesWouldLoseTheirSpace() {
        XCTAssertTrue(TodayView.stacksHeader(width: 288, largeText: false))    // 132 + 2 × 78: zu eng
        XCTAssertFalse(TodayView.stacksHeader(width: 292, largeText: false))   // genau 132 + 2 × 80
        XCTAssertFalse(TodayView.stacksHeader(width: 358, largeText: false))
        XCTAssertTrue(TodayView.stacksHeader(width: 358, largeText: true))
        // Nebeneinander bleiben je Seite mindestens 80 pt.
        for width in stride(from: 292.0, through: 430.0, by: 2) {
            XCTAssertGreaterThanOrEqual((width - TodayView.recoverySize(width: width)) / 2, 80)
        }
    }

    // MARK: Satz zum Tag

    func testInsightNamesLowerRestingHeartRate() {
        let prior = history { DayMetrics(date: day.adding(days: -$0), restingHR: 58) }
        let snapshot = DashboardDay(day: DayMetrics(date: day, restingHR: 54), history: prior)
        XCTAssertEqual(TodayInsight.sentence(for: snapshot),
                       "Dein Ruhepuls liegt 4 Schläge unter deinem 30-Tage-Schnitt.")
    }

    func testInsightUsesHRVWhenPulseIsTypical() {
        let prior = history { DayMetrics(date: day.adding(days: -$0), hrv: 50, restingHR: 58) }
        let snapshot = DashboardDay(day: DayMetrics(date: day, hrv: 60, restingHR: 58), history: prior)
        XCTAssertEqual(TodayInsight.sentence(for: snapshot), "Deine HRV liegt 20 % über deinem 30-Tage-Schnitt.")
    }

    func testInsightWithoutDataDoesNotInventValues() {
        let snapshot = DashboardDay(day: DayMetrics(date: day), history: [])
        XCTAssertEqual(TodayInsight.sentence(for: snapshot), "Für diesen Tag fehlen noch Messungen.")
    }

    func testInsightFallsBackToSteps() {
        let snapshot = DashboardDay(day: DayMetrics(date: day, steps: 8_400), history: [])
        XCTAssertEqual(TodayInsight.sentence(for: snapshot), "Bisher 8.400 Schritte.")
    }

    // MARK: Vergleich mit 30 Tagen

    @MainActor func testComparisonDirection() {
        let whole: (Double) -> String = { Format.number($0) }
        XCTAssertEqual(ComparisonRow.direction(value: 62, baseline: 58, format: whole), 1)
        XCTAssertEqual(ComparisonRow.direction(value: 50, baseline: 58, format: whole), -1)
        // Gleich nach Rundung: kein Pfeil, sonst widerspricht der Pfeil der angezeigten Zahl.
        XCTAssertEqual(ComparisonRow.direction(value: 58.2, baseline: 57.9, format: whole), 0)
        XCTAssertEqual(ComparisonRow.direction(value: nil, baseline: 58, format: whole), 0)
        XCTAssertEqual(ComparisonRow.direction(value: 58, baseline: nil, format: whole), 0)
        XCTAssertEqual(ComparisonRow.direction(value: .nan, baseline: 58, format: whole), 0)
    }

    // MARK: Kapseln und Today

    func testSleepCapsuleClock() {
        XCTAssertEqual(RingDetailView.clock(6 * 3600 + 8 * 60), "6:08")
        XCTAssertEqual(RingDetailView.clock(8 * 3600 + 32 * 60 + 20), "8:32")
        XCTAssertEqual(RingDetailView.clock(-30), "0:00")
    }

    func testTodaySupportsNewCardsAndRetiresMyDayFromExistingLayouts() {
        XCTAssertEqual(TodayTile.storedKinds(for: "activities"), [])
        XCTAssertEqual(TodayTile.storedKinds(for: "sleepPlan"), [.sleepPlan])
        XCTAssertEqual(TodayTile.storedKinds(for: "hydration"), [.hydration])
    }

    func testMissingMeasurementsAreRecognized() {
        XCTAssertFalse(TodayView.hasAnyMeasurement(DayMetrics(date: day)))
        XCTAssertTrue(TodayView.hasAnyMeasurement(DayMetrics(date: day, steps: 10)))
    }

    func testStressSpokenValue() {
        XCTAssertEqual(StressMonitorCard.spokenValue(nil), "Keine Messung")
        XCTAssertEqual(StressMonitorCard.spokenValue(1.24), "1,2 von 3, Mittel")
    }

    // MARK: Runde 3

    func testStrainTargetOnlyWithValidRecovery() throws {
        XCTAssertNil(RingDetailView.strainTarget(strain: 40, recovery: nil))
        let good = try XCTUnwrap(RingDetailView.strainTarget(strain: 40, recovery: 80))
        XCTAssertEqual(good.range, 35...55)
        XCTAssertEqual(good.status, "Im Ziel")
        XCTAssertEqual(RingDetailView.strainTarget(strain: 20, recovery: 80)?.status, "Unter dem Ziel")
        XCTAssertEqual(RingDetailView.strainTarget(strain: 60, recovery: 80)?.status, "Über dem Ziel")
        XCTAssertEqual(RingDetailView.strainTarget(strain: nil, recovery: 20)?.range, 10...25)
        XCTAssertEqual(RingDetailView.strainTarget(strain: nil, recovery: 20)?.status, "Noch keine Belastung")
    }

    func testTodayCardsKeepMetricsVisibleAndReadOldIDs() {
        XCTAssertEqual(TodayTile.requiredVisible, [.metrics])
        XCTAssertEqual(TodayTile.storedKinds(for: "stress"), [.stress])
        XCTAssertEqual(TodayTile.storedKinds(for: "unbekannt"), [])
        XCTAssertEqual(Set(TodayTile.allCases.map(\.title)).count, TodayTile.allCases.count)
    }
}
