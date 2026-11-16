import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: [SortDescriptor(\Habit.sortOrder), SortDescriptor(\Habit.createdAt)])
    private var habits: [Habit]

    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 0
    @AppStorage(SettingsKey.confetti) private var confettiEnabled = true

    @State private var day = Day.today
    @State private var entryTarget: EntryTarget?
    @State private var confettiTrigger = 0

    struct EntryTarget: Identifiable {
        let habit: Habit
        let day: Day
        var id: String { "\(habit.uuid.uuidString)-\(day.ordinal)" }
    }

    struct Row: Identifiable {
        let habit: Habit
        let snapshot: HabitSnapshot
        let state: DayState
        var id: UUID { habit.uuid }
    }

    private func rows(today: Day) -> [Row] {
        habits.filter { !$0.isPaused }.map { habit in
            let snapshot = habit.snapshot(today: today, weekStart: weekStart)
            return Row(habit: habit, snapshot: snapshot, state: snapshot.state(day))
        }
    }

    var body: some View {
        let today = Day.today
        let all = rows(today: today)
        let open = all.filter { $0.state == .pending || $0.state == .slipped }
        let done = all.filter { $0.state == .done }
        let skipped = all.filter { $0.state == .skipped }
        let total = open.count + done.count
        let allDone = total > 0 && open.isEmpty

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    progressCard(done: done.count, total: total, today: today)

                    if habits.isEmpty {
                        ContentUnavailableView(
                            "Noch nichts geplant",
                            systemImage: "checkmark.circle",
                            description: Text("Lege im Tab „Gewohnheiten“ deine erste Gewohnheit an.")
                        )
                        .padding(.top, 30)
                    } else if total == 0, skipped.isEmpty {
                        ContentUnavailableView(
                            "Heute steht nichts an",
                            systemImage: "sun.max",
                            description: Text("Genieße den freien Tag.")
                        )
                        .padding(.top, 30)
                    }

                    section("Offen", rows: open)
                    section("Erledigt", rows: done)
                    section("Übersprungen", rows: skipped)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(day == today ? "Heute" : day.weekdayLong)
            .toolbar {
                if day != today {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Heute") {
                            withAnimation(.snappy) { day = today }
                        }
                    }
                }
            }
            .sheet(item: $entryTarget) { target in
                EntrySheet(habit: target.habit, day: target.day)
            }
            .onChange(of: allDone) { wasDone, isDone in
                if isDone, !wasDone, confettiEnabled, day == today {
                    confettiTrigger += 1
                }
            }
        }
        .overlay {
            ConfettiView(trigger: confettiTrigger)
        }
    }

    // MARK: Fortschritt

    private func progressCard(done: Int, total: Int, today: Day) -> some View {
        let progress = total == 0 ? 0 : Double(done) / Double(total)
        return VStack(spacing: 16) {
            HStack {
                Button("Vorheriger Tag", systemImage: "chevron.left") {
                    withAnimation(.snappy) { day = day.adding(-1) }
                }
                Spacer()
                Text(day.longTitle)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                Spacer()
                Button("Nächster Tag", systemImage: "chevron.right") {
                    withAnimation(.snappy) { day = day.adding(1) }
                }
                .disabled(day >= today)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)

            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: progress, color: .accentColor, lineWidth: 12)
                        .animation(.snappy, value: progress)
                    Text("\(done)/\(total)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(done: done, total: total))
                        .font(.title3.weight(.bold))
                    Text(total == 0 ? "Keine fälligen Gewohnheiten" : "\(Format.percent(progress)) des Tages geschafft")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .card()
    }

    private func headline(done: Int, total: Int) -> String {
        if total == 0 { return "Frei" }
        if done == total { return "Alles geschafft" }
        if done == 0 { return "Los geht’s" }
        let left = total - done
        return left == 1 ? "Noch eine offen" : "Noch \(left) offen"
    }

    // MARK: Listen

    @ViewBuilder
    private func section(_ title: String, rows: [Row]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                ForEach(rows) { row in
                    rowView(row)
                }
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        let habit = row.habit
        let color = Palette.color(habit.colorID)
        return HStack(spacing: 12) {
            HabitIcon(symbol: habit.symbol, color: color, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle(row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if row.state == .skipped {
                Image(systemName: "forward.end.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
            } else {
                CompleteButton(habit: habit, snapshot: row.snapshot, day: day, size: 38)
            }
        }
        .card(padding: 12)
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture {
            entryTarget = EntryTarget(habit: habit, day: day)
        }
        .contextMenu {
            Button("Eintrag bearbeiten", systemImage: "square.and.pencil") {
                entryTarget = EntryTarget(habit: habit, day: day)
            }
            if row.state == .skipped {
                Button("Überspringen aufheben", systemImage: "arrow.uturn.backward") {
                    habit.setSkipped(false, on: day, in: context)
                }
            } else {
                Button("Überspringen", systemImage: "forward.end") {
                    habit.setSkipped(true, on: day, in: context)
                }
            }
        }
    }

    private func subtitle(_ row: Row) -> String {
        let habit = row.habit
        let snapshot = row.snapshot
        if row.state == .slipped { return "Rückfall eingetragen" }
        if habit.kind == .quit {
            let streak = snapshot.currentStreak
            return "\(streak) \(snapshot.streakUnit(streak)) ohne"
        }
        if habit.isCounter {
            return "\(Format.number(snapshot.amount(day))) / \(Format.amount(habit.dailyTarget, unit: habit.unit))"
        }
        if let progress = snapshot.periodProgress {
            let period = snapshot.effectiveFrequency == .perWeek ? "diese Woche" : "diesen Monat"
            return "\(progress.done)/\(progress.target) \(period)"
        }
        let streak = snapshot.currentStreak
        return streak > 0 ? "\(streak) \(snapshot.streakUnit(streak)) in Serie" : habit.goalDescription
    }
}

// MARK: - Konfetti

/// Dezentes Konfetti, wenn alle Gewohnheiten des Tages erledigt sind.
struct ConfettiView: View {
    let trigger: Int

    @State private var start: Date?

    private static let duration: TimeInterval = 2.6

    private static func noise(_ seed: Double) -> Double {
        let value = sin(seed * 12.9898) * 43_758.5453
        return value - value.rounded(.down)
    }

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let time = timeline.date.timeIntervalSince(start)
                guard time >= 0, time < Self.duration else { return }
                let fade = min(1, (Self.duration - time) / 0.6)
                for index in 0..<80 {
                    let seed = Double(index) + 1
                    let lane = Self.noise(seed)
                    let speed = 0.55 + Self.noise(seed * 1.7) * 0.75
                    let delay = Self.noise(seed * 2.3) * 0.35
                    let local = max(0, time - delay)
                    let x = size.width * lane + sin(local * 3 + seed) * 22
                    let y = -24 + (size.height * 0.95) * (local / Self.duration) * speed + 240 * local * local / 6
                    let side = 6 + Self.noise(seed * 3.1) * 5
                    let color = Palette.all[index % Palette.all.count].color
                    var piece = context
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(local * (2 + Self.noise(seed * 4.7) * 5) + seed))
                    piece.opacity = fade
                    let rect = CGRect(x: -side / 2, y: -side / 4, width: side, height: side / 2)
                    piece.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            let started = Date()
            start = started
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration + 0.2) {
                if start == started { start = nil }
            }
        }
    }
}
