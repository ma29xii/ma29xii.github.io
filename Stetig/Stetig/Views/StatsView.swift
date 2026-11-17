import Charts
import SwiftData
import SwiftUI

/// Auswertung über alle aktiven Gewohnheiten hinweg.
struct Overview {
    struct Item: Identifiable {
        let habit: Habit
        let snapshot: HabitSnapshot
        var id: UUID { habit.uuid }
    }

    let items: [Item]
    let today: Day

    init(habits: [Habit], today: Day = .today, weekStart: Int) {
        self.today = today
        self.items = habits.map { Item(habit: $0, snapshot: $0.snapshot(today: today, weekStart: weekStart)) }
    }

    /// Anteil der an diesem Tag fälligen Gewohnheiten, die erledigt wurden.
    /// `nil`, wenn an dem Tag nichts fällig war.
    func dayFraction(_ day: Day) -> Double? {
        Self.dayFraction(day, snapshots: items.map(\.snapshot))
    }

    static func dayFraction(_ day: Day, snapshots: [HabitSnapshot]) -> Double? {
        var relevant = 0
        var done = 0
        for snapshot in snapshots {
            if snapshot.isDone(day) {
                relevant += 1
                done += 1
            } else if snapshot.effectiveFrequency == .daily || snapshot.effectiveFrequency == .weekdays {
                if snapshot.isDue(day), !snapshot.isSkipped(day) {
                    relevant += 1
                }
            }
        }
        return relevant == 0 ? nil : Double(done) / Double(relevant)
    }

    var totalDone: Int { items.reduce(0) { $0 + $1.snapshot.totalDone } }

    var averageRate: Double {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.snapshot.rate(days: 30) } / Double(items.count)
    }

    var longestCurrentStreak: Int {
        items.filter { $0.snapshot.effectiveFrequency == .daily || $0.snapshot.effectiveFrequency == .weekdays }
            .map(\.snapshot.currentStreak)
            .max() ?? 0
    }

    var longestBestStreak: Int {
        items.filter { $0.snapshot.effectiveFrequency == .daily || $0.snapshot.effectiveFrequency == .weekdays }
            .map(\.snapshot.bestStreak)
            .max() ?? 0
    }

    /// Tage (rückwärts ab gestern bzw. heute), an denen alles Fällige erledigt war.
    func perfectDays(lookback: Int) -> (count: Int, bestRun: Int) {
        let snapshots = items.map(\.snapshot)
        var count = 0
        var best = 0
        var run = 0
        for offset in (0..<lookback).reversed() {
            let day = today.adding(-offset)
            guard let fraction = Self.dayFraction(day, snapshots: snapshots) else { continue }
            if fraction >= 1 {
                count += 1
                run += 1
                best = max(best, run)
            } else if day != today {
                run = 0
            }
        }
        return (count, best)
    }
}

struct StatsView: View {
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: [SortDescriptor(\Habit.sortOrder), SortDescriptor(\Habit.createdAt)])
    private var habits: [Habit]
    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 0
    @AppStorage(SettingsKey.accent, store: AppGroup.defaults) private var accentID = Palette.defaultID

    private var accent: HabitColor { Palette.entry(accentID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if habits.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Statistik",
                        systemImage: "chart.bar",
                        description: Text("Sobald du Gewohnheiten abhakst, erscheinen hier deine Auswertungen.")
                    )
                    .padding(.top, 80)
                } else {
                    content(Overview(habits: habits, weekStart: weekStart))
                }
            }
            .ambientBackground()
            .navigationTitle("Statistik")
        }
    }

    private func content(_ overview: Overview) -> some View {
        let perfect = overview.perfectDays(lookback: 365)
        return VStack(spacing: 16) {
            MetricsRow(items: [
                .init(value: Format.percent(overview.averageRate), label: "Ø Quote 30 T."),
                .init(value: "\(overview.totalDone)", label: "Erledigt"),
                .init(value: "\(perfect.count)", label: "Perfekte Tage"),
            ])

            trendCard(overview)
            heatmapCard(overview)
            weekdayCard(overview)
            rankingCard(overview)

            NavigationLink {
                AchievementsView(achievements: Achievements.evaluate(overview))
            } label: {
                let list = Achievements.evaluate(overview)
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.title3)
                        .foregroundStyle(accent.gradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Erfolge")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(list.filter(\.unlocked).count) von \(list.count) freigeschaltet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .card(padding: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .readableWidth()
    }

    // MARK: Karten

    private func trendCard(_ overview: Overview) -> some View {
        struct Point: Identifiable {
            let day: Day
            let value: Double
            var id: Int { day.ordinal }
        }
        let points = (0..<30).reversed().map { offset -> Point in
            let day = overview.today.adding(-offset)
            return Point(day: day, value: (overview.dayFraction(day) ?? 0) * 100)
        }
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle("Letzte 30 Tage")
            Chart(points) { point in
                BarMark(
                    x: .value("Tag", point.day.date(), unit: .day),
                    y: .value("Erledigt", point.value)
                )
                .foregroundStyle(accent.gradient)
                .opacity(point.value >= 100 ? 1 : 0.55)
                .cornerRadius(3)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Int.self) {
                            Text("\(number) %")
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .card(padding: 18)
    }

    private func heatmapCard(_ overview: Overview) -> some View {
        let snapshots = overview.items.map(\.snapshot)
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle("Gesamtbild")
            HeatmapGrid(today: overview.today, weekStart: weekStart, color: accent.color, endColor: accent.endColor, columns: 26, showMonths: true) { day in
                HeatCell(level: Overview.dayFraction(day, snapshots: snapshots) ?? 0)
            }
        }
        .card(padding: 18)
    }

    private func weekdayCard(_ overview: Overview) -> some View {
        var sums = Array(repeating: 0.0, count: 7)
        var counts = Array(repeating: 0, count: 7)
        for offset in 0..<84 {
            let day = overview.today.adding(-offset)
            if let fraction = overview.dayFraction(day) {
                sums[day.weekdayIndex] += fraction
                counts[day.weekdayIndex] += 1
            }
        }
        let averages = (0..<7).map { counts[$0] == 0 ? 0 : sums[$0] / Double(counts[$0]) * 100 }
        let order = (0..<7).map { ($0 + weekStart) % 7 }
        let best = averages.max() ?? 0
        let bestIndex = order.first { averages[$0] == best } ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            CardTitle("Wochentage", subtitle: best > 0 ? "Dein stärkster Tag: \(Day.weekdaySymbolsLong[bestIndex])" : "Noch keine Daten")
            Chart(order, id: \.self) { index in
                BarMark(
                    x: .value("Tag", Day.weekdaySymbolsShort[index]),
                    y: .value("Quote", averages[index])
                )
                .foregroundStyle(accent.gradient)
                .opacity(averages[index] == best && best > 0 ? 1 : 0.4)
                .cornerRadius(5)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis(.hidden)
            .frame(height: 120)
        }
        .card(padding: 18)
    }

    private func rankingCard(_ overview: Overview) -> some View {
        let ranked = overview.items
            .map { (item: $0, rate: $0.snapshot.rate(days: 30)) }
            .sorted { $0.rate > $1.rate }
        return VStack(alignment: .leading, spacing: 14) {
            CardTitle("Rangliste · 30 Tage")
            ForEach(ranked, id: \.item.id) { entry in
                let tint = Palette.entry(entry.item.habit.colorID)
                HStack(spacing: 12) {
                    HabitIcon(symbol: entry.item.habit.symbol, tint: tint, size: 32)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(entry.item.habit.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(Format.percent(entry.rate))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(tint.gradient)
                                    .frame(width: max(6, geo.size.width * min(1, max(0, entry.rate))))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .card(padding: 18)
    }
}

// MARK: - Erfolge

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let progress: Double

    var unlocked: Bool { progress >= 1 }
}

enum Achievements {
    static func evaluate(_ overview: Overview) -> [Achievement] {
        let total = Double(overview.totalDone)
        let best = Double(overview.longestBestStreak)
        let perfect = overview.perfectDays(lookback: 365)
        let quitBest = Double(
            overview.items.filter { $0.snapshot.rule.kind == .quit }.map(\.snapshot.bestStreak).max() ?? 0
        )
        let notes = Double(overview.items.reduce(0) { $0 + $1.habit.entries.filter { !$0.note.isEmpty }.count })

        func make(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ value: Double, _ goal: Double) -> Achievement {
            Achievement(id: id, title: title, detail: detail, symbol: symbol, progress: min(1, max(0, value / goal)))
        }

        return [
            make("first", "Erster Schritt", "Einen Tag erledigt", "figure.walk", total, 1),
            make("streak7", "Eine Woche", "7 Tage in Serie", "flame.fill", best, 7),
            make("streak30", "Ein Monat", "30 Tage in Serie", "calendar", best, 30),
            make("streak100", "Dreistellig", "100 Tage in Serie", "bolt.fill", best, 100),
            make("streak365", "Ein ganzes Jahr", "365 Tage in Serie", "crown.fill", best, 365),
            make("total50", "Routine", "50 erledigte Tage", "checkmark.seal.fill", total, 50),
            make("total250", "Gewohnheitstier", "250 erledigte Tage", "medal.fill", total, 250),
            make("total1000", "Meisterhaft", "1000 erledigte Tage", "trophy.fill", total, 1000),
            make("perfectDay", "Perfekter Tag", "Alles Fällige an einem Tag erledigt", "star.fill", Double(perfect.count), 1),
            make("perfectWeek", "Perfekte Woche", "7 perfekte Tage am Stück", "sparkles", Double(perfect.bestRun), 7),
            make("collector", "Vielseitig", "5 aktive Gewohnheiten", "square.grid.3x3.fill", Double(overview.items.count), 5),
            make("quit30", "Standhaft", "30 Tage ohne Rückfall", "shield.fill", quitBest, 30),
            make("notes10", "Reflektiert", "10 Notizen geschrieben", "pencil", notes, 10),
        ]
    }
}

struct AchievementsView: View {
    let achievements: [Achievement]

    @AppStorage(SettingsKey.accent, store: AppGroup.defaults) private var accentID = Palette.defaultID

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(achievements) { achievement in
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(achievement.unlocked ? AnyShapeStyle(Palette.entry(accentID).gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                            Image(systemName: achievement.symbol)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(achievement.unlocked ? Palette.entry(accentID).onColor : Color.secondary)
                        }
                        .frame(width: 60, height: 60)
                        Text(achievement.title)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(achievement.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2, reservesSpace: true)
                        if achievement.unlocked {
                            Label("Geschafft", systemImage: "checkmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.entry(accentID).color)
                        } else {
                            ProgressView(value: achievement.progress)
                                .tint(Palette.entry(accentID).color)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .card(padding: 14)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
        }
        .ambientBackground()
        .navigationTitle("Erfolge")
        .navigationBarTitleDisplayMode(.inline)
    }
}
