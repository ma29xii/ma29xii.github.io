import SwiftUI
import SwiftData

struct RoutineEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var allRoutines: [Routine]
    @Environment(\.dismiss) private var dismiss
    @Bindable var routine: Routine
    @State private var showPicker = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                TextField("Name", text: $routine.name)
                    .font(.formaHeadline)
            }
            Section {
                ForEach(routine.sortedItems) { item in
                    RoutineItemRow(item: item, unit: app.weightUnit)
                }
                .onDelete { offsets in
                    let items = routine.sortedItems
                    for i in offsets { context.delete(items[i]) }
                    renumber()
                }
                .onMove { from, to in
                    var items = routine.sortedItems
                    items.move(fromOffsets: from, toOffset: to)
                    for (i, item) in items.enumerated() { item.order = i }
                    try? context.save()
                }
                Button { showPicker = true } label: { Label("Übung hinzufügen", systemImage: "plus") }
            } header: {
                Text("Übungen")
            } footer: {
                Text("Wischen zum Löschen, gedrückt halten zum Verschieben.")
            }
            Section {
                Button("Training starten") {
                    routine.lastUsed = .now
                    try? context.save()
                    app.liveWorkout = LiveWorkout.from(routine, history: sessions, adjustment: app.workoutAdjustment)
                }
                .disabled(routine.items.isEmpty)
            }
            Section {
                TextField("Ohne Ordner", text: Binding(get: { routine.folder ?? "" },
                                                      set: { routine.folder = $0.isEmpty ? nil : String($0.prefix(40)) }))
                let others = Set(allRoutines.compactMap(\.folder)).subtracting([routine.folder ?? ""]).sorted()
                if !others.isEmpty {
                    Menu("Vorhandenen Ordner wählen") {
                        ForEach(others, id: \.self) { folder in Button(folder) { routine.folder = folder } }
                        if routine.folder != nil { Button("Ohne Ordner") { routine.folder = nil } }
                    }
                }
            } header: {
                Text("Ordner")
            }
            Section {
                Button("Routine duplizieren") {
                    routine.duplicate(in: context, existingNames: allRoutines.map(\.name))
                    try? context.save()
                    dismiss()
                }
                Button("Routine löschen", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("„\(routine.name)“ löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                // Erst zurück, dann löschen: sonst greift die Ansicht noch auf die gelöschte Routine zu.
                let target = routine
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    context.delete(target)
                    try? context.save()
                }
            }
        } message: {
            Text("Bisherige Trainings bleiben im Verlauf.")
        }
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView { exercise in
                let item = RoutineItem(order: routine.items.count, exerciseName: exercise.name, muscle: exercise.muscle)
                context.insert(item)
                item.routine = routine
                try? context.save()
            }
        }
        .onDisappear {
            routine.folder = routine.folder.flatMap(Routine.cleanFolder)
            try? context.save()
        }
    }

    private func renumber() {
        for (i, item) in routine.sortedItems.enumerated() { item.order = i }
        try? context.save()
    }
}

private struct RoutineItemRow: View {
    @Bindable var item: RoutineItem
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(item.exerciseName).font(.formaRowTitle)
            HStack(spacing: Space.s4) {
                Stepper("\(item.sets) Sätze", value: $item.sets, in: 1...10).font(.formaCaption)
            }
            HStack(spacing: Space.s4) {
                Stepper("\(item.reps) Wdh", value: $item.reps, in: 1...50).font(.formaCaption)
            }
            Stepper("\(Format.weight(item.weight, unit: unit)) \(unit.rawValue)", value: $item.weight, in: 0...400, step: 2.5).font(.formaCaption)
            Stepper("Pause \(Format.timer(item.restSeconds))", value: $item.restSeconds, in: 30...300, step: 15).font(.formaCaption)
        }
        .padding(.vertical, 4)
    }
}

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    let onPick: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { ex in
                            Button {
                                onPick(ex)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.name).font(.formaRowTitle).foregroundStyle(Theme.textPrimary)
                                    Text(ex.equipment).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Übung suchen")
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle("Übung wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }

    private var groups: [(String, [Exercise])] {
        let filtered = search.isEmpty ? exercises : exercises.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.muscle.localizedCaseInsensitiveContains(search) }
        let order = ["Brust", "Rücken", "Schultern", "Beine", "Arme", "Rumpf"]
        let muscles = Array(Set(filtered.map(\.muscle))).sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
        return muscles.map { m in (m, filtered.filter { $0.muscle == m }) }
    }
}

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var showNew = false
    @State private var newName = ""
    @State private var newMuscle = "Brust"
    @State private var newEquipment = "Kurzhantel"
    @State private var muscleFilter: Muscle?

    var body: some View {
        List {
            Section {
                MuscleMapView(intensity: muscleFilter.map { [$0: 1.0] } ?? [:], selected: muscleFilter, showsBoth: true) { m in
                    withAnimation(.snappy) { muscleFilter = muscleFilter == m ? nil : m }
                }
                .frame(height: 230)
                .padding(.vertical, Space.s2)
                .listRowBackground(Color.clear)
                // Vollständige Auswahl mit 44-pt-Zeilen, auch für VoiceOver und kleine Muskeln.
                Menu {
                    ForEach(Muscle.allCases) { m in
                        Button(m.name) { withAnimation(.snappy) { muscleFilter = m } }
                    }
                } label: {
                    Text(muscleFilter?.name ?? "Muskel wählen")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                if muscleFilter != nil {
                    Button("Filter aufheben") { withAnimation(.snappy) { muscleFilter = nil } }
                        .frame(minHeight: 44)
                }
            } footer: {
                if muscleFilter == nil { Text("Tipp auf einen Muskel, um die Übungen zu filtern.") }
            }
            if let muscle = muscleFilter {
                let matching = exercises.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                let direct = matching.filter { ExerciseCatalog.muscles(for: $0.name, group: $0.muscle).primary.contains(muscle) }
                let assist = matching.filter {
                    let m = ExerciseCatalog.muscles(for: $0.name, group: $0.muscle)
                    return m.secondary.contains(muscle) && !m.primary.contains(muscle)
                }
                if !direct.isEmpty { Section("Trainiert \(muscle.name) direkt") { ForEach(direct) { row($0) } } }
                if !assist.isEmpty { Section("Hilft mit") { ForEach(assist) { row($0) } } }
            } else {
                ForEach(["Brust", "Rücken", "Schultern", "Beine", "Arme", "Rumpf"], id: \.self) { muscle in
                    let items = exercises.filter { $0.muscle == muscle && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
                    if !items.isEmpty {
                        Section(muscle) {
                            ForEach(items) { row($0) }
                                .onDelete { offsets in
                                    for i in offsets where items[i].isCustom { context.delete(items[i]) }
                                    try? context.save()
                                }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Übung suchen")
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .navigationTitle("Übungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Eigene Übung")
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                Form {
                    TextField("Name", text: $newName)
                    Picker("Muskelgruppe", selection: $newMuscle) {
                        ForEach(["Brust", "Rücken", "Schultern", "Beine", "Arme", "Rumpf"], id: \.self) { Text($0) }
                    }
                    Picker("Gerät", selection: $newEquipment) {
                        ForEach(["Langhantel", "Kurzhantel", "Kabel", "Maschine", "Körpergewicht", "SZ-Stange", "Gerät"], id: \.self) { Text($0) }
                    }
                }
                .navigationTitle("Eigene Übung")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showNew = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") {
                            context.insert(Exercise(name: newName.trimmingCharacters(in: .whitespaces), muscle: newMuscle, equipment: newEquipment, isCustom: true))
                            try? context.save()
                            newName = ""
                            showNew = false
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func row(_ ex: Exercise) -> some View {
        NavigationLink { ExerciseDetailView(exercise: ex) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name).font(.formaRowTitle)
                    Text(([ex.equipment] + ExerciseCatalog.muscles(for: ex.name, group: ex.muscle).primary.map(\.name)).joined(separator: " · "))
                        .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if ex.isCustom { Text("eigene").font(.formaMicro).foregroundStyle(Theme.textTertiary) }
            }
        }
    }
}
