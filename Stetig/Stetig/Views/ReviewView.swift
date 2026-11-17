import SwiftData
import SwiftUI

// MARK: - Auswertung

/// Wochen- bzw. Jahresrückblick über alle Gewohnheiten.
struct Review {
    enum Scope {
        case week
        case year
    }

    struct Line: Identifiable {
        let habit: Habit
        let snapshot: HabitSnapshot
        let done: Int
        let due: Int
        var id: UUID { habit.uuid }
        var rate: Double? { due == 0 ? nil : Double(done) / Double(due) }
    }

    struct DayEntry: Identifiable {
        let day: Day
        let done: Int
        let due: Int
        var id: Int { day.ordinal }
        var rate: Double? { due == 0 ? nil : Double(done) / Double(due) }
    }

    let scope: Scope
    let start: Day
    let end: Day
    let today: Day
    let lines: [Line]
    let days: [DayEntry]

    init(scope: Scope, offset: Int, habits: [Habit], today: Day = .today, weekStart: Int) {
        let bounds = Self.bounds(scope: scope, offset: offset, today: today, weekStart: weekStart)
        self.init(scope: scope, start: bounds.start, end: bounds.end, habits: habits, today: today, weekStart: weekStart)
    }

    init(scope: Scope, start: Day, end: Day, habits: [Habit], today: Day, weekStart: Int) {
        self.scope = scope
        self.start = start
        self.end = end
        self.today = today
        let snapshots = habits.map { (habit: $0, snapshot: $0.snapshot(today: today, weekStart: weekStart)) }
        lines = snapshots.compactMap { item in
            let result = item.snapshot.tally(from: start, through: end)
            guard result.due > 0 || result.done > 0 else { return nil }
            return Line(habit: item.habit, snapshot: item.snapshot, done: result.done, due: result.due)
        }
        .sorted { ($0.rate ?? 0, $0.done) > ($1.rate ?? 0, $1.done) }

        var days: [DayEntry] = []
        var day = start
        let last = min(end, today)
        while day <= last {
            var done = 0
            var due = 0
            for item in snapshots {
                let result = item.snapshot.dayTally(day)
                done += result.done
                due += result.due
            }
            days.append(DayEntry(day: day, done: done, due: due))
            day = day.adding(1)
        }
        self.days = days
    }

    static func bounds(scope: Scope, offset: Int, today: Day, weekStart: Int) -> (start: Day, end: Day) {
        switch scope {
        case .week:
            let start = today.startOfWeek(weekStart: weekStart).adding(offset * 7)
            return (start, start.adding(6))
        case .year:
            let year = today.year + offset
            return (Day(year: year, month: 1, day: 1), Day(year: year, month: 12, day: 31))
        }
    }

    var done: Int { lines.reduce(0) { $0 + $1.done } }
    var due: Int { lines.reduce(0) { $0 + $1.due } }
    var rate: Double? { due == 0 ? nil : Double(done) / Double(due) }

    /// Tage, an denen alles Fällige erledigt war.
    var perfectDays: Int { days.filter { $0.due > 0 && $0.done >= $0.due }.count }

    var bestDay: DayEntry? {
        days.filter { $0.due > 0 }.max { ($0.rate ?? 0, $0.done) < ($1.rate ?? 0, $1.done) }
    }

    /// Quote je Monat (nur Jahr), `nil` für Monate ohne Fälliges.
    var monthRates: [Double?] {
        var done = Array(repeating: 0, count: 12)
        var due = Array(repeating: 0, count: 12)
        for entry in days {
            done[entry.day.month - 1] += entry.done
            due[entry.day.month - 1] += entry.due
        }
        return (0..<12).map { due[$0] == 0 ? nil : Double(done[$0]) / Double(due[$0]) }
    }

    var bestMonth: Int? {
        let rates = monthRates
        return rates.indices.filter { rates[$0] != nil }.max { (rates[$0] ?? 0) < (rates[$1] ?? 0) }
    }

    var title: String {
        switch scope {
        case .week:
            let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: start.adding(3).date())
            return "KW \(week)"
        case .year:
            return "\(start.year)"
        }
    }

    var subtitle: String {
        switch scope {
        case .week:
            let last = end
            if start.month == last.month {
                return "\(start.dayOfMonth).–\(last.dayOfMonth). \(last.monthLong) \(last.year)"
            }
            return "\(start.dayOfMonth). \(start.monthShort) – \(last.dayOfMonth). \(last.monthShort) \(last.year)"
        case .year:
            return end < today ? "Ganzes Jahr" : "Bis heute"
        }
    }

    var isCurrent: Bool { start <= today && today <= end }
}

// MARK: - Ansicht

struct ReviewView: View {
    let scope: Review.Scope

    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: [SortDescriptor(\Habit.sortOrder), SortDescriptor(\Habit.createdAt)])
    private var habits: [Habit]
    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 0
    @AppStorage(SettingsKey.accent, store: AppGroup.defaults) private var accentID = Palette.defaultID
    @State private var offset = 0

    private var accent: HabitColor { Palette.entry(accentID) }

    var body: some View {
        let today = Day.today
        let review = Review(scope: scope, offset: offset, habits: habits, today: today, weekStart: weekStart)
        let previous = Review(scope: scope, offset: offset - 1, habits: habits, today: today, weekStart: weekStart)

        ScrollView {
            VStack(spacing: 16) {
                header(review)
                summary(review, previous: previous)
                switch scope {
                case .week:
                    dayBars(review)
                case .year:
                    yearGrid(review)
                    monthBars(review)
                }
                habitList(review)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableWidth()
            .animation(.snappy, value: offset)
        }
        .ambientBackground()
        .navigationTitle(scope == .week ? "Wochenrückblick" : "Jahresrückblick")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Bausteine

    private func header(_ review: Review) -> some View {
        HStack {
            Button {
                offset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(scope == .week ? "Vorherige Woche" : "Vorheriges Jahr")

            Spacer()
            VStack(spacing: 2) {
                Text(review.title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                Text(review.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                offset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(offset >= 0)
            .accessibilityLabel(scope == .week ? "Nächste Woche" : "Nächstes Jahr")
        }
    }

    private func summary(_ review: Review, previous: Review) -> some View {
        let rate = review.rate ?? 0
        let delta: String? = {
            guard let now = review.rate, let before = previous.rate else { return nil }
            let points = Int(((now - before) * 100).rounded())
            let label = scope == .week ? "zur Vorwoche" : "zum Vorjahr"
            if points == 0 { return "gleich wie \(scope == .week ? "letzte Woche" : "letztes Jahr")" }
            return "\(points > 0 ? "+" : "−")\(abs(points)) Punkte \(label)"
        }()
        let best: String = {
            switch scope {
            case .week:
                return review.bestDay.map { $0.day.weekdayShort } ?? "–"
            case .year:
                return review.bestMonth.map { Day.monthSymbolsShort[$0] } ?? "–"
            }
        }()

        return VStack(spacing: 16) {
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(progress: rate, color: accent.color, endColor: accent.endColor, lineWidth: 12)
                    Text(review.rate.map(Format.percent) ?? "–")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text(headline(review))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let delta {
                        Label(delta, systemImage: (review.rate ?? 0) >= (previous.rate ?? 0) ? "arrow.up.right" : "arrow.down.right")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .card(padding: 18)

            MetricsRow(items: [
                .init(value: "\(review.done)", label: "Erledigt"),
                .init(value: "\(review.perfectDays)", label: "Perfekte Tage"),
                .init(value: best, label: scope == .week ? "Bester Tag" : "Bester Monat"),
            ])
        }
    }

    private func headline(_ review: Review) -> String {
        guard let rate = review.rate else {
            return review.isCurrent ? "Noch nichts fällig – leg los!" : "In diesem Zeitraum war nichts fällig."
        }
        switch rate {
        case 0.9...: return "Herausragend – fast alles geschafft."
        case 0.7..<0.9: return "Starke \(scope == .week ? "Woche" : "Bilanz")."
        case 0.4..<0.7: return "Solide – da geht noch was."
        default: return "Neuer Anlauf – jeder Tag zählt."
        }
    }

    private func dayBars(_ review: Review) -> some View {
        let days = (0..<7).map { review.start.adding($0) }
        let entries = Dictionary(uniqueKeysWithValues: review.days.map { ($0.day.ordinal, $0) })
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle("Tage", subtitle: "Anteil der fälligen Gewohnheiten, die erledigt wurden")
            RateBars(
                values: days.map { entries[$0.ordinal]?.rate },
                labels: days.map(\.weekdayShort),
                highlight: days.firstIndex(of: review.today),
                tint: accent
            )
            .frame(height: 130)
        }
        .card(padding: 18)
    }

    private func monthBars(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Monate", subtitle: "Quote je Monat")
            RateBars(
                values: review.monthRates,
                labels: Day.monthSymbolsShort.map { String($0.prefix(1)) },
                highlight: review.isCurrent ? review.today.month - 1 : nil,
                tint: accent
            )
            .frame(height: 130)
        }
        .card(padding: 18)
    }

    private func yearGrid(_ review: Review) -> some View {
        let entries = Dictionary(uniqueKeysWithValues: review.days.map { ($0.day.ordinal, $0) })
        let firstColumn = review.start.startOfWeek(weekStart: weekStart)
        let columns = firstColumn.days(until: review.end.startOfWeek(weekStart: weekStart)) / 7 + 1
        let start = review.start
        let end = review.end
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle("Dein Jahr", subtitle: "Jede Kachel ein Tag – je kräftiger, desto mehr geschafft")
            HeatmapGrid(
                today: review.end,
                weekStart: weekStart,
                color: accent.color,
                endColor: accent.endColor,
                columns: columns,
                showMonths: true
            ) { day in
                guard day >= start, day <= end, let entry = entries[day.ordinal], entry.due > 0 else { return HeatCell() }
                return HeatCell(level: entry.done == 0 ? 0 : max(0.15, entry.rate ?? 0))
            }
        }
        .card(padding: 18)
    }

    private func habitList(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle("Gewohnheiten")
            if review.lines.isEmpty {
                Text("Keine Einträge in diesem Zeitraum.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(review.lines) { line in
                let tint = Palette.entry(line.habit.colorID)
                HStack(spacing: 12) {
                    HabitIcon(symbol: line.habit.symbol, tint: tint, size: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(line.habit.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if scope == .week {
                            WeekDots(snapshot: line.snapshot, start: review.start, tint: tint)
                        } else {
                            ProgressView(value: line.rate ?? 0)
                                .tint(tint.color)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(line.rate.map(Format.percent) ?? "–")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        Text("\(line.done)/\(line.due)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card(padding: 18)
    }
}

/// Senkrechte Balken mit Beschriftung, z. B. Mo–So oder J–D.
struct RateBars: View {
    let values: [Double?]
    let labels: [String]
    var highlight: Int?
    let tint: HabitColor

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(values.indices, id: \.self) { index in
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(values[index] == nil ? AnyShapeStyle(Color.primary.opacity(0.06)) : AnyShapeStyle(tint.gradient))
                                .frame(height: max(6, geo.size.height * (values[index] ?? 0)))
                        }
                    }
                    Text(labels[index])
                        .font(.caption2.weight(index == highlight ? .bold : .regular))
                        .foregroundStyle(index == highlight ? .primary : .secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(labels[index]): \(values[index].map(Format.percent) ?? "nichts fällig")")
            }
        }
    }
}

/// Sieben kleine Punkte für eine Woche: erledigt, verpasst oder nicht fällig.
struct WeekDots: View {
    let snapshot: HabitSnapshot
    let start: Day
    let tint: HabitColor

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { index in
                let day = start.adding(index)
                let result = snapshot.dayTally(day)
                Circle()
                    .fill(result.done > 0 ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(result.due > 0 ? tint.color.opacity(0.22) : Color.primary.opacity(0.07)))
                    .frame(width: 11, height: 11)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Einstieg in der Statistik: zwei Glas-Kacheln für Woche und Jahr.
struct ReviewLinks: View {
    let habits: [Habit]
    let weekStart: Int
    let tint: HabitColor

    var body: some View {
        let today = Day.today
        let week = Review(scope: .week, offset: 0, habits: habits, today: today, weekStart: weekStart)
        let year = Review(scope: .year, offset: 0, habits: habits, today: today, weekStart: weekStart)
        HStack(spacing: 12) {
            tile(scope: .week, title: "Woche", detail: "\(week.title) · \(week.rate.map(Format.percent) ?? "–")", symbol: "calendar")
            tile(scope: .year, title: "Jahr", detail: "\(year.title) · \(year.rate.map(Format.percent) ?? "–")", symbol: "sparkles")
        }
    }

    private func tile(scope: Review.Scope, title: String, detail: String, symbol: String) -> some View {
        NavigationLink {
            ReviewView(scope: scope)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scope == .week ? "Wochenrückblick" : "Jahresrückblick")
    }
}
