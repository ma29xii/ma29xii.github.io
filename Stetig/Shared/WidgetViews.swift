import AppIntents
import SwiftData
import SwiftUI

// Darstellung der Home-Bildschirm-Widgets. Liegt im gemeinsamen Code, damit die App
// unter Einstellungen › Widgets & Siri exakt dieselben Views als Vorschau zeigen kann.

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

    var tint: HabitColor { Palette.entry(colorID) }
    var color: Color { tint.color }
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
            colorID: "mango",
            unit: "",
            isCounter: false,
            snapshot: HabitSnapshot(rule: rule, records: records, today: today)
        )
    }
}

enum WidgetLoader {
    static func habits(today: Day = .today) -> [HabitWidgetData] {
        let context = ModelContext(Store.shared)
        return habits(from: Store.activeHabits(in: context), today: today)
    }

    static func habits(from models: [Habit], today: Day = .today) -> [HabitWidgetData] {
        models
            .filter { !$0.isPaused && !$0.isArchived }
            .map { HabitWidgetData(habit: $0, today: today) }
    }

    /// Kurz nach Mitternacht neu laden, damit „heute“ stimmt.
    static func nextRefresh() -> Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? Date().addingTimeInterval(86_400)
        return tomorrow.addingTimeInterval(30)
    }

    static var accent: HabitColor {
        Palette.entry(AppGroup.defaults.string(forKey: SettingsKey.accent) ?? Palette.defaultID)
    }
}

/// Tagesfortschritt für das „Heute“-Widget.
struct TodaySummary {
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

// MARK: - Bausteine

struct WidgetCheck: View {
    let habit: HabitWidgetData
    var size: CGFloat = 30

    var body: some View {
        let done = habit.isDone
        let slipped = habit.snapshot.isSlip(habit.snapshot.today)
        let tint = habit.tint
        ZStack {
            if done || slipped {
                Circle().fill(tint.gradient)
            } else {
                Circle().fill(tint.color.opacity(0.16))
            }
            if habit.isCounter, !done, habit.snapshot.amount(habit.snapshot.today) > 0 {
                Circle()
                    .trim(from: 0, to: habit.snapshot.fraction(habit.snapshot.today))
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(size * 0.06)
                Text(Format.number(habit.snapshot.amount(habit.snapshot.today)))
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(tint.color)
                    .minimumScaleFactor(0.6)
            } else {
                Image(systemName: slipped ? "xmark" : "checkmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(done || slipped ? tint.onColor : tint.color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Widget „Gewohnheit“ (klein / mittel)

struct HabitWidgetContent: View {
    let habit: HabitWidgetData?
    let compact: Bool

    var body: some View {
        if let habit {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if !compact {
                        HabitIcon(symbol: habit.symbol, tint: habit.tint, size: 30)
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
                    .accessibilityLabel("\(habit.name) abhaken")
                }
                HeatmapGrid(snapshot: habit.snapshot, tint: habit.tint)
            }
        } else {
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
    }
}

// MARK: - Widget „Heute“ (klein / mittel / groß)

struct TodayWidgetContent: View {
    enum Size {
        case small
        case medium
        case large
    }

    let summary: TodaySummary
    let size: Size
    var accent: HabitColor = WidgetLoader.accent

    var body: some View {
        switch size {
        case .small:
            ring
        case .medium, .large:
            HStack(alignment: .center, spacing: 14) {
                ring.frame(maxWidth: 110)
                list(limit: size == .large ? 8 : 3)
            }
        }
    }

    private var ring: some View {
        ZStack {
            ProgressRing(progress: summary.progress, color: accent.color, endColor: accent.endColor, lineWidth: 10)
            VStack(spacing: 0) {
                Text("\(summary.done)/\(summary.total)")
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
            if summary.ordered.isEmpty {
                Text("Heute steht nichts an.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(summary.ordered.prefix(limit)) { habit in
                HStack(spacing: 8) {
                    HabitGlyph(symbol: habit.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(habit.tint.gradient)
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
