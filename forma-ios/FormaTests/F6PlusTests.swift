import XCTest
@testable import Forma

final class F6PlusTests: XCTestCase {
    private let calendar = Calendar.forma

    func testGroupsCoverAllTilesWithoutDuplicates() {
        XCTAssertEqual(PlusAction.capture, [.track, .water, .weight, .mood, .caffeine])
        XCTAssertEqual(PlusAction.now, [.training, .fasting, .plan, .breathe, .sleepPlan, .askCoach])
        XCTAssertEqual(Set(PlusAction.tiles).count, PlusAction.tiles.count)
        XCTAssertEqual(PlusAction.tiles.count, PlusAction.capture.count + PlusAction.now.count)
    }

    func testLevelsStayBetweenOneAndFive() {
        XCTAssertEqual(PlusLogic.clampLevel(0), 1)
        XCTAssertEqual(PlusLogic.clampLevel(3), 3)
        XCTAssertEqual(PlusLogic.clampLevel(9), 5)
        let entry = MoodEntry(mood: -2, energy: 12)
        XCTAssertEqual(entry.mood, 1)
        XCTAssertEqual(entry.energy, 5)
    }

    func testCaffeineKindsAndEntry() {
        XCTAssertEqual(CaffeineKind.cup.milligrams, 95)
        XCTAssertEqual(CaffeineKind.espresso.milligrams, 63)
        let entry = CaffeineEntry(kind: .espresso)
        XCTAssertEqual(entry.kind, "espresso")
        XCTAssertEqual(entry.milligrams, 63)
    }

    func testCaffeineTodayCountsOnlyTheSameDay() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15))!
        let morning = calendar.date(byAdding: .hour, value: -6, to: now)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let total = PlusLogic.caffeineToday([(morning, 95), (now, 63), (yesterday, 95)], now: now, calendar: calendar)
        XCTAssertEqual(total, 158)
        XCTAssertEqual(PlusLogic.caffeineToday([], now: now, calendar: calendar), 0)
    }

    func testCaffeineRemainingHalvesAfterFiveHours() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let five = now.addingTimeInterval(-5 * 3600)
        XCTAssertEqual(PlusLogic.caffeineRemaining([(now, 100)], now: now), 100, accuracy: 0.001)
        XCTAssertEqual(PlusLogic.caffeineRemaining([(five, 100)], now: now), 50, accuracy: 0.001)
        // Eine Aufnahme in der Zukunft zählt voll, nicht mehr als 100 %.
        XCTAssertEqual(PlusLogic.caffeineRemaining([(now.addingTimeInterval(3600), 100)], now: now), 100, accuracy: 0.001)
    }

    func testStaggerIsCapped() {
        XCTAssertEqual(FormaMotion.stagger(-3), 0)
        XCTAssertEqual(FormaMotion.stagger(2), 0.08, accuracy: 0.0001)
        XCTAssertEqual(FormaMotion.stagger(40), FormaMotion.stagger(8), accuracy: 0.0001)
    }
}
