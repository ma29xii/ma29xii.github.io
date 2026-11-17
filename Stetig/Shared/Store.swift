import Foundation
import SwiftData
import WidgetKit

extension Notification.Name {
    /// Daten wurden außerhalb der sichtbaren Oberfläche geändert (Widget, Mitteilung, Kurzbefehl).
    static let stetigExternalChange = Notification.Name("stetigExternalChange")
}

/// Gemeinsamer Speicherbereich von App und Widgets.
enum AppGroup {
    static let id: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String, !value.isEmpty, !value.contains("$(") {
            return value
        }
        return "group.io.github.ma29xii.stetig"
    }()

    static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard

    /// 0 = Montag, 6 = Sonntag.
    static var weekStart: Int {
        let value = defaults.integer(forKey: SettingsKey.weekStart)
        return (0...6).contains(value) ? value : 0
    }

    static var externalChangeCount: Int {
        defaults.integer(forKey: SettingsKey.externalChange)
    }

    static func noteExternalChange() {
        defaults.set(externalChangeCount + 1, forKey: SettingsKey.externalChange)
        NotificationCenter.default.post(name: .stetigExternalChange, object: nil)
    }
}

enum SettingsKey {
    static let weekStart = "weekStart"
    static let externalChange = "externalChange"
    static let appearance = "appearance"
    static let viewMode = "viewMode"
    static let gridColumns = "gridColumns"
    static let haptics = "haptics"
    static let appLock = "appLock"
    static let confetti = "confetti"
    static let sortMode = "sortMode"
    static let accent = "accent"
    static let summaryEnabled = "summaryEnabled"
    static let summaryMinutes = "summaryMinutes"
}

enum Store {
    static let schema = Schema([Habit.self, HabitEntry.self, HabitCategory.self])

    static var usesInMemoryStore: Bool {
        ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
    }

    static let shared: ModelContainer = make(inMemory: usesInMemoryStore)

    static func make(inMemory: Bool) -> ModelContainer {
        if !inMemory {
            do {
                let configuration = ModelConfiguration(schema: schema, url: storeURL(), cloudKitDatabase: .none)
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                print("Stetig: Datenbank konnte nicht geöffnet werden – \(error)")
            }
        }
        // Eigener Name je Container, damit sich flüchtige Speicher (Tests) nie Daten teilen.
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Stetig: Kein Datenspeicher verfügbar – \(error)")
        }
    }

    /// Bevorzugt den App-Group-Container (damit Widgets mitlesen können). Fehlt die
    /// Berechtigung – z. B. nach einem Sideload ohne App Group – wird der normale
    /// App-Ordner benutzt, die App funktioniert dann trotzdem.
    private static func storeURL() -> URL {
        let fileManager = FileManager.default
        let local = URL.applicationSupportDirectory.appending(path: "Stetig.store")
        try? fileManager.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)

        guard let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else {
            return local
        }
        let shared = group.appending(path: "Stetig.store")
        if !fileManager.fileExists(atPath: shared.path), fileManager.fileExists(atPath: local.path) {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: local.path + suffix)
                let target = URL(fileURLWithPath: shared.path + suffix)
                try? fileManager.copyItem(at: source, to: target)
            }
        }
        return shared
    }

    /// Speichert und aktualisiert die Widgets.
    static func commit(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("Stetig: Speichern fehlgeschlagen – \(error)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func activeHabits(in context: ModelContext) -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func habit(uuid: String, in context: ModelContext) -> Habit? {
        guard let id = UUID(uuidString: uuid) else { return nil }
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.uuid == id })
        return try? context.fetch(descriptor).first
    }
}
