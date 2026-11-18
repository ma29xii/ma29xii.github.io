import Foundation
import SwiftData

enum FoodMeal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: Self { self }

    var title: String {
        switch self {
        case .breakfast: "Frühstück"
        case .lunch: "Mittag"
        case .dinner: "Abend"
        case .snack: "Snack"
        }
    }
}

enum FoodNutrient: String, CaseIterable, Identifiable, Codable, Sendable {
    case energy = "energy-kcal"
    case protein = "proteins"
    case carbohydrates
    case sugar = "sugars"
    case fat
    case saturatedFat = "saturated-fat"
    case fiber
    case salt

    var id: Self { self }
    var unit: String { self == .energy ? "kcal" : "g" }

    var title: String {
        switch self {
        case .energy: "Energie"
        case .protein: "Eiweiß"
        case .carbohydrates: "Kohlenhydrate"
        case .sugar: "Zucker"
        case .fat: "Fett"
        case .saturatedFat: "Gesättigte Fette"
        case .fiber: "Ballaststoffe"
        case .salt: "Salz"
        }
    }
}

struct FoodNutrients: Hashable, Codable, Sendable {
    var values: [FoodNutrient: Double] = [:]

    func scaled(by factor: Double) -> Self {
        Self(values: values.mapValues { $0 * factor })
    }

    func fillingMissing(from other: Self) -> Self {
        Self(values: values.merging(other.values) { supplied, _ in supplied })
    }
}

enum FoodBase: String, Codable, Sendable {
    case grams = "g"
    case milliliters = "ml"

    var title: String { self == .grams ? "Gramm" : "Milliliter" }
}

enum FoodAmountUnit: String, CaseIterable, Identifiable {
    case base, servings

    var id: Self { self }
}

struct FoodProduct: Identifiable, Hashable, Codable, Sendable {
    let code: String
    let name: String
    let brand: String?
    let base: FoodBase
    let servingSize: Double?
    let per100: FoodNutrients
    let perServing: FoodNutrients

    var id: String { code }
    var canUseServings: Bool { servingSize != nil || !perServing.values.isEmpty }
    var canUseBase: Bool { !per100.values.isEmpty || !canUseServings }

    func amountLimit(in unit: FoodAmountUnit) -> Double {
        switch unit {
        case .base: 10_000
        case .servings: min(100, servingSize.map { 10_000 / $0 } ?? 100)
        }
    }

    func nutrients(for amount: Double, in unit: FoodAmountUnit) -> FoodNutrients? {
        guard amount.isFinite, amount > 0, amount <= amountLimit(in: unit) else { return nil }
        switch unit {
        case .base: return canUseBase ? per100.scaled(by: amount / 100) : nil
        case .servings: return canUseServings ? perServing.scaled(by: amount) : nil
        }
    }
}

/// Ein Eintrag speichert die Nährwerte der gegessenen Menge zum Zeitpunkt des Eintragens.
@Model
final class FoodEntry {
    var date: Date
    var mealRaw: String
    var name: String
    var brand: String?
    var amount: Double
    var unit: String
    var energy: Double?
    var protein: Double?
    var carbohydrates: Double?
    var sugar: Double?
    var fat: Double?
    var saturatedFat: Double?
    var fiber: Double?
    var salt: Double?

    init(date: Date = .now, meal: FoodMeal, product: FoodProduct, amount: Double,
         in unit: FoodAmountUnit, nutrients: FoodNutrients) {
        self.date = date
        self.mealRaw = meal.rawValue
        self.name = product.name
        self.brand = product.brand
        self.amount = amount
        self.unit = unit == .base ? product.base.rawValue : "Portion"
        self.energy = nutrients.values[.energy]
        self.protein = nutrients.values[.protein]
        self.carbohydrates = nutrients.values[.carbohydrates]
        self.sugar = nutrients.values[.sugar]
        self.fat = nutrients.values[.fat]
        self.saturatedFat = nutrients.values[.saturatedFat]
        self.fiber = nutrients.values[.fiber]
        self.salt = nutrients.values[.salt]
    }

    var meal: FoodMeal { FoodMeal(rawValue: mealRaw) ?? .snack }
}

struct FoodGoal {
    static let heightKey = "forma.bodyHeightCm"
    static let heightRange = 80.0...250.0

    let base: Double
    let activeEnergy: Double?
    let isPersonalized: Bool

    var target: Double { base + (activeEnergy ?? 0) }

    init(weightKg: Double, heightCm: Double, age: Int?, sex: BiologicalSex, activeEnergy: Double?) {
        if let age, (18...120).contains(age), (1...500).contains(weightKg),
           Self.heightRange.contains(heightCm), sex != .unknown {
            // Geschätzter Ruheenergiebedarf nach Mifflin–St Jeor, DOI 10.1093/ajcn/51.2.241.
            let estimate = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
            isPersonalized = estimate > 0
            base = isPersonalized ? estimate : 2_000
        } else {
            isPersonalized = false
            base = 2_000
        }
        self.activeEnergy = activeEnergy.flatMap { (0...12_000).contains($0) ? $0 : nil }
    }
}
