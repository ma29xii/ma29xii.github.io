import Foundation
import SwiftData

// MARK: - Einstellungen

enum FoodSettings {
    static let proteinGoalKey = "forma.food.goal.protein"
    static let carbsGoalKey = "forma.food.goal.carbs"
    static let fatGoalKey = "forma.food.goal.fat"
    static let waterGoalKey = "forma.food.goal.waterMl"
    static let fastHoursKey = "forma.food.fastHours"
    static let weightGoalKey = "forma.food.goal.weightKg"
    /// Gleicher Schlüssel wie Profil → Body, damit das Kalorienziel das neueste Gewicht nutzt.
    static let bodyWeightKey = "forma.bodyWeightKg"

    static let glassMl = 250.0
    static let defaultWaterMl = 2_500.0
    static let waterRange = 500.0...6_000.0
    static let weightRange = 20.0...400.0
    static let fastPlans: [Double] = [14, 16, 18, 20]
    static let fastRange = 10.0...72.0
}

/// Makro-Ziele in Gramm. Ein gespeicherter Wert 0 heißt „automatisch aus dem Kalorienziel“.
struct FoodMacroGoals: Equatable {
    let protein: Double
    let carbs: Double
    let fat: Double

    /// 25 % Eiweiß, 45 % Kohlenhydrate, 30 % Fett der Energie.
    static func automatic(kcal: Double) -> Self {
        let energy = max(0, kcal)
        return Self(protein: energy * 0.25 / 4, carbs: energy * 0.45 / 4, fat: energy * 0.30 / 9)
    }

    static func resolve(kcal: Double, protein: Double, carbs: Double, fat: Double) -> Self {
        let auto = automatic(kcal: kcal)
        func pick(_ stored: Double, _ fallback: Double) -> Double {
            stored.isFinite && stored > 0 && stored <= 1_000 ? stored : fallback
        }
        return Self(protein: pick(protein, auto.protein), carbs: pick(carbs, auto.carbs), fat: pick(fat, auto.fat))
    }
}

// MARK: - Rezepte und eigene Lebensmittel

struct FoodRecipeIngredient: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    let product: FoodProduct
    let amount: Double
    let unit: FoodAmountUnit

    var nutrients: FoodNutrients? { product.nutrients(for: amount, in: unit) }
}

enum FoodRecipeMath {
    /// Nährwerte je Portion. Ein Nährwert zählt nur, wenn jede Zutat ihn kennt – sonst wäre die Summe zu niedrig.
    static func product(code: String, name: String, servings: Int,
                        ingredients: [FoodRecipeIngredient]) -> FoodProduct? {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard servings > 0, servings <= 100, !title.isEmpty, !ingredients.isEmpty else { return nil }
        let parts = ingredients.compactMap(\.nutrients)
        guard parts.count == ingredients.count else { return nil }
        var total: [FoodNutrient: Double] = [:]
        for nutrient in FoodNutrient.allCases {
            let values = parts.compactMap { $0.values[nutrient] }
            if values.count == parts.count { total[nutrient] = values.reduce(0, +) }
        }
        return FoodProduct(code: code, name: title, brand: nil, base: .grams, servingSize: nil,
                           per100: FoodNutrients(),
                           perServing: FoodNutrients(values: total).scaled(by: 1 / Double(servings)))
    }

    /// Eigenes Lebensmittel aus Angaben je 100 g/ml; leere Felder bleiben unbekannt.
    static func custom(code: String, name: String, base: FoodBase, per100: [FoodNutrient: Double],
                       servingSize: Double?) -> FoodProduct? {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = per100.filter { $0.value.isFinite && $0.value >= 0 && $0.value <= ($0.key == .energy ? 900 : 100) }
        guard !title.isEmpty, title.count <= 100, values.count == per100.count, values[.energy] != nil else { return nil }
        let serving = servingSize.flatMap { $0.isFinite && $0 > 0 && $0 <= 5_000 ? $0 : nil }
        let nutrients = FoodNutrients(values: values)
        return FoodProduct(code: code, name: title, brand: nil, base: base, servingSize: serving, per100: nutrients,
                           perServing: serving.map { nutrients.scaled(by: $0 / 100) } ?? FoodNutrients())
    }
}

enum FoodLibraryKind: String, Codable, CaseIterable, Sendable {
    case favorite, custom, recipe
}

/// Favoriten, eigene Lebensmittel und Rezepte. Produkt und Zutaten liegen als JSON.
@Model
final class FoodLibraryItem {
    var createdAt: Date
    var kindRaw: String
    var name: String
    var code: String
    var servings: Int
    var productData: Data
    var ingredientsData: Data

    init(product: FoodProduct, kind: FoodLibraryKind, servings: Int = 1,
         ingredients: [FoodRecipeIngredient] = []) throws {
        createdAt = .now
        kindRaw = kind.rawValue
        name = product.name
        code = product.code
        self.servings = servings
        productData = try JSONEncoder().encode(product)
        ingredientsData = try JSONEncoder().encode(ingredients)
    }

    var kind: FoodLibraryKind { FoodLibraryKind(rawValue: kindRaw) ?? .custom }
    var product: FoodProduct? { try? JSONDecoder().decode(FoodProduct.self, from: productData) }
    var ingredients: [FoodRecipeIngredient] {
        (try? JSONDecoder().decode([FoodRecipeIngredient].self, from: ingredientsData)) ?? []
    }
}

// MARK: - Wasser, Fasten, Gewicht

@Model
final class FoodWaterEntry {
    var date: Date
    var milliliters: Double
    /// Kennung des importierten Widget-Ereignisses. Manuelle und ältere Einträge haben keine Kennung.
    var widgetEventID: UUID?

    init(date: Date = .now, milliliters: Double, widgetEventID: UUID? = nil) {
        self.date = date
        self.milliliters = milliliters
        self.widgetEventID = widgetEventID
    }
}

@Model
final class FoodFast {
    var start: Date
    var end: Date?
    var targetHours: Double

    init(start: Date = .now, targetHours: Double) {
        self.start = start
        self.targetHours = targetHours
    }
}

@Model
final class FoodWeightEntry {
    var date: Date
    var kilograms: Double

    init(date: Date = .now, kilograms: Double) {
        self.date = date
        self.kilograms = kilograms
    }
}

// MARK: - Foto-Erkennung

/// Ein Foto-Vorschlag als veränderbare Portion. Nährwerte bleiben proportional zur Menge.
struct FoodPhotoPortion: Identifiable {
    let id = UUID()
    let product: FoodProduct
    var grams: Double
    var included = true

    init?(guess: FoodGuess) {
        let values = [guess.kcal, guess.protein, guess.carbs, guess.fat]
        guard guess.grams.isFinite, guess.grams > 0, values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let factor = 100 / guess.grams
        product = FoodProduct(
            code: "photo-" + UUID().uuidString, name: guess.name, brand: nil, base: .grams, servingSize: nil,
            per100: FoodNutrients(values: [.energy: guess.kcal * factor, .protein: guess.protein * factor,
                                           .carbohydrates: guess.carbs * factor, .fat: guess.fat * factor]),
            perServing: FoodNutrients())
        grams = guess.grams
    }

    var nutrients: FoodNutrients? { product.nutrients(for: grams, in: .base) }
}

// MARK: - Auswertung

enum FoodTracking {
    struct Fast: Equatable {
        let elapsed: TimeInterval
        let target: TimeInterval
        var fraction: Double { target > 0 ? min(1, elapsed / target) : 0 }
        var remaining: TimeInterval { max(0, target - elapsed) }
        var reached: Bool { target > 0 && elapsed >= target }
    }

    /// Laufzeit eines Fastens. Ein beendetes Fasten bleibt auf seinem Endwert stehen.
    static func fast(start: Date, end: Date?, hours: Double, now: Date = .now) -> Fast {
        let stop = end.map { min($0, now) } ?? now
        let target = hours.isFinite ? max(0, hours) * 3_600 : 0
        return Fast(elapsed: max(0, stop.timeIntervalSince(start)), target: target)
    }

    /// Tage in Folge mit mindestens einem Eintrag. Heute zählt mit, bricht die Serie aber nicht, solange der Tag läuft.
    static func streak(dates: [Date], now: Date = .now, calendar: Calendar = .forma) -> Int {
        let today = calendar.startOfDay(for: now)
        let days = Set(dates.map { calendar.startOfDay(for: $0) }.filter { $0 <= today })
        var day = today
        if !days.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Zuletzt eingetragene, verschiedene Lebensmittel (Einträge neueste zuerst).
    static func recent(_ entries: [FoodEntry], limit: Int = 8) -> [FoodEntry] {
        var seen = Set<String>()
        var result: [FoodEntry] = []
        for entry in entries.sorted(by: { $0.date > $1.date }) where seen.insert(entry.productKey).inserted {
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }

    /// Am häufigsten eingetragene Lebensmittel, bei Gleichstand das zuletzt gegessene zuerst.
    static func frequent(_ entries: [FoodEntry], limit: Int = 8, minimumCount: Int = 2) -> [FoodEntry] {
        let groups = Dictionary(grouping: entries, by: \.productKey)
        return groups.values
            .filter { $0.count >= minimumCount }
            .compactMap { group -> (count: Int, latest: FoodEntry)? in
                guard let latest = group.max(by: { $0.date < $1.date }) else { return nil }
                return (count: group.count, latest: latest)
            }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                if a.latest.date != b.latest.date { return a.latest.date > b.latest.date }
                return a.latest.productKey < b.latest.productKey
            }
            .prefix(limit)
            .map { $0.latest }
    }

    /// Gewichtsänderung pro Woche aus dem ersten und letzten Eintrag der letzten 30 Tage.
    static func weeklyWeightChange(_ entries: [(date: Date, kg: Double)], now: Date = .now) -> Double? {
        let window = entries.filter { $0.date >= now.addingTimeInterval(-30 * 86_400) && $0.date <= now }
            .sorted { $0.date < $1.date }
        guard let first = window.first, let last = window.last else { return nil }
        let days = last.date.timeIntervalSince(first.date) / 86_400
        guard days >= 6 else { return nil }
        return (last.kg - first.kg) / days * 7
    }
}

// MARK: - Summen mit Lücken

/// Summe bekannter Werte. `complete == false`, sobald ein Eintrag keinen Wert hat: dann ist die Summe nur ein Mindestwert.
struct FoodSum: Equatable, Sendable {
    let known: Double
    let complete: Bool

    init(_ values: [Double?]) {
        known = values.compactMap { $0 }.filter(\.isFinite).reduce(0, +)
        complete = values.allSatisfy { $0?.isFinite == true }
    }

    /// Restbudget nur bei vollständigen Angaben, sonst offen.
    func remaining(of target: Double) -> Double? { complete && target > 0 ? target - known : nil }
}

// MARK: - Vorschau und Freigaben

extension FoodSettings {
    /// Eigene Foto-Freigabe für die Essensanalyse, getrennt von der Coach-Freigabe.
    static let photoConsentKey = "forma.food.photoConsent.v1"

    static func photoAnalysisAllowed(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: photoConsentKey)
    }

    static let previewSuite = "forma.preview.food"

    /// Speicher der Vorschau: Beispieldaten schreiben nie in Profil, Gewicht oder echte Ziele.
    /// Wird bei jedem App-Start geleert und mit einem Beispielprofil vorbelegt.
    // UserDefaults ist laut Apple threadsicher; Swift 6 kennt das nicht als Sendable.
    nonisolated(unsafe) static let previewDefaults: UserDefaults = {
        // shortcut: fester, gültiger Suite-Name; nil gibt es nur für die eigene Bundle-ID.
        let defaults = UserDefaults(suiteName: previewSuite)!
        defaults.removePersistentDomain(forName: previewSuite)
        // Nicht register(defaults:): die Registrierung gilt prozessweit und würde auch .standard vorbelegen.
        let profile: [String: Any] = [
            bodyWeightKey: 78.0, FoodGoal.heightKey: 180.0, "forma.birthYear": 1994, "forma.sex": BiologicalSex.male.rawValue
        ]
        for (key, value) in profile { defaults.set(value, forKey: key) }
        return defaults
    }()

    static func store(isSample: Bool) -> UserDefaults { isSample ? previewDefaults : .standard }
}
