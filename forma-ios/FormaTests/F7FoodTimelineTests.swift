import Foundation
import XCTest
@testable import Forma

/// F7-05: Zeitleiste und Balken des neuen Food-Tabs.
final class F7FoodTimelineTests: XCTestCase {
    private static let day = Calendar.forma.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    private func logged(_ id: String, hour: Int, kcal: Double? = 300) -> FoodTimelineItem {
        let time = Calendar.forma.date(bySettingHour: hour, minute: 0, second: 0, of: Self.day) ?? Self.day
        return FoodTimelineItem(id: id, kind: .logged, time: time, title: id, kcal: kcal)
    }

    func testSlotTimesFollowTheDay() {
        XCTAssertEqual(FoodTimeline.slotHour(.breakfast), 8)
        XCTAssertEqual(FoodTimeline.slotHour(.dinner), 19)
        let time = FoodTimeline.slotTime(meal: .lunch, day: Self.day)
        XCTAssertEqual(Calendar.forma.component(.hour, from: time), 12)
        XCTAssertTrue(Calendar.forma.isDate(time, inSameDayAs: Self.day))
    }

    func testPlannedGhostsSkipLoggedDishesAndSitAtTheirSlot() throws {
        let dish = try XCTUnwrap(MealPlanLogic.recipes.first)
        let open = try XCTUnwrap(try MealPlanLogic.item(for: dish, day: Self.day, meal: .dinner).entry)
        let doneItem = try MealPlanLogic.item(for: dish, day: Self.day, meal: .lunch)
        doneItem.loggedAt = .now
        let done = try XCTUnwrap(doneItem.entry)
        let ghosts = FoodTimeline.planned([open, done])
        XCTAssertEqual(ghosts.count, 1)
        XCTAssertTrue(ghosts[0].isPlanned)
        XCTAssertEqual(ghosts[0].title, dish.name)
        XCTAssertEqual(Calendar.forma.component(.hour, from: ghosts[0].time), 19)
    }

    func testMergeSortsByTimeAndPutsEatenBeforePlannedAtTheSameTime() {
        let ghost = FoodTimelineItem(id: "plan-a", kind: .planned, time: logged("x", hour: 19).time, title: "Plan", kcal: 900)
        let merged = FoodTimeline.merge([logged("b", hour: 19), logged("a", hour: 8)], [ghost])
        XCTAssertEqual(merged.map(\.id), ["a", "b", "plan-a"])
    }

    func testOnlyASingleMealIsProminentForOneMealADay() {
        XCTAssertTrue(FoodTimeline.isProminent(itemCount: 1, mealsPerDay: 1))
        XCTAssertFalse(FoodTimeline.isProminent(itemCount: 2, mealsPerDay: 1))
        XCTAssertFalse(FoodTimeline.isProminent(itemCount: 1, mealsPerDay: 3))
    }

    // MARK: Balken

    func testBarSegmentsShareTheFilledPartByEnergy() {
        // 100 g Protein = 400 kcal, 100 g Kohlenhydrate = 400 kcal, 20 g Fett = 180 kcal.
        let segments = FoodMacroBar.segments(protein: 100, carbs: 100, fat: 20, consumed: 1_000, target: 2_000)
        XCTAssertEqual(segments.map(\.kind), [.protein, .carbs, .fat])
        XCTAssertEqual(segments.reduce(0) { $0 + $1.fraction }, 0.5, accuracy: 0.0001)
        XCTAssertEqual(segments[0].fraction, segments[1].fraction, accuracy: 0.0001)
        XCTAssertLessThan(segments[2].fraction, segments[0].fraction)
    }

    func testBarNeverExceedsTheFullWidth() {
        let segments = FoodMacroBar.segments(protein: 100, carbs: 200, fat: 50, consumed: 5_000, target: 2_000)
        XCTAssertEqual(segments.reduce(0) { $0 + $1.fraction }, 1, accuracy: 0.0001)
    }

    func testBarWithoutMacrosFillsOneNeutralSegment() {
        let segments = FoodMacroBar.segments(protein: 0, carbs: 0, fat: 0, consumed: 500, target: 2_000)
        XCTAssertEqual(segments, [FoodMacroBar.Segment(kind: .unknown, fraction: 0.25)])
    }

    func testBarIsEmptyWithoutTargetOrFood() {
        XCTAssertTrue(FoodMacroBar.segments(protein: 10, carbs: 10, fat: 10, consumed: 0, target: 2_000).isEmpty)
        XCTAssertTrue(FoodMacroBar.segments(protein: 10, carbs: 10, fat: 10, consumed: 500, target: 0).isEmpty)
        XCTAssertTrue(FoodMacroBar.segments(protein: .nan, carbs: .infinity, fat: -5, consumed: .nan, target: 2_000).isEmpty)
    }
}
