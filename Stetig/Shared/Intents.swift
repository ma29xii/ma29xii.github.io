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

    /// Der Titel ist immer nur der Name – so kann Siri ihn im gesprochenen Satz erkennen.
    var displayRepresentation: DisplayRepresentation {
        if HabitGlyph.isEmoji(symbol) {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(symbol)")
        }
        return DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

struct HabitQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [HabitEntity] {
        let all = Self.load()
        return identifiers.compactMap { identifier in all.first { $0.id == identifier } }
    }

    /// Findet Gewohnheiten auch bei ungefährer Eingabe („lesen“, „Wasser“).
    func entities(matching string: String) async throws -> [HabitEntity] {
        HabitVoice.match(string, in: Self.load())
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

// MARK: - Sprachlogik (ohne AppIntents, damit sie testbar ist)

enum HabitVoice {
    /// Namensabgleich: exakt, dann Anfang, dann enthalten – jeweils ohne Groß-/Kleinschreibung.
    static func match(_ query: String, in habits: [HabitEntity]) -> [HabitEntity] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !needle.isEmpty else { return habits }
        func folded(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        let exact = habits.filter { folded($0.name) == needle }
        if !exact.isEmpty { return exact }
        let prefix = habits.filter { folded($0.name).hasPrefix(needle) }
        if !prefix.isEmpty { return prefix }
        return habits.filter { folded($0.name).contains(needle) || needle.contains(folded($0.name)) }
    }

    /// Deutsche Aufzählung: „A“, „A und B“, „A, B und C“.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " und " + items[items.count - 1]
        }
    }

    private static func streakSentence(_ snapshot: HabitSnapshot) -> String {
        let streak = snapshot.currentStreak
        guard streak > 1 else { return "" }
        return " Serie: \(streak) \(snapshot.streakUnit(streak))."
    }

    /// Markiert die Gewohnheit für heute als erledigt und liefert Siris Antwort.
    /// Anders als der Widget-Haken schaltet das nie zurück – „gemacht“ bleibt „gemacht“.
    static func complete(_ habit: Habit, amount: Double? = nil, today: Day = .today, in context: ModelContext) -> String {
        switch habit.kind {
        case .quit:
            habit.setAmount(0, on: today, in: context)
            let snapshot = habit.snapshot(today: today)
            let streak = snapshot.currentStreak
            return "\(habit.name): heute ohne Rückfall. \(streak) \(snapshot.streakUnit(streak)) am Stück."
        case .build:
            let before = habit.snapshot(today: today)
            if let amount, amount > 0 {
                habit.add(amount, on: today, in: context)
            } else if before.isDone(today) {
                return "\(habit.name) ist heute schon erledigt." + streakSentence(before)
            } else {
                habit.setAmount(max(habit.dailyTarget, 1), on: today, in: context)
            }
            let after = habit.snapshot(today: today)
            if after.isDone(today) {
                return "\(habit.name) für heute abgehakt." + streakSentence(after)
            }
            return "\(Format.amount(after.amount(today), unit: habit.unit)) von \(Format.amount(habit.dailyTarget, unit: habit.unit)) bei \(habit.name)."
        }
    }

    /// Antwort auf „Wie läuft …?“.
    static func status(_ habit: Habit, today: Day = .today) -> String {
        if habit.isPaused { return "\(habit.name) ist gerade pausiert." }
        let snapshot = habit.snapshot(today: today)
        let streak = snapshot.currentStreak
        let best = snapshot.bestStreak
        if habit.kind == .quit {
            return "\(habit.name): \(streak) \(snapshot.streakUnit(streak)) ohne Rückfall. Rekord: \(best)."
        }
        var sentence: String
        if let progress = snapshot.periodProgress {
            let period = snapshot.effectiveFrequency == .perWeek ? "diese Woche" : "diesen Monat"
            sentence = "\(habit.name): \(progress.done) von \(progress.target) \(period)."
        } else if snapshot.isDone(today) {
            sentence = "\(habit.name) ist heute erledigt."
        } else if habit.isCounter {
            sentence = "\(habit.name): \(Format.amount(snapshot.amount(today), unit: habit.unit)) von \(Format.amount(habit.dailyTarget, unit: habit.unit)) heute."
        } else if snapshot.isDue(today) {
            sentence = "\(habit.name) ist heute noch offen."
        } else {
            sentence = "\(habit.name) ist heute nicht dran."
        }
        sentence += " Aktuelle Serie: \(streak) \(snapshot.streakUnit(streak)), Rekord: \(best)."
        return sentence
    }

    /// Antwort auf „Was ist heute offen?“.
    static func today(_ habits: [Habit], today: Day = .today) -> String {
        let active = habits.filter { !$0.isArchived && !$0.isPaused }
        guard !active.isEmpty else { return "Du hast noch keine Gewohnheiten angelegt." }
        let open = active.filter { $0.snapshot(today: today).isPending(today) }.map(\.name)
        if open.isEmpty { return "Alles erledigt für heute. Stark!" }
        if open.count == 1 { return "Noch offen: \(open[0])." }
        return "Noch \(open.count) offen: \(list(open))."
    }
}

// MARK: - Intents

/// Hakt eine Gewohnheit für heute ab bzw. nimmt den Haken wieder weg (Widget-Knopf).
struct LogHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Gewohnheit umschalten"
    static let description = IntentDescription("Setzt oder entfernt den Haken für heute.")
    static let isDiscoverable = false

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

/// „Hey Siri, heute Lesen in Stetig gemacht.“
struct CompleteHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Gewohnheit erledigen"
    static let description = IntentDescription("Markiert eine Gewohnheit für heute als erledigt. Ideal für Siri und eigene Kurzbefehle.")

    @Parameter(title: "Gewohnheit", requestValueDialog: "Welche Gewohnheit?")
    var habit: HabitEntity

    @Parameter(title: "Menge", description: "Optional, z. B. 2 für zwei Gläser oder 15 für 15 Minuten.")
    var amount: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$habit) für heute erledigen") {
            \.$amount
        }
    }

    init() {}

    init(habit: HabitEntity) {
        self.habit = habit
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(Store.shared)
        guard let model = Store.habit(uuid: habit.id, in: context) else {
            return .result(dialog: "Diese Gewohnheit gibt es nicht mehr.")
        }
        let answer = HabitVoice.complete(model, amount: amount, in: context)
        AppGroup.noteExternalChange()
        return .result(dialog: "\(answer)")
    }
}

/// „Hey Siri, wie läuft Lesen in Stetig?“
struct HabitStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Serie abfragen"
    static let description = IntentDescription("Sagt dir, wie es bei einer Gewohnheit gerade läuft.")

    @Parameter(title: "Gewohnheit", requestValueDialog: "Für welche Gewohnheit?")
    var habit: HabitEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(Store.shared)
        guard let model = Store.habit(uuid: habit.id, in: context) else {
            return .result(dialog: "Diese Gewohnheit gibt es nicht mehr.")
        }
        return .result(dialog: "\(HabitVoice.status(model))")
    }
}

/// „Hey Siri, was ist heute in Stetig offen?“
struct TodayStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Heute offen"
    static let description = IntentDescription("Liest vor, welche Gewohnheiten heute noch offen sind.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(Store.shared)
        return .result(dialog: "\(HabitVoice.today(Store.activeHabits(in: context)))")
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
