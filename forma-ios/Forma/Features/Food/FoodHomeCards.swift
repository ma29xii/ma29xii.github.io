import SwiftUI

/// Texte der unteren Food-Karten, getrennt von der Ansicht, damit sie testbar bleiben.
enum FoodHomeCardsText {
    enum Trend: Equatable { case up, down, flat }

    /// Unterschied zum vorigen Wert; unter 0,05 kg gilt als gleich.
    static func weightTrend(latest: Double, previous: Double?) -> (trend: Trend, delta: Double)? {
        guard let previous, latest.isFinite, previous.isFinite else { return nil }
        let delta = latest - previous
        if abs(delta) < 0.05 { return (.flat, 0) }
        return (delta > 0 ? .up : .down, abs(delta))
    }

    static func nextPlanned(_ entries: [FoodPlanEntry], today: Date, calendar: Calendar = .forma) -> FoodPlanEntry? {
        let start = calendar.startOfDay(for: today)
        let order = Dictionary(uniqueKeysWithValues: FoodMeal.allCases.enumerated().map { ($1, $0) })
        return entries.filter { !$0.logged && $0.day >= start }
            .min { l, r in
                l.day != r.day ? l.day < r.day : (order[l.meal] ?? 0) < (order[r.meal] ?? 0)
            }
    }
}
