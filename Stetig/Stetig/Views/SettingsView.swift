import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import WidgetKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<Habit> { $0.isArchived }) private var archived: [Habit]
    @Query private var categories: [HabitCategory]

    @AppStorage(SettingsKey.appearance) private var appearance = 0
    @AppStorage(SettingsKey.accent, store: AppGroup.defaults) private var accentID = Palette.defaultID
    @AppStorage(SettingsKey.chipColor, store: AppGroup.defaults) private var chipColorID = ""
    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 0
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.confetti) private var confetti = true
    @AppStorage(SettingsKey.appLock) private var appLock = false
    @AppStorage(SettingsKey.summaryEnabled) private var summaryEnabled = false
    @AppStorage(SettingsKey.summaryMinutes) private var summaryMinutes = 21 * 60

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var exportDocument: DataDocument?
    @State private var exportType: UTType = .json
    @State private var exportName = "Stetig-Backup"
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var confirmDeleteAll = false
    @State private var confirmDemo = false
    @State private var message: String?

    private var appearanceSection: some View {
        Section("Darstellung") {
            Picker("Erscheinungsbild", selection: $appearance) {
                Text("System").tag(0)
                Text("Hell").tag(1)
                Text("Dunkel").tag(2)
            }
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Akzentfarbe", value: Palette.entry(accentID).name)
                ColorGrid(selection: $accentID)
            }
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Kategorien in Akzentfarbe", isOn: chipFollowsAccent.animation(.snappy))
                ChipPreview(tint: Palette.entry(chipColorID.isEmpty ? accentID : chipColorID))
                if !chipColorID.isEmpty {
                    LabeledContent("Farbe der Kategorien", value: Palette.entry(chipColorID).name)
                    ColorGrid(selection: $chipColorID)
                }
            }
            Picker("Wochenbeginn", selection: $weekStart) {
                Text("Montag").tag(0)
                Text("Sonntag").tag(6)
            }
            Toggle("Haptisches Feedback", isOn: $haptics)
            Toggle("Konfetti, wenn alles erledigt ist", isOn: $confetti)
        }
    }

    /// An: Kategorien folgen der Akzentfarbe. Aus: eigene Farbe, zuerst „Mono“ (weiß im Dunkelmodus).
    private var chipFollowsAccent: Binding<Bool> {
        Binding(
            get: { chipColorID.isEmpty },
            set: { chipColorID = $0 ? "" : "mono" }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SiriSetupView()
                    } label: {
                        Label("Siri-Kurzbefehle", systemImage: "mic.fill")
                    }
                    NavigationLink {
                        WidgetsSiriView()
                    } label: {
                        Label("Widgets & Siri", systemImage: "square.grid.2x2")
                    }
                }

                appearanceSection

                Section("Organisation") {
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        LabeledContent {
                            Text("\(categories.count)")
                        } label: {
                            Label("Kategorien", systemImage: "folder")
                        }
                    }
                    NavigationLink {
                        ArchiveView()
                    } label: {
                        LabeledContent {
                            Text("\(archived.count)")
                        } label: {
                            Label("Archiv", systemImage: "archivebox")
                        }
                    }
                }

                Section {
                    Toggle(isOn: $appLock) {
                        Label("Mit Face ID sperren", systemImage: "faceid")
                    }
                    .disabled(!AppLock.isAvailable && !appLock)
                } header: {
                    Text("Privatsphäre")
                } footer: {
                    Text("Alle Daten bleiben auf deinem Gerät. Kein Konto, keine Werbung, kein Tracking.")
                }

                Section {
                    LabeledContent {
                        Text(notificationLabel)
                    } label: {
                        Label("Mitteilungen", systemImage: "bell")
                    }
                    if notificationStatus == .notDetermined {
                        Button("Mitteilungen erlauben") {
                            Task {
                                await Reminders.requestAuthorization()
                                await refreshNotificationStatus()
                                Reminders.rescheduleAll(in: context)
                            }
                        }
                    } else if notificationStatus == .denied {
                        Button("In den Systemeinstellungen aktivieren") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                    Toggle("Täglicher Tagesabschluss", isOn: $summaryEnabled.animation())
                    if summaryEnabled {
                        DatePicker("Uhrzeit", selection: summaryTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Erinnerungen")
                } footer: {
                    Text("Erinnerungen für einzelne Gewohnheiten stellst du beim Bearbeiten ein. Der Tagesabschluss erinnert einmal täglich an alles Offene.")
                }

                Section {
                    Button {
                        export(json: true)
                    } label: {
                        Label("Backup exportieren (JSON)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Backup importieren", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        export(json: false)
                    } label: {
                        Label("Als Tabelle exportieren (CSV)", systemImage: "tablecells")
                    }
                    Button {
                        confirmDemo = true
                    } label: {
                        Label("Beispieldaten laden", systemImage: "sparkles")
                    }
                    Button(role: .destructive) {
                        confirmDeleteAll = true
                    } label: {
                        Label("Alle Daten löschen", systemImage: "trash")
                    }
                } header: {
                    Text("Daten")
                } footer: {
                    Text("Ein importiertes Backup wird mit den vorhandenen Daten zusammengeführt.")
                }

                Section("Über") {
                    NavigationLink {
                        TipsView()
                    } label: {
                        Label("Tipps & Gesten", systemImage: "lightbulb")
                    }
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("Stetig ist kostenlos und quelloffen – gebaut mit SwiftUI, SwiftData und Liquid Glass.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .ambientBackground()
            .navigationTitle("Einstellungen")
            .task { await refreshNotificationStatus() }
            .onChange(of: weekStart) { _, _ in
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onChange(of: accentID) { _, _ in
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onChange(of: appLock) { _, _ in
                Reminders.registerCategories()
            }
            .onChange(of: summaryEnabled) { _, enabled in
                Task {
                    if enabled {
                        await Reminders.requestAuthorization()
                        await refreshNotificationStatus()
                    }
                    Reminders.scheduleSummary(enabled: enabled, minutes: summaryMinutes)
                }
            }
            .onChange(of: summaryMinutes) { _, minutes in
                Reminders.scheduleSummary(enabled: summaryEnabled, minutes: minutes)
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: exportType,
                defaultFilename: exportName
            ) { result in
                if case .failure(let error) = result {
                    message = "Export fehlgeschlagen: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                importBackup(result)
            }
            .confirmationDialog("Wirklich alle Daten löschen?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Alles löschen", role: .destructive) {
                    Backup.deleteEverything(in: context)
                }
            } message: {
                Text("Alle Gewohnheiten, Einträge und Kategorien werden unwiderruflich entfernt.")
            }
            .confirmationDialog("Beispieldaten hinzufügen?", isPresented: $confirmDemo, titleVisibility: .visible) {
                Button("Hinzufügen") {
                    DemoData.insert(into: context)
                }
            } message: {
                Text("Es werden sieben Beispiel-Gewohnheiten mit Verlauf angelegt. Deine Daten bleiben erhalten.")
            }
            .alert("Hinweis", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var summaryTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: summaryMinutes / 60, minute: summaryMinutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            summaryMinutes = (parts.hour ?? 21) * 60 + (parts.minute ?? 0)
        }
    }

    private var notificationLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "Erlaubt"
        case .denied: "Deaktiviert"
        default: "Noch nicht gefragt"
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func export(json: Bool) {
        let stamp = Day.today.key
        if json {
            guard let data = try? Backup.exportJSON(from: context) else {
                message = "Das Backup konnte nicht erstellt werden."
                return
            }
            exportDocument = DataDocument(data: data)
            exportType = .json
            exportName = "Stetig-Backup-\(stamp)"
        } else {
            exportDocument = DataDocument(data: Backup.exportCSV(from: context))
            exportType = .commaSeparatedText
            exportName = "Stetig-Export-\(stamp)"
        }
        showExporter = true
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            let file = try Backup.decode(Data(contentsOf: url))
            let summary = Backup.restore(file, into: context)
            Reminders.rescheduleAll(in: context)
            message = "\(summary.habits) Gewohnheiten und \(summary.entries) Einträge importiert."
        } catch {
            message = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

// MARK: - Kategorien

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HabitCategory.sortOrder) private var categories: [HabitCategory]

    @State private var newName = ""
    @State private var renaming: HabitCategory?
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Neue Kategorie", text: $newName)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Hinzufügen", systemImage: "plus.circle.fill", action: add)
                        .labelStyle(.iconOnly)
                        .disabled(newName.trimmed.isEmpty)
                }
            }
            Section {
                ForEach(categories) { category in
                    Button {
                        renameText = category.name
                        renaming = category
                    } label: {
                        LabeledContent {
                            Text("\(category.habits.filter { !$0.isArchived }.count)")
                        } label: {
                            Text(category.name)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .onDelete { offsets in
                    let targets = offsets.map { categories[$0] }
                    for category in targets {
                        context.delete(category)
                    }
                    Store.commit(context)
                }
                .onMove { source, destination in
                    var ordered = categories
                    ordered.move(fromOffsets: source, toOffset: destination)
                    for (index, category) in ordered.enumerated() {
                        category.sortOrder = index
                    }
                    Store.commit(context)
                }
            } footer: {
                Text("Kategorien erscheinen als Filter über deinen Gewohnheiten. Beim Löschen bleiben die Gewohnheiten erhalten.")
            }
        }
        .navigationTitle("Kategorien")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .alert("Kategorie umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") {
                if let renaming, !renameText.trimmed.isEmpty {
                    renaming.name = renameText.trimmed
                    Store.commit(context)
                }
            }
        }
    }

    private func add() {
        let name = newName.trimmed
        guard !name.isEmpty else { return }
        let category = HabitCategory(name: name, sortOrder: (categories.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(category)
        Store.commit(context)
        newName = ""
    }
}

// MARK: - Archiv

struct ArchiveView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { $0.isArchived }, sort: \Habit.name) private var habits: [Habit]

    var body: some View {
        List {
            ForEach(habits) { habit in
                HStack(spacing: 12) {
                    HabitIcon(symbol: habit.symbol, colorID: habit.colorID, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name)
                        Text("\(habit.entries.filter { $0.amount > 0 }.count) Einträge")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Wiederherstellen") {
                        HabitAdmin.setArchived(false, habit: habit, in: context)
                    }
                    .buttonStyle(.glass)
                    .font(.footnote)
                }
            }
            .onDelete { offsets in
                let targets = offsets.map { habits[$0] }
                for habit in targets {
                    HabitAdmin.deleteNow(habit, in: context)
                }
            }
        }
        .overlay {
            if habits.isEmpty {
                ContentUnavailableView(
                    "Archiv ist leer",
                    systemImage: "archivebox",
                    description: Text("Archivierte Gewohnheiten verschwinden aus der Übersicht, behalten aber ihren Verlauf.")
                )
            }
        }
        .navigationTitle("Archiv")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tipps

struct TipsView: View {
    private struct Tip: Identifiable {
        let symbol: String
        let title: String
        let text: String
        var id: String { title }
    }

    private let tips: [Tip] = [
        Tip(symbol: "checkmark", title: "Abhaken", text: "Ein Tipp auf den Haken trägt den heutigen Tag ein. Bei Zählern geht es pro Tipp einen Schritt weiter, nach dem Ziel wieder auf null."),
        Tip(symbol: "hand.tap", title: "Vergangene Tage", text: "Öffne eine Gewohnheit und tippe im Monatskalender auf einen Tag, um ihn nachzutragen."),
        Tip(symbol: "hand.point.up.left", title: "Gedrückt halten", text: "Auf Karten, Kalendertagen und in „Heute“ öffnet langes Drücken ein Menü: überspringen, Menge und Notiz bearbeiten, pausieren, archivieren."),
        Tip(symbol: "forward.end", title: "Überspringen", text: "Übersprungene Tage unterbrechen die Serie nicht – gedacht für Krankheit, Urlaub oder Ruhetage."),
        Tip(symbol: "pause", title: "Pausieren", text: "Friert eine Gewohnheit ein. Beim Fortsetzen gelten die pausierten Tage als übersprungen."),
        Tip(symbol: "nosign", title: "Abgewöhnen", text: "Bei diesen Gewohnheiten zählt jeder Tag automatisch. Tippe nur dann auf den Haken, wenn es einen Rückfall gab."),
        Tip(symbol: "square.grid.2x2", title: "Widgets", text: "Halte den Home-Bildschirm gedrückt, tippe auf „Bearbeiten“ und füge ein Stetig-Widget hinzu. Der Haken im Widget funktioniert direkt."),
        Tip(symbol: "mic", title: "Siri", text: "Sag „Hey Siri, heute Lesen in Stetig gemacht“. Für einen kürzeren Satz ohne „in Stetig“ lege einen eigenen Kurzbefehl an – Anleitung unter Widgets & Siri."),
    ]

    var body: some View {
        List(tips) { tip in
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: tip.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tip.title).font(.headline)
                    Text(tip.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Tipps & Gesten")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Vorschau der Kategorie-Leiste mit der gewählten Farbe.
private struct ChipPreview: View {
    let tint: HabitColor

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                chip("Alle", selected: true)
                chip("Gesundheit", selected: false)
                chip("Fitness", selected: false)
            }
        }
        .accessibilityHidden(true)
    }

    private func chip(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(selected ? tint.onColor : Color.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glassEffect(selected ? Glass.regular.tint(tint.color) : Glass.regular, in: .capsule)
    }
}
