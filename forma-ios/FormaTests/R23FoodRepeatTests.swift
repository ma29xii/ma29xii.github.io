import XCTest
@testable import Forma

final class R23FoodRepeatTests: XCTestCase {
    func testYesterdayAndFiveMostFrequentFromFourteenCompleteDays() {
        let today = Date(timeIntervalSince1970: 1_795_000_000).startOfDay
        func entry(_ name: String, _ day: Int, _ hour: Int) -> FoodEntry {
            makeEntry(name, at: today.adding(days: day).addingTimeInterval(Double(hour) * 3_600))
        }

        let newest = entry("Hafer", -1, 18)
        let yesterday = [entry("Apfel", -1, 8), newest]
        let history = yesterday + [entry("hafer", -14, 8), entry("Hafer", -3, 12), entry("Apfel", -3, 11),
                                   entry("Brot", -2, 10), entry("Brot", -4, 10), entry("Reis", -2, 9),
                                   entry("Reis", -4, 9), entry("Joghurt", -5, 9), entry("Banane", -6, 10),
                                   entry("Heute", 0, 8), entry("Zu alt", -15, 20), entry("Zu alt", -16, 8)]
        let suggestions = FoodRepeatSuggestions(entries: Array(history.reversed()), day: today)

        XCTAssertEqual(suggestions.yesterday.map(\.name), ["Apfel", "Hafer"])
        XCTAssertEqual(suggestions.frequent.map(\.name), ["Hafer", "Apfel", "Brot", "Reis", "Joghurt"])
        XCTAssertTrue(suggestions.frequent.first === newest)
    }

    func testRepeatPreservesLegacyPortionAndMissingNutrients() {
        let old = makeEntry("Hafer", at: Date(timeIntervalSince1970: 1_000))
        old.unit = "Schale"
        old.productSnapshot = nil
        let now = Date(timeIntervalSince1970: 100_000)
        let copy = FoodEntry(repeating: old, at: now)

        XCTAssertFalse(copy === old)
        XCTAssertEqual(copy.date, now)
        XCTAssertEqual(copy.meal, old.meal)
        XCTAssertEqual(copy.amount, old.amount)
        XCTAssertEqual(copy.unit, old.unit)
        XCTAssertEqual(copy.loggedNutrients, old.loggedNutrients)
        XCTAssertNil(copy.productSnapshot)
    }

    private func makeEntry(_ name: String, at date: Date) -> FoodEntry {
        let product = FoodProduct(code: name, name: name, brand: nil, base: .grams, servingSize: nil,
                                  per100: FoodNutrients(), perServing: FoodNutrients())
        return FoodEntry(date: date, meal: .lunch, product: product, amount: 50, in: .base,
                         nutrients: FoodNutrients(values: [.energy: 180, .fiber: 3]))
    }
}
