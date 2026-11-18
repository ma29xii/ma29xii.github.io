import SwiftUI
import PhotosUI
import UserNotifications
import UIKit

struct ProfileView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("forma.claudeConsent") private var claudeConsent = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoError: String?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmDeleteCopy = false

    var body: some View {
        @Bindable var hub = hub
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: Space.s3) {
                            ProfileAvatar(image: app.profilePhoto, size: 48)
                            Text(app.profilePhoto == nil ? "Profilbild wählen" : "Profilbild ändern")
                        }
                        .frame(minHeight: 48)
                    }
                    if app.profilePhoto != nil {
                        Button("Profilbild entfernen", role: .destructive) {
                            selectedPhoto = nil
                            do {
                                try ProfilePhotoStore.remove()
                                app.profilePhoto = nil
                                photoError = nil
                            } catch {
                                photoError = "Das Profilbild konnte nicht entfernt werden."
                            }
                        }
                    }
                    if let photoError {
                        Text(photoError).font(.formaCaption).foregroundStyle(Theme.warning)
                    }
                    NavigationLink("Body") { BodyProfileView() }
                }

                Section {
                    Picker("Quelle", selection: $hub.preferredSource) {
                        ForEach([DataSourceKind.automatic, .health, .sample]) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Apple Health", value: hub.healthStatus)
                        .accessibilityIdentifier("profile.health.status")
                    Button {
                        Task { await hub.requestHealthAccess() }
                    } label: {
                        Label("Erneut verbinden", systemImage: "heart")
                    }
                    .disabled(!hub.health.isAvailable || hub.requestingHealthAccess)

                    NavigationLink {
                        GoogleHealthSharingView()
                    } label: {
                        LabeledContent("Google Health", value: "Über Apple Health")
                    }
                    .accessibilityIdentifier("profile.googleHealth")
                } header: {
                    Text("Datenquellen")
                } footer: {
                    Text("Lesefreigaben prüfst du in Apple Health unter Profilbild → Apps → Health.")
                }

                if hub.fitbit.isConnected {
                    Section("Fitbit") {
                        Button("Alte Fitbit-Verbindung entfernen", role: .destructive) {
                            hub.fitbit.disconnect()
                        }
                    }
                }

                if hub.activeSource == .health {
                    Section("Synchronisierung") {
                        LabeledContent("Letzter erfolgreicher Import", value: stamp(hub.lastUpdate))
                        LabeledContent("Letzter Abruf im Hintergrund", value: stamp(hub.lastBackgroundSync))
                        LabeledContent("Letzter Versuch im Hintergrund", value: stamp(hub.lastBackgroundAttempt))
                        if let note = hub.syncNote ?? hub.observerNote {
                            Text(note).font(.formaCaption).foregroundStyle(Theme.warning)
                        }
                        Button {
                            Task { await hub.syncAndNotify(background: false) }
                        } label: {
                            HStack {
                                Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                                if hub.isLoading { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(hub.isLoading || hub.requestingHealthAccess)
                    }
                }

                Section("Mitteilungen") {
                    if notificationStatus == .notDetermined {
                        Button("Mitteilungen erlauben") {
                            Task {
                                _ = await CoachNotifier.requestPermission()
                                notificationStatus = await CoachNotifier.authorizationStatus()
                                if hub.activeSource == .health { CoachNotifier.afterSync(hub) }
                            }
                        }
                    } else {
                        Button("iOS-Einstellungen öffnen") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }

                Section("Datenschutz") {
                    if claudeConsent {
                        Button("Externe Datenfreigabe widerrufen", role: .destructive) { claudeConsent = false }
                    }
                    Button("Lokale Kopie der Apple-Health-Daten löschen", role: .destructive) { confirmDeleteCopy = true }
                }
                .confirmationDialog("Lokale Kopie löschen?", isPresented: $confirmDeleteCopy, titleVisibility: .visible) {
                    Button("Löschen", role: .destructive) { hub.deleteLocalHealthCopy() }
                } message: {
                    Text("Beim nächsten Abruf lädt Health die Werte neu aus Apple Health.")
                }

                Section {
                    LabeledContent("Version", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0")
                }
            }
            .formaScreen()
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
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

    private func stamp(_ date: Date?) -> String {
        date.map { "\(Format.shortDate($0)), \(Format.clock($0))" } ?? "Noch keiner"
    }
}

private struct GoogleHealthSharingView: View {
    var body: some View {
        Form {
            Section("Fitbit-Daten teilen") {
                Text("Öffne Google Health und tippe auf dein Profilbild → Partner-Apps → Apple Health.")
                Text("Erlaube das Teilen von Schritten und Schlaf. Sobald diese Werte in Apple Health erscheinen, kann Health sie beim nächsten Abruf lesen.")
            }
            Section("Schrittquellen") {
                Text("In Apple Health kannst du unter Schritte → Datenquellen & -zugriff die Reihenfolge deiner Tracker ändern.")
            }
        }
        .formaScreen()
        .navigationTitle("Google Health")
        .navigationBarTitleDisplayMode(.inline)
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
            } else {
                Section {
                    Picker("Geburtsjahr", selection: $birthYear) {
                        Text(hub.person.origin == .health ? "Aus Apple Health" : "Nicht angegeben").tag(0)
                        let latestYear = Calendar.forma.component(.year, from: .now)
                        ForEach((1901...latestYear).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    Picker("Geschlecht", selection: $sexRaw) {
                        ForEach(BiologicalSex.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }

                Section("Gewicht") {
                    Picker("Einheit", selection: $app.weightUnit) {
                        Text("Kilogramm").tag(WeightUnit.kg)
                        Text("Pfund").tag(WeightUnit.lb)
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
                }
            }
        }
        .formaScreen()
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { weightText = displayWeight(weightKg, unit: app.weightUnit) }
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
