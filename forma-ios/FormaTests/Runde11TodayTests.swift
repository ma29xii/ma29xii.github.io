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

    func testCapsuleHeaderReservesRoomForBothSideMetrics() {
        XCTAssertTrue(TodayView.stacksHeader(width: 291, largeText: false))
        XCTAssertFalse(TodayView.stacksHeader(width: 292, largeText: false))
        XCTAssertTrue(TodayView.stacksHeader(width: 400, largeText: true))
        XCTAssertEqual(TodayView.recoverySize(width: 292), 132)
        XCTAssertEqual(TodayView.recoverySize(width: 360), 184)
    }

    func testEnergyChangesOnlyCompareAdjacentMeasuredHours() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let values: [(Int, Int?)] = [(0, 50), (1, 60), (2, 56), (3, nil), (4, 88), (7, 20)]
        let samples = values.map { hour, energy in
            HourlyEstimate(at: start.addingTimeInterval(Double(hour) * 3600), strain: nil, stress: nil, energy: energy)
        }
        let changes = DaySignals.energyChanges(samples)
        XCTAssertEqual(changes?.gained, 10)
        XCTAssertEqual(changes?.spent, 4)
        XCTAssertNil(DaySignals.energyChanges([samples[0], samples[3]]))
    }

    func testFoodCardAppearsInExistingTodayLayout() {
        let arrangement = TileArrangement<TodayTile>(storage: "energy,metrics|weekly")
        XCTAssertTrue(arrangement.visible.contains(.food))
        XCTAssertEqual(Array(arrangement.visible.prefix(2)), [.energy, .metrics])
        XCTAssertTrue(arrangement.hidden.contains(.weekly))
    }
}
