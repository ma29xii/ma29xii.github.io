import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct FormaApp: App {
    nonisolated static let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
    /// Nur für die Leistungsmessung im UI-Test: `-probeHide plan,metrics,...` blendet Abschnitte der Sleep-Seite aus.
    nonisolated static let probeHidden: Set<String> = {
        let args = ProcessInfo.processInfo.arguments
        guard isUITest, let index = args.firstIndex(of: "-probeHide"), index + 1 < args.count else { return [] }
        return Set(args[index + 1].split(separator: ",").map(String.init))
    }()
    private static let models: [any PersistentModel.Type] = [
        Exercise.self, Routine.self, RoutineItem.self, WorkoutSession.self, SetRecord.self, JournalAnswer.self,
        FoodEntry.self, FoodLibraryItem.self, FoodWaterEntry.self, FoodFast.self, FoodWeightEntry.self,
        FoodPlanItem.self
    ]
    @State private var hub = DataHub()
    @State private var app = AppState()

    init() {
        // Coach-Schlüssel aus dem App-Paket einmalig in den Schlüsselbund übernehmen.
        if !Self.isUITest {
            BundledKeys.installIfNeeded()
            // Siri-Kurzbefehle mit den aktuellen Parametern bei iOS anmelden.
            HealthShortcuts.updateAppShortcutParameters()
        }
    }

    var body: some Scene {
        let backgroundHub = hub
        WindowGroup {
            Group {
                if hub.isSample {
                    SampleRootView()
                        .modelContainer(for: Self.models, inMemory: true)
                } else {
                    RootView().environment(app)
                }
            }
            .environment(hub)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        }
        // JournalAnswer bleibt im Schema, damit vorhandene Trainingsspeicher beim Update geöffnet werden.
        .modelContainer(for: Self.models, inMemory: FormaApp.isUITest)
        // iOS weckt Health im Hintergrund. Den nächsten Termin zuerst planen, damit er auch steht,
        // wenn iOS den Abruf vorzeitig beendet.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.schedule()
            await backgroundHub.backgroundRefresh()
        }
    }
}

private struct SampleRootView: View {
    @State private var app = AppState(isDemo: true)

    var body: some View {
        RootView().environment(app)
    }
}

struct RootView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("forma.onboarded") private var onboarded = false
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var showOnboarding = false
    /// Was die Wurzel gerade präsentiert. Es folgt `app.liveWorkout` und `app.finishedSession`, solange die
    /// Trainingsseite aus dem Plus-Menü nicht offen ist (`trainingHomeOpen`); dann präsentiert sie selbst.
    @State private var shownWorkout: LiveWorkout?
    @State private var shownSummary: WorkoutSession?

    var body: some View {
        @Bindable var app = app
        TabView(selection: Binding(get: { app.selectedTab }, set: { app.selectTab($0) })) {
            Tab("Today", systemImage: "circle.circle", value: AppTab.today) {
                TodayView().scrollEdgeEffectStyle(.soft, for: .all)
            }
            Tab("Food", systemImage: "fork.knife", value: AppTab.food) {
                FoodHomeView().scrollEdgeEffectStyle(.soft, for: .all)
            }
            .accessibilityIdentifier("tab.food")
            Tab("Health", systemImage: "heart", value: AppTab.health) {
                HealthView().scrollEdgeEffectStyle(.soft, for: .all)
            }
            Tab("Coach", systemImage: "bubble.left.and.bubble.right", value: AppTab.coach) {
                CoachView().scrollEdgeEffectStyle(.soft, for: .all)
            }
            // Plus: Die Rolle `.search` setzt den Knopf als eigene runde Glas-Insel rechts neben die Leiste
            // (Systemplatz, keine nachgebaute Schwebefläche). Er wählt keinen Inhalt, sondern öffnet das Menü.
            Tab(value: AppTab.add, role: .search) {
                Color.clear
            } label: {
                Label {
                    Text(app.showPlus ? "Plus-Menü schließen" : "Plus")
                } icon: {
                    Image(systemName: "plus")
                        .rotationEffect(.degrees(app.showPlus ? 45 : 0))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0.06), value: app.showPlus)
                }
            }
            .accessibilityIdentifier("tab.plus")
        }
        // Ruhige Leiste: bleibt stehen, Glas vom System, Auswahl hell statt farbig.
        .tabBarMinimizeBehavior(.never)
        .plusFlow()
        .fullScreenCover(item: $shownWorkout) { workout in
            LiveWorkoutView(workout: workout)
        }
        // Wischt jemand die Zusammenfassung weg, gilt sie als geschlossen.
        .sheet(item: $shownSummary, onDismiss: {
            if !app.trainingHomeOpen { app.finishedSession = nil }
        }) { session in
            WorkoutSummaryView(session: session)
        }
        .sheet(isPresented: $app.showProfile) {
            ProfileView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .overlay {
            if !app.launchReady && !FormaApp.isUITest {
                HealthStartupView().transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: app.launchReady)
        .task {
            await Task.yield()
            TrainingSeed.seedIfNeeded(context)
            if app.isDemo {
                SampleData.seedWorkouts(hub.longDays, in: context)
            }
            app.profilePhoto = ProfilePhotoStore.load()
            WaterWidgetSync.sync(in: context, enabled: !app.isDemo)
            // Training, das iOS im Hintergrund beendet hat, wiederherstellen.
            if !app.isDemo, !FormaApp.isUITest, app.liveWorkout == nil,
               let restored = LiveWorkout.restore(alreadySaved: { id in
                   ((try? context.fetchCount(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.draftID == id }))) ?? 0) > 0
               }) {
                app.liveWorkout = restored
            } else if !app.isDemo, !FormaApp.isUITest, app.liveWorkout == nil {
                // Kein Entwurf zum Wiederherstellen: übrig gebliebene Sperrbildschirm-Anzeigen beenden.
                LiveTrainingActivity.endOrphans()
            }
            if !onboarded && !FormaApp.isUITest { showOnboarding = true }
            app.launchReady = !showOnboarding
            await hub.syncAndNotify(background: false)
        }
        .onChange(of: showOnboarding) { _, shown in
            if !shown { app.launchReady = true }
        }
        .onChange(of: app.liveWorkout?.draftID, initial: true) { _, _ in syncPresentations() }
        .onChange(of: app.finishedSession?.id, initial: true) { _, _ in syncPresentations() }
        .onChange(of: app.trainingHomeOpen) { _, _ in syncPresentations() }
        .onChange(of: sessions.count, initial: true) { _, _ in
            guard !app.isDemo else { return }
            let since = Date.now.startOfDay.adding(days: -30)
            hub.setFormaWorkouts(sessions.filter { $0.start >= since }.map {
                WorkoutSummary(name: $0.title, start: $0.start, duration: max(0, $0.duration), energy: nil, isStrength: true)
            })
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active, !hub.isSample, !FormaApp.isUITest else { return }
            let plan = UserDefaults.standard.double(forKey: FoodSettings.fastHoursKey)
            try? FastingWidgetSync.sync(in: context, planHours: plan)
            FastingActivity.reconcile(in: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && !app.isDemo { BackgroundRefresh.schedule() }
            if phase == .active {
                WaterWidgetSync.sync(in: context, enabled: !app.isDemo)
                Task { await hub.syncAndNotify(background: false) }
            }
        }
        // Ganz am Ende: Der Tracker liegt so auch in den hier gezeigten Sheets (Profil, Zusammenfassung) im Environment.
        .achievementTracking(healthScope: hub.achievementHealthScope)
    }
    private func syncPresentations() {
        let blocked = app.trainingHomeOpen
        shownWorkout = blocked ? nil : app.liveWorkout
        shownSummary = blocked ? nil : app.finishedSession
    }
}

/// Planung des Hintergrundabrufs. Wann genau, entscheidet iOS.
@MainActor
enum BackgroundRefresh {
    static let identifier = "com.ma29xii.forma.refresh"
    /// Ergebnis der letzten Terminanfrage für das Profil: frühester Zeitpunkt (Sekunden), Fehlertext, Zeitpunkt der Anfrage.
    static let plannedKey = "forma.refresh.planned"
    static let errorKey = "forma.refresh.error"
    static let attemptKey = "forma.refresh.attempt"

    static func schedule(earliest: TimeInterval = 45 * 60) {
        guard !FormaApp.isUITest else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        let start = Date.now.addingTimeInterval(earliest)
        request.earliestBeginDate = start
        let defaults = UserDefaults.standard
        defaults.set(Date.now.timeIntervalSince1970, forKey: attemptKey)
        do {
            try BGTaskScheduler.shared.submit(request)
            defaults.set(start.timeIntervalSince1970, forKey: plannedKey)
            defaults.removeObject(forKey: errorKey)
        } catch {
            defaults.removeObject(forKey: plannedKey)
            defaults.set(message(for: error), forKey: errorKey)
        }
    }

    private static func message(for error: any Error) -> String {
        switch (error as? BGTaskScheduler.Error)?.code {
        case .notPermitted: "Hintergrundaktualisierung ist für Health aus (iOS-Einstellungen)."
        case .unavailable: "Auf diesem Gerät nicht verfügbar."
        case .tooManyPendingTaskRequests: "iOS hat schon zu viele Termine vorgemerkt."
        default: "iOS hat den Termin abgelehnt."
        }
    }
}
