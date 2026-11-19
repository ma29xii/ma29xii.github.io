import Foundation
import SwiftData

// MARK: - Datenmodell

/// Eine geplante Mahlzeit: Lebensmittel mit Menge für einen bestimmten Tag.
/// Das Produkt liegt als JSON, damit der Plan auch ohne Netz und ohne Katalog bestehen bleibt.
@Model
final class FoodPlanItem {
    var uid: UUID
    var createdAt: Date
    /// Anfang des geplanten Tages.
    var day: Date
    var mealRaw: String
    var amount: Double
    var unitRaw: String
    var productData: Data
    /// Für die Einkaufsliste abgehakt.
    var bought: Bool
    /// Wann der Plan ins Tagebuch übernommen wurde; `nil` solange offen.
    var loggedAt: Date?

    init(day: Date, meal: FoodMeal, product: FoodProduct, amount: Double, unit: FoodAmountUnit) throws {
        uid = UUID()
        createdAt = .now
        self.day = Calendar.forma.startOfDay(for: day)
        mealRaw = meal.rawValue
        self.amount = amount
        unitRaw = unit.rawValue
        productData = try JSONEncoder().encode(product)
        bought = false
        loggedAt = nil
    }

    var meal: FoodMeal { FoodMeal(rawValue: mealRaw) ?? .snack }
    var amountUnit: FoodAmountUnit { FoodAmountUnit(rawValue: unitRaw) ?? .base }
    var product: FoodProduct? { try? JSONDecoder().decode(FoodProduct.self, from: productData) }

    /// Wertkopie für die Rechenlogik; `nil`, wenn das gespeicherte Produkt nicht lesbar ist.
    var entry: FoodPlanEntry? {
        guard let product else { return nil }
        return FoodPlanEntry(id: uid, day: day, meal: meal, product: product, amount: amount,
                             unit: amountUnit, bought: bought, logged: loggedAt != nil)
    }
}

/// Wertkopie eines Plan-Eintrags. Die Logik rechnet nur damit und braucht keine Datenbank.
struct FoodPlanEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let day: Date
    let meal: FoodMeal
    let product: FoodProduct
    let amount: Double
    let unit: FoodAmountUnit
    var bought: Bool
    let logged: Bool

    var nutrients: FoodNutrients? { product.nutrients(for: amount, in: unit) }
    var kcal: Double? { nutrients?.values[.energy].flatMap { $0.isFinite ? $0 : nil } }
}

// MARK: - Einkaufsliste

/// Gruppen der Einkaufsliste in der Reihenfolge, in der man durch den Laden geht.
enum ShoppingGroup: Int, CaseIterable, Sendable {
    case produce, bakery, dairy, meat, pantry, drinks, other

    var title: String {
        switch self {
        case .produce: "Obst und Gemüse"
        case .bakery: "Backwaren"
        case .dairy: "Milch, Eier und Käse"
        case .meat: "Fleisch und Fisch"
        case .pantry: "Vorrat"
        case .drinks: "Getränke"
        case .other: "Sonstiges"
        }
    }

    /// shortcut: Die Produktdaten kennen keine Warengruppe. Die Zuordnung rät aus Wörtern im Namen;
    /// Unbekanntes landet in „Sonstiges“. Upgrade, sobald der Katalog eine Kategorie liefert.
    private static let rules: [(group: ShoppingGroup, words: [String])] = [
        (.meat, ["hähnchen", "hühner", "huhn", "pute", "rind", "schwein", "hack", "wurst", "schinken", "speck",
                 "lachs", "fisch", "thunfisch", "garnele", "fleisch", "steak"]),
        (.dairy, ["milch", "joghurt", "jogurt", "quark", "käse", "butter", "sahne", "skyr", "frischkäse",
                  "mozzarella", "eier", "ei"]),
        (.bakery, ["brot", "brötchen", "toast", "semmel", "croissant", "baguette", "wrap"]),
        (.drinks, ["wasser", "saft", "tee", "kaffee", "cola", "limo", "bier", "wein", "schorle", "getränk", "drink"]),
        (.produce, ["apfel", "äpfel", "banane", "birne", "beere", "tomate", "gurke", "salat", "paprika", "zwiebel",
                    "karotte", "möhre", "kartoffel", "brokkoli", "spinat", "zucchini", "obst", "gemüse", "orange",
                    "zitrone", "avocado", "pilz", "knoblauch", "lauch", "kohl", "traube", "mango", "ananas"]),
        (.pantry, ["nudel", "pasta", "reis", "haferflocken", "müsli", "mehl", "zucker", "olivenöl", "rapsöl", "linsen", "bohnen",
                   "kichererbsen", "nüsse", "mandel", "honig", "marmelade", "konserve", "cornflakes", "couscous",
                   "quinoa", "schokolade", "haferdrink"])
    ]

    static func group(forName name: String) -> ShoppingGroup {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init)
        for rule in rules {
            for word in words where rule.words.contains(where: { matches(word, $0) }) { return rule.group }
        }
        return .other
    }

    /// Lange Stichwörter dürfen mitten im Wort stehen („Vollkornbrot“), kurze nur am Anfang oder Ende.
    /// Zwei Buchstaben („ei“) gelten nur als ganzes Wort.
    private static func matches(_ word: String, _ key: String) -> Bool {
        if key.count <= 2 { return word == key }
        if key.count >= 5 { return word.contains(key) }
        return word.hasPrefix(key) || word.hasSuffix(key)
    }
}

/// Gesammelte Menge eines Lebensmittels in Gramm, Milliliter oder Portionen.
struct ShoppingQuantity: Equatable, Sendable {
    enum Kind: String, Sendable { case grams, milliliters, servings }

    let kind: Kind
    var value: Double

    var text: String {
        switch kind {
        case .grams:
            return value >= 1_000 ? FoodText.number(value / 1_000, digits: 2) + " kg" : FoodText.number(value.rounded()) + " g"
        case .milliliters:
            return value >= 1_000 ? FoodText.liters(value) : FoodText.number(value.rounded()) + " ml"
        case .servings:
            return value == 1 ? "1 Portion" : FoodText.number(value, digits: 2) + " Portionen"
        }
    }
}

struct ShoppingLine: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let brand: String?
    let group: ShoppingGroup
    let quantity: ShoppingQuantity
    /// Alle Plan-Einträge, aus denen die Zeile entsteht. Abhaken betrifft alle zusammen.
    let entryIDs: [UUID]
    /// Wahr, wenn jeder dieser Einträge abgehakt ist.
    let bought: Bool
}

// MARK: - Planungslogik

enum FoodPlanLogic {
    /// So viele Tage ab heute lassen sich planen.
    static let horizon = 7

    static func days(from start: Date, count: Int = horizon, calendar: Calendar = .forma) -> [Date] {
        let first = calendar.startOfDay(for: start)
        return (0..<max(0, count)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// Einträge eines Tages, nach Mahlzeit (Frühstück bis Snack) und Anlegen sortiert.
    static func entries(_ all: [FoodPlanEntry], on day: Date, calendar: Calendar = .forma) -> [FoodPlanEntry] {
        let order = Dictionary(uniqueKeysWithValues: FoodMeal.allCases.enumerated().map { ($1, $0) })
        return all.enumerated()
            .filter { calendar.isDate($0.element.day, inSameDayAs: day) }
            .sorted { lhs, rhs in
                let l = order[lhs.element.meal] ?? 0, r = order[rhs.element.meal] ?? 0
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    /// Offene Einträge vor heute: geplant, aber nie eingetragen.
    static func overdue(_ all: [FoodPlanEntry], today: Date, calendar: Calendar = .forma) -> [FoodPlanEntry] {
        let start = calendar.startOfDay(for: today)
        return all.filter { !$0.logged && $0.day < start }.sorted { $0.day < $1.day }
    }

    struct DaySummary: Equatable, Sendable {
        let kcal: Double
        /// Falsch, wenn bei mindestens einem Eintrag Energie unbekannt ist (dann ist `kcal` ein Mindestwert).
        let complete: Bool
        let count: Int
    }

    static func summary(of entries: [FoodPlanEntry]) -> DaySummary {
        var total = 0.0
        var complete = true
        for entry in entries {
            if let kcal = entry.kcal { total += kcal } else { complete = false }
        }
        return DaySummary(kcal: total, complete: complete, count: entries.count)
    }

    /// Übernehmen geht für heute und frühere Tage, nicht für kommende.
    static func canLog(day: Date, now: Date, calendar: Calendar = .forma) -> Bool {
        calendar.startOfDay(for: day) <= calendar.startOfDay(for: now)
    }

    /// Zeitpunkt des Tagebuch-Eintrags: heute „jetzt“, an früheren Tagen die übliche Uhrzeit der Mahlzeit.
    static func logDate(day: Date, meal: FoodMeal, now: Date, calendar: Calendar = .forma) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let hour: Int
        switch meal {
        case .breakfast: hour = 8
        case .lunch: hour = 12
        case .snack: hour = 15
        case .dinner: hour = 19
        }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    // MARK: Einkaufsliste

    /// Einkaufsmenge eines Eintrags. Portionen mit bekannter Portionsgröße werden in Gramm/Milliliter umgerechnet,
    /// damit Mengen desselben Produkts zusammenzählen.
    static func quantity(for entry: FoodPlanEntry) -> ShoppingQuantity? {
        guard entry.amount.isFinite, entry.amount > 0 else { return nil }
        let base: ShoppingQuantity.Kind = entry.product.base == .grams ? .grams : .milliliters
        switch entry.unit {
        case .base:
            return ShoppingQuantity(kind: base, value: entry.amount)
        case .servings:
            if let size = entry.product.servingSize, size.isFinite, size > 0 {
                return ShoppingQuantity(kind: base, value: entry.amount * size)
            }
            return ShoppingQuantity(kind: .servings, value: entry.amount)
        }
    }

    /// Einkaufsliste für alle noch nicht eingetragenen Einträge ab heute. Gleiche Produkte werden zusammengezählt.
    /// Sortierung: Gruppe, Offenes vor Abgehaktem, Name.
    static func shoppingLines(from entries: [FoodPlanEntry], today: Date, calendar: Calendar = .forma) -> [ShoppingLine] {
        let start = calendar.startOfDay(for: today)
        struct Bucket {
            var name: String
            var brand: String?
            var quantity: ShoppingQuantity
            var ids: [UUID]
            var allBought: Bool
        }
        var order: [String] = []
        var buckets: [String: Bucket] = [:]
        for entry in entries where !entry.logged && entry.day >= start {
            guard let quantity = quantity(for: entry) else { continue }
            let key = [entry.product.name.lowercased(), (entry.product.brand ?? "").lowercased(), quantity.kind.rawValue]
                .joined(separator: "|")
            if var bucket = buckets[key] {
                bucket.quantity.value += quantity.value
                bucket.ids.append(entry.id)
                bucket.allBought = bucket.allBought && entry.bought
                buckets[key] = bucket
            } else {
                order.append(key)
                buckets[key] = Bucket(name: entry.product.name, brand: entry.product.brand, quantity: quantity,
                                      ids: [entry.id], allBought: entry.bought)
            }
        }
        let lines = order.compactMap { key in
            buckets[key].map {
                ShoppingLine(id: key, name: $0.name, brand: $0.brand, group: ShoppingGroup.group(forName: $0.name),
                             quantity: $0.quantity, entryIDs: $0.ids, bought: $0.allBought)
            }
        }
        return lines.sorted { lhs, rhs in
            if lhs.group != rhs.group { return lhs.group.rawValue < rhs.group.rawValue }
            if lhs.bought != rhs.bought { return !lhs.bought }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Offene Zeilen als Text zum Teilen (Nachrichten, Notizen).
    static func shoppingText(_ lines: [ShoppingLine]) -> String {
        let open = lines.filter { !$0.bought }
        guard !open.isEmpty else { return "" }
        var text = "Einkaufsliste"
        for group in ShoppingGroup.allCases {
            let inGroup = open.filter { $0.group == group }
            guard !inGroup.isEmpty else { continue }
            text += "\n\n" + group.title
            for line in inGroup { text += "\n• \(line.name): \(line.quantity.text)" }
        }
        return text
    }
}

// MARK: - Tagebuch-Übernahme

enum FoodPlanStore {
    enum LogError: Error { case unreadable }

    /// Trägt die Einträge ins Tagebuch ein und markiert sie als übernommen. Alles in einer Transaktion:
    /// Klappt eines nicht, bleibt der Plan unverändert. Bereits übernommene Einträge werden übersprungen.
    @MainActor
    @discardableResult
    static func log(_ items: [FoodPlanItem], in context: ModelContext, now: Date = .now) throws -> Int {
        let open = items.filter { $0.loggedAt == nil && FoodPlanLogic.canLog(day: $0.day, now: now) }
        var prepared: [(FoodPlanItem, FoodEntry)] = []
        for item in open {
            guard let product = item.product, let nutrients = item.entry?.nutrients else { throw LogError.unreadable }
            let date = FoodPlanLogic.logDate(day: item.day, meal: item.meal, now: now)
            prepared.append((item, FoodEntry(date: date, meal: item.meal, product: product, amount: item.amount,
                                             in: item.amountUnit, nutrients: nutrients)))
        }
        guard !prepared.isEmpty else { return 0 }
        try FoodEntry.saveChange(in: context) {
            for (item, entry) in prepared {
                context.insert(entry)
                item.loggedAt = now
            }
        }
        return prepared.count
    }
}
