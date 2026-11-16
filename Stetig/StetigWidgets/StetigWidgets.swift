import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

@main
struct StetigWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HabitGridWidget()
        TodayWidget()
    }
}

// MARK: - Daten

/// Reine Wertkopie einer Gewohnheit für die Widget-Darstellung.
struct HabitWidgetData: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let colorID: String
    let unit: String
    let isCounter: Bool
    let snapshot: HabitSnapshot

    var color: Color { Palette.color(colorID) }
    var entity: HabitEntity { HabitEntity(id: id, name: name, symbol: symbol) }
    var state: DayState { snapshot.state(snapshot.today) }
    var isDone: Bool { snapshot.isDone(snapshot.today) }

    var streakText: String {
        let streak = snapshot.currentStreak
        return "\(streak) \(snapshot.streakUnit(streak))"
    }
}

extension HabitWidgetData {
    init(habit: Habit, today: Day) {
        self.init(
            id: habit.uuid.uuidString,
            name: habit.name,
            symbol: habit.symbol,
            colorID: habit.colorID,
            unit: habit.unit,
            isCounter: habit.isCounter,
            snapshot: habit.snapshot(today: today)
        )
    }

    static var sample: HabitWidgetData {
        let today = Day.today
        var records: [Int: DayRecord] = [:]
        for offset in 0..<200 where (offset * 7 + offset / 3) % 5 != 0 {
            records[today.adding(-offset).ordinal] = DayRecord(amount: 1)
        }
        let rule = HabitRule(firstDay: today.adding(-200))
        return HabitWidgetData(
            id: "sample",
            name: "Lesen",
            symbol: "book.fill",
            colorID: "indigo",
            unit: "",
            isCounter: false,
            snapshot: HabitSnapshot(rule: rule, records: records, today: today)
        )
    }
}

enum WidgetLoader {
    static func habits(today: Day = .today) -> [HabitWidgetData] {
        let context = ModelContext(Store.shared)
        return Store.activeHabits(in: context)
            .filter { !$0.isPaused }
            .map { HabitWidgetData(habit: $0, today: today) }
    }

    /// Kurz nach Mitternacht neu laden, damit „heute“ stimmt.
    static func nextRefresh() -> Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? Date().addingTimeInterval(86_400)
        return tomorrow.addingTimeInterval(30)
    }
}

// MARK: - Bausteine

struct WidgetCheck: View {
    let habit: HabitWidgetData
    var size: CGFloat = 30

    var body: some View {
        let done = habit.isDone
        let quit = habit.snapshot.rule.kind == .quit
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(habit.color.opacity(done ? 1 : 0.2))
            .frame(width: size, height: size)
            .overlay {
                if habit.isCounter, !done, habit.snapshot.amount(habit.snapshot.today) > 0 {
                    Text(Format.number(habit.snapshot.amount(habit.snapshot.today)))
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .foregroundStyle(habit.color)
                        .minimumScaleFactor(0.6)
                } else {
                    Image(systemName: quit && !done ? "xmark" : "checkmark")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(done ? Color.white : habit.color.opacity(0.7))
                }
            }
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
                case .accessoryInline: inline(habit)
                default: system(habit)
                }
            } else {
                empty
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Lege in Stetig eine Gewohnheit an")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private func system(_ habit: HabitWidgetData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if family != .systemSmall {
                    HabitIcon(symbol: habit.symbol, color: habit.color, size: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(habit.streakText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(intent: LogHabitIntent(habit: habit.entity)) {
                    WidgetCheck(habit: habit)
                }
                .buttonStyle(.plain)
            }
            HeatmapGrid(snapshot: habit.snapshot, color: habit.color)
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

    private func inline(_ habit: HabitWidgetData) -> some View {
        Text("\(habit.name): \(habit.streakText)")
    }
}

// MARK: - Widget: Heute

struct TodayEntry: TimelineEntry {
    let date: Date
    let habits: [HabitWidgetData]

    var relevant: [HabitWidgetData] {
        habits.filter { $0.state != .notDue && $0.state != .skipped }
    }

    var done: Int { relevant.filter(\.isDone).count }
    var total: Int { relevant.count }
    var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }

    /// Offene zuerst, dann erledigte.
    var ordered: [HabitWidgetData] {
        relevant.filter { !$0.isDone } + relevant.filter(\.isDone)
    }
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

    private var tint: Color { Palette.color("indigo") }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    ProgressRing(progress: entry.progress, color: .primary, lineWidth: 5)
                        .padding(3)
                    Text("\(entry.done)/\(entry.total)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .padding(8)
                }
                .widgetAccentable()
            case .systemSmall:
                ring
            default:
                HStack(alignment: .center, spacing: 14) {
                    ring.frame(maxWidth: 110)
                    list(limit: family == .systemLarge ? 8 : 3)
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var ring: some View {
        ZStack {
            ProgressRing(progress: entry.progress, color: tint, lineWidth: 10)
            VStack(spacing: 0) {
                Text("\(entry.done)/\(entry.total)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.6)
                Text("Heute")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .padding(5)
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.ordered.isEmpty {
                Text("Heute steht nichts an.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.ordered.prefix(limit)) { habit in
                HStack(spacing: 8) {
                    HabitGlyph(symbol: habit.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(habit.color)
                        .frame(width: 18)
                    Text(habit.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(habit.isDone ? .secondary : .primary)
                    Spacer(minLength: 0)
                    Button(intent: LogHabitIntent(habit: habit.entity)) {
                        WidgetCheck(habit: habit, size: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
