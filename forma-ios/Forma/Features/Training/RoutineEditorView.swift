import SwiftUI
import SwiftData

struct RoutineEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @Bindable var routine: Routine
    @State private var showPicker = false

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
                    app.liveWorkout = LiveWorkout.from(routine, history: sessions, adjustment: TrainingAdjustment.today)
                }
                .disabled(routine.items.isEmpty)
            }
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
        .onDisappear { try? context.save() }
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

    var body: some View {
        List {
            ForEach(["Brust", "Rücken", "Schultern", "Beine", "Arme", "Rumpf"], id: \.self) { muscle in
                let items = exercises.filter { $0.muscle == muscle && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
                if !items.isEmpty {
                    Section(muscle) {
                        ForEach(items) { ex in
                            NavigationLink { ExerciseDetailView(exercise: ex) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name).font(.formaRowTitle)
                                        Text(ex.equipment).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    if ex.isCustom { Text("eigene").font(.formaMicro).foregroundStyle(Theme.textTertiary) }
                                }
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets where items[i].isCustom { context.delete(items[i]) }
                            try? context.save()
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
}
