import SwiftUI
import PhotosUI
import UserNotifications
import UIKit

struct ProfileView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("forma.birthYear") private var birthYear = 0
    @AppStorage("forma.sex") private var sexRaw = BiologicalSex.unknown.rawValue
    @AppStorage("forma.bodyWeightKg") private var weightKg = 0.0
    @AppStorage(BackgroundRefresh.plannedKey) private var refreshPlanned = 0.0
    @AppStorage(BackgroundRefresh.errorKey) private var refreshError = ""
    @AppStorage(BackgroundRefresh.attemptKey) private var refreshAttempt = 0.0
    @AppStorage(CoachProviders.consentKey) private var coachConsent = false
    @AppStorage(CoachProviders.photoConsentKey) private var coachPhotoConsent = false
    @AppStorage(FoodSettings.photoConsentKey) private var foodPhotoConsent = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoError: String?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmDisconnect = false
    @State private var showBody = false
    @State private var showAchievements = false
    @State private var showSleepPlan = false

    var body: some View {
        NavigationStack {
            Form {
                photoSection

                Section {
                    // Button statt NavigationLink: die Liste zeichnet sonst automatisch einen Pfeil.
                    Button { showBody = true } label: {
                        SettingsRow(title: "Body", systemImage: "figure.stand")
                    }
                    .accessibilityIdentifier("Body")
                    Button { showAchievements = true } label: {
                        SettingsRow(title: "Erfolge", systemImage: "seal")
                    }
                    .accessibilityIdentifier("profile.achievements")
                }
                .listRowBackground(Theme.card)

                Section {
                    ThemePicker()
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Design").formaLabelStyle()
                }
                .listRowBackground(Theme.card)

                sourceSection

                consentSection

                Section {
                    if notificationStatus == .notDetermined {
                        Button {
                            Task {
                                await CoachNotifier.requestPermission()
                                notificationStatus = await CoachNotifier.authorizationStatus()
                            }
                        } label: {
                            SettingsRow(title: "Mitteilungen erlauben", systemImage: "bell")
                        }
                    } else {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            SettingsRow(title: "Mitteilungen", systemImage: "bell",
                                        detail: ProfileText.notifications(notificationStatus), external: true)
                        }
                    }
                    Button { showSleepPlan = true } label: {
                        SettingsRow(title: "Schlafplan", systemImage: "moon.stars")
                    }
                    .accessibilityIdentifier("profile.wake")
                } header: {
                    Text("Mitteilungen").formaLabelStyle()
                }
                .listRowBackground(Theme.card)

                Section {
                } footer: {
                    Text("Health \(ProfileText.version)")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationDestination(isPresented: $showBody) { BodyProfileView() }
            .navigationDestination(isPresented: $showAchievements) {
                AchievementsView(healthScope: hub.achievementHealthScope, isSample: hub.isSample)
            }
            .navigationDestination(isPresented: $showSleepPlan) {
                SleepPlanView(store: FoodSettings.store(isSample: hub.isSample))
                    .id(hub.isSample)
            }
            .formaScreen()
            .refreshable { await hub.syncAndNotify(background: false) }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .confirmationDialog("Google Health trennen?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Trennen", role: .destructive) { hub.disconnectGoogle() }
            } message: {
                Text("Health liest dann keine neuen Werte mehr. Du kannst jederzeit wieder verbinden.")
            }
            .task { notificationStatus = await CoachNotifier.authorizationStatus() }
            .task(id: selectedPhoto) {
                guard let photo = selectedPhoto else { return }
                photoError = nil
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else {
                        throw ProfilePhotoStore.PhotoError.invalidImage
                    }
                    try Task.checkCancellation()
                    guard selectedPhoto == photo else { return }
                    app.profilePhoto = try ProfilePhotoStore.save(data)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, selectedPhoto == photo else { return }
                    photoError = "Das Profilbild konnte nicht geladen werden."
                }
            }
        }
    }

    // MARK: Freigaben

    /// Nur Widerruf: Zustimmen geschieht dort, wo der Text erklärt, was gesendet wird (Coach-Dialog, Essensfoto).
    /// Der Chat-Widerruf läuft über `CoachProviders`: Er beendet auch laufende Anfragen und nimmt beide Foto-Freigaben mit.
    @ViewBuilder private var consentSection: some View {
        if coachConsent || coachPhotoConsent || foodPhotoConsent {
            Section {
                if coachConsent {
                    revokeRow("Fragen an den Online-Coach", systemImage: "cloud", id: "profile.consent.chat",
                              note: "Danach geht nichts mehr online, auch keine Fotos. Der Coach antwortet auf dem iPhone.") {
                        CoachProviders.revokeChatConsent()
                    }
                }
                if coachPhotoConsent {
                    revokeRow("Fotos im Chat", systemImage: "photo", id: "profile.consent.chatPhotos",
                              note: "Fotos im Chat werden nicht mehr gesendet. Fragen ohne Foto gehen weiter online.") {
                        coachPhotoConsent = false
                    }
                }
                if foodPhotoConsent {
                    revokeRow("Fotos beim Essen", systemImage: "fork.knife", id: "profile.consent.foodPhotos",
                              note: "Essensfotos werden nicht mehr zur Analyse gesendet. Der Chat bleibt online.") {
                        CoachProviders.revokeFoodPhotoConsent()
                    }
                }
            } header: {
                Text("Freigaben").formaLabelStyle()
            }
            .listRowBackground(Theme.card)
        }
    }

    private func revokeRow(_ title: String, systemImage: String, id: String, note: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s2) {
                SettingsRow(title: title, systemImage: systemImage, detail: "Widerrufen")
                Text(note)
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityHint("Gibt diese Freigabe zurück")
        .accessibilityIdentifier(id)
    }

    private var bodySummary: String? {
        ProfileText.bodySummary(birthYear: birthYear, sex: BiologicalSex(rawValue: sexRaw) ?? .unknown,
                                weightKg: weightKg, unit: app.weightUnit)
    }

    // MARK: Profilbild

    /// Kopf wie die Apple-ID-Zeile in den iOS-Einstellungen: Bild links, Name und Angaben rechts.
    private var photoSection: some View {
        Section {
            HStack(spacing: Space.s4) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ProfileAvatar(image: app.profilePhoto, size: 60)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.onSelection)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Theme.selection))
                                .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                        }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if app.profilePhoto != nil {
                        Button("Bild entfernen", systemImage: "trash", role: .destructive) { removePhoto() }
                    }
                }
                .accessibilityLabel(app.profilePhoto == nil ? "Profilbild wählen" : "Profilbild ändern")
                .accessibilityActions {
                    if app.profilePhoto != nil {
                        Button("Bild entfernen") { removePhoto() }
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mein Profil").font(.system(.title3, weight: .semibold))
                    if let bodySummary {
                        Text(bodySummary).font(.formaBody).foregroundStyle(Theme.textSecondary)
                    }
                    if let photoError {
                        Text(photoError).font(.formaCaption).foregroundStyle(Theme.warning)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.s1)
        }
        .listRowBackground(Theme.card)
    }

    private func removePhoto() {
        selectedPhoto = nil
        do {
            try ProfilePhotoStore.remove()
            app.profilePhoto = nil
            photoError = nil
        } catch {
            photoError = "Das Profilbild konnte nicht entfernt werden."
        }
    }

    // MARK: Datenquelle

    private var sourceSection: some View {
        let status = GoogleStatus(hub.google)
        return Section {
            HStack(spacing: Space.s3) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardRaised))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Google Health").font(.formaRowTitle)
                    HStack(spacing: 6) {
                        Circle().fill(status.tone.color).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(status.title).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: Space.s2)
                if status.isBusy || hub.isLoading { ProgressView() }
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile.google.status")

            if let note = hub.syncNote, status.tone != .problem {
                Text(note).font(.formaCaption).foregroundStyle(Theme.warning)
            }

            if let detail = status.detail {
                Text(detail)
                    .font(.formaCaption)
                    .foregroundStyle(status.tone == .problem ? Theme.warning : Theme.textSecondary)
            }

            if case .connected = hub.google, let plan = ProfileText.backgroundPlan(
                planned: refreshPlanned > 0 ? Date(timeIntervalSince1970: refreshPlanned) : nil,
                error: refreshError,
                attempt: refreshAttempt > 0 ? Date(timeIntervalSince1970: refreshAttempt) : nil) {
                Text(plan.text)
                    .font(.formaCaption)
                    .foregroundStyle(plan.isProblem ? Theme.warning : Theme.textSecondary)
                    .accessibilityIdentifier("profile.refresh.plan")
            }

            switch hub.google {
            case .connected:
                Button {
                    Task { await hub.syncAndNotify(background: false) }
                } label: {
                    Label("Jetzt aktualisieren", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(hub.isLoading)
                Button("Google Health trennen", role: .destructive) { confirmDisconnect = true }
            case .disconnected, .failed:
                Button {
                    Task { await connect() }
                } label: {
                    Label("Mit Google Health verbinden", systemImage: "link")
                }
            case .connecting, .notConfigured:
                EmptyView()
            }

            Toggle(isOn: Binding(
                get: { hub.isSample },
                set: { hub.preferredSource = $0 ? .sample : .google }
            )) {
                Text("Beispieldaten zeigen")
            }
            .accessibilityIdentifier("profile.sample")
        } header: {
            Text("Datenquelle").formaLabelStyle()
        }
        .listRowBackground(Theme.card)
    }

    private func connect() async {
        await hub.connectGoogle()
        if case .connected = hub.google, hub.isSample { hub.preferredSource = .google }
    }
}

/// Status der Google-Verbindung in Worten (testbar ohne Oberfläche).
struct GoogleStatus: Equatable {
    enum Tone: Equatable {
        case off, busy, good, problem
        var color: Color {
            switch self {
            case .off: Theme.textQuaternary
            case .busy: Theme.warning
            case .good: Theme.recoveryHigh
            case .problem: Theme.warning
            }
        }
    }

    let title: String
    var detail: String? = nil
    let tone: Tone
    var isBusy: Bool { tone == .busy }

    init(_ connection: GoogleConnection, now: Date = .now) {
        switch connection {
        case .notConfigured:
            title = "Vorschau-Version"
            tone = .off
        case .disconnected:
            title = "Nicht verbunden"
            tone = .off
        case .connecting:
            title = "Verbinde …"
            tone = .busy
        case .connected(let lastSync):
            title = lastSync.map { "Verbunden · \(ProfileText.stamp($0, now: now))" } ?? "Verbunden"
            tone = .good
        case .failed(let message):
            title = "Verbindung unterbrochen"
            detail = message
            tone = .problem
        }
    }
}

/// Kurztexte für die Einstellungen (testbar ohne Oberfläche).
enum ProfileText {
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    static func bodySummary(birthYear: Int, sex: BiologicalSex, weightKg: Double, unit: WeightUnit) -> String? {
        var parts: [String] = []
        if birthYear > 0 { parts.append(String(birthYear)) }
        if sex != .unknown { parts.append(sex.title) }
        if weightKg.isFinite, weightKg > 0 { parts.append("\(Format.weight(weightKg, unit: unit)) \(unit.rawValue)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// „heute, 08:15“, „gestern, 22:40“ oder „17.11., 08:15“.
    /// Zeile zur Hintergrund-Aktualisierung: geplanter Zeitpunkt oder Fehler samt Uhrzeit der Anfrage.
    /// `nil`, solange noch nie ein Termin angefragt wurde.
    static func backgroundPlan(planned: Date?, error: String?, attempt: Date?, now: Date = .now) -> (text: String, isProblem: Bool)? {
        if let error, !error.isEmpty {
            let when = attempt.map { " (\(stamp($0, now: now)))" } ?? ""
            return ("Hintergrund-Abruf nicht geplant\(when): \(error)", true)
        }
        guard let planned else { return nil }
        return ("Nächster Hintergrund-Abruf frühestens \(stamp(planned, now: now))", false)
    }

    static func stamp(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.forma
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "heute"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            day = "gestern"
        } else {
            day = Format.shortDate(date)
        }
        return "\(day), \(Format.clock(date))"
    }

    static func notifications(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: "An"
        case .denied: "Aus"
        default: "Nicht gefragt"
        }
    }
}

/// Zeile in den Einstellungen: Symbol im Graphit-Feld, Titel, Wert rechts.
private struct SettingsRow: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    var external = false

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.cardRaised))
                .accessibilityHidden(true)
            Text(title).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Space.s2)
            if let detail {
                Text(detail).font(.formaBody).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            if external {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textQuaternary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
    }
}

private struct BodyProfileView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @AppStorage("forma.birthYear") private var birthYear = 0
    @AppStorage("forma.sex") private var sexRaw = BiologicalSex.unknown.rawValue
    @AppStorage("forma.bodyWeightKg") private var weightKg = 0.0
    @State private var weightText = ""
    @State private var weightError = false
    @AppStorage(FoodGoal.heightKey) private var heightCm = 0.0
    @State private var heightText = ""
    @State private var heightError = false

    var body: some View {
        @Bindable var app = app
        Form {
            if hub.isSample {
                Section {
                    SampleDataBadge()
                    if let birthday = hub.person.birthDate {
                        LabeledContent("Geburtsjahr", value: String(Calendar.forma.component(.year, from: birthday)))
                    }
                    LabeledContent("Geschlecht", value: hub.person.sex.title)
                    LabeledContent("Gewicht", value: "\(Format.weight(SampleData.weightKg, unit: app.weightUnit)) \(app.weightUnit.rawValue)")
                }
                .listRowBackground(Theme.card)
            } else {
                Section {
                    Picker("Geburtsjahr", selection: $birthYear) {
                        Text("Nicht angegeben").tag(0)
                        let latestYear = Calendar.forma.component(.year, from: .now)
                        ForEach((1901...latestYear).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    Picker("Geschlecht", selection: $sexRaw) {
                        ForEach(BiologicalSex.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    HStack {
                        Text("Gewicht")
                        TextField("Nicht angegeben", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Gewicht")
                        Text(app.weightUnit.rawValue).foregroundStyle(Theme.textSecondary)
                    }
                    if weightText != displayWeight(weightKg, unit: app.weightUnit) {
                        Button("Gewicht speichern") { saveWeight() }
                    }
                    if weightError {
                        Text("Gib ein Gewicht zwischen 1 und 500 kg ein oder lass das Feld leer.")
                            .font(.formaCaption).foregroundStyle(Theme.warning)
                    }
                    HStack {
                        Text("Größe")
                        TextField("Nicht angegeben", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Körpergröße")
                        Text("cm").foregroundStyle(Theme.textSecondary)
                    }
                    if heightText != heightDisplay {
                        Button("Größe speichern") { saveHeight() }
                    }
                    if heightError {
                        Text("Gib 80 bis 250 cm ein oder lass das Feld leer.")
                            .font(.formaCaption).foregroundStyle(Theme.warning)
                    }
                } header: {
                    Text("Über dich").formaLabelStyle()
                }
                .listRowBackground(Theme.card)
            }

            Section {
                Picker("Gewicht", selection: $app.weightUnit) {
                    Text("Kilogramm").tag(WeightUnit.kg)
                    Text("Pfund").tag(WeightUnit.lb)
                }
            } header: {
                Text("Einheiten").formaLabelStyle()
            }
            .listRowBackground(Theme.card)
        }
        .formaScreen()
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            weightText = displayWeight(weightKg, unit: app.weightUnit)
            heightText = heightDisplay
        }
        .onChange(of: birthYear) { _, _ in hub.profileChanged() }
        .onChange(of: sexRaw) { _, _ in hub.profileChanged() }
        .onChange(of: app.weightUnit) { old, new in
            let wasEdited = weightText != displayWeight(weightKg, unit: old)
            if !wasEdited {
                weightText = displayWeight(weightKg, unit: new)
            } else if let kg = inputWeight(unit: old) {
                weightText = displayWeight(kg, unit: new)
            }
            weightError = false
        }
    }

    private func displayWeight(_ kg: Double, unit: WeightUnit) -> String {
        guard kg.isFinite, kg > 0 else { return "" }
        let value = unit == .kg ? kg : kg * 2.20462
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...1)).locale(.german))
    }

    private func inputWeight(unit: WeightUnit) -> Double? {
        let value = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return 0 }
        let decimal = value.contains(",")
            ? value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            : value
        guard let number = Double(decimal), number.isFinite else { return nil }
        return unit == .kg ? number : number / 2.20462
    }

    private var heightDisplay: String { FoodGoal.heightRange.contains(heightCm) ? FoodText.input(heightCm) : "" }

    private func saveHeight() {
        if heightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            heightCm = 0
        } else if let cm = FoodText.decimal(heightText), FoodGoal.heightRange.contains(cm) {
            heightCm = cm
        } else {
            heightError = true
            return
        }
        heightText = heightDisplay
        heightError = false
    }

    private func saveWeight() {
        guard let kg = inputWeight(unit: app.weightUnit),
              weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (1...500).contains(kg) else {
            weightError = true
            return
        }
        weightKg = kg
        weightText = displayWeight(kg, unit: app.weightUnit)
        weightError = false
    }
}
