import SwiftUI
import SwiftData

struct LiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query private var library: [Exercise]
    @Bindable var workout: LiveWorkout
    @State private var showPicker = false
    @State private var confirmEnd = false
    @State private var completedCount = 0
    @State private var saveError: String?

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
            .sensoryFeedback(.success, trigger: completedCount)
        }
    }

    // MARK: Übungen

    private func exerciseBlock(_ exIndex: Int, _ exercise: LiveExercise) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(exercise.name).font(.formaTitle).padding(.top, Space.s6)
            Text(exercise.lastTime ?? exercise.muscle).font(.formaBody).foregroundStyle(Theme.textSecondary).padding(.top, 4)
            if let progression = exercise.progression {
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
    }

    private func setRow(_ exIndex: Int, _ setIndex: Int, _ set: LiveSet) -> some View {
        let active = exIndex == workout.exerciseIndex && setIndex == workout.setIndex && !set.done
        let number = set.isWarmup ? "Auf" : "\(workout.workSetNumber(exercise: exIndex, set: setIndex))"
        return Button { workout.select(exercise: exIndex, set: setIndex) } label: {
            HStack {
                Text(number).font(.formaValue).foregroundStyle(set.isWarmup ? Theme.textTertiary : Theme.textSecondary).frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.weight(set.weight, unit: app.weightUnit)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText(value: set.weight))
                    if let previous = set.previous, !set.done {
                        Text("vorher \(previous) \(app.weightUnit == .kg ? "kg" : "")").font(.formaMicro).foregroundStyle(Theme.textTertiary)
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
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer()
            }
            // Eine Glasebene (der Dock), darin matte Knöpfe – kein Glas auf Glas (Codex R-01-27).
            HStack(spacing: Space.s2) {
                Button { workout.extendRest(by: 15) } label: {
                    Text("+15 s").font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("15 Sekunden mehr Pause")
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
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: Space.s3) {
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
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Reserve").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                        Text("Wdh. übrig").font(.formaMicro).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 4)
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
            Button(set?.isWarmup == true ? "Aufwärmsatz abschließen" : "Satz \(workout.workSetNumber(exercise: workout.exerciseIndex, set: workout.setIndex)) abschließen") {
                // An die angezeigte Satz-ID gebunden: Doppeltipp schließt nicht zwei Sätze ab (Codex A-06).
                guard let id = set?.id else { return }
                var accepted = false
                withAnimation(.snappy) { accepted = workout.completeCurrentSet(id: id) }
                if accepted { completedCount += 1 }
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
        app.liveWorkout = nil
        if let session {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                app.finishedSession = session
            }
        }
    }
}
