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
                ExerciseMuscleCard(name: exercise.name, group: exercise.muscle, equipment: exercise.equipment) { tappedMuscle = $0 }
                    .padding(.top, Space.s4)

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
        let lifts = sessions.map { s in
            (date: s.start, sets: s.workSets.filter { $0.exerciseName == exercise.name }.map { (weight: $0.weight, reps: $0.reps) })
        }
        ExerciseProgressSection(series: ExerciseProgressPoint.series(lifts), records: ExerciseRecords.from(lifts), unit: app.weightUnit)

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

/// Fortschritt einer Übung: eine große Zahl, ein ruhiges Diagramm (geschätztes Maximum oder Volumen), Bestwerte.
private struct ExerciseProgressSection: View {
    enum Metric: Hashable { case oneRepMax, volume }
    let series: [ExerciseProgressPoint]
    let records: ExerciseRecords?
    let unit: WeightUnit
    @State private var metric = Metric.oneRepMax

    private var factor: Double { unit == .kg ? 1 : 2.20462 }
    private func kg(_ p: ExerciseProgressPoint) -> Double { metric == .oneRepMax ? p.oneRepMax : p.volume }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero.padding(.top, Space.s5)
            if series.count >= 2 {
                chart.padding(.top, Space.s4)
                QuietSegments(options: [(Metric.oneRepMax, "Maximum"), (Metric.volume, "Volumen")], selection: $metric)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Nach zwei Trainings mit dieser Übung siehst du hier deinen Verlauf.")
                    .font(.formaBody).foregroundStyle(Theme.textSecondary).padding(.top, Space.s4)
            }
            if let records { recordList(records) }
        }
    }

    private var hero: some View {
        let value = metric == .oneRepMax ? records?.bestOneRepMax : series.last?.volume
        let first = series.first.map(kg), last = series.last.map(kg)
        let delta = (first != nil && last != nil && series.count >= 2) ? last! - first! : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { Format.weight($0, unit: unit) } ?? "–")
                    .font(.formaDisplay)
                    .contentTransition(.numericText())
                Text(unit.rawValue).font(.formaBody).foregroundStyle(Theme.textSecondary)
            }
            Text(metric == .oneRepMax ? "Geschätztes Maximum, bester Wert" : "Volumen im letzten Training")
                .font(.formaCaption).foregroundStyle(Theme.textSecondary)
            if let delta, let start = series.first?.date, abs(delta) >= 0.05 {
                Text("\(delta > 0 ? "+" : "−")\(Format.weight(abs(delta), unit: unit)) \(unit.rawValue) seit \(start.formatted(Date.FormatStyle(locale: .german).day().month(.abbreviated)))")
                    .font(.formaCaptionStrong).foregroundStyle(Theme.textTertiary)
            }
        }
        .animation(.smooth, value: metric)
    }

    private var chart: some View {
        Chart(series) { p in
            AreaMark(x: .value("Datum", p.date), y: .value("Wert", kg(p) * factor))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [Theme.textPrimary.opacity(0.14), Theme.textPrimary.opacity(0)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Datum", p.date), y: .value("Wert", kg(p) * factor))
                .interpolationMethod(.monotone)
                .foregroundStyle(Theme.textPrimary)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            if p.id == series.last?.id {
                PointMark(x: .value("Datum", p.date), y: .value("Wert", kg(p) * factor))
                    .foregroundStyle(Theme.textPrimary)
                    .symbolSize(40)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel().foregroundStyle(Theme.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: 180)
        .animation(.smooth, value: metric)
        .accessibilityLabel(metric == .oneRepMax ? "Verlauf des geschätzten Maximums" : "Verlauf des Volumens")
    }

    private func recordList(_ r: ExerciseRecords) -> some View {
        FormaSection(title: "Bestwerte") {
            Plate {
                MetricRow(title: "Geschätztes Maximum",
                          subtitle: r.bestOneRepMaxDate?.formatted(Date.FormatStyle(locale: .german).day().month(.wide).year()),
                          value: Format.weight(r.bestOneRepMax, unit: unit), unit: unit.rawValue)
                RowDivider()
                MetricRow(title: "Schwerstes Gewicht", subtitle: "× \(r.heaviestReps) Wdh.",
                          value: Format.weight(r.heaviest, unit: unit), unit: unit.rawValue)
                RowDivider()
                MetricRow(title: "Meiste Wiederholungen", value: "\(r.mostReps)", unit: "Wdh.")
                RowDivider()
                MetricRow(title: "Volumen in einem Training", value: Format.weight(r.bestSessionVolume, unit: unit), unit: unit.rawValue)
            }
        }
    }
}

/// Muskelkarte einer Übung, frei auf dem Hintergrund. Darunter nur Typografie:
/// Hauptmuskeln hell, Gerät und mithelfende Muskeln leise.
struct ExerciseMuscleCard: View {
    let name: String
    let group: String
    var equipment: String? = nil
    var onSelect: ((Muscle) -> Void)? = nil

    var body: some View {
        let muscles = ExerciseCatalog.muscles(for: name, group: group)
        let detail = ([equipment].compactMap { $0 } + (muscles.secondary.isEmpty ? [] : ["mit " + muscles.secondary.map(\.name).joined(separator: ", ")]))
            .joined(separator: " · ")
        VStack(spacing: Space.s2) {
            MuscleMapView(intensity: ExerciseCatalog.intensity(primary: muscles.primary, secondary: muscles.secondary), onSelect: onSelect)
                .frame(height: 380)
            Text(muscles.primary.map(\.name).joined(separator: " · "))
                .font(.formaRowTitle)
            if !detail.isEmpty {
                Text(detail)
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Richtige Ausführung: Bewegung, Schritte, häufige Fehler, Atmung und Tempo.
struct ExerciseGuideSections: View {
    let info: ExerciseInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Die Bewegung steht frei, ohne Karte und ohne Überschrift – sie erklärt sich selbst.
            if let motion = info.motion {
                ExerciseMotionView(motion: motion)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.s5)
            }
            FormaSection(title: "Schritte") {
                Plate {
                    ForEach(Array(info.steps.enumerated()), id: \.offset) { i, step in
                        if i > 0 { RowDivider(inset: 48) }
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Text("\(i + 1)")
                                .font(.formaValue)
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 20, alignment: .leading)
                                .accessibilityLabel("Schritt \(i + 1)")
                            Text(step).font(.formaBody).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            FormaSection(title: "Typische Fehler") {
                Plate {
                    ForEach(Array(info.mistakes.enumerated()), id: \.offset) { i, mistake in
                        if i > 0 { RowDivider() }
                        Text(mistake)
                            .font(.formaBody)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, 14)
                    }
                }
            }
            FormaSection(title: "Atmung und Tempo") {
                Plate {
                    labeledRow("Atmung", info.breathing)
                    RowDivider()
                    labeledRow("Tempo", info.tempo)
                }
            }
        }
    }

    private func labeledRow(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.formaCaptionStrong).foregroundStyle(Theme.textTertiary)
            Text(text).font(.formaBody).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
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
                    ExerciseMuscleCard(name: name, group: group, equipment: ExerciseCatalog.info(for: name)?.equipment) { tappedMuscle = $0 }
                        .padding(.top, Space.s4)
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
    var recovery: RecoveryState? = nil
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
                    if let recovery {
                        LabeledContent("Zustand (geschätzt)", value: recovery.title)
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
