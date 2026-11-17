import SwiftData
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case grid
    case week
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Raster"
        case .week: "Woche"
        case .compact: "Kompakt"
        }
    }

    var symbol: String {
        switch self {
        case .grid: "square.grid.3x3"
        case .week: "calendar"
        case .compact: "list.bullet"
        }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case manual
    case name
    case streak
    case rate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "Eigene Reihenfolge"
        case .name: "Name"
        case .streak: "Längste Serie"
        case .rate: "Beste Quote"
        }
    }
}

struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: [SortDescriptor(\Habit.sortOrder), SortDescriptor(\Habit.createdAt)])
    private var habits: [Habit]
    @Query(sort: \HabitCategory.sortOrder) private var categories: [HabitCategory]

    @AppStorage(SettingsKey.viewMode) private var viewModeRaw = ViewMode.grid.rawValue
    @AppStorage(SettingsKey.gridColumns) private var gridColumns = 26
    @AppStorage(SettingsKey.sortMode) private var sortModeRaw = SortMode.manual.rawValue
    @AppStorage(SettingsKey.accent, store: AppGroup.defaults) private var accentID = Palette.defaultID
    @AppStorage(SettingsKey.chipColor, store: AppGroup.defaults) private var chipColorID = ""

    @State private var path: [Habit] = []
    @State private var selectedCategory: UUID?
    @State private var searchText = ""
    @State private var showNew = false
    @State private var showReorder = false
    @State private var editing: Habit?
    @State private var deleting: Habit?
    @Namespace private var zoom

    private var mode: ViewMode { ViewMode(rawValue: viewModeRaw) ?? .grid }

    private var sortMode: SortMode { SortMode(rawValue: sortModeRaw) ?? .manual }
    /// Farbe der ausgewählten Kategorie – eigene Wahl oder die Akzentfarbe.
    private var chipTint: HabitColor { Palette.entry(chipColorID.isEmpty ? accentID : chipColorID) }

    private var filtered: [Habit] {
        let visible = habits.filter { habit in
            if let selectedCategory, habit.category?.uuid != selectedCategory { return false }
            let query = searchText.trimmed
            if !query.isEmpty, !habit.name.localizedCaseInsensitiveContains(query) { return false }
            return true
        }
        switch sortMode {
        case .manual:
            return visible
        case .name:
            return visible.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .streak:
            let keyed = visible.map { (habit: $0, value: $0.snapshot().currentStreak) }
            return keyed.sorted { $0.value > $1.value }.map(\.habit)
        case .rate:
            let keyed = visible.map { (habit: $0, value: $0.snapshot().rate(days: 30)) }
            return keyed.sorted { $0.value > $1.value }.map(\.habit)
        }
    }

    var body: some View {
        // Einmal pro Durchlauf filtern und sortieren (Sortierung nach Serie rechnet jede Gewohnheit durch).
        let visible = filtered
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(visible) { habit in
                        HabitCard(habit: habit, mode: mode, columns: gridColumns)
                            .matchedTransitionSource(id: habit.persistentModelID, in: zoom)
                            .contentShape(.rect(cornerRadius: 22))
                            .onTapGesture { path.append(habit) }
                            .contextMenu { menu(for: habit) }
                            .accessibilityAction(named: "Öffnen") { path.append(habit) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .onChange(of: habits.count) { old, new in
                // Neu angelegte Gewohnheit sichtbar machen.
                guard new > old, let newest = habits.max(by: { $0.createdAt < $1.createdAt }) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.snappy) { proxy.scrollTo(newest.id, anchor: .center) }
                }
            }
            }
            .ambientBackground()
            .overlay {
                if habits.isEmpty {
                    emptyState
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !categories.isEmpty, !habits.isEmpty {
                    categoryBar
                }
            }
            .navigationTitle("Gewohnheiten")
            .navigationDestination(for: Habit.self) { habit in
                HabitDetailView(habit: habit)
                    .navigationTransition(.zoom(sourceID: habit.persistentModelID, in: zoom))
            }
            .searchable(text: $searchText, prompt: "Gewohnheit suchen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Ansicht", selection: $viewModeRaw) {
                            ForEach(ViewMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.symbol).tag(mode.rawValue)
                            }
                        }
                        if mode == .grid {
                            Picker("Zeitraum", selection: $gridColumns) {
                                Text("4 Monate").tag(18)
                                Text("6 Monate").tag(26)
                                Text("9 Monate").tag(39)
                            }
                        }
                        Picker("Sortierung", selection: $sortModeRaw) {
                            ForEach(SortMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        Divider()
                        Button("Reihenfolge ändern", systemImage: "arrow.up.arrow.down") {
                            sortModeRaw = SortMode.manual.rawValue
                            showReorder = true
                        }
                        .disabled(habits.count < 2)
                    } label: {
                        Label("Ansicht", systemImage: "line.3.horizontal.decrease")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Neue Gewohnheit", systemImage: "plus") {
                        showNew = true
                    }
                    .accessibilityIdentifier("add-habit")
                }
            }
            .sheet(isPresented: $showNew) {
                HabitEditorView()
            }
            .sheet(item: $editing) { habit in
                HabitEditorView(habit: habit)
            }
            .sheet(isPresented: $showReorder) {
                ReorderView()
            }
            .confirmationDialog(
                "„\(deleting?.name ?? "")“ löschen?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    if let habit = deleting {
                        HabitAdmin.delete(habit, in: context)
                    }
                    deleting = nil
                }
            } message: {
                Text("Alle Einträge dieser Gewohnheit gehen verloren.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Noch keine Gewohnheiten", systemImage: "square.grid.3x3.fill")
        } description: {
            Text("Lege deine erste Gewohnheit an und fülle Tag für Tag dein Raster.")
        } actions: {
            Button {
                showNew = true
            } label: {
                Text("Gewohnheit anlegen")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.glassProminent)
            Button("Mit Beispieldaten ausprobieren") {
                DemoData.insert(into: context)
            }
            .buttonStyle(.glass)
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(title: "Alle", symbol: nil, id: nil)
                    ForEach(categories) { category in
                        chip(title: category.name, symbol: category.symbol, id: category.uuid)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(title: String, symbol: String?, id: UUID?) -> some View {
        let isSelected = selectedCategory == id
        return Button {
            withAnimation(.snappy) { selectedCategory = id }
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    HabitGlyph(symbol: symbol)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isSelected ? chipTint.onColor : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? Glass.regular.tint(chipTint.color).interactive() : Glass.regular.interactive(),
            in: .capsule
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func menu(for habit: Habit) -> some View {
        let today = Day.today
        Button("Bearbeiten", systemImage: "pencil") { editing = habit }
        if habit.entry(on: today)?.skipped == true {
            Button("Überspringen aufheben", systemImage: "arrow.uturn.backward") {
                habit.setSkipped(false, on: today, in: context)
            }
        } else {
            Button("Heute überspringen", systemImage: "forward.end") {
                habit.setSkipped(true, on: today, in: context)
            }
        }
        Button(habit.isPaused ? "Fortsetzen" : "Pausieren", systemImage: habit.isPaused ? "play" : "pause") {
            HabitAdmin.setPaused(!habit.isPaused, habit: habit, in: context)
        }
        Button("Duplizieren", systemImage: "plus.square.on.square") {
            HabitAdmin.duplicate(habit, in: context)
        }
        Button("Archivieren", systemImage: "archivebox") {
            HabitAdmin.setArchived(true, habit: habit, in: context)
        }
        Divider()
        Button("Löschen", systemImage: "trash", role: .destructive) { deleting = habit }
    }
}

// MARK: - Karte

struct HabitCard: View {
    let habit: Habit
    let mode: ViewMode
    let columns: Int

    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 0

    var body: some View {
        let snapshot = habit.snapshot(weekStart: weekStart)
        let tint = Palette.entry(habit.colorID)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                HabitIcon(symbol: habit.symbol, tint: tint, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(status(snapshot))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 8)
                CompleteButton(habit: habit, snapshot: snapshot, day: snapshot.today)
            }

            switch mode {
            case .grid:
                HeatmapGrid(snapshot: snapshot, tint: tint, columns: columns)
            case .week:
                WeekStrip(habit: habit, snapshot: snapshot)
            case .compact:
                EmptyView()
            }
        }
        .card(padding: 16)
        .opacity(habit.isPaused ? 0.55 : 1)
    }

    /// Genau eine Statuszeile pro Karte – das Wichtigste auf einen Blick.
    private func status(_ snapshot: HabitSnapshot) -> String {
        if habit.isPaused { return "Pausiert" }
        let streak = snapshot.currentStreak
        let streakText: String? = streak > 0 ? "\(streak) \(snapshot.streakUnit(streak)) in Serie" : nil
        if habit.isCounter {
            let progress = "\(Format.number(snapshot.amount(snapshot.today))) / \(Format.amount(habit.dailyTarget, unit: habit.unit))"
            return [progress, streak > 0 ? "\(streak) \(snapshot.streakUnit(streak))" : nil].compactMap { $0 }.joined(separator: " · ")
        }
        if let progress = snapshot.periodProgress {
            let period = snapshot.effectiveFrequency == .perWeek ? "diese Woche" : "diesen Monat"
            return "\(progress.done)/\(progress.target) \(period)"
        }
        if habit.kind == .quit {
            return "\(streak) \(snapshot.streakUnit(streak)) ohne"
        }
        return streakText ?? (habit.details.isEmpty ? habit.goalDescription : habit.details)
    }

}

// MARK: - Reihenfolge

struct ReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: [SortDescriptor(\Habit.sortOrder), SortDescriptor(\Habit.createdAt)])
    private var habits: [Habit]

    var body: some View {
        NavigationStack {
            List {
                ForEach(habits) { habit in
                    HStack(spacing: 12) {
                        HabitIcon(symbol: habit.symbol, colorID: habit.colorID, size: 32)
                        Text(habit.name)
                    }
                }
                .onMove { source, destination in
                    var ordered = habits
                    ordered.move(fromOffsets: source, toOffset: destination)
                    for (index, habit) in ordered.enumerated() {
                        habit.sortOrder = index
                    }
                    Store.commit(context)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reihenfolge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Verwaltung

enum HabitAdmin {
    static func nextSortOrder(in context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        return (all.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Löscht in zwei Schritten: erst ausblenden, dann – wenn keine Ansicht die
    /// Gewohnheit mehr zeigt – endgültig entfernen. So greift keine noch sichtbare
    /// Ansicht (z. B. die Detailseite während der Rück-Animation) auf Gelöschtes zu.
    static func delete(_ habit: Habit, in context: ModelContext) {
        Reminders.cancel(uuid: habit.uuid)
        habit.isArchived = true
        habit.reminderEnabled = false
        Store.commit(context)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            deleteNow(habit, in: context)
        }
    }

    static func deleteNow(_ habit: Habit, in context: ModelContext) {
        Reminders.cancel(uuid: habit.uuid)
        context.delete(habit)
        Store.commit(context)
    }

    /// Legt eine Kopie mit denselben Einstellungen, aber ohne Verlauf an.
    static func duplicate(_ habit: Habit, in context: ModelContext) {
        var draft = HabitDraft(habit: habit)
        draft.name = habit.name + " (Kopie)"
        let copy = Habit(name: draft.name)
        copy.sortOrder = nextSortOrder(in: context)
        context.insert(copy)
        draft.apply(to: copy, categories: habit.category.map { [$0] } ?? [])
        Store.commit(context)
        Reminders.reschedule(copy)
    }

    static func setArchived(_ archived: Bool, habit: Habit, in context: ModelContext) {
        habit.isArchived = archived
        Store.commit(context)
        Reminders.reschedule(habit)
    }

    static func setPaused(_ paused: Bool, habit: Habit, in context: ModelContext) {
        habit.setPaused(paused, in: context)
        Reminders.reschedule(habit)
    }
}
