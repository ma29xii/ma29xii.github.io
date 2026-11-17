import SwiftData
import SwiftUI

/// Bearbeitbare Kopie einer Gewohnheit. Erst „Sichern“ schreibt in die Datenbank.
struct HabitDraft: Equatable {
    var name = ""
    var details = ""
    var symbol = "checkmark"
    var colorID = Palette.defaultID
    var kind: HabitKind = .build
    var frequency: HabitFrequency = .daily
    var weekdayMask = 0b111_1111
    var timesPerPeriod = 3
    var dailyTarget: Double = 1
    var unit = ""
    var step: Double = 1
    var reminderEnabled = false
    var reminderMinutes = 20 * 60
    var hasStart = false
    var start = Date()
    var hasEnd = false
    var end = Date().addingTimeInterval(30 * 86_400)
    var categoryID: UUID?

    init() {}

    init(habit: Habit) {
        name = habit.name
        details = habit.details
        symbol = habit.symbol
        colorID = habit.colorID
        kind = habit.kind
        frequency = habit.frequency
        weekdayMask = habit.weekdayMask
        timesPerPeriod = habit.timesPerPeriod
        dailyTarget = habit.dailyTarget
        unit = habit.unit
        step = habit.step
        reminderEnabled = habit.reminderEnabled
        reminderMinutes = habit.reminderMinutes
        hasStart = habit.startDay > 0
        if hasStart { start = Day(key: habit.startDay).date() }
        hasEnd = habit.endDay > 0
        if hasEnd { end = Day(key: habit.endDay).date() }
        categoryID = habit.category?.uuid
    }

    var isValid: Bool {
        guard !name.trimmed.isEmpty else { return false }
        if kind == .build, frequency == .weekdays, weekdayMask & 0b111_1111 == 0 { return false }
        if hasStart, hasEnd, Day(date: end) < Day(date: start) { return false }
        return true
    }

    func apply(to habit: Habit, categories: [HabitCategory]) {
        habit.name = name.trimmed
        habit.details = details.trimmed
        habit.symbol = symbol
        habit.colorID = colorID
        habit.kind = kind
        habit.frequency = kind == .quit ? .daily : frequency
        habit.weekdayMask = weekdayMask
        habit.timesPerPeriod = max(1, timesPerPeriod)
        habit.dailyTarget = kind == .quit ? max(0, dailyTarget) : max(1, dailyTarget)
        habit.unit = unit.trimmed
        habit.step = max(0.1, step)
        habit.reminderEnabled = reminderEnabled
        habit.reminderMinutes = reminderMinutes
        habit.startDay = hasStart ? Day(date: start).key : 0
        habit.endDay = hasEnd ? Day(date: end).key : 0
        habit.category = categories.first { $0.uuid == categoryID }
    }
}

struct HabitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \HabitCategory.sortOrder) private var categories: [HabitCategory]

    private let habit: Habit?
    @State private var draft: HabitDraft
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    init(habit: Habit? = nil, template: HabitDraft? = nil) {
        self.habit = habit
        _draft = State(initialValue: habit.map { HabitDraft(habit: $0) } ?? template ?? HabitDraft())
    }

    private var tint: HabitColor { Palette.entry(draft.colorID) }
    private var color: Color { tint.color }

    var body: some View {
        NavigationStack {
            Form {
                if habit == nil {
                    Section {
                        NavigationLink {
                            TemplatesView { template in
                                draft = template
                            }
                        } label: {
                            Label("Aus Vorlage wählen", systemImage: "wand.and.stars")
                        }
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        HabitIcon(symbol: draft.symbol, tint: tint, size: 44)
                        TextField("Name", text: $draft.name)
                            .font(.headline)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .accessibilityIdentifier("habit-name")
                    }
                    TextField("Beschreibung (optional)", text: $draft.details)
                }

                Section("Farbe") {
                    ColorGrid(selection: $draft.colorID)
                }

                Section {
                    NavigationLink {
                        SymbolPickerView(selection: $draft.symbol, tint: tint)
                    } label: {
                        LabeledContent("Symbol") {
                            HabitGlyph(symbol: draft.symbol)
                                .foregroundStyle(tint.gradient)
                        }
                    }
                }

                Section {
                    Picker("Art", selection: $draft.kind) {
                        ForEach(HabitKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(draft.kind == .build
                        ? "Etwas, das du regelmäßig tun möchtest."
                        : "Etwas, das du lassen möchtest. Jeder Tag ohne Rückfall zählt automatisch.")
                }

                if draft.kind == .build {
                    buildGoalSection
                } else {
                    quitGoalSection
                }

                if !categories.isEmpty {
                    Section {
                        Picker("Kategorie", selection: $draft.categoryID) {
                            Text("Keine").tag(UUID?.none)
                            ForEach(categories) { category in
                                Text(category.name).tag(UUID?.some(category.uuid))
                            }
                        }
                    }
                }

                Section {
                    Toggle("Erinnerung", isOn: $draft.reminderEnabled.animation())
                    if draft.reminderEnabled {
                        DatePicker("Uhrzeit", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    if draft.reminderEnabled, draft.kind == .build, draft.frequency == .weekdays {
                        Text("Erinnert nur an den gewählten Wochentagen.")
                    }
                }

                Section {
                    Toggle(draft.kind == .quit ? "Startdatum (seit wann?)" : "Startdatum", isOn: $draft.hasStart.animation())
                    if draft.hasStart {
                        DatePicker("Beginn", selection: $draft.start, displayedComponents: .date)
                    }
                    Toggle("Enddatum", isOn: $draft.hasEnd.animation())
                    if draft.hasEnd {
                        DatePicker("Ende", selection: $draft.end, displayedComponents: .date)
                    }
                } header: {
                    Text("Zeitraum")
                } footer: {
                    Text("Ideal für Challenges, z. B. 30 Tage. Ohne Angabe läuft die Gewohnheit unbegrenzt.")
                }

                if habit != nil {
                    Section {
                        Button("Gewohnheit löschen", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(habit == nil ? "Neue Gewohnheit" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("save-habit")
                }
            }
            .confirmationDialog("Gewohnheit wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let habit {
                        HabitAdmin.delete(habit, in: context)
                    }
                    dismiss()
                }
            } message: {
                Text("Alle Einträge gehen verloren.")
            }
            .onAppear {
                if habit == nil, draft.name.isEmpty {
                    nameFocused = true
                }
            }
        }
    }

    // MARK: Abschnitte

    private var buildGoalSection: some View {
        Section {
            Picker("Rhythmus", selection: $draft.frequency.animation()) {
                ForEach(HabitFrequency.allCases) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }
            switch draft.frequency {
            case .daily:
                EmptyView()
            case .weekdays:
                WeekdayPicker(mask: $draft.weekdayMask, tint: tint)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            case .perWeek:
                Stepper("\(draft.timesPerPeriod)× pro Woche", value: $draft.timesPerPeriod, in: 1...7)
            case .perMonth:
                Stepper("\(draft.timesPerPeriod)× pro Monat", value: $draft.timesPerPeriod, in: 1...31)
            }
            LabeledContent("Tagesziel") {
                HStack(spacing: 8) {
                    TextField("1", value: $draft.dailyTarget, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 50)
                    Stepper("Tagesziel", value: $draft.dailyTarget, in: 1...100_000, step: max(1, draft.step))
                        .labelsHidden()
                }
            }
            LabeledContent("Einheit") {
                TextField("z. B. Gläser, min, km", text: $draft.unit)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
            }
            if draft.dailyTarget > 1 {
                LabeledContent("Schritt pro Tipp") {
                    TextField("1", value: $draft.step, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("Ziel")
        } footer: {
            Text(draft.dailyTarget > 1
                ? "Der Tag zählt, sobald \(Format.amount(draft.dailyTarget, unit: draft.unit.trimmed)) erreicht sind. Teilmengen färben die Kachel heller."
                : "Ein Tipp hakt den Tag ab. Erhöhe das Tagesziel, um Mengen zu zählen.")
        }
    }

    private var quitGoalSection: some View {
        Section {
            Stepper(value: $draft.dailyTarget, in: 0...100, step: 1) {
                Text(draft.dailyTarget <= 0 ? "Tageslimit: gar nicht" : "Tageslimit: \(Format.number(draft.dailyTarget))")
            }
            if draft.dailyTarget > 0 {
                LabeledContent("Einheit") {
                    TextField("z. B. Tassen", text: $draft.unit)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                }
            }
        } header: {
            Text("Ziel")
        } footer: {
            Text(draft.dailyTarget <= 0
                ? "Tippe auf den Haken, wenn es einen Rückfall gab – die Serie beginnt dann neu."
                : "Bis zum Limit bleibt der Tag gültig. Jeder Tipp zählt eins hoch.")
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: draft.reminderMinutes / 60,
                minute: draft.reminderMinutes % 60,
                second: 0,
                of: Date()
            ) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            draft.reminderMinutes = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
        }
    }

    // MARK: Sichern

    private func save() {
        let target: Habit
        if let habit {
            target = habit
        } else {
            target = Habit(name: draft.name.trimmed)
            target.sortOrder = HabitAdmin.nextSortOrder(in: context)
            context.insert(target)
        }
        draft.apply(to: target, categories: categories)
        Store.commit(context)

        if target.reminderEnabled {
            Task {
                await Reminders.requestAuthorization()
                Reminders.reschedule(target)
            }
        } else {
            Reminders.reschedule(target)
        }
        dismiss()
    }
}

// MARK: - Symbole

struct SymbolPickerView: View {
    @Binding var selection: String
    let tint: HabitColor

    @Environment(\.dismiss) private var dismiss
    @State private var emoji = ""

    static let groups: [(title: String, symbols: [String])] = [
        ("Allgemein", ["checkmark", "star.fill", "heart.fill", "flame.fill", "bolt.fill", "sparkles", "flag.fill", "target", "trophy.fill", "leaf.fill", "sun.max.fill", "moon.fill"]),
        ("Gesundheit", ["drop.fill", "pills.fill", "cross.case.fill", "bed.double.fill", "lungs.fill", "brain.head.profile", "eye.fill", "hand.raised.fill", "face.smiling", "stethoscope", "bandage.fill", "waterbottle.fill"]),
        ("Bewegung", ["figure.walk", "figure.run", "figure.yoga", "figure.strengthtraining.traditional", "figure.pool.swim", "figure.outdoor.cycle", "dumbbell.fill", "bicycle", "sportscourt.fill", "soccerball", "tennis.racket", "figure.hiking"]),
        ("Essen & Trinken", ["fork.knife", "cup.and.saucer.fill", "carrot.fill", "mug.fill", "wineglass.fill", "birthday.cake.fill", "takeoutbag.and.cup.and.straw.fill", "fish.fill"]),
        ("Geist & Lernen", ["book.fill", "books.vertical.fill", "graduationcap.fill", "pencil", "text.book.closed.fill", "headphones", "music.note", "guitars.fill", "paintbrush.fill", "camera.fill", "globe", "character.bubble.fill", "figure.mind.and.body"]),
        ("Produktivität", ["laptopcomputer", "desktopcomputer", "keyboard", "envelope.fill", "phone.fill", "calendar", "clock.fill", "timer", "alarm.fill", "list.bullet", "tray.full.fill", "briefcase.fill", "chart.line.uptrend.xyaxis", "lightbulb.fill"]),
        ("Zuhause & Alltag", ["house.fill", "cart.fill", "washer.fill", "trash.fill", "shower.fill", "bathtub.fill", "pawprint.fill", "tree.fill", "creditcard.fill", "banknote.fill", "car.fill", "airplane"]),
        ("Abgewöhnen", ["nosign", "smoke.fill", "iphone.slash", "play.slash.fill", "gamecontroller.fill", "bag.fill", "xmark.circle.fill", "hourglass"]),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Eigenes Emoji")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("z. B. 🎯", text: $emoji)
                            .onChange(of: emoji) { _, value in
                                guard let last = value.last else { return }
                                let single = String(last)
                                if emoji != single { emoji = single }
                                if HabitGlyph.isEmoji(single) {
                                    selection = single
                                }
                            }
                        if HabitGlyph.isEmoji(selection) {
                            Text(selection).font(.title2)
                        }
                    }
                    .card(padding: 14)
                }

                ForEach(Self.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                            ForEach(group.symbols, id: \.self) { symbol in
                                let isSelected = selection == symbol
                                Button {
                                    selection = symbol
                                    dismiss()
                                } label: {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.color.opacity(0.14)))
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay {
                                            Image(systemName: symbol)
                                                .font(.system(size: 19, weight: .semibold))
                                                .foregroundStyle(isSelected ? AnyShapeStyle(tint.onColor) : AnyShapeStyle(tint.gradient))
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(symbol)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .ambientBackground(tint)
        .navigationTitle("Symbol")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Vorlagen

struct HabitTemplateGroup: Identifiable {
    let title: String
    let templates: [HabitDraft]
    var id: String { title }
}

enum HabitTemplates {
    static func make(
        _ name: String,
        _ symbol: String,
        _ colorID: String,
        kind: HabitKind = .build,
        frequency: HabitFrequency = .daily,
        times: Int = 3,
        target: Double = 1,
        unit: String = "",
        step: Double = 1,
        details: String = ""
    ) -> HabitDraft {
        var draft = HabitDraft()
        draft.name = name
        draft.symbol = symbol
        draft.colorID = colorID
        draft.kind = kind
        draft.frequency = frequency
        draft.timesPerPeriod = times
        draft.dailyTarget = target
        draft.unit = unit
        draft.step = step
        draft.details = details
        return draft
    }

    static let groups: [HabitTemplateGroup] = [
        HabitTemplateGroup(title: "Gesundheit", templates: [
            make("Wasser trinken", "drop.fill", "lagoon", target: 8, unit: "Gläser"),
            make("Früh schlafen", "bed.double.fill", "ultra", details: "Vor 23 Uhr im Bett"),
            make("Vitamine nehmen", "pills.fill", "mango"),
            make("Zahnseide", "sparkles", "glacier"),
            make("Gesund essen", "carrot.fill", "volt"),
        ]),
        HabitTemplateGroup(title: "Bewegung", templates: [
            make("Spazieren gehen", "figure.walk", "aurora"),
            make("Laufen", "figure.run", "sunset", frequency: .perWeek, times: 3),
            make("Krafttraining", "dumbbell.fill", "lava", frequency: .perWeek, times: 3),
            make("Dehnen", "figure.yoga", "candy", target: 10, unit: "min", step: 5),
            make("10.000 Schritte", "figure.hiking", "neon", target: 10_000, unit: "Schritte", step: 1000),
        ]),
        HabitTemplateGroup(title: "Geist", templates: [
            make("Lesen", "book.fill", "mango", target: 20, unit: "min", step: 5),
            make("Meditieren", "figure.mind.and.body", "iris", target: 10, unit: "min", step: 5),
            make("Tagebuch schreiben", "pencil", "flamingo"),
            make("Sprache lernen", "character.bubble.fill", "lagoon", target: 15, unit: "min", step: 5),
        ]),
        HabitTemplateGroup(title: "Produktivität", templates: [
            make("Fokusarbeit", "laptopcomputer", "graphite", target: 60, unit: "min", step: 15),
            make("Aufräumen", "house.fill", "aurora"),
            make("Posteingang leeren", "tray.full.fill", "glacier"),
            make("Woche planen", "calendar", "orchid", frequency: .perWeek, times: 1),
        ]),
        HabitTemplateGroup(title: "Abgewöhnen", templates: [
            make("Nicht rauchen", "nosign", "aurora", kind: .quit, target: 0),
            make("Kein Alkohol", "wineglass.fill", "ultra", kind: .quit, target: 0),
            make("Kein Zucker", "birthday.cake.fill", "flamingo", kind: .quit, target: 0),
            make("Weniger Kaffee", "cup.and.saucer.fill", "sunset", kind: .quit, target: 2, unit: "Tassen"),
            make("Kein Social Media", "iphone.slash", "orchid", kind: .quit, target: 0),
        ]),
    ]
}

struct TemplatesView: View {
    var onSelect: (HabitDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(HabitTemplates.groups) { group in
                Section(group.title) {
                    ForEach(group.templates, id: \.name) { template in
                        Button {
                            onSelect(template)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                HabitIcon(symbol: template.symbol, colorID: template.colorID, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .foregroundStyle(.primary)
                                    Text(subtitle(template))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Vorlagen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func subtitle(_ template: HabitDraft) -> String {
        if template.kind == .quit {
            return template.dailyTarget > 0 ? "Höchstens \(Format.amount(template.dailyTarget, unit: template.unit)) pro Tag" : "Abgewöhnen"
        }
        let amount = template.dailyTarget > 1 ? Format.amount(template.dailyTarget, unit: template.unit) + " · " : ""
        switch template.frequency {
        case .perWeek: return amount + "\(template.timesPerPeriod)× pro Woche"
        case .perMonth: return amount + "\(template.timesPerPeriod)× pro Monat"
        default: return amount + "Jeden Tag"
        }
    }
}
