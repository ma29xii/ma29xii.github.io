import SwiftUI
import SwiftData
import UserNotifications

struct LiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query private var library: [Exercise]
    /// Verlauf für „Letztes Mal“ und Vorwerte: numerisch in kg, Anzeige in der gewählten Einheit (Gegenprüfung 02 #13).
    @Query(sort: \WorkoutSession.start, order: .reverse) private var history: [WorkoutSession]
    @Bindable var workout: LiveWorkout
    @State private var showPicker = false
    @State private var confirmEnd = false
    @State private var completedCount = 0
    @State private var saveError: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var notificationStatus: UNAuthorizationStatus = .authorized
    @State private var guide: LiveExercise?
    @State private var record: RecordMoment?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let adjustment = workout.adjustment {
                            Label("Heute angepasst: \(adjustment.title). Deine Routine bleibt gespeichert wie sie ist.", systemImage: "sparkles")
                                .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                                .padding(.top, Space.s3)
                        }
                        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { exIndex, exercise in
                            exerciseBlock(exIndex, exercise).id(exercise.id)
                        }
                        Button { showPicker = true } label: { Label("Übung hinzufügen", systemImage: "plus") }
                            .buttonStyle(.glass)
                            .padding(.top, Space.s5)
                        Color.clear.frame(height: Space.s5)
                    }
                    .padding(.horizontal, Space.page)
                }
                .onChange(of: workout.exerciseIndex) { _, new in
                    guard workout.exercises.indices.contains(new) else { return }
                    withAnimation { proxy.scrollTo(workout.exercises[new].id, anchor: .top) }
                }
            }
            .safeAreaInset(edge: .bottom) { dock }
            .overlay(alignment: .top) {
                if let record {
                    RecordToast(moment: record, unit: app.weightUnit)
                        .id(record.id)
                        .padding(.horizontal, Space.page)
                        .padding(.top, Space.s2)
                        .transition(.opacity)
                        .onTapGesture { withAnimation { self.record = nil } }
                }
            }
            .task(id: record?.id) {
                guard let id = record?.id else { return }
                // Abbruch heißt: ein neuer Hinweis ist da. Dann nichts ausblenden.
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                if record?.id == id { withAnimation(.smooth) { record = nil } }
            }
            .sensoryFeedback(.levelChange, trigger: record?.id) { _, new in new != nil }
            .formaScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TimelineView(.periodic(from: workout.start, by: 1)) { ctx in
                        VStack(spacing: 0) {
                            Text(workout.title).font(.system(size: 15, weight: .semibold))
                            Text(Format.timer(Int(ctx.date.timeIntervalSince(workout.start)))).font(.formaCaption).monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Beenden") { confirmEnd = true }
                }
            }
            .confirmationDialog("Training beenden?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("Speichern und beenden") { finish() }
                Button("Verwerfen", role: .destructive) { app.liveWorkout = nil }
                Button("Weiter trainieren", role: .cancel) {}
            }
            .alert("Training konnte nicht gespeichert werden", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("Erneut versuchen") { finish() }
                Button("Weiter trainieren", role: .cancel) {}
            } message: {
                Text("Dein Training ist nicht verloren, es bleibt hier offen. \(saveError ?? "")")
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { ex in workout.addExercise(name: ex.name, muscle: ex.muscle) }
            }
            .sheet(item: $guide) { ex in ExerciseGuideSheet(name: ex.name, group: ex.muscle) }
            .sensoryFeedback(.success, trigger: completedCount)
            .task { notificationStatus = await CoachNotifier.authorizationStatus() }
        }
    }

    // MARK: Übungen

    private func exerciseBlock(_ exIndex: Int, _ exercise: LiveExercise) -> some View {
        let groups = workout.exercises.map(\.superset)
        let position = Superset.position(groups, at: exIndex)
        let partners = Superset.members(groups, at: exIndex).filter { $0 != exIndex }.map { workout.exercises[$0].name }
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Space.s6)
                .supersetThread(position == .middle || position == .last)
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(exercise.name).font(.formaTitle)
                    .accessibilityLabel(position == nil ? exercise.name : "\(exercise.name), Supersatz")
                Spacer(minLength: 0)
                Button { guide = exercise } label: {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ausführung und Muskeln")
            }
            .supersetNode(position)
            VStack(alignment: .leading, spacing: 0) {
            if !partners.isEmpty {
                Text("Im Wechsel mit \(partners.joined(separator: ", "))")
                    .font(.formaCaptionStrong).foregroundStyle(SupersetStyle.tint)
            }
            Text(lastTimeText(exercise.name) ?? exercise.muscle).font(.formaBody).foregroundStyle(Theme.textSecondary).padding(.top, 4)
            if let progression = progressionText(exercise) {
                HStack(spacing: Space.s2) {
                    Label(progression, systemImage: exercise.suggestedWeight != nil ? "arrow.up.right" : "equal")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(exercise.suggestedWeight != nil ? Theme.younger : Theme.textSecondary)
                    if exercise.suggestedWeight != nil {
                        // Vorschlag wird erst mit Bestätigung wirksam (Codex R-02-12).
                        Button("Übernehmen") { withAnimation(.snappy) { workout.applyProgression(exercise: exIndex) } }
                            .buttonStyle(SmallPillButtonStyle())
                    }
                }
                .padding(.top, 6)
            }
            Plate {
                HStack {
                    Text("Satz").frame(width: 40, alignment: .leading)
                    Text(app.weightUnit.rawValue).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Wdh").frame(maxWidth: .infinity, alignment: .leading)
                    Text("RIR").frame(width: 36, alignment: .leading)
                    Spacer().frame(width: 28)
                }
                .font(.formaMicro).foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, Space.s4)
                .frame(height: 36)
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                    RowDivider()
                    setRow(exIndex, setIndex, set)
                }
                RowDivider()
                Button { workout.addSet(to: exIndex) } label: {
                    Label("Satz hinzufügen", systemImage: "plus").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Space.s4)
            }
            .supersetThread(position == .first || position == .middle)
        }
    }

    /// Steigerungshinweis mit Gewicht in der gewählten Einheit (z. B. „+5,5 lb: …“).
    private func progressionText(_ exercise: LiveExercise) -> String? {
        guard let note = exercise.progression else { return nil }
        let unit = app.weightUnit
        if let applied = exercise.appliedWeight { return "\(note): \(Format.weight(applied, unit: unit)) \(unit.rawValue)" }
        if exercise.suggestedWeight != nil { return "+\(Format.weight(Progression.step, unit: unit)) \(unit.rawValue): \(note)" }
        return note
    }

    /// Bestwert-Moment: nur wenn es die Übung schon einmal gab und der Satz alles Bisherige übertrifft,
    /// auch frühere Sätze dieses Trainings (so feiert die App jede Verbesserung genau einmal).
    private func checkRecord(name: String, weight: Double, reps: Int, setID: UUID) {
        let historyBest = history.map { $0.bestOneRepMax(for: name) }.max() ?? 0
        guard historyBest > 0 else { return }
        let earlier = workout.exercises.filter { $0.name == name }.flatMap(\.sets)
            .filter { $0.done && !$0.isWarmup && $0.id != setID }
            .map { OneRepMax.epley(weight: $0.weight, reps: $0.reps) }.max() ?? 0
        guard PersonalRecord.isNew(weight: weight, reps: reps, previousBest: max(historyBest, earlier)) else { return }
        withAnimation(.smooth) { record = RecordMoment(exercise: name, oneRepMax: OneRepMax.epley(weight: weight, reps: reps)) }
    }

    private func lastWorkSets(_ name: String) -> [SetRecord] {
        guard let session = history.first(where: { $0.sets.contains { $0.exerciseName == name } }) else { return [] }
        return session.workSets.filter { $0.exerciseName == name }.sorted { $0.order < $1.order }
    }

    private func lastTimeText(_ name: String) -> String? {
        let work = lastWorkSets(name)
        guard let top = work.max(by: { $0.weight < $1.weight }) else { return nil }
        return "Letztes Mal \(work.count) × \(top.reps) · \(Format.weight(top.weight, unit: app.weightUnit)) \(app.weightUnit.rawValue)"
    }

    /// Vorwert für den n-ten Arbeitssatz, z. B. „170,9 lb × 8“.
    private func previousText(_ exIndex: Int, _ setIndex: Int) -> String? {
        guard workout.exercises.indices.contains(exIndex) else { return nil }
        let sets = workout.exercises[exIndex].sets
        guard sets.indices.contains(setIndex), !sets[setIndex].isWarmup else { return nil }
        let workIndex = sets[..<setIndex].filter { !$0.isWarmup }.count
        let previous = lastWorkSets(workout.exercises[exIndex].name)
        guard previous.indices.contains(workIndex) else { return nil }
        let p = previous[workIndex]
        return "\(Format.weight(p.weight, unit: app.weightUnit)) \(app.weightUnit.rawValue) × \(p.reps)"
    }

    private func setRow(_ exIndex: Int, _ setIndex: Int, _ set: LiveSet) -> some View {
        setButton(exIndex, setIndex, set)
            .contextMenu {
                Button("Satz löschen", systemImage: "trash", role: .destructive) {
                    withAnimation(.snappy) { workout.removeSet(exercise: exIndex, set: setIndex) }
                }
            }
    }

    private func setButton(_ exIndex: Int, _ setIndex: Int, _ set: LiveSet) -> some View {
        let active = exIndex == workout.exerciseIndex && setIndex == workout.setIndex && !set.done
        let number = set.isWarmup ? "Auf" : "\(workout.workSetNumber(exercise: exIndex, set: setIndex))"
        return Button { workout.select(exercise: exIndex, set: setIndex) } label: {
            HStack {
                Text(number).font(.formaValue).foregroundStyle(set.isWarmup ? Theme.textTertiary : Theme.textSecondary).frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.weight(set.weight, unit: app.weightUnit)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText(value: set.weight))
                    if let previous = previousText(exIndex, setIndex), !set.done {
                        Text("vorher \(previous)").font(.formaMicro).foregroundStyle(Theme.textTertiary)
                            .accessibilityLabel("Letztes Mal \(previous)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(set.reps)").font(.system(size: 17, weight: .semibold)).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                Text(set.rir.map { $0 >= 4 ? "4+" : "\($0)" } ?? "–").font(.formaCaption).foregroundStyle(Theme.textSecondary).frame(width: 36, alignment: .leading)
                ZStack {
                    Circle().strokeBorder(Theme.textQuaternary, lineWidth: 1.5).opacity(set.done ? 0 : 1)
                    if set.done {
                        Circle().fill(Theme.selection)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.onSelection)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 28, height: 28)
            }
            .foregroundStyle(set.done ? Theme.textTertiary : Theme.textPrimary)
            .padding(.horizontal, Space.s4)
            .frame(minHeight: 52)
            .background(active ? Color.white.opacity(0.07) : Color.clear)
            .overlay(alignment: .leading) {
                if active { Capsule().fill(Theme.textPrimary).frame(width: 3).padding(.vertical, 10) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(set.done)
        .accessibilityLabel("\(set.isWarmup ? "Aufwärmsatz" : "Satz \(number)"), \(Format.weight(set.weight, unit: app.weightUnit)) \(app.weightUnit.rawValue), \(set.reps) Wiederholungen")
        .accessibilityValue(set.done ? "erledigt\(set.rir.map { ", \($0) übrig" } ?? "")" : (active ? "aktiv" : "offen"))
        .accessibilityHint(set.done ? "" : "Wählt diesen Satz aus")
    }

    // MARK: Dock (Glas, Daumenzone)

    private var dock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let remaining = Int((workout.restEndsAt ?? .distantPast).timeIntervalSince(ctx.date).rounded(.up))
            Group {
                if workout.allDone {
                    Button("Training beenden") { finish() }.buttonStyle(PrimaryButtonStyle())
                } else if remaining > 0 {
                    restView(remaining)
                } else if workout.currentSet != nil {
                    setControls
                } else {
                    Button("Übung hinzufügen") { showPicker = true }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(Space.s4)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.dock, style: .continuous))
            // Spürbares Signal, wenn die Pause abläuft (zusätzlich zur Benachrichtigung).
            .sensoryFeedback(.impact(weight: .heavy), trigger: remaining > 0) { old, new in old && !new }
            .padding(.horizontal, Space.s2)
            .padding(.bottom, Space.s1)
        }
    }

    private func restView(_ remaining: Int) -> some View {
        VStack(spacing: Space.s4) {
            HStack(spacing: Space.s4) {
                RingView(value: Double(remaining) / Double(max(1, workout.restTotal)) * 100, color: Theme.textPrimary, size: 56, lineWidth: 5, showsNumber: false)
                    .animation(.linear(duration: 1), value: remaining)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pause").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                    Text(Format.timer(remaining)).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityLabel("Noch \(remaining) Sekunden Pause")
                    if let next = workout.currentLabel {
                        Text("Als Nächstes: \(next)").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    // Freiwillig und erst hier, mit Kontext – nicht beim Trainingsstart (Codex R-02-26/A-33).
                    if !workout.isDemo && notificationStatus == .notDetermined {
                        Button("Bei Pausenende benachrichtigen") {
                            Task {
                                _ = await CoachNotifier.requestPermission()
                                notificationStatus = await CoachNotifier.authorizationStatus()
                                if let end = workout.restEndsAt { RestNotifier.schedule(at: end, next: workout.currentExercise?.name) }
                            }
                        }
                        .font(.formaCaptionStrong)
                        .padding(.top, 4)
                    }
                }
                Spacer()
            }
            // Eine Glasebene (der Dock), darin matte Knöpfe – kein Glas auf Glas (Codex R-01-27).
            HStack(spacing: Space.s2) {
                // Nur so viel anbieten, wie bis zur Obergrenze wirklich geht (Gegenprüfung 04 #7).
                let extra = LiveWorkout.possibleExtension(15, remaining: remaining)
                Button { workout.extendRest(by: extra) } label: {
                    Text(extra > 0 ? "+\(extra) s" : "Maximum").font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(extra == 0)
                .accessibilityLabel(extra > 0 ? "\(extra) Sekunden mehr Pause" : "Längste Pause erreicht")
                Button("Pause beenden") { workout.skipRest() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("rest.skip")
            }
        }
    }

    private var setControls: some View {
        let set = workout.currentSet
        let step = app.weightUnit == .kg ? 2.5 : 5 / 2.20462   // 2,5 kg bzw. 5 lb
        return VStack(spacing: Space.s3) {
            if let label = workout.currentLabel {
                Text(label)
                    .font(.system(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)   // bei großer Schrift umbrechen statt schrumpfen (Codex R-02-17)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
            }
            // Bei Bedienungshilfen-Schriftgrößen untereinander statt nebeneinander.
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Space.s2)) : AnyLayout(HStackLayout(spacing: Space.s3))) {
                stepper(value: Format.weight(set?.weight ?? 0, unit: app.weightUnit), unit: app.weightUnit.rawValue,
                        minus: { workout.changeWeight(by: -step) }, plus: { workout.changeWeight(by: step) })
                stepper(value: "\(set?.reps ?? 0)", unit: "Wdh",
                        minus: { workout.changeReps(by: -1) }, plus: { workout.changeReps(by: 1) })
            }
            if let plates = plateText(for: set?.weight ?? 0) {
                Text(plates)
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                    .accessibilityLabel("Scheiben pro Seite: \(plates)")
            }
            if set?.isWarmup == false {
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Reserve").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                        Text("Wdh. übrig, optional").font(.formaMicro).foregroundStyle(Theme.textTertiary)
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                    HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        // Antippen wählt, nochmal antippen hebt auf (Reserve ist optional, Codex A-18).
                        Button { workout.currentRIR = workout.currentRIR == i ? nil : i } label: {
                            Text(i == 4 ? "4+" : "\(i)")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(workout.currentRIR == i ? Theme.onSelection : Theme.textSecondary)
                                .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                    .fill(workout.currentRIR == i ? Theme.selection : Color.white.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(i == 4 ? "4 oder mehr Wiederholungen übrig" : "\(i) Wiederholungen übrig")
                        .accessibilityAddTraits(workout.currentRIR == i ? .isSelected : [])
                    }
                    }
                }
            }
            Button(set?.isWarmup == true ? "Aufwärmsatz abschließen" : "Satz \(workout.workSetNumber(exercise: workout.exerciseIndex, set: workout.setIndex)) abschließen") {
                // An die angezeigte Satz-ID gebunden: Doppeltipp schließt nicht zwei Sätze ab (Codex A-06).
                guard let id = set?.id, let done = set, let name = workout.currentExercise?.name else { return }
                var accepted = false
                withAnimation(.snappy) { accepted = workout.completeCurrentSet(id: id) }
                if accepted {
                    completedCount += 1
                    if !done.isWarmup { checkRecord(name: name, weight: done.weight, reps: done.reps, setID: id) }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func stepper(value: String, unit: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: minus) { Image(systemName: "minus").frame(width: 44, height: 44) }
                .accessibilityLabel("Weniger \(unit)")
            VStack(spacing: 0) {
                Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
                Text(unit).font(.formaMicro).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            Button(action: plus) { Image(systemName: "plus").frame(width: 44, height: 44) }
                .accessibilityLabel("Mehr \(unit)")
        }
        .buttonStyle(.plain)
        .font(.system(size: 18, weight: .medium))
        .frame(height: 56)
        .sensoryFeedback(.selection, trigger: value)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
        .buttonRepeatBehavior(.enabled)
    }

    /// Scheibenrechner für Langhantel-Übungen (Stange 20 kg, Scheiben 25 bis 1,25 kg).
    private func plateText(for weight: Double) -> String? {
        guard app.weightUnit == .kg, let name = workout.currentExercise?.name,
              library.first(where: { $0.name == name })?.equipment == "Langhantel" else { return nil }
        guard let plates = PlateMath.perSide(total: weight) else { return nil }
        if plates.isEmpty { return "Nur die Stange (20 kg)" }
        return "Pro Seite: " + plates.map { Format.number($0, decimals: $0.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2) + " kg" }.joined(separator: " + ") + " · 20-kg-Stange"
    }

    private func finish() {
        let session: WorkoutSession?
        do {
            session = try workout.save(into: context)
        } catch {
            saveError = error.localizedDescription
            return
        }
        // Lücke zwischen Vollbild-Ende und Zusammenfassung als belegt markieren (Gegenprüfung 04 #5).
        app.workoutSummaryIncoming = session != nil
        app.liveWorkout = nil
        if let session {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                app.finishedSession = session
                app.workoutSummaryIncoming = false
            }
        }
    }
}
