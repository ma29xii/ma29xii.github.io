import SwiftUI
import SwiftData

enum TrainingTile: String, TileKind {
    case next, weeklySets, routines, history, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .next: "Als Nächstes"
        case .weeklySets: "Muskeln, 7 Tage"
        case .routines: "Routinen"
        case .history: "Verlauf"
        case .library: "Bibliothek"
        }
    }
    var systemImage: String {
        switch self {
        case .next: "play.circle"
        case .weeklySets: "figure.strengthtraining.traditional"
        case .routines: "list.bullet.rectangle"
        case .history: "clock.arrow.circlepath"
        case .library: "books.vertical"
        }
    }
    var summary: String {
        switch self {
        case .next: "Nächste Routine mit Start-Knopf"
        case .weeklySets: "Muskelkarte nach Sätzen"
        case .routines: "Deine Pläne"
        case .history: "Letzte Trainings"
        case .library: "Übungen und freies Training"
        }
    }
}

enum TrainingRoute: Hashable {
    case routine(PersistentIdentifier)
    case library
    case history
}

/// Bisherige Trainingsseite als eigenständige Ansicht (Runde 11: kein eigener Tab mehr, Plus-Menü öffnet sie).
struct TrainingHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Als Blatt geöffnet (Plus-Menü): dann zeigt die Seite Live-Training und Zusammenfassung selbst,
    /// weil das Hauptfenster nicht über einem offenen Blatt präsentieren kann.
    @Environment(\.isPresented) private var isPresented
    @State private var routineToDelete: Routine?
    @State private var sessionToDelete: WorkoutSession?
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var path: [TrainingRoute] = []
    @State private var tappedMuscle: Muscle?
    /// Angetippter Muskel auf der Karte: zeigt Name, Sätze und letzte Belastung direkt in der Kachel.
    @State private var selectedMuscle: Muscle?
    @State private var muscleMode = MuscleMode.week

    private enum MuscleMode: Hashable { case week, recovery }

    private var next: Routine? { routines.min { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if app.isDemo { SampleDataBadge() }
                    // Wie auf Today: „Anpassen“ steht unter der letzten Karte, kein Symbol oben.
                    InlineTileStack<TrainingTile, AnyView>(storageKey: "forma.tiles.training") { tile in
                        AnyView(view(for: tile))
                    }
                    .padding(.top, Space.s3)
                    Color.clear.frame(height: Space.s7)
                }
                .padding(.horizontal, Space.page)
            }
            .formaScreen()
            .navigationTitle("Training")
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { app.showProfile = true } label: { Image(systemName: "person.crop.circle") }
                            .accessibilityLabel("Profil und Einstellungen")
                    }
                }
            }
            .fullScreenCover(item: isPresented ? Bindable(app).liveWorkout : .constant(nil)) { workout in
                LiveWorkoutView(workout: workout)
            }
            .sheet(item: isPresented ? Bindable(app).finishedSession : .constant(nil)) { session in
                WorkoutSummaryView(session: session)
            }
            .confirmationDialog("„\(routineToDelete?.name ?? "")“ löschen?", isPresented: Binding(get: { routineToDelete != nil }, set: { if !$0 { routineToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let routine = routineToDelete { context.delete(routine); try? context.save() }
                    routineToDelete = nil
                }
            } message: {
                Text("Bisherige Trainings bleiben im Verlauf.")
            }
            .confirmationDialog("Training löschen?", isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } })) {
                Button("Löschen", role: .destructive) {
                    if let session = sessionToDelete { context.delete(session); try? context.save() }
                    sessionToDelete = nil
                }
            }
            .navigationDestination(for: TrainingRoute.self) { route in
                switch route {
                case .routine(let id):
                    if let routine = context.model(for: id) as? Routine { RoutineEditorView(routine: routine) }
                case .library: ExerciseLibraryView()
                case .history: HistoryView()
                }
            }
            .sheet(item: $tappedMuscle) { m in
                MuscleExercisesSheet(muscle: m, weeklySets: weeklyVolume[m] ?? 0, recovery: hasRecentWork ? MuscleRecovery.state(recoveryLoad[m] ?? 0) : nil)
            }
        }
    }

    @ViewBuilder private func view(for tile: TrainingTile) -> some View {
        switch tile {
        case .next:
            if let next { nextCard(next) } else { emptyCard }
        case .routines:
            WidgetCard(title: tile.title, systemImage: tile.systemImage) {
                if routines.isEmpty { MetricRow(title: "Noch keine Routine") }
                ForEach(Array(Routine.grouped(routines).enumerated()), id: \.offset) { groupIndex, group in
                    if let folder = group.folder {
                        Text(folder)
                            .formaLabelStyle(Theme.textTertiary)
                            .padding(.horizontal, Space.s4)
                            .padding(.top, groupIndex == 0 ? Space.s2 : Space.s5)
                            .padding(.bottom, Space.s1)
                    } else if groupIndex > 0 {
                        RowDivider()
                    }
                    ForEach(Array(group.routines.enumerated()), id: \.element.id) { index, routine in
                        if index > 0 { RowDivider() }
                        Button { path.append(.routine(routine.persistentModelID)) } label: {
                            MetricRow(title: routine.name, subtitle: "\(routine.items.count) Übungen · \(routine.muscleSummary)")
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Duplizieren", systemImage: "plus.square.on.square") { duplicate(routine) }
                            Button("Löschen", systemImage: "trash", role: .destructive) { routineToDelete = routine }
                        }
                    }
                }
                RowDivider()
                Button(action: addRoutine) {
                    Label("Neue Routine", systemImage: "plus").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        case .history:
            WidgetCard(title: tile.title, systemImage: tile.systemImage, accessory: sessions.isEmpty ? nil : "\(sessions.count) gesamt") {
                if sessions.isEmpty { MetricRow(title: "Noch kein Training", subtitle: "Deine Trainings erscheinen hier") }
                ForEach(Array(sessions.prefix(5).enumerated()), id: \.element.id) { index, session in
                    if index > 0 { RowDivider() }
                    Button { app.finishedSession = session } label: { SessionRow(session: session) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Löschen", systemImage: "trash", role: .destructive) { sessionToDelete = session }
                        }
                }
                if !sessions.isEmpty {
                    RowDivider()
                    Button { path.append(.history) } label: { MetricRow(title: "Kalender und alle Trainings") }
                        .buttonStyle(.plain)
                }
            }
        case .weeklySets:
            let volume = weeklyVolume
            let total = sessions.filter { $0.start >= Self.weekCutoff() }.reduce(0) { $0 + $1.workSets.count }
            WidgetCard(title: tile.title, systemImage: tile.systemImage, accessory: total > 0 ? "\(total) Sätze" : nil) { weeklyMuscles(volume) }
        case .library:
            WidgetCard(title: tile.title, systemImage: tile.systemImage) {
                Button { path.append(.library) } label: {
                    MetricRow(title: "Übungsbibliothek")
                }
                .buttonStyle(.plain)
                RowDivider()
                Button { app.liveWorkout = LiveWorkout.empty() } label: {
                    MetricRow(title: "Freies Training")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func nextCard(_ routine: Routine) -> some View {
        let adjustment = TrainingAdjustment.today
        return WidgetCard(title: "Als Nächstes", systemImage: TrainingTile.next.systemImage) {
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name).font(.formaHeadline)
                Text("\(routine.items.count) Übungen · \(routine.totalSets) Sätze · \(routine.muscleSummary)")
                    .font(.formaBody).foregroundStyle(Theme.textSecondary)
                if let adjustment {
                    Label("Coach-Anpassung für heute: \(adjustment.title)", systemImage: "sparkles")
                        .font(.formaCaption).foregroundStyle(Theme.textSecondary).padding(.top, 6)
                }
                Button("\(routine.name) starten") { start(routine) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("training.start")
                    .padding(.top, Space.s4)
                Button { app.liveWorkout = LiveWorkout.empty() } label: {
                    Text("Freies Training").font(.formaBody).frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, 6)
            .padding(.bottom, Space.s4)
        }
    }

    private var emptyCard: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Leg deine erste Routine an").font(.formaHeadline)
                Button("Neue Routine", action: addRoutine).buttonStyle(PrimaryButtonStyle())
            }
            .padding(Space.s4)
        }
    }

    /// Beginn des 7-Tage-Fensters (heute eingeschlossen).
    private static func weekCutoff(now: Date = .now) -> Date {
        Calendar.forma.date(byAdding: .day, value: -6, to: Calendar.forma.startOfDay(for: now)) ?? now
    }

    /// Arbeitssätze ab einem Zeitpunkt (Zeit = Trainingsbeginn) und die Gruppen eigener Übungen.
    private func entries(since cutoff: Date) -> [(exercise: String, date: Date)] {
        sessions.filter { $0.start >= cutoff }.flatMap { s in s.workSets.map { (exercise: $0.exerciseName, date: s.start) } }
    }

    private var exerciseGroups: [String: String] {
        let library = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        return Dictionary(library.map { ($0.name, $0.muscle) }, uniquingKeysWith: { a, _ in a })
    }

    /// Sätze je Muskel der letzten 7 Tage (primär 1, sekundär ½).
    private var weeklyVolume: [Muscle: Double] {
        MuscleVolume.lastSevenDays(entries(since: Self.weekCutoff()), groups: exerciseGroups)
    }

    /// Mindestens ein Arbeitssatz in den letzten 72 h – sonst gibt es keine Einstufung.
    private var hasRecentWork: Bool {
        !entries(since: Date.now.addingTimeInterval(-MuscleRecovery.window)).isEmpty
    }

    /// Restbelastung je Muskel aus den letzten 72 h.
    private var recoveryLoad: [Muscle: Double] {
        MuscleRecovery.load(entries(since: Date.now.addingTimeInterval(-MuscleRecovery.window)), groups: exerciseGroups)
    }

    private func weeklyMuscles(_ volume: [Muscle: Double]) -> some View {
        let ranked = volume.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let untrained = Muscle.allCases.filter { (volume[$0] ?? 0) == 0 }
        let load = recoveryLoad
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if muscleMode == .week {
                    MuscleMapView(intensity: volume.mapValues(MuscleVolume.level), selected: selectedMuscle, showsBoth: true) { select($0) }
                } else {
                    MuscleMapView(intensity: load.mapValues(MuscleRecovery.level), selected: selectedMuscle, showsBoth: true, tint: Theme.older) { select($0) }
                }
            }
            .frame(height: 250)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .animation(.smooth, value: muscleMode)
            if let muscle = selectedMuscle {
                selectedRow(muscle, volume: volume, load: load)
                    .transition(.opacity)
            } else if muscleMode == .week && !ranked.isEmpty {
                volumeLegend
                    .transition(.opacity)
            }
            QuietSegments(options: [(MuscleMode.week, "7 Tage"), (MuscleMode.recovery, "Erholung")], selection: $muscleMode)
                .frame(maxWidth: .infinity)
            if muscleMode == .recovery {
                recoveryRows(load)
            } else if ranked.isEmpty {
                Text("Nach deinem ersten Training färbt sich hier jeder Muskel nach seinen Sätzen der letzten 7 Tage.")
                    .font(.formaBody).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom], Space.s4)
            } else {
                ForEach(ranked.prefix(4), id: \.key) { entry in
                    Button { tappedMuscle = entry.key } label: {
                        HStack(spacing: Space.s3) {
                            Text(entry.key.name).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                                .frame(width: 112, alignment: .leading)
                            ProgressLine(fraction: min(1, entry.value / 20), height: 6)
                            Text(MuscleVolume.text(entry.value)).font(.formaValue).frame(width: 36, alignment: .trailing)
                        }
                        .padding(.horizontal, Space.s4)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(entry.key.name), \(MuscleVolume.text(entry.value)) Sätze")
                }
                if !untrained.isEmpty {
                    Text("Noch nicht dran: " + untrained.map(\.name).joined(separator: ", "))
                        .font(.formaCaption).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.top, Space.s2)
                }
                Color.clear.frame(height: Space.s4)
            }
        }
    }

    private func select(_ muscle: Muscle) {
        withAnimation(.smooth(duration: 0.25)) { selectedMuscle = selectedMuscle == muscle ? nil : muscle }
    }

    /// Name, Sätze bzw. Zustand und letzte Belastung des angetippten Muskels; Tippen öffnet die Übungen dazu.
    private func selectedRow(_ muscle: Muscle, volume: [Muscle: Double], load: [Muscle: Double]) -> some View {
        let sets = volume[muscle] ?? 0
        let last = MuscleVolume.lastTrained(entries(since: .distantPast), groups: exerciseGroups)[muscle]
        var parts: [String] = []
        if muscleMode == .week {
            parts.append(sets > 0 ? "\(MuscleVolume.text(sets)) Sätze · \(MuscleVolume.band(sets)?.title ?? "")" : "Keine Sätze in 7 Tagen")
        } else if hasRecentWork {
            parts.append(MuscleRecovery.state(load[muscle] ?? 0).title)
        }
        parts.append(last.map { "zuletzt \(MuscleVolume.lastText($0))" } ?? "noch nie trainiert")
        return Button { tappedMuscle = muscle } label: {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(muscle.name).font(.formaRowTitle).foregroundStyle(Theme.textPrimary)
                    Text(parts.joined(separator: " · ")).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(muscle.name), \(parts.joined(separator: ", "))")
        .accessibilityHint("Zeigt Übungen für diesen Muskel")
    }

    /// Stufen relativ zum Wochenziel; grau = nicht trainiert.
    private var volumeLegend: some View {
        let target = MuscleVolume.weeklyTarget
        let items = MuscleVolume.Band.allCases.map { band in
            (band, band == .target ? "\(band.title) \(Int(target.lowerBound))–\(Int(target.upperBound))" : band.title)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s3) { ForEach(items, id: \.0) { legendSwatch($0.0, $0.1) } }
            Grid(alignment: .leading, horizontalSpacing: Space.s4, verticalSpacing: Space.s2) {
                GridRow {
                    legendSwatch(items[0].0, items[0].1)
                    legendSwatch(items[1].0, items[1].1)
                }
                GridRow {
                    legendSwatch(items[2].0, items[2].1)
                    legendSwatch(items[3].0, items[3].1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stufen nach Sätzen pro Woche: wenig, unter Ziel, im Ziel \(Int(target.lowerBound)) bis \(Int(target.upperBound)), über Ziel. Grau heißt nicht trainiert.")
    }

    private func legendSwatch(_ band: MuscleVolume.Band, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(Theme.cardRaised)
                .overlay { RoundedRectangle(cornerRadius: 3).fill(MuscleMapView.fill(band.level)) }
                .frame(width: 10, height: 10)
            Text(label).font(.formaMicro).foregroundStyle(Theme.textSecondary).fixedSize()
        }
    }

    /// Belastete und sich erholende Muskeln der letzten 72 h; der Rest ist frisch.
    @ViewBuilder private func recoveryRows(_ load: [Muscle: Double]) -> some View {
        let byState = Dictionary(grouping: Muscle.allCases) { MuscleRecovery.state(load[$0] ?? 0) }
        VStack(alignment: .leading, spacing: Space.s2) {
            // Einstufung nur aus auswertbaren Arbeitssätzen; Aufwärmsätze zählen nicht (Gegenprüfung 04 #8).
            if !sessions.contains(where: { !$0.workSets.isEmpty }) {
                Text("Noch keine Trainingsdaten.")
                    .font(.formaBody).foregroundStyle(Theme.textSecondary)
            } else if !hasRecentWork {
                Text("Keine Arbeitssätze in den letzten 72 Stunden erfasst.")
                    .font(.formaBody).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach([RecoveryState.loaded, .recovering], id: \.self) { state in
                    if let muscles = byState[state], !muscles.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            Circle().fill(Theme.older.opacity(state == .loaded ? 1 : 0.5)).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(state.title).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                            Text(muscles.map(\.name).joined(separator: ", ")).font(.formaCaption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                let fresh = byState[.fresh]?.count ?? 0
                Text(fresh == Muscle.allCases.count ? "Alle Muskeln sind frisch." : "\(fresh) von \(Muscle.allCases.count) Muskeln sind frisch.")
                    .font(.formaCaption).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s4)
    }

    private func duplicate(_ routine: Routine) {
        let copy = routine.duplicate(in: context, existingNames: routines.map(\.name))
        try? context.save()
        path.append(.routine(copy.persistentModelID))
    }

    private func addRoutine() {
        let routine = Routine(name: "Neue Routine")
        context.insert(routine)
        try? context.save()
        path.append(.routine(routine.persistentModelID))
    }

    private func start(_ routine: Routine) {
        routine.lastUsed = .now
        try? context.save()
        app.liveWorkout = LiveWorkout.from(routine, history: sessions, adjustment: app.workoutAdjustment)
    }
}

struct SessionRow: View {
    let session: WorkoutSession
    @Environment(AppState.self) private var app
    var body: some View {
        MetricRow(title: session.title,
                  subtitle: "\(session.start.formatted(Date.FormatStyle(locale: .german).weekday(.abbreviated).day().month(.abbreviated))) · \(Format.duration(session.duration)) · \(session.workSets.count) Sätze",
                  value: Format.weight(session.volume, unit: app.weightUnit), unit: app.weightUnit.rawValue)
    }
}

struct HistoryView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var selectedDay: Date?

    var body: some View {
        let shown = selectedDay.map { day in sessions.filter { Calendar.forma.isDate($0.start, inSameDayAs: day) } } ?? sessions
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Plate {
                    TrainingCalendarCard(dates: sessions.map(\.start), selectedDay: $selectedDay)
                        .padding(Space.s4)
                }
                .padding(.top, Space.s3)
                FormaSection(title: selectedDay.map { $0.formatted(Date.FormatStyle(locale: .german).weekday(.wide).day().month(.wide)) } ?? "Alle Trainings") {
                    Plate {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, session in
                            if index > 0 { RowDivider() }
                            Button { app.finishedSession = session } label: { SessionRow(session: session) }.buttonStyle(.plain)
                        }
                    }
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.page)
        }
        .formaScreen()
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
    }
}
