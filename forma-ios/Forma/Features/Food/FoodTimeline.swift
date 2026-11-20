import Foundation

/// Ein Punkt der Tages-Zeitleiste im Food-Tab: entweder schon gegessen oder vom Coach geplant („Geist“).
/// Reine Wertetypen, damit Sortierung und Balken ohne Datenbank testbar bleiben.
struct FoodTimelineItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case logged, planned }

    let id: String
    let kind: Kind
    let time: Date
    let title: String
    let kcal: Double?

    var isPlanned: Bool { kind == .planned }
}

enum FoodTimeline {
    /// Uhrzeit, an der ein geplantes Gericht in der Zeitleiste steht (Plan-Einträge haben keine eigene Zeit).
    static func slotHour(_ meal: FoodMeal) -> Int {
        switch meal {
        case .breakfast: 8
        case .lunch: 12
        case .snack: 15
        case .dinner: 19
        }
    }

    static func slotTime(meal: FoodMeal, day: Date, calendar: Calendar = .forma) -> Date {
        calendar.date(bySettingHour: slotHour(meal), minute: 0, second: 0, of: day) ?? day
    }

    /// Noch nicht übernommene Plan-Einträge als Geister an ihrer Tageszeit.
    static func planned(_ entries: [FoodPlanEntry], calendar: Calendar = .forma) -> [FoodTimelineItem] {
        entries.filter { !$0.logged }.map { entry in
            FoodTimelineItem(id: "plan-" + entry.id.uuidString, kind: .planned,
                             time: slotTime(meal: entry.meal, day: entry.day, calendar: calendar),
                             title: entry.product.name, kcal: entry.kcal)
        }
    }

    /// Zeitlich aufsteigend; bei gleicher Zeit steht Gegessenes vor Geplantem.
    static func merge(_ logged: [FoodTimelineItem], _ planned: [FoodTimelineItem]) -> [FoodTimelineItem] {
        (logged + planned).sorted { left, right in
            if left.time != right.time { return left.time < right.time }
            if left.kind != right.kind { return left.kind == .logged }
            return left.id < right.id
        }
    }

    /// Bei einer Mahlzeit pro Tag (OMAD) steht die eine Mahlzeit groß da – solange es nur sie gibt.
    static func isProminent(itemCount: Int, mealsPerDay: Int) -> Bool {
        mealsPerDay == 1 && itemCount == 1
    }
}

/// Der eine Balken im Kopf: gefüllt bis zum Anteil der Tageskalorien, geteilt in Protein, Kohlenhydrate und Fett.
enum FoodMacroBar {
    enum Kind: Hashable, Sendable { case protein, carbs, fat, unknown }

    struct Segment: Equatable, Sendable {
        let kind: Kind
        /// Anteil an der ganzen Balkenbreite (0 bis 1).
        let fraction: Double
    }

    /// Die Segmente teilen den gefüllten Teil im Verhältnis ihrer Energie (4/4/9 kcal je Gramm).
    /// Ohne Makro-Angaben, aber mit Kalorien, füllt ein einziges neutrales Segment.
    static func segments(protein: Double, carbs: Double, fat: Double,
                         consumed: Double, target: Double) -> [Segment] {
        guard target.isFinite, target > 0, consumed.isFinite, consumed > 0 else { return [] }
        let filled = min(1, consumed / target)
        func energy(_ grams: Double, _ perGram: Double) -> Double {
            grams.isFinite && grams > 0 ? grams * perGram : 0
        }
        let parts: [(Kind, Double)] = [(.protein, energy(protein, 4)), (.carbs, energy(carbs, 4)), (.fat, energy(fat, 9))]
        let total = parts.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [Segment(kind: .unknown, fraction: filled)] }
        return parts.filter { $0.1 > 0 }.map { Segment(kind: $0.0, fraction: filled * $0.1 / total) }
    }
}
