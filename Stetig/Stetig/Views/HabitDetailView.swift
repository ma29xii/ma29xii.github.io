import Charts
import SwiftData
import SwiftUI

struct HabitDetailView: View {
    let habit: Habit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 0

    @State private var month = Day.today.startOfMonth
    @State private var entryDay: Day?
    @State private var showEditor = false
    @State private var showShare = false
    @State private var showTimer = false
    @State private var confirmDelete = false

    private var tint: HabitColor { Palette.entry(habit.colorID) }
    private var color: Color { tint.color }

    private var supportsTimer: Bool {
        habit.kind == .build && ["min", "min.", "minuten"].contains(habit.unit.lowercased())
    }

    var body: some View {
        let snapshot = habit.snapshot(weekStart: weekStart)

        ScrollView {
            VStack(spacing: 16) {
                header(snapshot)
                if habit.isPaused {
                    pausedBanner
                }
                if habit.isCounter || (habit.kind == .quit && habit.dailyTarget > 0) {
                    todayCounter(snapshot)
                }
                metrics(snapshot)
                yearCard(snapshot)
                MonthCalendar(habit: habit, snapshot: snapshot, month: $month) { day in
                    entryDay = day
                }
                .card(padding: 18)
                chartsCard(snapshot)
                notesCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .ambientBackground(tint)
        .tint(tint.color)
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten", systemImage: "pencil") { showEditor = true }
                    .tint(tint.color)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Als Bild teilen", systemImage: "square.and.arrow.up") { showShare = true }
                    Button("Heutigen Eintrag bearbeiten", systemImage: "square.and.pencil") { entryDay = .today }
                    Button(habit.isPaused ? "Fortsetzen" : "Pausieren", systemImage: habit.isPaused ? "play" : "pause") {
                        HabitAdmin.setPaused(!habit.isPaused, habit: habit, in: context)
                    }
                    Button("Archivieren", systemImage: "archivebox") {
                        HabitAdmin.setArchived(true, habit: habit, in: context)
                        dismiss()
                    }
                    Divider()
                    Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("Mehr", systemImage: "ellipsis")
                }
                .tint(tint.color)
            }
        }
        .sheet(isPresented: $showEditor) {
            HabitEditorView(habit: habit)
        }
        .sheet(item: $entryDay) { day in
            EntrySheet(habit: habit, day: day)
        }
        .sheet(isPresented: $showShare) {
            ShareSheetView(habit: habit)
        }
        .sheet(isPresented: $showTimer) {
            TimerSheet(habit: habit)
        }
        .confirmationDialog("Gewohnheit wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                dismiss()
                HabitAdmin.delete(habit, in: context)
            }
        } message: {
            Text("Alle Einträge gehen verloren.")
        }
    }

    // MARK: Kopf

    private func header(_ snapshot: HabitSnapshot) -> some View {
        HStack(spacing: 14) {
            HabitIcon(symbol: habit.symbol, tint: tint, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.title3.weight(.bold))
                Text([habit.goalDescription, habit.category?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !habit.details.isEmpty {
                    Text(habit.details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            CompleteButton(habit: habit, snapshot: snapshot, day: snapshot.today, size: 52)
        }
        .card(padding: 18)
    }

    private var pausedBanner: some View {
        HStack {
            Label("Pausiert – die Serie ist eingefroren.", systemImage: "pause.circle.fill")
                .font(.subheadline)
            Spacer()
            Button("Fortsetzen") {
                HabitAdmin.setPaused(false, habit: habit, in: context)
            }
            .buttonStyle(.glass)
        }
        .card(padding: 14)
    }

    private func todayCounter(_ snapshot: HabitSnapshot) -> some View {
        let today = snapshot.today
        let amount = snapshot.amount(today)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Heute")
                    .font(.headline)
                Spacer()
                Text(habit.kind == .quit
                    ? "\(Format.number(amount)) von max. \(Format.amount(habit.dailyTarget, unit: habit.unit))"
                    : "\(Format.number(amount)) / \(Format.amount(habit.dailyTarget, unit: habit.unit))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                let fraction = min(1, habit.dailyTarget > 0 ? amount / habit.dailyTarget : 0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(8, geo.size.width * fraction))
                        .opacity(fraction > 0 ? 1 : 0)
                }
            }
            .frame(height: 8)
            .animation(.snappy, value: amount)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.snappy) { habit.add(-habit.step, on: today, in: context) }
                    } label: {
                        Image(systemName: "minus").frame(width: 28, height: 22)
                    }
                    .disabled(amount <= 0)
                    Button {
                        withAnimation(.snappy) { habit.add(habit.step, on: today, in: context) }
                    } label: {
                        Label("\(Format.number(habit.step))", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                    }
                    if supportsTimer {
                        Button {
                            showTimer = true
                        } label: {
                            Image(systemName: "timer").frame(width: 28, height: 22)
                        }
                        .accessibilityLabel("Timer")
                    }
                }
                .buttonStyle(.glass)
            }
        }
        .card()
    }

    // MARK: Kennzahlen

    private func metrics(_ snapshot: HabitSnapshot) -> some View {
        let streak = snapshot.currentStreak
        let best = snapshot.bestStreak
        var second: [MetricsRow.Item] = [
            .init(value: "\(snapshot.totalDone)", label: habit.kind == .quit ? "Tage geschafft" : "Erledigt"),
        ]
        if habit.kind == .build, habit.isCounter || !habit.unit.isEmpty {
            second.append(.init(value: Format.amount(snapshot.totalAmount, unit: habit.unit), label: "Summe"))
        } else {
            let weekStartDay = snapshot.weekStart(of: snapshot.today)
            second.append(.init(value: "\(snapshot.doneCount(from: weekStartDay, through: snapshot.today))×", label: "Diese Woche"))
        }
        second.append(.init(value: snapshot.rule.firstDay.shortTitle, label: "Seit"))

        return VStack(spacing: 10) {
            MetricsRow(items: [
                .init(value: "\(streak)", label: "Serie (\(snapshot.streakUnit(streak)))"),
                .init(value: "\(best)", label: "Rekord"),
                .init(value: Format.percent(snapshot.rate(days: 30)), label: "Quote 30 T."),
            ])
            MetricsRow(items: second)
        }
    }

    // MARK: Jahresraster

    private func yearCard(_ snapshot: HabitSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Verlauf")
            ScrollView(.horizontal) {
                HeatmapGrid(snapshot: snapshot, tint: tint, columns: 53, showMonths: true)
                    .frame(height: 138)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)
        }
        .card(padding: 18)
    }

    // MARK: Diagramme

    private func chartsCard(_ snapshot: HabitSnapshot) -> some View {
        let weeks = Array(snapshot.weeklyCounts(weeks: 12).enumerated())
        let weekdays = snapshot.weekdayCounts()
        let order = (0..<7).map { ($0 + snapshot.rule.weekStart) % 7 }
        let best = weekdays.max() ?? 0
        let bestIndex = order.first { weekdays[$0] == best } ?? 0

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("Letzte 12 Wochen")
                Chart(weeks, id: \.offset) { item in
                    BarMark(
                        x: .value("Woche", String(item.offset)),
                        y: .value("Tage", item.element.count)
                    )
                    .foregroundStyle(tint.gradient)
                    .cornerRadius(5)
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: 0...7)
                .chartYAxis {
                    AxisMarks(values: [0, 7]) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 110)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                CardTitle("Wochentage", subtitle: best > 0 ? "Am stärksten: \(Day.weekdaySymbolsLong[bestIndex])" : "Noch keine Daten")
                Chart(order, id: \.self) { index in
                    BarMark(
                        x: .value("Tag", Day.weekdaySymbolsShort[index]),
                        y: .value("Anzahl", weekdays[index])
                    )
                    .foregroundStyle(tint.gradient)
                    .opacity(weekdays[index] == best && best > 0 ? 1 : 0.4)
                    .cornerRadius(5)
                }
                .chartYAxis(.hidden)
                .frame(height: 110)
            }
        }
        .card(padding: 18)
    }

    // MARK: Notizen

    private var notesCard: some View {
        let notes = habit.entries
            .filter { !$0.note.isEmpty }
            .sorted { $0.day > $1.day }
            .prefix(12)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("Notizen")
                Spacer()
                Button("Notiz für heute", systemImage: "plus") {
                    entryDay = .today
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            }
            if notes.isEmpty {
                Text("Halte fest, wie es lief – z. B. was geholfen oder gestört hat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(notes), id: \.day) { entry in
                    let day = Day(key: entry.day)
                    Button {
                        entryDay = day
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(day.weekdayShort), \(day.shortTitle)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color)
                            Text(entry.note)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }
}

// MARK: - Monatskalender

struct MonthCalendar: View {
    let habit: Habit
    let snapshot: HabitSnapshot
    @Binding var month: Day
    var onEdit: (Day) -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        let color = Palette.color(habit.colorID)
        let weekStart = snapshot.rule.weekStart
        let leading = (month.weekdayIndex - weekStart + 7) % 7
        let count = month.daysInMonth
        let noteDays = Set(habit.entries.filter { !$0.note.isEmpty }.map(\.day))

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(month.monthLong) \(String(month.year))")
                    .font(.headline)
                Spacer()
                Button("Vorheriger Monat", systemImage: "chevron.left") {
                    withAnimation(.snappy) { month = month.addingMonths(-1) }
                }
                Button("Nächster Monat", systemImage: "chevron.right") {
                    withAnimation(.snappy) { month = month.addingMonths(1) }
                }
                .disabled(month >= snapshot.today.startOfMonth)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)

            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Day.weekdaySymbolsShort[(index + weekStart) % 7])
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Leerfelder bekommen negative IDs, Tage ihre Tagesnummer – so sind alle IDs eindeutig.
            let cells: [Int] = Array(-leading..<0) + (0..<count).map { month.adding($0).ordinal }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(cells, id: \.self) { cell in
                    if cell < 0 {
                        Color.clear.frame(height: 38)
                    } else {
                        let day = Day(ordinal: cell)
                        dayCell(day, color: color, hasNote: noteDays.contains(day.key))
                    }
                }
            }

        }
    }

    private func dayCell(_ day: Day, color: Color, hasNote: Bool) -> some View {
        let tint = Palette.entry(habit.colorID)
        let cell = snapshot.cell(day)
        let isFuture = day > snapshot.today
        let isToday = day == snapshot.today
        let skipped = habit.entry(on: day)?.skipped == true

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                habit.advance(on: day, in: context)
            }
        } label: {
            ZStack {
                if cell.level > 0 {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.gradient)
                        .opacity(0.3 + 0.7 * cell.level)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(isFuture ? 0.03 : 0.07))
                }
                if cell.skipped {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(color.opacity(0.6), lineWidth: 1.5)
                }
                if isToday {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.5)
                }
                Text("\(day.dayOfMonth)")
                    .font(.footnote.weight(isToday ? .bold : .medium))
                    .foregroundStyle(cell.level > 0.6 ? tint.onColor : (isFuture ? Color.secondary.opacity(0.5) : Color.primary))
                if cell.slipped {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(color)
                        .offset(y: 12)
                }
                if hasNote {
                    Circle()
                        .fill(cell.level > 0.6 ? tint.onColor : color)
                        .frame(width: 4, height: 4)
                        .offset(x: 12, y: -12)
                }
            }
            .frame(height: 38)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .contextMenu {
            if !isFuture {
                Button("Eintrag bearbeiten", systemImage: "square.and.pencil") { onEdit(day) }
                Button(skipped ? "Überspringen aufheben" : "Überspringen", systemImage: skipped ? "arrow.uturn.backward" : "forward.end") {
                    habit.setSkipped(!skipped, on: day, in: context)
                }
                Button("Eintrag leeren", systemImage: "eraser", role: .destructive) {
                    habit.clear(on: day, in: context)
                }
            }
        }
        .accessibilityLabel("\(day.dayOfMonth). \(day.monthLong)")
        .accessibilityValue(cell.level >= 1 ? "erledigt" : (cell.skipped ? "übersprungen" : "offen"))
    }
}

// MARK: - Eintrag eines Tages

struct EntrySheet: View {
    let habit: Habit
    let day: Day

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var amount: Double
    @State private var skipped: Bool
    @State private var note: String

    init(habit: Habit, day: Day) {
        self.habit = habit
        self.day = day
        let entry = habit.entry(on: day)
        _amount = State(initialValue: entry?.amount ?? 0)
        _skipped = State(initialValue: entry?.skipped ?? false)
        _note = State(initialValue: entry?.note ?? "")
    }

    private var isSimple: Bool {
        (habit.kind == .build && !habit.isCounter) || (habit.kind == .quit && habit.dailyTarget <= 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isSimple {
                        Toggle(habit.kind == .quit ? "Rückfall" : "Erledigt", isOn: Binding(
                            get: { amount > 0 },
                            set: { amount = $0 ? max(habit.dailyTarget, 1) : 0 }
                        ))
                    } else {
                        LabeledContent(habit.unit.isEmpty ? "Menge" : habit.unit.capitalized) {
                            HStack(spacing: 8) {
                                TextField("0", value: $amount, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(minWidth: 60)
                                Stepper("Menge", value: $amount, in: 0...1_000_000, step: max(0.1, habit.step))
                                    .labelsHidden()
                            }
                        }
                    }
                    Toggle("Überspringen", isOn: $skipped)
                } footer: {
                    Text("Übersprungene Tage unterbrechen die Serie nicht – für Krankheit, Urlaub oder Ruhetage.")
                }
                .disabled(day > .today)

                Section("Notiz") {
                    TextField("Wie lief es?", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Button("Eintrag leeren", role: .destructive) {
                        habit.clear(on: day, in: context)
                        dismiss()
                    }
                }
            }
            .navigationTitle(day.longTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { save() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let entry = habit.ensureEntry(on: day)
        entry.amount = skipped ? 0 : max(0, amount)
        entry.skipped = skipped
        entry.note = note.trimmed
        entry.updatedAt = Date()
        Store.commit(context)
        dismiss()
    }
}

// MARK: - Teilen

struct ShareCard: View {
    let name: String
    let symbol: String
    let tint: HabitColor
    let snapshot: HabitSnapshot

    var body: some View {
        let streak = snapshot.currentStreak
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                HabitIcon(symbol: symbol, tint: tint, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    Text("\(streak) \(snapshot.streakUnit(streak)) in Serie · \(snapshot.totalDone) Tage gesamt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HeatmapGrid(snapshot: snapshot, tint: tint, columns: 26)
            Text("Stetig")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
    }
}

struct ShareSheetView: View {
    let habit: Habit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var rendered: Image?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                card
                    .padding(.horizontal, 20)
                if let rendered {
                    ShareLink(item: rendered, preview: SharePreview(habit.name, image: rendered)) {
                        Label("Bild teilen", systemImage: "square.and.arrow.up")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    ProgressView()
                }
                Spacer()
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ambientBackground(Palette.entry(habit.colorID))
            .navigationTitle("Teilen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .task { render() }
        }
        .presentationDetents([.medium, .large])
    }

    private var card: ShareCard {
        ShareCard(name: habit.name, symbol: habit.symbol, tint: Palette.entry(habit.colorID), snapshot: habit.snapshot())
    }

    @MainActor
    private func render() {
        let content = card
            .frame(width: 380)
            .padding(16)
            .ambientBackground(Palette.entry(habit.colorID))
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        if let image = renderer.uiImage {
            rendered = Image(uiImage: image)
        }
    }
}

// MARK: - Timer

struct TimerSheet: View {
    let habit: Habit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var startedAt: Date?
    @State private var accumulated: TimeInterval = 0

    private func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    var body: some View {
        let tint = Palette.entry(habit.colorID)
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let seconds = Int(elapsed(at: timeline.date))
                let goal = max(1, habit.dailyTarget * 60)
                VStack(spacing: 28) {
                    ZStack {
                        ProgressRing(progress: Double(seconds) / goal, color: tint.color, endColor: tint.endColor, lineWidth: 14)
                        VStack(spacing: 4) {
                            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("Ziel: \(Format.amount(habit.dailyTarget, unit: habit.unit))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 240, height: 240)

                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                if let started = startedAt {
                                    accumulated += Date().timeIntervalSince(started)
                                    startedAt = nil
                                } else {
                                    startedAt = Date()
                                }
                            } label: {
                                Label(startedAt == nil ? "Start" : "Pause", systemImage: startedAt == nil ? "play.fill" : "pause.fill")
                                    .frame(minWidth: 90, minHeight: 28)
                            }
                            .buttonStyle(.glass)

                            Button {
                                let minutes = (elapsed(at: Date()) / 60).rounded()
                                if minutes > 0 {
                                    habit.add(minutes, on: .today, in: context)
                                }
                                dismiss()
                            } label: {
                                Label("Übernehmen", systemImage: "checkmark")
                                    .frame(minWidth: 90, minHeight: 28)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(seconds < 30)
                        }
                    }
                    Text("Die gestoppte Zeit wird auf volle Minuten gerundet und zu heute addiert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
