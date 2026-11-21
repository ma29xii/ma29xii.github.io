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

enum FoodAmountUnit: String, CaseIterable, Identifiable, Codable, Sendable {
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
    /// Das eingetragene Produkt als JSON, damit „Zuletzt“ und „Häufig“ es wieder eintragen können.
    var productSnapshot: Data?

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
        self.productSnapshot = try? JSONEncoder().encode(product)
    }

    /// Menge, Einheit, Mahlzeit und bereits erfasste Nährwerte unverändert übernehmen.
    init(repeating entry: FoodEntry, at date: Date) {
        self.date = date
        self.mealRaw = entry.mealRaw
        self.name = entry.name
        self.brand = entry.brand
        self.amount = entry.amount
        self.unit = entry.unit
        self.energy = entry.energy
        self.protein = entry.protein
        self.carbohydrates = entry.carbohydrates
        self.sugar = entry.sugar
        self.fat = entry.fat
        self.saturatedFat = entry.saturatedFat
        self.fiber = entry.fiber
        self.salt = entry.salt
        self.productSnapshot = entry.productSnapshot
    }

    /// Gleiche Lebensmittel erkennen, auch bei Einträgen ohne Produkt-Snapshot.
    var productKey: String { (name + "|" + (brand ?? "")).lowercased() }

    var loggedNutrients: FoodNutrients {
        let pairs: [(FoodNutrient, Double?)] = [
            (.energy, energy), (.protein, protein), (.carbohydrates, carbohydrates), (.sugar, sugar),
            (.fat, fat), (.saturatedFat, saturatedFat), (.fiber, fiber), (.salt, salt)
        ]
        var values: [FoodNutrient: Double] = [:]
        for (nutrient, value) in pairs { if let value { values[nutrient] = value } }
        return FoodNutrients(values: values)
    }

    /// Produkt zum erneuten Eintragen. Alte Einträge ohne Snapshot rechnen aus der eingetragenen Menge zurück.
    var reusableProduct: FoodProduct? {
        if let productSnapshot, let product = try? JSONDecoder().decode(FoodProduct.self, from: productSnapshot) {
            return product
        }
        guard amount.isFinite, amount > 0 else { return nil }
        let code = "entry-" + productKey
        if unit == "Portion" {
            return FoodProduct(code: code, name: name, brand: brand, base: .grams, servingSize: nil,
                               per100: FoodNutrients(), perServing: loggedNutrients.scaled(by: 1 / amount))
        }
        return FoodProduct(code: code, name: name, brand: brand, base: FoodBase(rawValue: unit) ?? .grams,
                           servingSize: nil, per100: loggedNutrients.scaled(by: 100 / amount), perServing: FoodNutrients())
    }

    var meal: FoodMeal { FoodMeal(rawValue: mealRaw) ?? .snack }

    @MainActor
    static func saveChange(in context: ModelContext, _ change: () -> Void) throws {
        // Ausstehende Änderungen anderer Ansichten vor dieser Änderung abschließen.
        if context.hasChanges { try context.save() }
        do {
            try context.transaction(block: change)
        } catch {
            context.rollback()
            throw error
        }
    }
}

struct FoodGoal {
    static func forDay(_ day: Date, birthYear: Int, weight: Double, height: Double,
                       sex: String, activeEnergy: Double?) -> Self {
        let year = Calendar.forma.component(.year, from: day)
        let age = (1900...year).contains(birthYear) ? year - birthYear : nil
        return Self(weightKg: weight, heightCm: height, age: age,
                    sex: BiologicalSex(rawValue: sex) ?? .unknown, activeEnergy: activeEnergy)
    }

    static let heightKey = "forma.bodyHeightCm"
    static let heightRange = 80.0...250.0

    let base: Double
    let activeEnergy: Double?
    let isPersonalized: Bool
    let proteinGrams: Double

    var target: Double { base + (activeEnergy ?? 0) }
    var carbGrams: Double {
        // 30 % der Zielkalorien sind für Fett vorgesehen. Protein und Kohlenhydrate liefern je 4 kcal/g.
        max(0, (target - target * 0.30) / 4 - proteinGrams)
    }
    var fiberGrams: Double { target / 1_000 * 14 }

    init(weightKg: Double, heightCm: Double, age: Int?, sex: BiologicalSex, activeEnergy: Double?) {
        let hasWeight = (1...500).contains(weightKg)
        proteinGrams = hasWeight ? weightKg * 1.8 : 120
        if let age, (18...120).contains(age), hasWeight,
           Self.heightRange.contains(heightCm), sex != .unknown {
            // Geschätzter Ruheenergiebedarf nach Mifflin–St Jeor, DOI 10.1093/ajcn/51.2.241.
            let estimate = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
            isPersonalized = estimate > 0
            base = estimate > 0 ? estimate : 2_000
        } else {
            isPersonalized = false
            base = 2_000
        }
        self.activeEnergy = activeEnergy.flatMap { (0...12_000).contains($0) ? $0 : nil }
    }
}
