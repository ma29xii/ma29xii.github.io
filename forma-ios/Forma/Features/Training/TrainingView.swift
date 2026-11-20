import SwiftUI
import SwiftData

enum TrainingTile: String, TileKind {
    case activities, next, routines, cardio, strength, weeklySets, history, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .next: "Als Nächstes"
        case .activities: "Aktivitäten"
        case .cardio: "Cardio"
        case .strength: "Krafttraining"
        case .weeklySets: "Muskelgruppen"
        case .routines: "Routinen"
        case .history: "Verlauf"
        case .library: "Bibliothek"
        }
    }
    var systemImage: String {
        switch self {
        case .next: "play.circle"
        case .activities: "figure.walk"
        case .cardio: "heart"
        case .strength: "dumbbell"
        case .weeklySets: "figure.strengthtraining.traditional"
        case .routines: "list.bullet.rectangle"
        case .history: "clock.arrow.circlepath"
        case .library: "books.vertical"
        }
    }
    var summary: String {
        switch self {
        case .next: "Nächste Routine mit Start-Knopf"
        case .activities: "Erfasste Aktivitäten"
        case .cardio: "Dauer, Energie und VO₂max"
        case .strength: "Arbeitssätze und Volumen"
        case .weeklySets: "Muskelkarte nach Belastung und Erholung"
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
    case activities(cardioOnly: Bool)
    case activity(UUID)
    case metric(MetricKind)
}

struct TrainingStrainTarget {
    enum Tone: Equatable { case neutral, green, orange }

    let range: ClosedRange<Int>
    let status: String
    let tone: Tone
    let offersLightRoutine: Bool

    init?(strain: Int?, recovery: Int?) {
        guard let recovery, let target = RingDetailView.strainTarget(strain: strain, recovery: recovery) else { return nil }
        range = target.range
        status = target.status
        tone = switch target.status {
        case "Im Ziel": .green
        case "Über dem Ziel": .orange
        default: .neutral
        }
        offersLightRoutine = recovery < 34
    }
}

/// Bisherige Trainingsseite als eigenständige Ansicht (Runde 11: kein eigener Tab mehr, Plus-Menü öffnet sie).
struct TrainingHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Environment(DataHub.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .refreshable { await hub.refresh() }
            .formaScreen()
            .navigationTitle("Fitness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.backgroundTop, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
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
                case .activities(let cardioOnly):
                    InsightPage(title: cardioOnly ? "Cardio" : "Aktivitäten") {
                        FitnessActivityHistory(workouts: cardioOnly ? fitnessActivities.filter(FitnessCardio.includes) : fitnessActivities)
                    }
                case .activity(let id):
                    if let activity = fitnessActivities.first(where: { $0.id == id }) {
                        FitnessActivityDetail(activity: activity)
                    }
                case .metric(let kind):
                    MetricDetailView(kind: kind)
                }
            }
            .sheet(item: $tappedMuscle) { m in
                MuscleExercisesSheet(muscle: m, weeklySets: weeklyVolume[m] ?? 0, recovery: muscleRecoveryState(m))
            }
        }
    }

    @ViewBuilder private func view(for tile: TrainingTile) -> some View {
        switch tile {
        case .next:
            if let next {
                TimelineView(.everyMinute) { timeline in
                    nextCard(next, target: strainTarget(at: timeline.date))
                }
            } else {
                emptyCard
            }
        case .activities:
            FitnessActivityHistory(workouts: fitnessActivities, title: tile.title, limit: 4)
        case .cardio:
            cardioCards
        case .strength:
            strengthCards
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
            WidgetCard(title: tile.title, systemImage: tile.systemImage, accessory: total > 0 ? "\(total) Sätze · 7 Tage" : "7 Tage") {
                weeklyMuscles(volume)
            }
            .accessibilityIdentifier("fitness.muscles")
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

    private func strainTarget(at date: Date) -> TrainingStrainTarget? {
        guard !hub.isSample else { return nil }
        let today = date.startOfDay
        let recent = hub.days
        guard let day = recent.last(where: { $0.date == today }) else { return nil }
        let snapshot = DashboardDay(day: day, history: recent)
        return TrainingStrainTarget(strain: snapshot.strain, recovery: snapshot.recovery)
    }

    private func nextCard(_ routine: Routine, target: TrainingStrainTarget?) -> some View {
        let adjustment = TrainingAdjustment.today
        let offersLightRoutine = target?.offersLightRoutine == true
        return WidgetCard(title: "Als Nächstes", systemImage: TrainingTile.next.systemImage) {
            VStack(alignment: .leading, spacing: 4) {
                if let target {
                    strainTargetRow(target)
                        .padding(.bottom, Space.s1)
                }
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
                if offersLightRoutine {
                    // Rote Recovery: dieselbe Routine, bewusst locker angehen.
                    Button { start(routine) } label: {
                        Text("Lockere Einheit").font(.formaBody).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
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

    private func strainTargetRow(_ target: TrainingStrainTarget) -> some View {
        let low = target.range.lowerBound
        let high = target.range.upperBound
        let tint: Color = switch target.tone {
        case .neutral: Theme.textSecondary
        case .green: Theme.younger
        case .orange: Theme.older
        }
        let goal = HStack(spacing: Space.s2) {
            Circle().fill(Theme.strain).frame(width: 6, height: 6)
            Text("Heute: Strain \(low)–\(high)").foregroundStyle(Theme.textSecondary)
        }
        let status = Text(target.status)
            .foregroundStyle(tint)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, Space.s1)
            .background(tint.opacity(0.12), in: Capsule())

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s2) {
                goal.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                status.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                goal
                status
            }
        }
        .font(.formaCaptionStrong)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tagesziel")
        .accessibilityValue("Strain \(low) bis \(high), \(target.status)")
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

    /// Das Dashboard verwendet denselben zusammengeführten Verlauf wie Today.
    private var fitnessActivities: [WorkoutSummary] {
        let now = Date.now
        var seen: Set<UUID> = []
        return hub.days.flatMap(\.workouts).filter {
            $0.start <= now && seen.insert($0.id).inserted
        }
        .sorted { $0.start > $1.start }
    }

    private static func weekDays(now: Date = .now) -> [Date] {
        (-6...0).compactMap { Calendar.forma.startOfDay(offsetBy: $0, from: now) }
    }

    private var cardioCards: some View {
        let dates = Self.weekDays()
        let cardio = fitnessActivities.filter { $0.start >= Self.weekCutoff() && FitnessCardio.includes($0) }
        let grouped = Dictionary(grouping: cardio) { Calendar.forma.startOfDay(for: $0.start) }
        let duration = WorkoutSummary.totalDuration(cardio)
        let energy = FitnessCardio.energy(cardio)
        let fitness = hub.longDays.filter { $0.date <= Date.now }.sorted { $0.date < $1.date }
        let latestVO2 = fitness.compactMap(MetricKind.vo2max.value).last
        let weekVO2 = Dictionary(fitness.compactMap { day in day.vo2max.map { (day.date, $0) } }, uniquingKeysWith: { _, latest in latest })
        return FitnessMetricGrid(title: "Cardio · 7 Tage") {
            NavigationLink(value: TrainingRoute.activities(cardioOnly: true)) {
                FitnessMetricCard(title: "Dauer", value: cardio.isEmpty ? "–" : Format.duration(duration), tint: Theme.younger,
                                  bars: dates.map { date in grouped[date].map { WorkoutSummary.totalDuration($0) } })
            }
            .buttonStyle(.plain)
            FitnessMetricCard(title: "Aktive Energie", value: energy.map { ($0.complete ? "" : "≥ ") + Format.number($0.value) + " kcal" } ?? "–",
                              tint: Theme.younger, bars: dates.map { date in grouped[date].flatMap(FitnessCardio.energy)?.value })
            NavigationLink(value: TrainingRoute.metric(.vo2max)) {
                FitnessMetricCard(title: "VO₂max · letzter Wert", value: latestVO2.map(MetricKind.vo2max.measurement) ?? "–",
                                  tint: MetricKind.vo2max.tint, bars: dates.map { weekVO2[$0] })
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("fitness.cardio")
    }

    private var strengthCards: some View {
        let dates = Self.weekDays()
        let recent = sessions.filter { $0.start >= Self.weekCutoff() && $0.start <= .now && !$0.workSets.isEmpty }
        let grouped = Dictionary(grouping: recent) { Calendar.forma.startOfDay(for: $0.start) }
        let sets = recent.reduce(0) { $0 + $1.workSets.count }
        let volume = recent.reduce(0.0) { $0 + $1.volume }
        return FitnessMetricGrid(title: "Krafttraining · 7 Tage") {
            NavigationLink(value: TrainingRoute.history) {
                FitnessMetricCard(title: "Arbeitssätze", value: recent.isEmpty ? "–" : Format.number(Double(sets)), tint: Theme.strain,
                                  bars: dates.map { date in grouped[date].map { Double($0.reduce(0) { $0 + $1.workSets.count }) } })
            }
            .buttonStyle(.plain)
            NavigationLink(value: TrainingRoute.history) {
                FitnessMetricCard(title: "Volumen",
                                  value: recent.isEmpty ? "–" : "\(Format.weight(volume, unit: app.weightUnit)) \(app.weightUnit.rawValue)",
                                  tint: Theme.strain, bars: dates.map { date in grouped[date].map { $0.reduce(0) { $0 + $1.volume } } })
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("fitness.strength")
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

    /// Restbelastung je Muskel aus den letzten 72 h.
    private var recoveryLoad: [Muscle: Double] {
        MuscleRecovery.load(entries(since: Date.now.addingTimeInterval(-MuscleRecovery.window)), groups: exerciseGroups)
    }

    private func muscleRecoveryState(_ muscle: Muscle) -> RecoveryState? {
        guard (weeklyVolume[muscle] ?? 0) > 0 else { return nil }
        return MuscleRecovery.state(recoveryLoad[muscle] ?? 0)
    }

    private func weeklyMuscles(_ volume: [Muscle: Double]) -> some View {
        let ranked = volume.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let untrained = Muscle.allCases.filter { (volume[$0] ?? 0) == 0 }
        let load = recoveryLoad
        let states = volume.mapValues { _ in RecoveryState.fresh }.merging(load.mapValues(MuscleRecovery.state)) { _, current in current }
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if muscleMode == .week {
                    MuscleMapView(intensity: volume.mapValues(MuscleVolume.level), selected: selectedMuscle, showsBoth: true) { select($0) }
                } else {
                    MuscleMapView(intensity: states.mapValues { $0 == .fresh ? 0.44 : 0.85 },
                                  selected: selectedMuscle, showsBoth: true, muscleTints: states.mapValues(recoveryTint)) { select($0) }
                }
            }
            .frame(height: 250)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .animation(reduceMotion ? nil : .smooth, value: muscleMode)
            if let muscle = selectedMuscle {
                selectedRow(muscle, volume: volume, load: load)
                    .transition(.opacity)
            } else if muscleMode == .week && !ranked.isEmpty {
                volumeLegend
                    .transition(.opacity)
            }
            QuietSegments(options: [(MuscleMode.week, "Belastung"), (MuscleMode.recovery, "Erholung")],
                          selection: $muscleMode, animation: reduceMotion ? .easeOut(duration: 0.15) : .smooth)
                .frame(maxWidth: .infinity)
            if muscleMode == .recovery {
                recoveryTiles(states)
            } else if ranked.isEmpty {
                Text("Keine Arbeitssätze in 7 Tagen")
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
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { selectedMuscle = selectedMuscle == muscle ? nil : muscle }
    }

    /// Name, Sätze bzw. Zustand und letzte Belastung des angetippten Muskels; Tippen öffnet die Übungen dazu.
    private func selectedRow(_ muscle: Muscle, volume: [Muscle: Double], load: [Muscle: Double]) -> some View {
        let sets = volume[muscle] ?? 0
        let last = MuscleVolume.lastTrained(entries(since: .distantPast), groups: exerciseGroups)[muscle]
        var parts: [String] = []
        if muscleMode == .week {
            parts.append(sets > 0 ? "\(MuscleVolume.text(sets)) Sätze · \(MuscleVolume.band(sets)?.title ?? "")" : "Keine Sätze in 7 Tagen")
        } else if sets > 0 {
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

    private func recoveryTint(_ state: RecoveryState) -> Color {
        switch state {
        case .fresh: Theme.younger
        case .recovering: Theme.warning
        case .loaded: Theme.older
        }
    }

    @ViewBuilder private func recoveryTiles(_ states: [Muscle: RecoveryState]) -> some View {
        if states.isEmpty {
            DashboardEmpty(title: "Keine Arbeitssätze in 7 Tagen")
        } else {
            FitnessMetricGrid(title: "Muskelregeneration") {
                ForEach(Muscle.allCases.filter { states[$0] != nil }) { muscle in
                    if let state = states[muscle] {
                        Button {
                            tappedMuscle = muscle
                        } label: {
                            FitnessMetricCard(title: muscle.name, value: state.title, tint: recoveryTint(state),
                                              bars: [])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding([.horizontal, .bottom], Space.s4)
        }
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
