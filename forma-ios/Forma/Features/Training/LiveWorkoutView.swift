import SwiftUI
import SwiftData

struct LiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Bindable var workout: LiveWorkout
    @State private var showPicker = false
    @State private var confirmEnd = false
    @State private var completedCount = 0

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
                        Color.clear.frame(height: 300)
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
        let number = set.isWarmup ? "A" : "\(workout.workSetNumber(exercise: exIndex, set: setIndex))"
        return Button { if !set.done { workout.select(exercise: exIndex, set: setIndex) } } label: {
            HStack {
                Text(number).font(.formaValue).foregroundStyle(set.isWarmup ? Theme.textTertiary : Theme.textSecondary).frame(width: 40, alignment: .leading)
                Text(Format.weight(set.weight, unit: app.weightUnit)).font(.system(size: 17, weight: .semibold)).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                Text("\(set.reps)").font(.system(size: 17, weight: .semibold)).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                Text(set.rir.map { $0 >= 4 ? "4+" : "\($0)" } ?? "–").font(.formaCaption).foregroundStyle(Theme.textSecondary).frame(width: 36, alignment: .leading)
                ZStack {
                    Circle().strokeBorder(Theme.textQuaternary, lineWidth: 1.5).opacity(set.done ? 0 : 1)
                    if set.done {
                        Circle().fill(Theme.selection)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.onSelection)
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
        .accessibilityLabel("Satz \(number), \(Format.weight(set.weight, unit: app.weightUnit)) \(app.weightUnit.rawValue), \(set.reps) Wiederholungen\(set.done ? ", erledigt" : "")")
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
                    Text(Format.timer(remaining)).font(.system(size: 34, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
                Spacer()
            }
            GlassEffectContainer(spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Button { workout.extendRest(by: 15) } label: { Text("+15 s").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                    Button { workout.skipRest() } label: { Text("Weiter").fontWeight(.semibold).foregroundStyle(Theme.onSelection).frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent)
                }
                .controlSize(.large)
            }
        }
    }

    private var setControls: some View {
        let set = workout.currentSet
        let step = app.weightUnit == .kg ? 2.5 : 2.5 / 2.20462 * 2
        return VStack(spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                stepper(value: Format.weight(set?.weight ?? 0, unit: app.weightUnit), unit: app.weightUnit.rawValue,
                        minus: { workout.changeWeight(by: -step) }, plus: { workout.changeWeight(by: step) })
                stepper(value: "\(set?.reps ?? 0)", unit: "Wdh",
                        minus: { workout.changeReps(by: -1) }, plus: { workout.changeReps(by: 1) })
            }
            if set?.isWarmup == false {
                HStack(spacing: 6) {
                    Text("Reserve").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    ForEach(0..<5, id: \.self) { i in
                        Button { workout.currentRIR = i } label: {
                            Text(i == 4 ? "4+" : "\(i)")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 40, height: 36)
                                .foregroundStyle(workout.currentRIR == i ? Theme.onSelection : Theme.textSecondary)
                                .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                    .fill(workout.currentRIR == i ? Theme.selection : Color.white.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(i) Wiederholungen in Reserve")
                        .accessibilityAddTraits(workout.currentRIR == i ? .isSelected : [])
                    }
                }
            }
            Button(set?.isWarmup == true ? "Aufwärmsatz abschließen" : "Satz \(workout.workSetNumber(exercise: workout.exerciseIndex, set: workout.setIndex)) abschließen") {
                withAnimation(.snappy) { workout.completeCurrentSet() }
                completedCount += 1
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
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
        .buttonRepeatBehavior(.enabled)
    }

    private func finish() {
        let session = workout.save(into: context)
        app.liveWorkout = nil
        if let session {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                app.finishedSession = session
            }
        }
    }
}
