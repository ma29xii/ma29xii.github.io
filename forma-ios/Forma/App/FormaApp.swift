import SwiftUI
import SwiftData

@main
struct FormaApp: App {
    static let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
    @State private var hub = DataHub()
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(hub)
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.selection)
        }
        .modelContainer(for: [Exercise.self, Routine.self, RoutineItem.self, WorkoutSession.self, SetRecord.self, JournalAnswer.self],
                        inMemory: FormaApp.isUITest)
    }
}

struct RootView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("forma.onboarded") private var onboarded = false
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            Tab("Heute", systemImage: "circle.circle", value: AppTab.today) {
                TodayView()
            }
            Tab("Training", systemImage: "dumbbell", value: AppTab.training) {
                TrainingView()
            }
            Tab("Gesundheit", systemImage: "heart.text.square", value: AppTab.health) {
                HealthView()
            }
            Tab("Coach", systemImage: "bubble.left.and.text.bubble.right", value: AppTab.coach) {
                CoachView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(item: $app.liveWorkout) { workout in
            LiveWorkoutView(workout: workout)
        }
        .sheet(item: $app.finishedSession) { session in
            WorkoutSummaryView(session: session)
        }
        .sheet(isPresented: $app.showProfile) {
            ProfileView()
        }
        .sheet(isPresented: $app.showJournal) {
            JournalView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .task {
            TrainingSeed.seedIfNeeded(context)
            if !onboarded && !FormaApp.isUITest { showOnboarding = true }
            await hub.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await hub.refresh() } }
        }
    }
}
