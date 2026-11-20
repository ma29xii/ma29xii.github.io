import Foundation
import XCTest
@testable import Forma

final class F6MealPlanTests: XCTestCase {
    private static let day = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Lokaler Rückfall

    func testEveryDishHitsItsCalorieTargetWithinFifteenPercent() {
        for meals in MealPlanSettings.range {
            for kcal in stride(from: 1_500.0, through: 3_200.0, by: 100) {
                let request = MealPlanRequest(days: 7, meals: meals, kcal: kcal, protein: 150, carbs: 200)
                let plan = MealPlanLogic.fallbackPlan(request)
                let slots = MealPlanLogic.slots(meals)
                for row in plan {
                    for (index, dish) in row.enumerated() {
                        let target = kcal * slots[index].share
                        XCTAssertLessThanOrEqual(abs(dish.totalKcal - target) / target, MealPlanLogic.tolerance,
                                                 "\(dish.name) bei \(kcal) kcal, \(meals) Mahlzeiten")
                    }
                }
            }
        }
    }

    func testOneMealPerDayGivesOneDishPerDayInTheEvening() {
        let plan = MealPlanLogic.fallbackPlan(MealPlanRequest(days: 7, meals: 1, kcal: 2_000, protein: 150, carbs: 200))
        XCTAssertEqual(plan.count, 7)
        XCTAssertTrue(plan.allSatisfy { $0.count == 1 })
        XCTAssertEqual(MealPlanLogic.slots(1).map(\.meal), [.dinner])
        XCTAssertEqual(MealPlanSettings.defaultMeals, 1)
    }

    func testTwoAndThreeMealsUseTheirSlots() {
        XCTAssertEqual(MealPlanLogic.slots(2).map(\.meal), [.lunch, .dinner])
        XCTAssertEqual(MealPlanLogic.slots(3).map(\.meal), [.breakfast, .lunch, .dinner])
        for meals in MealPlanSettings.range {
            XCTAssertEqual(MealPlanLogic.slots(meals).map(\.share).reduce(0, +), 1, accuracy: 0.0001)
        }
        XCTAssertEqual(MealPlanSettings.clamp(0), 1)
        XCTAssertEqual(MealPlanSettings.clamp(9), 3)
    }

    func testOneWeekOfOneMealHasNoRepeatedDish() {
        let plan = MealPlanLogic.fallbackPlan(MealPlanRequest(days: 7, meals: 1, kcal: 2_200, protein: 150, carbs: 200))
        let names = plan.flatMap { $0.map(\.name) }
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testRecipeListIsBigEnoughAndSane() {
        XCTAssertGreaterThanOrEqual(MealPlanLogic.recipes.count, 12)
        XCTAssertEqual(Set(MealPlanLogic.recipes.map(\.name)).count, MealPlanLogic.recipes.count)
        for recipe in MealPlanLogic.recipes {
            XCTAssertFalse(recipe.ingredients.isEmpty)
            XCTAssertGreaterThan(recipe.protein * 4 / recipe.kcal, 0.2, "\(recipe.name) soll proteinreich sein")
        }
    }

    func testReplacementAvoidsTheCurrentDish() {
        let first = MealPlanLogic.fallbackDish(targetKcal: 1_800)
        let next = MealPlanLogic.fallbackDish(targetKcal: 1_800, avoid: [first.name])
        XCTAssertNotEqual(first.name, next.name)
        XCTAssertLessThanOrEqual(abs(next.totalKcal - 1_800) / 1_800, MealPlanLogic.tolerance)
    }

    func testBrokenTargetStillGivesADish() {
        XCTAssertGreaterThan(MealPlanLogic.fallbackDish(targetKcal: .nan).totalKcal, 0)
        XCTAssertGreaterThan(MealPlanLogic.fallbackDish(targetKcal: -5).totalKcal, 0)
    }

    // MARK: JSON

    private static let json = """
    {"dishes":[
      {"name":" Hähnchen-Reis-Bowl ","ingredients":["Hähnchen"," Reis ","Brokkoli"],"kcal":1850,"protein":150,"carbs":180},
      {"name":"Lachs mit Kartoffeln","ingredients":["Lachs","Kartoffeln"],"kcal":1900,"protein":120,"carbs":140}
    ]}
    """

    func testDecodesDishesAndTrimsText() throws {
        let dishes = try MealPlanLogic.parse(Self.json, expected: 2)
        XCTAssertEqual(dishes.map(\.name), ["Hähnchen-Reis-Bowl", "Lachs mit Kartoffeln"])
        XCTAssertEqual(dishes[0].ingredients, ["Hähnchen", "Reis", "Brokkoli"])
        XCTAssertEqual(dishes[0].kcal, 1_850)
        XCTAssertEqual(dishes[0].portions, 1)
    }

    func testRejectsWrongCountAndImplausibleValues() {
        XCTAssertThrowsError(try MealPlanLogic.parse(Self.json, expected: 3))
        XCTAssertThrowsError(try MealPlanLogic.parse("kein JSON", expected: 1))
        let noName = #"{"dishes":[{"name":" ","ingredients":["a"],"kcal":800,"protein":50,"carbs":60}]}"#
        let hugeKcal = #"{"dishes":[{"name":"x","ingredients":["a"],"kcal":90000,"protein":50,"carbs":60}]}"#
        let noIngredients = #"{"dishes":[{"name":"x","ingredients":[],"kcal":800,"protein":50,"carbs":60}]}"#
        let missing = #"{"dishes":[{"name":"x","ingredients":["a"],"kcal":800}]}"#
        for bad in [noName, hugeKcal, noIngredients, missing] {
            XCTAssertThrowsError(try MealPlanLogic.parse(bad, expected: 1), bad)
        }
    }

    func testOffTargetAIDishIsReplacedLocally() throws {
        let dishes = try MealPlanLogic.parse(Self.json, expected: 2)
        // Ziel 1.850 kcal: erstes Gericht trifft, zweites (1.900) auch; bei 1.200 würden beide ersetzt.
        let request = MealPlanRequest(days: 2, meals: 1, kcal: 1_850, protein: 150, carbs: 200)
        let kept = MealPlanLogic.reconcile(dishes, request: request)
        XCTAssertEqual(kept.flatMap { $0.map(\.name) }, dishes.map(\.name))
        let low = MealPlanRequest(days: 2, meals: 1, kcal: 1_200, protein: 150, carbs: 200)
        let replaced = MealPlanLogic.reconcile(dishes, request: low)
        for row in replaced {
            XCTAssertLessThanOrEqual(abs(row[0].totalKcal - 1_200) / 1_200, MealPlanLogic.tolerance)
        }
    }

    func testRequestTextNamesGoalsAndAvoidedDishes() {
        let request = MealPlanRequest(days: 3, meals: 1, kcal: 2_000, protein: 140, carbs: 180, avoid: ["Pizza"])
        let text = MealPlanLogic.userMessage(for: request)
        XCTAssertTrue(text.contains("2000 kcal"))
        XCTAssertTrue(text.contains("Pizza"))
        XCTAssertTrue(MealPlanLogic.system(for: request).contains("\"dishes\""))
    }

    // MARK: Einwilligung

    func testSampleDataAndUITestNeverSend() {
        for consent in [false, true] {
            XCTAssertEqual(MealPlanLogic.source(isSample: true, isUITest: false, hasKey: true, consent: consent), .local)
            XCTAssertEqual(MealPlanLogic.source(isSample: false, isUITest: true, hasKey: true, consent: consent), .local)
            XCTAssertEqual(MealPlanLogic.source(isSample: false, isUITest: false, hasKey: false, consent: consent), .local)
        }
        XCTAssertEqual(MealPlanLogic.source(isSample: false, isUITest: false, hasKey: true, consent: false), .askConsent)
        XCTAssertEqual(MealPlanLogic.source(isSample: false, isUITest: false, hasKey: true, consent: true), .online)
    }

    func testNothingIsSentWithoutConsent() async {
        let request = MealPlanRequest(days: 1, meals: 1, kcal: 2_000, protein: 150, carbs: 200)
        do {
            _ = try await MealPlanLogic.onlinePlan(request, anthropicKey: "test", openAIKey: nil,
                                                   maySend: { false }, send: { _ in
                XCTFail("Ohne Einwilligung darf nichts gesendet werden")
                return Data()
            })
            XCTFail("Erwartet: Abbruch")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    // MARK: Plan-Einträge

    func testDishBecomesPlanItemWithScaledNutrientsAndIngredients() throws {
        var dish = try XCTUnwrap(MealPlanLogic.recipes.first)
        dish.portions = 1.5
        let item = try MealPlanLogic.item(for: dish, day: Self.day, meal: .dinner)
        let entry = try XCTUnwrap(item.entry)
        XCTAssertTrue(MealPlanLogic.isCoachDish(entry.product))
        XCTAssertEqual(try XCTUnwrap(entry.kcal), dish.kcal * 1.5, accuracy: 0.01)
        XCTAssertEqual(entry.nutrients?.values[.protein] ?? 0, dish.protein * 1.5, accuracy: 0.01)
        XCTAssertEqual(entry.nutrients?.values[.carbohydrates] ?? 0, dish.carbs * 1.5, accuracy: 0.01)
        XCTAssertEqual(entry.product.brand, dish.ingredients.joined(separator: ", "))
        XCTAssertEqual(item.meal, .dinner)
    }

    func testPlannedDishAppearsInShoppingList() throws {
        let dish = try XCTUnwrap(MealPlanLogic.recipes.first)
        let item = try MealPlanLogic.item(for: dish, day: Self.day, meal: .dinner)
        let lines = FoodPlanLogic.shoppingLines(from: [try XCTUnwrap(item.entry)], today: Self.day)
        XCTAssertEqual(lines.map(\.name), [dish.name])
    }

    // MARK: Food-Karten unten

    func testWeightTrend() {
        XCTAssertNil(FoodHomeCardsText.weightTrend(latest: 80, previous: nil))
        XCTAssertEqual(FoodHomeCardsText.weightTrend(latest: 80, previous: 80.02)?.trend, .flat)
        let down = FoodHomeCardsText.weightTrend(latest: 79.5, previous: 80)
        XCTAssertEqual(down?.trend, .down)
        XCTAssertEqual(down?.delta ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(FoodHomeCardsText.weightTrend(latest: 81, previous: 80)?.trend, .up)
    }

    func testNextPlannedPicksEarliestOpenDishAndSkipsLoggedAndPast() throws {
        let cal = Calendar.forma
        let today = cal.startOfDay(for: Self.day)
        let tomorrow = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: today))
        let yesterday = try XCTUnwrap(cal.date(byAdding: .day, value: -1, to: today))
        let dish = try XCTUnwrap(MealPlanLogic.recipes.first)
        func entry(_ day: Date, _ meal: FoodMeal, logged: Bool = false) throws -> FoodPlanEntry {
            let item = try MealPlanLogic.item(for: dish, day: day, meal: meal)
            if logged { item.loggedAt = .now }
            return try XCTUnwrap(item.entry)
        }
        let old = try entry(yesterday, .dinner)
        let done = try entry(today, .lunch, logged: true)
        let evening = try entry(today, .dinner)
        let lunchTomorrow = try entry(tomorrow, .lunch)
        let picked = FoodHomeCardsText.nextPlanned([lunchTomorrow, old, done, evening], today: Self.day)
        XCTAssertEqual(picked?.id, evening.id)
        XCTAssertNil(FoodHomeCardsText.nextPlanned([old, done], today: Self.day))
    }
}
