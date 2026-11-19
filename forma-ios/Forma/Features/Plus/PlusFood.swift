import SwiftUI

/// Einzige Naht zum Tracker in `Features/Food/` (food-yazio): Essen, Wasser, Fasten, Gewicht.
/// Die Ansichten mit `standalone: true` bringen NavigationStack und Schließen-Knopf selbst mit.
enum PlusFood {
    // Barcode und Suche sind zwei Reiter im selben Sheet; „Essen suchen“ startet in der Suche.
    @ViewBuilder static func scan() -> some View { FoodScanSheet() }
    @ViewBuilder static func search() -> some View { FoodScanSheet(startInSearch: true) }
    @ViewBuilder static func photo() -> some View { FoodPhotoSheet() }
    @ViewBuilder static func log() -> some View { FoodLogView() }
    @ViewBuilder static func plan() -> some View { FoodPlanView() }
    @ViewBuilder static func water() -> some View { FoodWaterView(standalone: true) }
    @ViewBuilder static func fasting() -> some View { FoodFastingView(standalone: true) }
    @ViewBuilder static func weight() -> some View { FoodWeightView(standalone: true) }
}
