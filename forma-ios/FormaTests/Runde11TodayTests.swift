import XCTest
@testable import Forma

/// Runde 11 (Maxis Feedback 03) auf Today: Schritte-Halbkreis, Energie-Kachel, Kopf-Varianten.
final class Runde11TodayTests: XCTestCase {
    // T7: Schritte gegen das Coach-Ziel, ohne Ziel nur der Wert.
    func testStepFractionNeedsGoalAndSteps() {
        XCTAssertEqual(TodayView.stepFraction(steps: 6_240, goal: 8_569), 6_240.0 / 8_569, accuracy: 0.0001)
        XCTAssertEqual(TodayView.stepFraction(steps: 6_240, goal: nil), 0)
        XCTAssertEqual(TodayView.stepFraction(steps: nil, goal: 8_569), 0)
        XCTAssertEqual(TodayView.stepFraction(steps: 500, goal: 0), 0)
        XCTAssertGreaterThan(TodayView.stepFraction(steps: 12_000, goal: 8_000), 1)
    }

    func testSpokenStepsWithAndWithoutGoal() {
        XCTAssertEqual(TodayView.spokenSteps(steps: 6_240, goal: 8_569), "6.240 von 8.569")
        XCTAssertEqual(TodayView.spokenSteps(steps: 6_240, goal: nil), "6.240")
        XCTAssertEqual(TodayView.spokenSteps(steps: nil, goal: 8_569), "Keine Messung")
    }

    func testTickArcFillsWholeTicksAndCaps() {
        XCTAssertEqual(TickArc.filledTicks(fraction: 0, count: 41), 0)
        XCTAssertEqual(TickArc.filledTicks(fraction: 0.001, count: 41), 1)   // jeder Fortschritt ist sichtbar
        XCTAssertEqual(TickArc.filledTicks(fraction: 0.5, count: 41), 21)
        XCTAssertEqual(TickArc.filledTicks(fraction: 1, count: 41), 41)
        XCTAssertEqual(TickArc.filledTicks(fraction: 1.4, count: 41), 41)
        XCTAssertEqual(TickArc.filledTicks(fraction: .nan, count: 41), 0)
    }

    // T5: Energie als eigene Kachel mit Zustandsfarbe.
    func testEnergyTileExistsAndColorsByLevel() {
        XCTAssertTrue(TodayTile.allCases.contains(.energy))
        XCTAssertEqual(TodayTile.energy.title, "Energie")
        XCTAssertEqual(EnergyTile.tint(80), Theme.recoveryHigh)
        XCTAssertEqual(EnergyTile.tint(50), Theme.recoveryMid)
        XCTAssertEqual(EnergyTile.tint(10), Theme.older)
    }

    // T6/T7: Die Kachel „Kennzahlen“ ist jetzt die Schritte-Kachel und bleibt immer sichtbar.
    func testStepsTileStaysRequired() {
        XCTAssertEqual(TodayTile.metrics.title, "Schritte")
        XCTAssertEqual(TodayTile.requiredVisible, [.metrics])
    }

    // T2: Kapseln bleiben Standard, Ringe sind die zweite Variante.
    func testHeaderStylesAreStable() {
        XCTAssertEqual(TodayHeaderStyle.capsules.rawValue, "capsules")
        XCTAssertEqual(TodayHeaderStyle(rawValue: "rings"), .rings)
        XCTAssertNil(TodayHeaderStyle(rawValue: "unbekannt"))
    }
}
