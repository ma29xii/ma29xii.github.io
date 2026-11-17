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
                    case .background:
                        lock.lockIfEnabled()
                    default:
                        break
                    }
                }
        }
    }

    /// Widgets, Mitteilungen und Kurzbefehle schreiben mit einem eigenen Kontext.
    /// Danach wird die Oberfläche mit frischen Daten neu aufgebaut.
    private func reloadIfNeeded() {
        let current = AppGroup.externalChangeCount
        guard current != seenExternalChange else { return }
        seenExternalChange = current
        context = ModelContext(Store.shared)
        generation += 1
    }
}

enum AppTab: Hashable {
    case habits
    case today
    case stats
    case settings
}

struct RootView: View {
    @Environment(AppLock.self) private var lock
    @State private var tab: AppTab = .habits

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
        .overlay {
            if lock.isLocked {
                LockScreen()
                    .transition(.opacity)
            }
        }
        .animation(.default, value: lock.isLocked)
        .task { lock.unlock() }
    }
}
