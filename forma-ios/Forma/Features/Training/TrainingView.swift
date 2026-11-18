import SwiftUI
import SwiftData

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
    @State private var path: [TrainingRoute] = []

    private var next: Routine? { routines.min { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let next { nextCard(next) } else { emptyCard }

                    FormaSection(title: "Routinen", actionTitle: "Neu", action: addRoutine) {
                        Plate {
                            if routines.isEmpty { MetricRow(title: "Noch keine Routine") }
                            ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                                if index > 0 { RowDivider() }
                                HStack(spacing: 0) {
                                    Button { path.append(.routine(routine.persistentModelID)) } label: {
                                        MetricRow(title: routine.name, subtitle: "\(routine.items.count) Übungen · \(routine.muscleSummary)", showsChevron: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .contextMenu {
                                    Button("Starten", systemImage: "play") { start(routine) }
                                    Button("Löschen", systemImage: "trash", role: .destructive) { context.delete(routine); try? context.save() }
                                }
                            }
                        }
                    }

                    FormaSection(title: "Verlauf", actionTitle: sessions.count > 5 ? "Alle" : nil, action: { path.append(.history) }) {
                        Plate {
                            if sessions.isEmpty { MetricRow(title: "Noch kein Training", subtitle: "Deine Trainings erscheinen hier") }
                            ForEach(Array(sessions.prefix(5).enumerated()), id: \.element.id) { index, session in
                                if index > 0 { RowDivider() }
                                Button { app.finishedSession = session } label: { SessionRow(session: session) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    FormaSection(title: "Harte Sätze diese Woche") {
                        Plate { weeklySets }
                    }

                    FormaSection(title: "Bibliothek") {
                        Plate {
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
                    Color.clear.frame(height: Space.s7)
                }
                .padding(.horizontal, Space.page)
            }
            .formaScreen()
            .navigationTitle("Training")
            .toolbar {
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
        }
    }

    private func nextCard(_ routine: Routine) -> some View {
        let adjustment = TrainingAdjustment.today
        return Plate {
            VStack(alignment: .leading, spacing: 4) {
                Text("Als Nächstes").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                Text(routine.name).font(.formaHeadline)
                Text("\(routine.items.count) Übungen · \(routine.totalSets) Sätze · \(routine.muscleSummary)")
                    .font(.formaBody).foregroundStyle(Theme.textSecondary)
                if let adjustment {
                    Label("Coach-Anpassung für heute: \(adjustment.title)", systemImage: "sparkles")
                        .font(.formaCaption).foregroundStyle(Theme.textSecondary).padding(.top, 6)
                }
                Button("Training starten") { start(routine) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, Space.s4)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, 20)
            .padding(.bottom, Space.s4)
        }
        .padding(.top, Space.s3)
    }

    private var emptyCard: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Leg deine erste Routine an").font(.formaHeadline)
                Button("Neue Routine", action: addRoutine).buttonStyle(PrimaryButtonStyle())
            }
            .padding(Space.s4)
        }
        .padding(.top, Space.s3)
    }

    private var weeklySets: some View {
        let weekStart = Calendar.forma.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let sets = sessions.filter { $0.start >= weekStart }.flatMap(\.workSets)
        let library = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let muscleFor: (String) -> String = { name in library.first { $0.name == name }?.muscle ?? "Andere" }
        let groups = ["Brust", "Rücken", "Beine", "Schultern", "Arme"]
        return VStack(spacing: 0) {
            ForEach(groups, id: \.self) { g in
                let n = sets.filter { muscleFor($0.exerciseName) == g && ($0.rir < 0 || $0.rir <= 3) }.count
                HStack(spacing: Space.s3) {
                    Text(g).font(.formaCaption).foregroundStyle(Theme.textSecondary).frame(width: 76, alignment: .leading)
                    ZStack(alignment: .leading) {
                        ProgressLine(fraction: Double(n) / 20, height: 6)
                        GeometryReader { geo in Rectangle().fill(Theme.textTertiary).frame(width: 1, height: 10).offset(x: geo.size.width / 2, y: -2) }
                            .frame(height: 6)
                    }
                    Text("\(n)").font(.formaValue).frame(width: 28, alignment: .trailing)
                }
                .padding(.horizontal, Space.s4)
                .frame(minHeight: 40)
            }
            Text("Strich: 10 Sätze pro Woche als Richtwert")
                .font(.formaCaption).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .bottom], Space.s4)
        }
        .padding(.top, Space.s2)
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
        app.liveWorkout = LiveWorkout.from(routine, history: sessions, adjustment: TrainingAdjustment.today)
    }
}

struct SessionRow: View {
    let session: WorkoutSession
    var body: some View {
        MetricRow(title: session.title,
                  subtitle: "\(session.start.formatted(Date.FormatStyle(locale: .german).weekday(.abbreviated).day().month(.abbreviated))) · \(Format.duration(session.duration)) · \(session.workSets.count) Sätze",
                  value: Format.number(session.volume), unit: "kg", showsChevron: true)
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
