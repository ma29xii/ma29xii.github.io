import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct FormaApp: App {
    nonisolated static let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
    @State private var hub = DataHub()
    @State private var app = AppState()

    var body: some Scene {
        let backgroundHub = hub
        WindowGroup {
            RootView()
                .environment(hub)
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.selection)
        }
        .modelContainer(for: [Exercise.self, Routine.self, RoutineItem.self, WorkoutSession.self, SetRecord.self, JournalAnswer.self],
                        inMemory: FormaApp.isUITest)
        // iOS weckt Forma regelmäßig im Hintergrund (zusätzlich zu Apple-Health-Benachrichtigungen).
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await backgroundHub.backgroundRefresh()
            await BackgroundRefresh.schedule()
        }
    }
}

struct RootView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("forma.onboarded") private var onboarded = false
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
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
        .tabBarMinimizeBehavior(.never) // vier gleichrangige Tabs immer erreichbar (Codex R-01-12)
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
            // Training, das iOS im Hintergrund beendet hat, wiederherstellen.
            if !FormaApp.isUITest, app.liveWorkout == nil, let restored = LiveWorkout.restore() {
                app.liveWorkout = restored
            }
            if !onboarded && !FormaApp.isUITest { showOnboarding = true }
            await hub.refresh()
        }
        .onChange(of: sessions.count, initial: true) { _, _ in
            let since = Date.now.startOfDay.adding(days: -30)
            hub.setFormaWorkouts(sessions.filter { $0.start >= since }.map {
                WorkoutSummary(name: $0.title, start: $0.start, duration: max(0, $0.duration), energy: nil, isStrength: true)
            })
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
            if phase == .active { Task { await hub.refresh() } }
        }
    }
}

/// Planung des Hintergrundabrufs. iOS entscheidet selbst, wann genau (meist alle 1–4 Stunden,
/// abhängig von Nutzung und Akku). Zusammen mit der Apple-Health-Zustellung ergibt das einen
/// zuverlässigen Sync, ohne dass die App offen sein muss.
@MainActor
enum BackgroundRefresh {
    static let identifier = "com.ma29xii.forma.refresh"

    static func schedule(earliest: TimeInterval = 45 * 60) {
        guard !FormaApp.isUITest else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(earliest)
        try? BGTaskScheduler.shared.submit(request)
    }
}
