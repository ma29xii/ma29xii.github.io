import SwiftData
import XCTest
@testable import Forma

final class FoodPlanTests: XCTestCase {
    private let calendar = Calendar.forma
    /// Mittag eines festen Tages, damit nichts von der Uhrzeit des Testlaufs abhängt.
    private var noon: Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSinceReferenceDate: 800_000_000))!
    }
    private var today: Date { calendar.startOfDay(for: noon) }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    private func product(_ name: String, base: FoodBase = .grams, serving: Double? = nil, kcal100: Double? = 100) -> FoodProduct {
        let per100 = kcal100.map { FoodNutrients(values: [.energy: $0]) } ?? FoodNutrients()
        return FoodProduct(code: "t-" + name, name: name, brand: nil, base: base, servingSize: serving, per100: per100,
                           perServing: serving.map { per100.scaled(by: $0 / 100) } ?? FoodNutrients())
    }

    private func entry(_ name: String, day: Date, meal: FoodMeal = .lunch, amount: Double = 100,
                       unit: FoodAmountUnit = .base, serving: Double? = nil, base: FoodBase = .grams,
                       bought: Bool = false, logged: Bool = false, kcal100: Double? = 100) -> FoodPlanEntry {
        FoodPlanEntry(id: UUID(), day: day, meal: meal,
                      product: product(name, base: base, serving: serving, kcal100: kcal100),
                      amount: amount, unit: unit, bought: bought, logged: logged)
    }

    // MARK: Tage und Summen

    func testDaysStartAtMidnightAndAreConsecutive() {
        let days = FoodPlanLogic.days(from: noon)
        XCTAssertEqual(days.count, FoodPlanLogic.horizon)
        XCTAssertEqual(days.first, today)
        for pair in zip(days, days.dropFirst()) {
            XCTAssertEqual(calendar.dateComponents([.day], from: pair.0, to: pair.1).day, 1)
        }
        XCTAssertTrue(FoodPlanLogic.days(from: noon, count: 0).isEmpty)
    }

    func testEntriesOfADayAreSortedByMealThenCreationOrder() {
        let all = [entry("Abendbrot", day: today, meal: .dinner), entry("Müsli", day: today, meal: .breakfast),
                   entry("Apfel", day: today, meal: .snack), entry("Joghurt", day: today, meal: .breakfast),
                   entry("Morgen", day: day(1), meal: .breakfast)]
        let names = FoodPlanLogic.entries(all, on: today).map(\.product.name)
        XCTAssertEqual(names, ["Müsli", "Joghurt", "Abendbrot", "Apfel"])
    }

    func testSummaryIsMinimumWhenEnergyIsMissing() {
        let complete = FoodPlanLogic.summary(of: [entry("A", day: today, amount: 200), entry("B", day: today, amount: 50)])
        XCTAssertEqual(complete.kcal, 250, accuracy: 0.001)
        XCTAssertTrue(complete.complete)
        let partial = FoodPlanLogic.summary(of: [entry("A", day: today, amount: 200), entry("B", day: today, kcal100: nil)])
        XCTAssertEqual(partial.kcal, 200, accuracy: 0.001)
        XCTAssertFalse(partial.complete)
        XCTAssertTrue(FoodPlanText.energy(partial).hasPrefix("mind. "))
        XCTAssertEqual(FoodPlanLogic.summary(of: []).count, 0)
    }

    func testOverdueListsOnlyOpenEntriesBeforeToday() {
        let all = [entry("Gestern offen", day: day(-1)), entry("Gestern erledigt", day: day(-1), logged: true),
                   entry("Heute", day: today), entry("Vorgestern", day: day(-2))]
        XCTAssertEqual(FoodPlanLogic.overdue(all, today: noon).map(\.product.name), ["Vorgestern", "Gestern offen"])
    }

    // MARK: Übernahme

    func testCanLogOnlyTodayAndEarlier() {
        XCTAssertTrue(FoodPlanLogic.canLog(day: today, now: noon))
        XCTAssertTrue(FoodPlanLogic.canLog(day: day(-3), now: noon))
        XCTAssertFalse(FoodPlanLogic.canLog(day: day(1), now: noon))
    }

    func testLogDateIsNowToday_andTypicalHourOnEarlierDays() {
        XCTAssertEqual(FoodPlanLogic.logDate(day: today, meal: .dinner, now: noon), noon)
        let earlier = FoodPlanLogic.logDate(day: day(-1), meal: .breakfast, now: noon)
        XCTAssertEqual(calendar.component(.hour, from: earlier), 8)
        XCTAssertTrue(calendar.isDate(earlier, inSameDayAs: day(-1)))
        XCTAssertEqual(calendar.component(.hour, from: FoodPlanLogic.logDate(day: day(-1), meal: .dinner, now: noon)), 19)
    }

    @MainActor
    func testLogWritesDiaryEntryOnceAndSkipsFutureDays() throws {
        let container = try ModelContainer(for: FoodPlanItem.self, FoodEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let due = try FoodPlanItem(day: today, meal: .lunch, product: product("Reis"), amount: 150, unit: .base)
        let future = try FoodPlanItem(day: day(2), meal: .lunch, product: product("Nudeln"), amount: 80, unit: .base)
        context.insert(due)
        context.insert(future)

        XCTAssertEqual(try FoodPlanStore.log([due, future], in: context, now: noon), 1)
        XCTAssertNotNil(due.loggedAt)
        XCTAssertNil(future.loggedAt, "Kommende Tage werden nicht übernommen")
        let entries = try context.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "Reis")
        XCTAssertEqual(entries.first?.energy ?? 0, 150, accuracy: 0.001)

        XCTAssertEqual(try FoodPlanStore.log([due], in: context, now: noon), 0, "Nie doppelt eintragen")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 1)
    }

    // MARK: Einkaufsliste

    func testShoppingLinesSumSameProductAcrossDays() {
        let lines = FoodPlanLogic.shoppingLines(from: [
            entry("Haferflocken", day: today, amount: 60), entry("Haferflocken", day: day(1), amount: 60),
            entry("Haferflocken", day: day(2), amount: 90)
        ], today: noon)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].quantity.value, 210, accuracy: 0.001)
        XCTAssertEqual(lines[0].quantity.text, "210 g")
        XCTAssertEqual(lines[0].entryIDs.count, 3)
    }

    func testServingsWithKnownSizeConvertToBaseUnitAndOthersStayPortions() {
        let withSize = FoodPlanLogic.quantity(for: entry("Joghurt", day: today, amount: 3, unit: .servings, serving: 150))
        XCTAssertEqual(withSize, ShoppingQuantity(kind: .grams, value: 450))
        let milk = FoodPlanLogic.quantity(for: entry("Milch", day: today, amount: 2, unit: .servings, serving: 250, base: .milliliters))
        XCTAssertEqual(milk, ShoppingQuantity(kind: .milliliters, value: 500))
        let noSize = FoodPlanLogic.quantity(for: entry("Riegel", day: today, amount: 1.5, unit: .servings))
        XCTAssertEqual(noSize, ShoppingQuantity(kind: .servings, value: 1.5))
        XCTAssertNil(FoodPlanLogic.quantity(for: entry("Kaputt", day: today, amount: 0)))
        XCTAssertNil(FoodPlanLogic.quantity(for: entry("Kaputt", day: today, amount: .nan)))
    }

    func testShoppingListSkipsLoggedAndPastEntries() {
        let lines = FoodPlanLogic.shoppingLines(from: [
            entry("Gestern", day: day(-1)), entry("Schon gegessen", day: today, logged: true), entry("Reis", day: today)
        ], today: noon)
        XCTAssertEqual(lines.map(\.name), ["Reis"])
    }

    func testBoughtStateIsOnlyTrueWhenEveryEntryIsBought() {
        let partly = FoodPlanLogic.shoppingLines(from: [
            entry("Reis", day: today, bought: true), entry("Reis", day: day(1), bought: false)
        ], today: noon)
        XCTAssertEqual(partly.first?.bought, false)
        let all = FoodPlanLogic.shoppingLines(from: [
            entry("Reis", day: today, bought: true), entry("Reis", day: day(1), bought: true)
        ], today: noon)
        XCTAssertEqual(all.first?.bought, true)
    }

    func testShoppingLinesAreSortedByGroupThenOpenBeforeBoughtThenName() {
        let lines = FoodPlanLogic.shoppingLines(from: [
            entry("Apfelsaft", day: today), entry("Banane", day: today, bought: true), entry("Apfel", day: today),
            entry("Vollkornbrot", day: today), entry("Kekse", day: today)
        ], today: noon)
        XCTAssertEqual(lines.map(\.name), ["Apfel", "Banane", "Vollkornbrot", "Apfelsaft", "Kekse"])
    }

    func testQuantityTexts() {
        XCTAssertEqual(ShoppingQuantity(kind: .grams, value: 1_200).text, "1,2 kg")
        XCTAssertEqual(ShoppingQuantity(kind: .grams, value: 999.6).text, "1.000 g")
        XCTAssertEqual(ShoppingQuantity(kind: .milliliters, value: 1_500).text, "1,5 l")
        XCTAssertEqual(ShoppingQuantity(kind: .milliliters, value: 330).text, "330 ml")
        XCTAssertEqual(ShoppingQuantity(kind: .servings, value: 1).text, "1 Portion")
        XCTAssertEqual(ShoppingQuantity(kind: .servings, value: 2.5).text, "2,5 Portionen")
    }

    func testGroupGuessFromName() {
        XCTAssertEqual(ShoppingGroup.group(forName: "Vollkornbrot"), .bakery)
        XCTAssertEqual(ShoppingGroup.group(forName: "Apfelsaft"), .drinks)
        XCTAssertEqual(ShoppingGroup.group(forName: "Hähnchenbrust"), .meat)
        XCTAssertEqual(ShoppingGroup.group(forName: "Magerquark"), .dairy)
        XCTAssertEqual(ShoppingGroup.group(forName: "Eier"), .dairy)
        XCTAssertEqual(ShoppingGroup.group(forName: "Banane"), .produce)
        XCTAssertEqual(ShoppingGroup.group(forName: "Haferflocken"), .pantry)
        XCTAssertEqual(ShoppingGroup.group(forName: "Kekse"), .other, "Unbekanntes landet in Sonstiges")
        XCTAssertEqual(ShoppingGroup.group(forName: ""), .other)
    }

    func testShoppingTextListsOnlyOpenLinesByGroup() {
        let lines = FoodPlanLogic.shoppingLines(from: [
            entry("Banane", day: today, amount: 200), entry("Reis", day: today, amount: 150, bought: true),
            entry("Vollkornbrot", day: today, amount: 500)
        ], today: noon)
        let text = FoodPlanLogic.shoppingText(lines)
        XCTAssertTrue(text.hasPrefix("Einkaufsliste"))
        XCTAssertTrue(text.contains("Obst und Gemüse\n• Banane: 200 g"))
        XCTAssertTrue(text.contains("Backwaren\n• Vollkornbrot: 500 g"))
        XCTAssertFalse(text.contains("Reis"))
        XCTAssertEqual(FoodPlanLogic.shoppingText([]), "")
    }

    // MARK: Texte

    func testDayTitles() {
        XCTAssertEqual(FoodPlanText.dayTitle(today, now: noon), "Heute")
        XCTAssertEqual(FoodPlanText.dayTitle(day(1), now: noon), "Morgen")
        let later = FoodPlanText.dayTitle(day(3), now: noon)
        XCTAssertFalse(later.isEmpty)
        XCTAssertNotEqual(later, "Heute")
        XCTAssertNotEqual(later, "Morgen")
    }

    func testEntryDetailNamesMealAndAmount() {
        XCTAssertEqual(FoodPlanText.detail(for: entry("Reis", day: today, meal: .dinner, amount: 150)), "Abend · 150 g")
        XCTAssertEqual(FoodPlanText.detail(for: entry("Riegel", day: today, meal: .snack, amount: 1, unit: .servings)), "Snack · 1 Portion")
    }
}
