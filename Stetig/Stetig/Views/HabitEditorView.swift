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
                Section {
                    KindChooser(kind: $draft.kind.animation(.snappy), tint: tint)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

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

// MARK: - Art

/// Ganz oben im Editor: Gewohnheit aufbauen oder etwas abgewöhnen.
struct KindChooser: View {
    @Binding var kind: HabitKind
    let tint: HabitColor

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                tile(.build, symbol: "arrow.up.right", title: "Aufbauen", detail: "Etwas regelmäßig tun")
                tile(.quit, symbol: "nosign", title: "Abgewöhnen", detail: "Etwas sein lassen")
            }
        }
    }

    private func tile(_ value: HabitKind, symbol: String, title: String, detail: String) -> some View {
        let isSelected = kind == value
        return Button {
            kind = value
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .opacity(0.75)
                }
            }
            .foregroundStyle(isSelected ? tint.onColor : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? Glass.regular.tint(tint.color).interactive() : Glass.regular.interactive(),
            in: .rect(cornerRadius: 22, style: .continuous)
        )
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Symbole

struct SymbolPickerView: View {
    @Binding var selection: String
    let tint: HabitColor

    enum Mode: String, CaseIterable, Identifiable {
        case symbols = "Symbole"
        case emojis = "Emojis"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var emoji = ""
    @State private var mode: Mode

    init(selection: Binding<String>, tint: HabitColor) {
        _selection = selection
        self.tint = tint
        _mode = State(initialValue: HabitGlyph.isEmoji(selection.wrappedValue) ? .emojis : .symbols)
    }

    static let groups: [(title: String, symbols: [String])] = [
        ("Allgemein", ["checkmark", "star.fill", "heart.fill", "flame.fill", "bolt.fill", "sparkles", "sparkle", "flag.fill", "target", "trophy.fill", "crown.fill", "medal.fill", "rosette", "checkmark.seal.fill", "hand.thumbsup.fill", "gift.fill", "bell.fill", "infinity", "star.circle.fill", "wand.and.stars"]),
        ("Gesundheit", ["drop.fill", "pills.fill", "pill.fill", "cross.case.fill", "bed.double.fill", "lungs.fill", "brain.head.profile", "brain", "eye.fill", "ear.fill", "hand.raised.fill", "face.smiling", "stethoscope", "bandage.fill", "waterbottle.fill", "syringe.fill", "heart.text.square.fill", "facemask.fill", "scalemass.fill", "zzz", "powersleep", "thermometer.medium", "allergens", "mouth.fill"]),
        ("Bewegung", ["figure.walk", "figure.run", "figure.yoga", "figure.strengthtraining.traditional", "figure.pool.swim", "figure.outdoor.cycle", "figure.hiking", "figure.dance", "figure.boxing", "figure.climbing", "figure.skiing.downhill", "figure.martial.arts", "figure.pilates", "figure.rower", "figure.jumprope", "figure.core.training", "figure.cooldown", "figure.stairs", "dumbbell.fill", "bicycle", "sportscourt.fill", "soccerball", "basketball.fill", "football.fill", "volleyball.fill", "tennis.racket", "skateboard.fill"]),
        ("Essen & Trinken", ["fork.knife", "cup.and.saucer.fill", "mug.fill", "carrot.fill", "wineglass.fill", "birthday.cake.fill", "takeoutbag.and.cup.and.straw.fill", "fish.fill", "frying.pan.fill", "popcorn.fill", "refrigerator.fill", "stove.fill", "oven.fill", "basket.fill"]),
        ("Geist & Lernen", ["book.fill", "book.closed.fill", "books.vertical.fill", "text.book.closed.fill", "graduationcap.fill", "pencil", "pencil.and.outline", "magazine.fill", "newspaper.fill", "headphones", "music.note", "guitars.fill", "pianokeys", "mic.fill", "music.mic", "paintbrush.fill", "camera.fill", "film.fill", "theatermasks.fill", "puzzlepiece.fill", "globe", "translate", "character.bubble.fill", "quote.bubble.fill", "atom", "function", "figure.mind.and.body"]),
        ("Produktivität", ["laptopcomputer", "desktopcomputer", "keyboard", "envelope.fill", "paperplane.fill", "phone.fill", "calendar", "calendar.badge.clock", "clock.fill", "timer", "alarm.fill", "list.bullet", "checklist", "doc.text.fill", "folder.fill", "tray.full.fill", "printer.fill", "briefcase.fill", "chart.line.uptrend.xyaxis", "chart.bar.fill", "chart.pie.fill", "lightbulb.fill", "flag.checkered", "person.2.fill", "bubble.left.and.bubble.right.fill"]),
        ("Zuhause & Alltag", ["house.fill", "sofa.fill", "lamp.desk.fill", "cart.fill", "washer.fill", "dishwasher.fill", "trash.fill", "shower.fill", "bathtub.fill", "bubbles.and.sparkles", "tshirt.fill", "scissors", "hammer.fill", "wrench.and.screwdriver.fill", "fanblades.fill", "creditcard.fill", "banknote.fill", "car.fill", "airplane"]),
        ("Natur & Tiere", ["leaf.fill", "tree.fill", "camera.macro", "sun.max.fill", "moon.fill", "sunrise.fill", "sunset.fill", "cloud.sun.fill", "snowflake", "wind", "mountain.2.fill", "water.waves", "beach.umbrella.fill", "tent.fill", "globe.europe.africa.fill", "pawprint.fill", "dog.fill", "cat.fill", "bird.fill", "tortoise.fill", "hare.fill", "ladybug.fill", "ant.fill", "teddybear.fill"]),
        ("Miteinander", ["person.fill", "figure.2.and.child.holdinghands", "hands.sparkles.fill", "hand.wave.fill", "message.fill", "heart.circle.fill", "eyeglasses"]),
        ("Abgewöhnen", ["nosign", "smoke.fill", "iphone.slash", "play.slash.fill", "gamecontroller.fill", "bag.fill", "xmark.circle.fill", "xmark.octagon.fill", "hourglass", "tv.fill", "bell.slash.fill", "moon.zzz.fill", "cart.badge.minus", "dice.fill", "speaker.slash.fill", "eye.slash.fill", "wifi.slash", "hand.raised.slash.fill", "exclamationmark.triangle.fill"]),
    ]

    static let emojiGroups: [(title: String, emojis: [String])] = [
        ("Gefühl & Erfolg", ["😀", "😊", "😌", "🥰", "😎", "🤩", "🙏", "💪", "❤️", "🔥", "✨", "🌟", "💯", "🎯", "🏆", "🥇", "🎉", "🚀", "🌈", "☀️"]),
        ("Gesundheit", ["💧", "🥤", "💊", "🩺", "🦷", "🛌", "😴", "🧴", "🧼", "🚿", "🛁", "🫁", "🧠", "👀", "🌞", "🌙", "⏰", "🧘", "🫀", "🩹"]),
        ("Sport", ["🏃", "🚶", "🧗", "🏋️", "🚴", "🏊", "🤸", "⚽", "🏀", "🎾", "🏓", "🥊", "🥾", "⛷️", "🏄", "🛹", "🏐", "🤾", "🧘‍♀️", "🏸"]),
        ("Essen & Trinken", ["🥗", "🍎", "🥦", "🥕", "🍌", "🥑", "🍳", "🥛", "☕", "🍵", "🫖", "🥜", "🍓", "🫐", "🍋", "🥣", "🍫", "🍰", "🍕", "🍷"]),
        ("Lernen & Kreativ", ["📚", "📖", "✍️", "📝", "🎓", "🧩", "🎨", "🎸", "🎹", "🎻", "🥁", "🎧", "🎤", "📷", "🌍", "🗣️", "💡", "🔬", "♟️", "🧶"]),
        ("Arbeit & Geld", ["💻", "📱", "📧", "📅", "✅", "📈", "💰", "💶", "🏦", "🧾", "📦", "🗂️", "⌛", "📞", "🗓️", "📊", "🖊️", "📌", "🧑‍💻", "🤝"]),
        ("Zuhause & Natur", ["🏠", "🧹", "🧺", "🛒", "🪴", "🌱", "🌳", "🌻", "🌷", "🐶", "🐱", "🐴", "🚗", "🚲", "✈️", "🧳", "♻️", "🕯️", "🛏️", "🧸"]),
        ("Miteinander", ["👨‍👩‍👧", "👫", "💬", "📲", "💌", "🎁", "🫶", "👋", "🙌", "😘", "🤗", "🥂"]),
        ("Abgewöhnen", ["🚭", "🚫", "📵", "🍬", "🎮", "🛍️", "🍟", "🍔", "🥃", "🍺", "🎰", "📺", "😤", "💤", "⛔", "🙅"]),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Picker("Art", selection: $mode.animation(.snappy)) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .symbols:
                    ForEach(Self.groups, id: \.title) { group in
                        section(group.title) {
                            ForEach(group.symbols, id: \.self) { symbol in
                                tile(symbol) {
                                    Image(systemName: symbol)
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(selection == symbol ? AnyShapeStyle(tint.onColor) : AnyShapeStyle(tint.gradient))
                                }
                            }
                        }
                    }
                case .emojis:
                    customEmoji
                    ForEach(Self.emojiGroups, id: \.title) { group in
                        section(group.title) {
                            ForEach(group.emojis, id: \.self) { item in
                                tile(item) {
                                    Text(item).font(.system(size: 24))
                                }
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

    private var customEmoji: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eigenes Emoji")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                TextField("Beliebiges Emoji eingeben, z. B. 🎯", text: $emoji)
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
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                content()
            }
        }
    }

    private func tile<Glyph: View>(_ value: String, @ViewBuilder label: () -> Glyph) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
            dismiss()
        } label: {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.color.opacity(0.14)))
                .aspectRatio(1, contentMode: .fit)
                .overlay { label() }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
