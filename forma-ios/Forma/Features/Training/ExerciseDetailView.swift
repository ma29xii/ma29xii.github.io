import SwiftUI
import SwiftData
import Charts

/// Übung: Muskelkarte oben, darunter Ausführung oder Verlauf (geschätztes Maximum, Bestwert, letzte Sätze).
struct ExerciseDetailView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutSession.start) private var sessions: [WorkoutSession]
    let exercise: Exercise
    @State private var tab: DetailTab?
    @State private var tappedMuscle: Muscle?

    enum DetailTab: Hashable { case guide, history }

    private var points: [(Date, Double)] {
        sessions.compactMap { s in
            let best = s.bestOneRepMax(for: exercise.name)
            return best > 0 ? (s.start, best) : nil
        }
    }

    var body: some View {
        let pts = points
        let current = tab ?? (pts.isEmpty ? .guide : .history)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(exercise.muscle) · \(exercise.equipment)")
                    .font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                    .padding(.top, Space.s4)
                ExerciseMuscleCard(name: exercise.name, group: exercise.muscle) { tappedMuscle = $0 }
                    .padding(.top, Space.s3)

                Picker("Inhalt", selection: Binding(get: { current }, set: { tab = $0 })) {
                    Text("Ausführung").tag(DetailTab.guide)
                    Text("Verlauf").tag(DetailTab.history)
                }
                .pickerStyle(.segmented)
                .padding(.top, Space.s5)

                switch current {
                case .guide:
                    if let info = ExerciseCatalog.info(for: exercise.name) {
                        ExerciseGuideSections(info: info)
                    } else {
                        Text("Für eigene Übungen gibt es keine Anleitung. Die Karte zeigt die Hauptmuskeln der Gruppe „\(exercise.muscle)“.")
                            .font(.formaBody).foregroundStyle(Theme.textSecondary).padding(.top, Space.s5)
                    }
                case .history:
                    history(pts)
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.page)
        }
        .formaScreen()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $tappedMuscle) { MuscleExercisesSheet(muscle: $0) }
    }

    @ViewBuilder private func history(_ pts: [(Date, Double)]) -> some View {
        let best = pts.map(\.1).max()
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(best.map { Format.weight($0, unit: app.weightUnit) } ?? "–").font(.formaDisplay)
                Text(app.weightUnit.rawValue).font(.formaBody).foregroundStyle(Theme.textSecondary)
            }
            Text("bestes geschätztes Maximum (Epley)").font(.formaCaption).foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, Space.s5)

        if pts.count >= 2 {
            Plate {
                Chart {
                    ForEach(pts, id: \.0) { p in
                        LineMark(x: .value("Datum", p.0), y: .value("1RM", p.1))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.textPrimary)
                        PointMark(x: .value("Datum", p.0), y: .value("1RM", p.1))
                            .foregroundStyle(Theme.textPrimary)
                            .symbolSize(18)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel().foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textTertiary) }
                }
                .frame(height: 200)
                .padding(Space.s4)
            }
            .padding(.top, Space.s4)
        } else {
            Text("Nach zwei Trainings mit dieser Übung siehst du hier deinen Verlauf.")
                .font(.formaBody).foregroundStyle(Theme.textSecondary).padding(.top, Space.s4)
        }

        let recent = sessions.reversed().filter { $0.sets.contains { $0.exerciseName == exercise.name } }.prefix(6)
        if !recent.isEmpty {
            FormaSection(title: "Letzte Trainings") {
                Plate {
                    ForEach(Array(recent.enumerated()), id: \.offset) { index, s in
                        if index > 0 { RowDivider() }
                        let work = s.workSets.filter { $0.exerciseName == exercise.name }
                        MetricRow(title: s.start.formatted(Date.FormatStyle(locale: .german).day().month(.wide)),
                                  subtitle: work.map { "\(Format.weight($0.weight, unit: app.weightUnit)) × \($0.reps)" }.joined(separator: " · "),
                                  value: Format.weight(s.bestOneRepMax(for: exercise.name), unit: app.weightUnit), unit: app.weightUnit.rawValue)
                    }
                }
            }
        }
    }
}

// MARK: - Bausteine

/// Muskelkarte einer Übung mit Legende (Hauptmuskeln kräftig, mithelfende gedämpft).
struct ExerciseMuscleCard: View {
    let name: String
    let group: String
    var onSelect: ((Muscle) -> Void)? = nil

    var body: some View {
        let muscles = ExerciseCatalog.muscles(for: name, group: group)
        Plate {
            MuscleMapView(intensity: ExerciseCatalog.intensity(primary: muscles.primary, secondary: muscles.secondary), onSelect: onSelect)
                .frame(height: 330)
                .padding(.top, Space.s4)
            VStack(alignment: .leading, spacing: 6) {
                legendRow(level: 1, title: "Hauptmuskeln", muscles: muscles.primary)
                if !muscles.secondary.isEmpty {
                    legendRow(level: ExerciseCatalog.secondaryLevel, title: "Hilft mit", muscles: muscles.secondary)
                }
                if onSelect != nil {
                    Text("Tipp auf einen Muskel für passende Übungen.").font(.formaCaption).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
        }
    }

    private func legendRow(level: Double, title: String, muscles: [Muscle]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Circle().fill(Theme.strain.opacity(0.22 + 0.78 * level)).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(title).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
            Text(muscles.map(\.name).joined(separator: ", ")).font(.formaCaption).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Richtige Ausführung: Bewegung, Schritte, häufige Fehler, Atmung und Tempo.
struct ExerciseGuideSections: View {
    let info: ExerciseInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let motion = info.motion {
                FormaSection(title: "Bewegung") {
                    Plate { ExerciseMotionView(motion: motion).padding(.vertical, Space.s2) }
                }
            }
            FormaSection(title: "Ausführung") {
                Plate {
                    ForEach(Array(info.steps.enumerated()), id: \.offset) { i, step in
                        if i > 0 { RowDivider(inset: 54) }
                        HStack(alignment: .top, spacing: Space.s3) {
                            Text("\(i + 1)")
                                .font(.formaMicro).monospacedDigit()
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Theme.cardRaised))
                                .accessibilityLabel("Schritt \(i + 1)")
                            Text(step).font(.formaBody).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            FormaSection(title: "Häufige Fehler") {
                Plate {
                    ForEach(Array(info.mistakes.enumerated()), id: \.offset) { i, mistake in
                        if i > 0 { RowDivider(inset: 54) }
                        textRow(symbol: "xmark.circle", text: mistake)
                    }
                }
            }
            FormaSection(title: "Atmung und Tempo") {
                Plate {
                    textRow(symbol: "wind", text: info.breathing)
                    RowDivider(inset: 54)
                    textRow(symbol: "metronome", text: info.tempo)
                }
            }
        }
    }

    private func textRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(text).font(.formaBody).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 12)
    }
}

/// Anleitung als Blatt, z. B. aus dem Live-Training.
struct ExerciseGuideSheet: View {
    let name: String
    let group: String
    @Environment(\.dismiss) private var dismiss
    @State private var tappedMuscle: Muscle?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ExerciseMuscleCard(name: name, group: group) { tappedMuscle = $0 }
                        .padding(.top, Space.s3)
                    if let info = ExerciseCatalog.info(for: name) {
                        ExerciseGuideSections(info: info)
                    } else {
                        Text("Für eigene Übungen gibt es keine Anleitung.")
                            .font(.formaBody).foregroundStyle(Theme.textSecondary).padding(.top, Space.s5)
                    }
                    Color.clear.frame(height: Space.s7)
                }
                .padding(.horizontal, Space.page)
            }
            .formaScreen()
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .sheet(item: $tappedMuscle) { MuscleExercisesSheet(muscle: $0) }
        }
    }
}

/// Ein Muskel: wo er sitzt, wie viel er zuletzt bekam und welche Übungen ihn trainieren.
struct MuscleExercisesSheet: View {
    let muscle: Muscle
    var weeklySets: Double? = nil
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    var body: some View {
        let direct = exercises.filter { ExerciseCatalog.muscles(for: $0.name, group: $0.muscle).primary.contains(muscle) }
        let assist = exercises.filter {
            let m = ExerciseCatalog.muscles(for: $0.name, group: $0.muscle)
            return m.secondary.contains(muscle) && !m.primary.contains(muscle)
        }
        NavigationStack {
            List {
                Section {
                    MuscleMapView(intensity: [muscle: 1], selected: muscle, showsBoth: true)
                        .frame(height: 220)
                        .padding(.vertical, Space.s2)
                        .listRowBackground(Color.clear)
                    if let weeklySets {
                        LabeledContent("Sätze, letzte 7 Tage", value: MuscleVolume.text(weeklySets))
                    }
                }
                if !direct.isEmpty {
                    Section("Trainiert \(muscle.name) direkt") { ForEach(direct) { row($0) } }
                }
                if !assist.isEmpty {
                    Section("Hilft mit") { ForEach(assist) { row($0) } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle(muscle.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ ex: Exercise) -> some View {
        NavigationLink { ExerciseDetailView(exercise: ex) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(.formaRowTitle)
                Text(ex.equipment).font(.formaCaption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
