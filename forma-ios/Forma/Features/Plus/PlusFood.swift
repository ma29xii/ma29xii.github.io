import SwiftUI

/// Einzige Naht zum Tracker in `Features/Food/` (food-yazio): Essen, Wasser, Fasten, Gewicht.
/// Die Ansichten mit `standalone: true` bringen NavigationStack und Schließen-Knopf selbst mit.
enum PlusFood {
    @ViewBuilder static func track() -> some View { FoodTrackSheet() }
    @ViewBuilder static func scan() -> some View { FoodScanSheet() }
    /// Trainingsseite als eigenes Blatt. Sie bringt NavigationStack, Live-Training und Zusammenfassung selbst mit.
    @ViewBuilder static func training() -> some View { TrainingHomeView() }
    @ViewBuilder static func plan() -> some View { FoodPlanView() }
    @ViewBuilder static func water() -> some View { FoodWaterView(standalone: true) }
    @ViewBuilder static func fasting() -> some View { FoodFastingView(standalone: true) }
    @ViewBuilder static func weight() -> some View { FoodWeightView(standalone: true) }
}
