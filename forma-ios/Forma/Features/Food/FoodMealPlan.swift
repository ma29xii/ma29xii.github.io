import Foundation
import SwiftData

// MARK: - Einstellung

enum MealPlanSettings {
    /// 1 = One Meal a Day (Standard), 2 oder 3 Mahlzeiten.
    static let mealsKey = "forma.food.mealsPerDay"
    static let defaultMeals = 1
    static let range = 1...3

    static func clamp(_ value: Int) -> Int { min(range.upperBound, max(range.lowerBound, value)) }

    static func title(_ meals: Int) -> String {
        meals == 1 ? "1 (One Meal a Day)" : "\(clamp(meals))"
    }
}

// MARK: - Gericht

/// Ein vom Coach vorgeschlagenes Gericht. Nährwerte gelten je Portion, `portions` skaliert sie.
struct MealPlanDish: Codable, Equatable, Sendable {
    var name: String
    var ingredients: [String]
    var kcal: Double
    var protein: Double
    var carbs: Double
    /// Nur lokal: Menge in Portionen (KI-Antworten liefern immer die ganze Mahlzeit, also 1).
    var portions = 1.0

    private enum CodingKeys: String, CodingKey { case name, ingredients, kcal, protein, carbs }

    var totalKcal: Double { kcal * portions }
}

// MARK: - Planung

struct MealPlanRequest: Equatable, Sendable {
    var days: Int
    var meals: Int
    var kcal: Double
    var protein: Double
    var carbs: Double
    /// Namen, die nicht wiederkehren sollen (bereits geplant oder gerade ersetzt).
    var avoid: [String] = []
}

enum MealPlanLogic {
    static let codePrefix = "coach-plan-"
    /// Zulässige Abweichung vom Kalorienziel einer Mahlzeit.
    static let tolerance = 0.15
    /// KI-Gerichte weiter daneben werden durch ein lokales ersetzt.
    static let acceptedAIDeviation = 0.25
    static let maxDays = 7

    struct Slot: Equatable, Sendable {
        let meal: FoodMeal
        let share: Double
    }

    /// OMAD: ein Gericht am Abend. Zwei: Mittag und Abend. Drei: Frühstück, Mittag, Abend.
    static func slots(_ meals: Int) -> [Slot] {
        switch MealPlanSettings.clamp(meals) {
        case 1: [Slot(meal: .dinner, share: 1)]
        case 2: [Slot(meal: .lunch, share: 0.4), Slot(meal: .dinner, share: 0.6)]
        default: [Slot(meal: .breakfast, share: 0.25), Slot(meal: .lunch, share: 0.35), Slot(meal: .dinner, share: 0.4)]
        }
    }

    /// Bei einer Mahlzeit pro Tag passen sieben Gerichte in eine Antwort, sonst drei Tage.
    static func defaultDays(meals: Int) -> Int { meals == 1 ? maxDays : 3 }

    static func isCoachDish(_ product: FoodProduct) -> Bool { product.code.hasPrefix(codePrefix) }

    // MARK: Quelle

    enum Source: Equatable { case local, online, askConsent }

    /// Beispieldaten und UI-Test senden nie. Ohne Schlüssel bleibt alles lokal, ohne Einwilligung wird gefragt.
    static func source(isSample: Bool, isUITest: Bool, hasKey: Bool, consent: Bool) -> Source {
        if isSample || isUITest || !hasKey { return .local }
        return consent ? .online : .askConsent
    }

    // MARK: Lokaler Rückfall

    /// Rezepte als große Teller (ca. 900–1400 kcal), damit eine einzige Mahlzeit am Tag das Ziel trifft.
    /// Kleinere Mahlzeiten ergeben sich über die Portionsgröße (ab 0,25).
    static let recipes: [MealPlanDish] = [
        MealPlanDish(name: "Hähnchen-Reis-Bowl mit Brokkoli",
                     ingredients: ["Hähnchenbrust", "Basmatireis", "Brokkoli", "Olivenöl", "Sojasauce"],
                     kcal: 1_000, protein: 85, carbs: 105),
        MealPlanDish(name: "Lachs mit Kartoffeln und Spinat",
                     ingredients: ["Lachsfilet", "Kartoffeln", "Spinat", "Zitrone", "Butter"],
                     kcal: 1_100, protein: 70, carbs: 80),
        MealPlanDish(name: "Rindergulasch mit Vollkornnudeln",
                     ingredients: ["Rindfleisch", "Paprika", "Zwiebeln", "Tomaten", "Vollkornnudeln"],
                     kcal: 1_300, protein: 90, carbs: 115),
        MealPlanDish(name: "Thunfisch-Nudelsalat mit Joghurtdressing",
                     ingredients: ["Vollkornnudeln", "Thunfisch", "Mais", "Gurke", "Joghurt"],
                     kcal: 900, protein: 68, carbs: 100),
        MealPlanDish(name: "Putenpfanne mit Gemüsereis",
                     ingredients: ["Putenbrust", "Reis", "Zucchini", "Karotten", "Zwiebeln"],
                     kcal: 1_000, protein: 82, carbs: 105),
        MealPlanDish(name: "Rotes Linsen-Curry mit Reis und Skyr",
                     ingredients: ["Rote Linsen", "Kokosmilch", "Tomaten", "Spinat", "Reis", "Skyr"],
                     kcal: 1_100, protein: 62, carbs: 140),
        MealPlanDish(name: "Rührei-Bowl mit Avocado und Vollkornbrot",
                     ingredients: ["Eier", "Avocado", "Vollkornbrot", "Tomaten", "Hüttenkäse"],
                     kcal: 950, protein: 58, carbs: 60),
        MealPlanDish(name: "Hackfleisch-Gemüse-Pfanne mit Kartoffeln",
                     ingredients: ["Rinderhack", "Kartoffeln", "Paprika", "Zucchini", "Tomatenmark"],
                     kcal: 1_400, protein: 85, carbs: 95),
        MealPlanDish(name: "Kabeljau mit Süßkartoffeln und Bohnen",
                     ingredients: ["Kabeljau", "Süßkartoffeln", "grüne Bohnen", "Olivenöl", "Zitrone"],
                     kcal: 900, protein: 72, carbs: 90),
        MealPlanDish(name: "Hähnchen-Quark-Wraps mit Salat",
                     ingredients: ["Wraps", "Hähnchenbrust", "Magerquark", "Salat", "Gurke"],
                     kcal: 1_000, protein: 80, carbs: 85),
        MealPlanDish(name: "Garnelen-Reispfanne mit Paprika",
                     ingredients: ["Garnelen", "Reis", "Paprika", "Erbsen", "Knoblauch"],
                     kcal: 900, protein: 65, carbs: 100),
        MealPlanDish(name: "Kichererbsen-Bowl mit Feta und Ei",
                     ingredients: ["Kichererbsen", "Feta", "Eier", "Gurke", "Quinoa"],
                     kcal: 1_050, protein: 55, carbs: 115)
    ]

    /// Wählt das Rezept, dessen Größe dem Ziel am nächsten liegt, und skaliert es in 0,05-Portionen auf das Ziel.
    /// Rezepte, die so nur mit Portionen unter 0,25 oder über 3 passen, kommen zuletzt; bereits Genutztes (`avoid`) danach.
    static func fallbackDish(targetKcal: Double, avoid: Set<String> = []) -> MealPlanDish {
        let target = targetKcal.isFinite && targetKcal > 0 ? targetKcal : 700
        let avoided = Set(avoid.map { $0.lowercased() })
        let ranked = recipes.map { recipe -> (dish: MealPlanDish, key: [Double]) in
            let factor = target / recipe.kcal
            let usable = (0.25...3).contains(factor)
            let reasonable = (0.5...2.2).contains(factor)
            let key = [usable ? 0 : 1, avoided.contains(recipe.name.lowercased()) ? 1 : 0, reasonable ? 0 : 1, abs(log(factor))]
            return (recipe, key)
        }
        let best = ranked.min { $0.key.lexicographicallyPrecedes($1.key) } ?? ranked[0]
        var dish = best.dish
        dish.portions = min(3, max(0.25, (target / dish.kcal * 20).rounded() / 20))
        return dish
    }

    /// Ein Gericht je Slot und Tag, in der Reihenfolge Tag für Tag. Gerichte wiederholen sich erst, wenn alle dran waren.
    static func fallbackPlan(_ request: MealPlanRequest) -> [[MealPlanDish]] {
        let slots = slots(request.meals)
        var picked = Set<String>()
        return (0..<max(0, request.days)).map { _ in
            slots.map { slot in
                if picked.count >= recipes.count { picked = [] }
                let dish = fallbackDish(targetKcal: request.kcal * slot.share, avoid: picked.union(request.avoid))
                picked.insert(dish.name)
                return dish
            }
        }
    }

    // MARK: JSON (KI)

    static let schema = """
    {
      "type": "object",
      "properties": {
        "dishes": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": {"type": "string"},
              "ingredients": {"type": "array", "items": {"type": "string"}},
              "kcal": {"type": "number"},
              "protein": {"type": "number"},
              "carbs": {"type": "number"}
            },
            "required": ["name", "ingredients", "kcal", "protein", "carbs"],
            "additionalProperties": false
          }
        }
      },
      "required": ["dishes"],
      "additionalProperties": false
    }
    """

    static func system(for request: MealPlanRequest) -> String {
        """
        Du planst Mahlzeiten für die App Health. Verwende kurze deutsche Gerichtsnamen und eine Zutatenliste mit \
        höchstens acht Zutaten. Alltagstaugliche, proteinreiche Gerichte, keine Wiederholungen. \
        Gib je Gericht Energie in kcal sowie Eiweiß und Kohlenhydrate in Gramm für die ganze Mahlzeit an. \
        Treffe das Kalorienziel jeder Mahlzeit auf etwa 10 Prozent genau. Gib ausschließlich JSON nach diesem Schema aus:
        \(schema)
        """
    }

    static func userMessage(for request: MealPlanRequest) -> String {
        let slots = slots(request.meals)
        let lines = slots.map { "\($0.meal.title): etwa \(Int((request.kcal * $0.share).rounded())) kcal" }
        var text = """
        Plane \(request.days) Tag(e) mit je \(slots.count) Mahlzeit(en). Tagesziel: \(Int(request.kcal.rounded())) kcal, \
        mindestens \(Int(request.protein.rounded())) g Eiweiß, etwa \(Int(request.carbs.rounded())) g Kohlenhydrate.
        Mahlzeiten je Tag in dieser Reihenfolge: \(lines.joined(separator: "; ")).
        Liste die Gerichte Tag für Tag auf, insgesamt \(request.days * slots.count).
        """
        let avoid = request.avoid.prefix(20).filter { !$0.isEmpty }
        if !avoid.isEmpty { text += "\nNicht verwenden: " + avoid.joined(separator: ", ") + "." }
        return text
    }

    static func parse(_ json: String, expected: Int) throws -> [MealPlanDish] {
        guard json.utf8.count <= 32_000,
              let response = try? JSONDecoder().decode(Response.self, from: Data(json.utf8)),
              response.dishes.count == expected else {
            throw CoachProviders.ReplyError.invalidResponse
        }
        return try response.dishes.map { dish in
            let name = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let ingredients = dish.ingredients.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !name.isEmpty, name.count <= 100,
                  name.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil,
                  (1...12).contains(ingredients.count),
                  ingredients.allSatisfy({ !$0.isEmpty && $0.count <= 60 }),
                  (50...4_500).contains(dish.kcal),
                  (0...400).contains(dish.protein), (0...800).contains(dish.carbs) else {
                throw CoachProviders.ReplyError.invalidResponse
            }
            return MealPlanDish(name: name, ingredients: ingredients, kcal: dish.kcal, protein: dish.protein, carbs: dish.carbs)
        }
    }

    private struct Response: Decodable { let dishes: [MealPlanDish] }

    /// Ordnet KI-Gerichte den Slots zu. Was das Kalorienziel zu weit verfehlt, ersetzt ein lokales Gericht.
    static func reconcile(_ dishes: [MealPlanDish], request: MealPlanRequest) -> [[MealPlanDish]] {
        let slots = slots(request.meals)
        var used = Set(request.avoid)
        var result: [[MealPlanDish]] = []
        // Lokale Ersatzgerichte sollen sich nicht mit KI-Gerichten doppeln.
        used.formUnion(dishes.map(\.name))
        for day in 0..<request.days {
            var row: [MealPlanDish] = []
            for (index, slot) in slots.enumerated() {
                let target = request.kcal * slot.share
                var dish = dishes[day * slots.count + index]
                if abs(dish.totalKcal - target) > target * acceptedAIDeviation {
                    dish = fallbackDish(targetKcal: target, avoid: used)
                }
                used.insert(dish.name)
                row.append(dish)
            }
            result.append(row)
        }
        return result
    }

    /// Fragt den Coach (Anbieter-Schicht mit Einwilligungsprüfung). Wirft bei jedem Fehler; der Aufrufer fällt dann lokal zurück.
    static func onlinePlan(
        _ request: MealPlanRequest, anthropicKey: String?, openAIKey: String?,
        maySend: @escaping @Sendable () -> Bool, send: @escaping CoachProviders.Transport = CoachProviders.fetch
    ) async throws -> [[MealPlanDish]] {
        let expected = request.days * slots(request.meals).count
        let dishes = try await CoachProviders.structuredReply(
            system: system(for: request), user: userMessage(for: request), schema: schema,
            anthropicKey: anthropicKey, openAIKey: openAIKey, maySend: maySend, send: send
        ) { try parse($0, expected: expected) }
        return reconcile(dishes, request: request)
    }

    /// Online, wenn erlaubt und erreichbar; sonst die lokale Rezeptliste. `usedOnline` sagt, was geklappt hat.
    @MainActor
    static func plan(_ request: MealPlanRequest, online: Bool) async -> (days: [[MealPlanDish]], usedOnline: Bool) {
        if online, let keys = try? CoachProviders.externalCredentials(),
           let days = try? await onlinePlan(request, anthropicKey: keys.anthropic, openAIKey: keys.openAI,
                                            maySend: { CoachProviders.allowsExternalData() }) {
            return (days, true)
        }
        return (fallbackPlan(request), false)
    }

    // MARK: Plan-Einträge

    static func product(for dish: MealPlanDish) -> FoodProduct {
        FoodProduct(
            code: codePrefix + UUID().uuidString, name: dish.name,
            brand: dish.ingredients.isEmpty ? nil : dish.ingredients.joined(separator: ", "),
            base: .grams, servingSize: nil, per100: FoodNutrients(),
            perServing: FoodNutrients(values: [.energy: dish.kcal, .protein: dish.protein, .carbohydrates: dish.carbs])
        )
    }

    static func item(for dish: MealPlanDish, day: Date, meal: FoodMeal) throws -> FoodPlanItem {
        try FoodPlanItem(day: day, meal: meal, product: product(for: dish), amount: dish.portions, unit: .servings)
    }
}

// MARK: - Speichern

enum MealPlanStore {
    /// Ersetzt offene Coach-Gerichte der betroffenen Tage durch den neuen Plan. Eigene und eingetragene Einträge bleiben.
    @MainActor
    static func apply(_ days: [[MealPlanDish]], from start: Date, meals: Int,
                      existing: [FoodPlanItem], in context: ModelContext) throws {
        let slots = MealPlanLogic.slots(meals)
        let covered = Set(FoodPlanLogic.days(from: start, count: days.count).map { Calendar.forma.startOfDay(for: $0) })
        var created: [FoodPlanItem] = []
        for (dayIndex, day) in FoodPlanLogic.days(from: start, count: days.count).enumerated() {
            for (index, dish) in days[dayIndex].enumerated() where index < slots.count {
                created.append(try MealPlanLogic.item(for: dish, day: day, meal: slots[index].meal))
            }
        }
        let stale = existing.filter {
            $0.loggedAt == nil && covered.contains($0.day) && ($0.product.map(MealPlanLogic.isCoachDish) ?? false)
        }
        try FoodEntry.saveChange(in: context) {
            for item in stale { context.delete(item) }
            for item in created { context.insert(item) }
        }
    }

    /// Tauscht ein Coach-Gericht gegen ein neues für denselben Tag und dieselbe Mahlzeit.
    @MainActor
    static func replace(_ old: FoodPlanItem, with dish: MealPlanDish, in context: ModelContext) throws {
        let fresh = try MealPlanLogic.item(for: dish, day: old.day, meal: old.meal)
        try FoodEntry.saveChange(in: context) {
            context.delete(old)
            context.insert(fresh)
        }
    }
}
