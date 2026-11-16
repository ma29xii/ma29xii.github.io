import AppIntents
import SwiftData
import WidgetKit

/// Eine Gewohnheit, wie sie Widgets, Kurzbefehle und Siri sehen.
struct HabitEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Gewohnheit"
    static let defaultQuery = HabitQuery()

    var id: String
    var name: String
    var symbol: String

    init(id: String, name: String, symbol: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }

    init(habit: Habit) {
        self.init(id: habit.uuid.uuidString, name: habit.name, symbol: habit.symbol)
    }

    var displayRepresentation: DisplayRepresentation {
        if HabitGlyph.isEmoji(symbol) {
            return DisplayRepresentation(title: "\(symbol) \(name)")
        }
        return DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

struct HabitQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HabitEntity] {
        let all = Self.load()
        return identifiers.compactMap { identifier in all.first { $0.id == identifier } }
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        Self.load()
    }

    func defaultResult() async -> HabitEntity? {
        Self.load().first
    }

    static func load() -> [HabitEntity] {
        let context = ModelContext(Store.shared)
        return Store.activeHabits(in: context).map { HabitEntity(habit: $0) }
    }
}

/// Hakt eine Gewohnheit für heute ab (oder zählt einen Schritt weiter).
/// Wird von den interaktiven Widgets und von Kurzbefehlen benutzt.
struct LogHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Gewohnheit abhaken"
    static let description = IntentDescription("Trägt die gewählte Gewohnheit für heute ein.")

    @Parameter(title: "Gewohnheit")
    var habit: HabitEntity

    init() {}

    init(habit: HabitEntity) {
        self.habit = habit
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = ModelContext(Store.shared)
        if let model = Store.habit(uuid: habit.id, in: context) {
            model.advance(on: .today, in: context)
            AppGroup.noteExternalChange()
        }
        return .result()
    }
}

/// Auswahl der Gewohnheit beim Konfigurieren eines Widgets.
struct SelectHabitIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Gewohnheit wählen"
    static let description = IntentDescription("Wähle die Gewohnheit, die das Widget zeigen soll.")

    @Parameter(title: "Gewohnheit")
    var habit: HabitEntity?

    init() {}
}
