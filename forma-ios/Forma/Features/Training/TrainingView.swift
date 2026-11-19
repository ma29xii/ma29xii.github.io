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

struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var editingTiles = false
    @State private var path: [TrainingRoute] = []
    @State private var tappedMuscle: Muscle?

    private var next: Routine? { routines.min { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if app.isDemo { SampleDataBadge() }
                    TileStack<TrainingTile, AnyView>(storageKey: "forma.tiles.training", screenTitle: "Training", isEditing: $editingTiles) { tile in
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { editingTiles = true } label: { Image(systemName: "square.grid.2x2") }
                        .accessibilityLabel("Training anpassen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.showProfile = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Profil und Einstellungen")
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
            .sheet(item: $tappedMuscle) { m in MuscleExercisesSheet(muscle: m, weeklySets: weeklyVolume[m] ?? 0) }
        }
    }

    @ViewBuilder private func view(for tile: TrainingTile) -> some View {
        switch tile {
        case .next:
            if let next { nextCard(next) } else { emptyCard }
        case .routines:
            WidgetCard(title: tile.title, systemImage: tile.systemImage) {
                if routines.isEmpty { MetricRow(title: "Noch keine Routine") }
                ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                    if index > 0 { RowDivider() }
                    Button { path.append(.routine(routine.persistentModelID)) } label: {
                        MetricRow(title: routine.name, subtitle: "\(routine.items.count) Übungen · \(routine.muscleSummary)", showsChevron: true)
                    }
                    .buttonStyle(.plain)
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
                }
                if sessions.count > 5 {
                    RowDivider()
                    Button { path.append(.history) } label: { MetricRow(title: "Alle Trainings", showsChevron: true) }
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
                    MetricRow(title: "Übungsbibliothek", subtitle: "Übungen ansehen und eigene anlegen", showsChevron: true)
                }
                .buttonStyle(.plain)
                RowDivider()
                Button { app.liveWorkout = LiveWorkout.empty() } label: {
                    MetricRow(title: "Freies Training", subtitle: "Ohne Routine starten, Übungen unterwegs hinzufügen", showsChevron: true)
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

    /// Sätze je Muskel der letzten 7 Tage (primär 1, sekundär ½).
    private var weeklyVolume: [Muscle: Double] {
        let cutoff = Self.weekCutoff()
        let entries = sessions.filter { $0.start >= cutoff }.flatMap { s in s.workSets.map { (exercise: $0.exerciseName, date: s.start) } }
        let library = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let groups = Dictionary(library.map { ($0.name, $0.muscle) }, uniquingKeysWith: { a, _ in a })
        return MuscleVolume.lastSevenDays(entries, groups: groups)
    }

    private func weeklyMuscles(_ volume: [Muscle: Double]) -> some View {
        let ranked = volume.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let untrained = Muscle.allCases.filter { (volume[$0] ?? 0) == 0 }
        return VStack(alignment: .leading, spacing: 0) {
            MuscleMapView(intensity: volume.mapValues(MuscleVolume.level), showsBoth: true) { tappedMuscle = $0 }
                .frame(height: 250)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            if ranked.isEmpty {
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
                  value: Format.weight(session.volume, unit: app.weightUnit), unit: app.weightUnit.rawValue, showsChevron: true)
    }
}

struct HistoryView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        ScrollView {
            Plate {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { RowDivider() }
                    Button { app.finishedSession = session } label: { SessionRow(session: session) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.s3)
        }
        .formaScreen()
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
    }
}
