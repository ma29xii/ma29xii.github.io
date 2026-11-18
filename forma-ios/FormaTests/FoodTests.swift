import Foundation
import SwiftData
import XCTest
@testable import Forma

final class FoodTests: XCTestCase {
    func testProductParserReadsAllNutrientsAndKeepsDeclaredPortion() throws {
        let data = Data(#"""
        {"status":1,"product":{"code":"3017620422003","product_name":"Haselnusscreme",
        "product_name_de":"Nusscreme","brands":"Beispiel","serving_quantity":"30",
        "serving_quantity_unit":"g","nutriments":{"energy-kcal_100g":500,"proteins_100g":"6.5",
        "carbohydrates_100g":55,"sugars_100g":45,"fat_100g":30,"saturated-fat_100g":11,
        "fiber_100g":3,"salt_100g":0.2,"energy-kcal_serving":149}}}
        """#.utf8)
        let product = try XCTUnwrap(FoodCatalog.decodeProduct(data))

        XCTAssertEqual(product.name, "Nusscreme")
        XCTAssertEqual(product.brand, "Beispiel")
        XCTAssertEqual(product.servingSize, 30)
        XCTAssertEqual(product.per100.values, [.energy: 500, .protein: 6.5, .carbohydrates: 55,
                                             .sugar: 45, .fat: 30, .saturatedFat: 11, .fiber: 3, .salt: 0.2])
        let serving = product.nutrients(for: 1, in: .servings)
        XCTAssertEqual(serving?.values[.energy], 149)
        XCTAssertEqual(try XCTUnwrap(serving?.values[.protein]), 1.95, accuracy: 0.001)
    }

    func testParserAcceptsMissingFieldsAndRejectsInvalidNumbers() throws {
        let data = Data(#"""
        {"status":1,"code":"20003166","product":{"nutriments":{"energy_100g":418.4,
        "proteins_100g":true,"fat_100g":-1,"fiber_100g":"NaN","sugars_100g":0,
        "carbohydrates_100g":999,"salt_100g":{}}}}
        """#.utf8)
        let product = try XCTUnwrap(FoodCatalog.decodeProduct(data))
        XCTAssertEqual(product.name, "Produkt 20003166")
        XCTAssertEqual(try XCTUnwrap(product.per100.values[.energy]), 100, accuracy: 0.0001)
        XCTAssertEqual(product.per100.values[.sugar], 0)
        XCTAssertNil(product.per100.values[.protein])
        XCTAssertNil(product.per100.values[.fat])
        XCTAssertNil(product.per100.values[.fiber])
        XCTAssertNil(product.per100.values[.carbohydrates])
        XCTAssertNil(product.nutrients(for: 1, in: .servings))

        let noNutrients = Data(#"{"status":1,"code":"20003166","product":{}}"#.utf8)
        XCTAssertTrue(try XCTUnwrap(FoodCatalog.decodeProduct(noNutrients)).per100.values.isEmpty)
    }

    func testMalformedProductAndMissingBarcode() throws {
        XCTAssertThrowsError(try FoodCatalog.decodeProduct(Data("{kaputt".utf8)))
        XCTAssertThrowsError(try FoodCatalog.decodeProduct(Data(#"{"status":1,"product":[]}"#.utf8)))
        XCTAssertNil(try FoodCatalog.decodeProduct(Data(#"{"status":0,"status_verbose":"product not found"}"#.utf8)))
    }

    func testSearchDecodesLocalizedHitsAndDeduplicates() throws {
        let data = Data(#"""
        {"hits":[{"code":"20003166","product_name":"Haferflocken","brands":["A","a"]},
        {"code":"20003166","product_name":"Doppelt"},{"product_name":"Ohne Code"},null,
        {"code":"4058172307409","product_name":"Feinblatt"}]}
        """#.utf8)
        let hits = try FoodCatalog.decodeSearch(data)
        XCTAssertEqual(hits.map(\.id), ["20003166", "4058172307409"])
        XCTAssertEqual(hits.first?.brand, "A")
        XCTAssertThrowsError(try FoodCatalog.decodeSearch(Data(#"{"errors":[]}"#.utf8)))
    }

    func testPortionsScaleAndConvertBetweenDeclaredBases() throws {
        let data = Data(#"""
        {"status":1,"code":"5449000000996","product":{"product_quantity_unit":"ml", "serving_size":"1 Portion (330 ml)",
        "nutriments":{"energy-kcal_serving":132,"carbohydrates_100g":10}}}
        """#.utf8)
        let product = try XCTUnwrap(FoodCatalog.decodeProduct(data))
        XCTAssertEqual(product.base, .milliliters)
        XCTAssertEqual(product.servingSize, 330)
        XCTAssertEqual(try XCTUnwrap(product.per100.values[.energy]), 40, accuracy: 0.0001)
        XCTAssertEqual(product.nutrients(for: 1.5, in: .servings)?.values[.carbohydrates], 49.5)
        XCTAssertEqual(product.nutrients(for: 0.5, in: .servings)?.values[.energy], 66)
        XCTAssertEqual(product.nutrients(for: 150, in: .base)?.values[.energy], 60)
        XCTAssertNil(product.nutrients(for: 0, in: .base))
        XCTAssertNil(product.nutrients(for: .infinity, in: .servings))
    }

    func testPortionWithoutKnownWeightStaysUsable() throws {
        let data = Data(#"""
        {"status":1,"code":"20003166","product":{"nutriments":{"energy-kcal_serving":120}}}
        """#.utf8)
        let product = try XCTUnwrap(FoodCatalog.decodeProduct(data))
        XCTAssertNil(product.servingSize)
        XCTAssertNil(product.per100.values[.energy])
        XCTAssertEqual(product.nutrients(for: 2, in: .servings)?.values[.energy], 240)
    }

    func testCalorieGoalUsesRestingEnergyAndAddsOnlyRealActivity() {
        let male = FoodGoal(weightKg: 80, heightCm: 180, age: 30, sex: .male, activeEnergy: 300)
        XCTAssertEqual(male.base, 1_780)
        XCTAssertEqual(male.target, 2_080)
        XCTAssertTrue(male.isPersonalized)

        let female = FoodGoal(weightKg: 80, heightCm: 180, age: 30, sex: .female, activeEnergy: nil)
        XCTAssertEqual(female.target, 1_614)
        XCTAssertNil(female.activeEnergy)

        let fallback = FoodGoal(weightKg: 80, heightCm: 0, age: 30, sex: .male, activeEnergy: 220)
        XCTAssertEqual(fallback.base, 2_000)
        XCTAssertEqual(fallback.target, 2_220)
        XCTAssertFalse(fallback.isPersonalized)

        let invalid = FoodGoal(weightKg: .nan, heightCm: 180, age: 16, sex: .unknown, activeEnergy: -50)
        XCTAssertEqual(invalid.target, 2_000)
        XCTAssertNil(invalid.activeEnergy)
        XCTAssertEqual(FoodGoal(weightKg: 80, heightCm: 180, age: 16, sex: .male, activeEnergy: 0).activeEnergy, 0)
        XCTAssertFalse(FoodGoal(weightKg: 80, heightCm: 180, age: 16, sex: .male, activeEnergy: nil).isPersonalized)
    }

    func testUPCEScanExpandsTheCompressedCodeWithoutTouchingEAN8() {
        XCTAssertEqual(FoodCatalog.barcode("04252614", isUPCE: true), "042100005264")
        XCTAssertEqual(FoodCatalog.barcode("20003166", isUPCE: false), "20003166")
        XCTAssertNil(FoodCatalog.barcode("12345678", isUPCE: true))
        XCTAssertNil(FoodCatalog.barcode("/3017620422003", isUPCE: false))
    }

    func testRecipeCombinesMillilitersAndGramsByTheirOwnReferenceAndDividesByServings() throws {
        let grain = FoodProduct(code: "grain", name: "Hafer", brand: nil, base: .grams, servingSize: nil,
                                per100: FoodNutrients(values: [.energy: 400, .protein: 10]), perServing: .init())
        let milk = FoodProduct(code: "milk", name: "Milch", brand: nil, base: .milliliters, servingSize: nil,
                               per100: FoodNutrients(values: [.energy: 50]), perServing: .init())
        let ingredients = [FoodRecipeIngredient(product: grain, amount: 50, unit: .base),
                           FoodRecipeIngredient(product: milk, amount: 200, unit: .base)]
        let recipe = try XCTUnwrap(FoodRecipeMath.product(code: "recipe", name: "Porridge", servings: 2,
                                                         ingredients: ingredients))
        XCTAssertFalse(recipe.canUseBase)
        XCTAssertEqual(recipe.nutrients(for: 1.5, in: .servings)?.values[.energy], 225)
        XCTAssertNil(recipe.perServing.values[.protein])
        XCTAssertNil(FoodRecipeMath.product(code: "recipe", name: "Porridge", servings: 0, ingredients: ingredients))
    }

    func testPhotoPortionRescalesEnergyAndMacrosAndKeepsUnknownValuesEmpty() throws {
        let guess = FoodGuess(name: "Reis", grams: 200, kcal: 260, protein: 6, carbs: 56, fat: 0.5, confidence: 0.75)
        let portion = try XCTUnwrap(FoodPhotoPortion(guess: guess))
        let half = try XCTUnwrap(portion.product.nutrients(for: 100, in: .base))
        XCTAssertEqual(half.values[.energy], 130)
        XCTAssertEqual(half.values[.carbohydrates], 28)
        XCTAssertNil(half.values[.sugar])
        let invalid = FoodGuess(name: "Reis", grams: .nan, kcal: 260, protein: 6, carbs: 56, fat: 0.5, confidence: 0.75)
        XCTAssertNil(FoodPhotoPortion(guess: invalid))
    }

    func testStreakUsesCalendarDaysAcrossSpringClockChangeAndIgnoresFutureEntries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 12)))
        func day(_ offset: Int) throws -> Date {
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: now))
        }
        XCTAssertEqual(FoodTracking.streak(dates: [try day(-1), try day(-1), try day(-2), try day(1)],
                                           now: now, calendar: calendar), 2)
        XCTAssertEqual(FoodTracking.streak(dates: [try day(-2)], now: now, calendar: calendar), 0)
    }

    func testFastingUsesElapsedTimeCapsTheRingAndFreezesAnEndedSession() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(8 * 3_600)
        XCTAssertEqual(FoodTracking.fast(start: start, end: end, hours: 16, now: end.addingTimeInterval(1)).fraction, 0.5)
        XCTAssertEqual(FoodTracking.fast(start: start, end: nil, hours: 16, now: start.addingTimeInterval(70_000)).fraction, 1)
        XCTAssertEqual(FoodTracking.fast(start: start, end: nil, hours: 16, now: start.addingTimeInterval(-60)).elapsed, 0)
    }

    @MainActor
    func testLibraryPreservesRecipeIngredientsAndUsesLoggedAmountsForLegacyHistory() throws {
        let product = FoodProduct(code: "grain", name: "Hafer", brand: nil, base: .grams, servingSize: nil,
                                  per100: FoodNutrients(values: [.energy: 400]), perServing: .init())
        let ingredient = FoodRecipeIngredient(product: product, amount: 80, unit: .base)
        let recipe = try XCTUnwrap(FoodRecipeMath.product(code: "recipe", name: "Haferbrei", servings: 2,
                                                         ingredients: [ingredient]))
        let container = try ModelContainer(for: FoodEntry.self, FoodLibraryItem.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let item = try FoodLibraryItem(product: recipe, kind: .recipe, servings: 2, ingredients: [ingredient])
        let entry = FoodEntry(meal: .lunch, product: product, amount: 50, in: .base,
                              nutrients: FoodNutrients(values: [.energy: 200]))
        entry.productSnapshot = nil
        try FoodEntry.saveChange(in: context) {
            context.insert(item)
            context.insert(entry)
        }
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<FoodLibraryItem>()).first)
        XCTAssertEqual(saved.ingredients.first?.amount, 80)
        XCTAssertEqual(saved.product?.perServing.values[.energy], 160)
        XCTAssertEqual(entry.reusableProduct?.nutrients(for: 75, in: .base)?.values[.energy], 300)
    }

    @MainActor
    func testEntrySavesAndDeletesWithoutReplacingMissingNutrients() throws {
        let data = Data(#"{"status":1,"code":"20003166","product":{"nutriments":{"energy-kcal_100g":400}}}"#.utf8)
        let product = try XCTUnwrap(FoodCatalog.decodeProduct(data))
        let nutrients = try XCTUnwrap(product.nutrients(for: 75, in: .base))
        let container = try ModelContainer(for: FoodEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let entry = FoodEntry(meal: .breakfast, product: product, amount: 75, in: .base, nutrients: nutrients)
        try FoodEntry.saveChange(in: context) { context.insert(entry) }

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(saved.meal, .breakfast)
        XCTAssertEqual(saved.energy, 300)
        XCTAssertNil(saved.fiber)

        try FoodEntry.saveChange(in: context) { context.delete(saved) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 0)
    }
}
