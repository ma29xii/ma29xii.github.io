import SwiftData
import SwiftUI

@main
struct StetigApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(SettingsKey.appearance) private var appearance = 0
    @AppStorage(SettingsKey.accent, store: AppGroup.defaults) private var accentID = Palette.defaultID
    @Environment(\.scenePhase) private var scenePhase

    @State private var context: ModelContext
    @State private var generation = 0
    @State private var seenExternalChange = AppGroup.externalChangeCount
    @State private var lock = AppLock()
    @State private var reloadPending = false

    init() {
        DemoData.seedIfRequested()
        _context = State(initialValue: ModelContext(Store.shared))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(generation)
                .modelContext(context)
                .environment(lock)
                .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
                .tint(Palette.entry(accentID).color)
                .onReceive(NotificationCenter.default.publisher(for: .stetigExternalChange)) { _ in
                    reloadIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        reloadIfNeeded()
                        lock.unlock()
                    case .inactive:
                        lock.coverIfEnabled()
                    case .background:
                        lock.lockIfEnabled()
                    default:
                        break
                    }
                }
        }
    }

    /// Widgets, Mitteilungen und Kurzbefehle schreiben mit einem eigenen Kontext.
    /// Danach wird die Oberfläche mit frischen Daten neu aufgebaut – aber nie,
    /// während ein Blatt offen ist (Timer, Editor), sonst gingen Eingaben verloren.
    private func reloadIfNeeded() {
        let current = AppGroup.externalChangeCount
        guard current != seenExternalChange else { return }
        if Self.isPresentingSheet {
            guard !reloadPending else { return }
            reloadPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                reloadPending = false
                reloadIfNeeded()
            }
            return
        }
        seenExternalChange = current
        context = ModelContext(Store.shared)
        generation += 1
    }

    private static var isPresentingSheet: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}

enum AppTab: String, Hashable {
    case habits
    case today
    case stats
    case settings
}

/// Bestätigung, nachdem ein eigener Siri-Satz eine Gewohnheit abgehakt hat.
struct VoiceConfirmation: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let tint: HabitColor
}

struct RootView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.modelContext) private var context
    /// Bleibt erhalten, wenn die Oberfläche nach Widget-Änderungen neu aufgebaut wird.
    @SceneStorage("tab") private var tab: AppTab = .habits
    @State private var confirmation: VoiceConfirmation?
    @State private var showStoreWarning = Store.openFailed
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]

    var body: some View {
        TabView(selection: $tab) {
            Tab("Gewohnheiten", systemImage: "square.grid.3x3.fill", value: AppTab.habits) {
                HabitsView()
            }
            Tab("Heute", systemImage: "checkmark.circle.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("Statistik", systemImage: "chart.bar.fill", value: AppTab.stats) {
                StatsView()
            }
            Tab("Einstellungen", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .accessibilityHidden(lock.isLocked)
        .overlay(alignment: .top) {
            if let confirmation {
                VoiceBanner(text: confirmation.text, tint: confirmation.tint)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: confirmation.id) {
                        try? await Task.sleep(for: .seconds(3.5))
                        withAnimation(.snappy) { self.confirmation = nil }
                    }
            }
        }
        .animation(.snappy, value: confirmation)
        .onContinueUserActivity(VoiceShortcut.activityType) { activity in
            completeFromVoice(activity)
        }
        .alert("Daten konnten nicht geladen werden", isPresented: $showStoreWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Stetig läuft gerade nur vorübergehend. Änderungen gehen beim Beenden verloren. Starte die App neu – deine gespeicherten Daten werden dabei nicht verändert.")
        }
        .task { lock.unlock() }
        .task(id: habits.map(\.name).sorted().joined(separator: "|")) {
            // Neue oder umbenannte Gewohnheiten sofort für Siri-Sätze bekannt machen.
            SiriSync.refresh()
        }
    }

    /// „Hey Siri, heute Lesen gemacht“ (eigener Satz): Stetig öffnet sich, hakt ab und bestätigt.
    private func completeFromVoice(_ activity: NSUserActivity) {
        guard let id = VoiceShortcut.habitID(from: activity),
              let habit = Store.habit(uuid: id, in: context) else { return }
        let answer = HabitVoice.complete(habit, in: context)
        confirmation = VoiceConfirmation(text: answer, tint: Palette.entry(habit.colorID))
    }
}
