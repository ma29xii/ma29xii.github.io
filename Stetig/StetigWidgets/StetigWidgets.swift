import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

@main
struct StetigWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HabitGridWidget()
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
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
                default: HabitWidgetContent(habit: habit, compact: family == .systemSmall)
                }
            } else {
                HabitWidgetContent(habit: nil, compact: true)
            }
        }
        .containerBackground(.background, for: .widget)
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular])
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
            case .systemSmall:
                TodayWidgetContent(summary: summary, size: .small)
            case .systemLarge:
                TodayWidgetContent(summary: summary, size: .large)
            default:
                TodayWidgetContent(summary: summary, size: .medium)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}
