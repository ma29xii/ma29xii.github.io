import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

@main
struct StetigWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HabitGridWidget()
        MultiHabitWidget()
        TodayWidget()
        LogHabitControl()
    }
}

// MARK: - Kontrollzentrum

/// Auswahl der Gewohnheit für das Steuerelement im Kontrollzentrum.
struct SelectHabitControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Gewohnheit wählen"

    @Parameter(title: "Gewohnheit")
    var habit: HabitEntity?

    init() {}
}

/// Wie `LogHabitIntent`, aber ohne Pflichtangabe – das Steuerelement kann
/// angelegt werden, bevor eine Gewohnheit gewählt ist.
struct LogSelectedHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Gewählte Gewohnheit abhaken"
    static let isDiscoverable = false

    @Parameter(title: "Gewohnheit")
    var habit: HabitEntity?

    init() {}

    init(habit: HabitEntity?) {
        self.habit = habit
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let habit else { return .result() }
        let context = ModelContext(Store.shared)
        if let model = Store.habit(uuid: habit.id, in: context) {
            model.advance(on: .today, in: context)
            AppGroup.noteExternalChange()
        }
        return .result()
    }
}

struct LogHabitControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "LogHabitControl", intent: SelectHabitControlIntent.self) { configuration in
            ControlWidgetButton(action: LogSelectedHabitIntent(habit: configuration.habit)) {
                Label(
                    configuration.habit?.name ?? "Gewohnheit wählen",
                    systemImage: configuration.habit.map { HabitGlyph.isEmoji($0.symbol) ? "checkmark.circle.fill" : $0.symbol } ?? "checkmark.circle.fill"
                )
            }
        }
        .displayName("Gewohnheit abhaken")
        .description("Hakt die gewählte Gewohnheit für heute ab.")
        .promptsForUserConfiguration()
    }
}

// MARK: - Widget: einzelne Gewohnheit

struct HabitGridEntry: TimelineEntry {
    let date: Date
    let habit: HabitWidgetData?
}

struct HabitGridProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitGridEntry {
        HabitGridEntry(date: Date(), habit: .sample)
    }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> HabitGridEntry {
        entry(for: configuration, preview: context.isPreview)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<HabitGridEntry> {
        Timeline(entries: [entry(for: configuration, preview: false)], policy: .after(WidgetLoader.nextRefresh()))
    }

    private func entry(for configuration: SelectHabitIntent, preview: Bool) -> HabitGridEntry {
        let all = WidgetLoader.habits()
        let selected = configuration.habit.flatMap { choice in all.first { $0.id == choice.id } }
        return HabitGridEntry(date: Date(), habit: selected ?? all.first ?? (preview ? .sample : nil))
    }
}

struct HabitGridWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HabitGridWidget", intent: SelectHabitIntent.self, provider: HabitGridProvider()) { entry in
            HabitGridWidgetView(entry: entry)
        }
        .configurationDisplayName("Gewohnheit")
        .description("Das Kachel-Raster einer Gewohnheit – mit Haken zum direkten Abhaken.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct HabitGridWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HabitGridEntry

    var body: some View {
        Group {
            if let habit = entry.habit {
                switch family {
                case .accessoryCircular: circular(habit)
                case .accessoryRectangular: rectangular(habit)
                case .accessoryInline: Text("\(habit.name): \(habit.streakText)")
                default:
                    HabitWidgetContent(
                        habit: habit,
                        size: family == .systemSmall ? .small : family == .systemLarge ? .large : .medium
                    )
                }
            } else {
                HabitWidgetContent(habit: nil, size: .small)
            }
        }
        .containerBackground(for: .widget) {
            WidgetBackdrop(tint: entry.habit?.tint ?? WidgetLoader.accent)
        }
    }

    private func rectangular(_ habit: HabitWidgetData) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                HabitGlyph(symbol: habit.symbol)
                    .font(.caption2.weight(.semibold))
                Text(habit.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(habit.snapshot.currentStreak)")
                    .font(.caption2.weight(.bold))
            }
            HeatmapGrid(snapshot: habit.snapshot, color: .primary)
                .widgetAccentable()
        }
    }

    private func circular(_ habit: HabitWidgetData) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                HabitGlyph(symbol: habit.symbol)
                    .font(.caption2.weight(.semibold))
                Text("\(habit.snapshot.currentStreak)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.6)
            }
            .widgetAccentable()
        }
    }
}

// MARK: - Widget: Heute

struct TodayEntry: TimelineEntry {
    let date: Date
    let habits: [HabitWidgetData]

    var summary: TodaySummary { TodaySummary(habits: habits) }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), habits: [.sample])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let habits = WidgetLoader.habits()
        completion(TodayEntry(date: Date(), habits: habits.isEmpty && context.isPreview ? [.sample] : habits))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: Date(), habits: WidgetLoader.habits())
        completion(Timeline(entries: [entry], policy: .after(WidgetLoader.nextRefresh())))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Heute")
        .description("Dein Tagesfortschritt und die offenen Gewohnheiten.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        let summary = entry.summary
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    ProgressRing(progress: summary.progress, color: .primary, lineWidth: 5)
                        .padding(3)
                    Text("\(summary.done)/\(summary.total)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .padding(8)
                }
                .widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heute \(summary.done)/\(summary.total)")
                        .font(.headline)
                        .widgetAccentable()
                    let open = summary.ordered.filter { !$0.isDone }.map(\.name)
                    Text(open.isEmpty ? "Alles erledigt" : "Offen: " + open.joined(separator: ", "))
                        .font(.caption)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemSmall:
                TodayWidgetContent(summary: summary, size: .small)
            case .systemLarge:
                TodayWidgetContent(summary: summary, size: .large)
            default:
                TodayWidgetContent(summary: summary, size: .medium)
            }
        }
        .containerBackground(for: .widget) {
            WidgetBackdrop(tint: WidgetLoader.accent)
        }
    }
}

// MARK: - Widget: mehrere Gewohnheiten

/// Auswahl der Gewohnheiten für das Mehrfach-Widget. Ohne Auswahl werden die ersten
/// Gewohnheiten in der Reihenfolge der App gezeigt.
struct SelectHabitsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Gewohnheiten wählen"
    static let description = IntentDescription("Wähle, welche Gewohnheiten das Widget zeigt.")

    @Parameter(title: "Gewohnheiten", size: [.systemMedium: 3, .systemLarge: 6])
    var habits: [HabitEntity]?

    init() {}
}

struct MultiHabitEntry: TimelineEntry {
    let date: Date
    let habits: [HabitWidgetData]
}

struct MultiHabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MultiHabitEntry {
        MultiHabitEntry(date: Date(), habits: [.sample])
    }

    func snapshot(for configuration: SelectHabitsIntent, in context: Context) async -> MultiHabitEntry {
        entry(for: configuration, preview: context.isPreview)
    }

    func timeline(for configuration: SelectHabitsIntent, in context: Context) async -> Timeline<MultiHabitEntry> {
        Timeline(entries: [entry(for: configuration, preview: false)], policy: .after(WidgetLoader.nextRefresh()))
    }

    private func entry(for configuration: SelectHabitsIntent, preview: Bool) -> MultiHabitEntry {
        let all = WidgetLoader.habits()
        let chosen = (configuration.habits ?? []).compactMap { choice in all.first { $0.id == choice.id } }
        let list = chosen.isEmpty ? all : chosen
        return MultiHabitEntry(date: Date(), habits: list.isEmpty && preview ? [.sample] : list)
    }
}

struct MultiHabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MultiHabitWidget", intent: SelectHabitsIntent.self, provider: MultiHabitProvider()) { entry in
            MultiHabitWidgetView(entry: entry)
        }
        .configurationDisplayName("Mehrere Gewohnheiten")
        .description("Bis zu sechs Gewohnheiten mit den letzten zwei Wochen – direkt abhaken.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct MultiHabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MultiHabitEntry

    var body: some View {
        MultiHabitWidgetContent(habits: entry.habits, limit: family == .systemLarge ? 6 : 3)
            .containerBackground(for: .widget) {
                WidgetBackdrop(tint: WidgetLoader.accent)
            }
    }
}
