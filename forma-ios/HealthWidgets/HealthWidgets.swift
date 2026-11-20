import AppIntents
import SwiftUI
import WidgetKit

@main
struct HealthWidgets: WidgetBundle {
    var body: some Widget {
        TodayHealthWidget()
        WeekWidget()
        HealthAgeWidget()
        SleepWidget()
        StepsWidget()
        EnergyWidget()
        SignalsWidget()
        WaterWidget()
        FastingWidget()
        TrainingLiveWidget()
        FastingLiveWidget()
        StartTrainingControl()
        AddWaterControl()
        FastingControl()
    }
}

struct StartTrainingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ma29xii.forma.start-training") {
            ControlWidgetButton(action: StartTrainingIntent()) {
                Label("Training starten", systemImage: "dumbbell.fill")
            }
        }
        .displayName("Training starten")
        .description("Starte direkt ein Training in Health.")
    }
}
