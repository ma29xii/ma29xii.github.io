import SwiftUI
import AuthenticationServices

struct ProfileView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var apiKey = Keychain.get("anthropic.key") ?? ""
    @State private var fitbitBusy = false
    @State private var message: String?
    @AppStorage("forma.birthYear") private var birthYear = 0
    @AppStorage("forma.claudeConsent") private var claudeConsent = false
    @AppStorage("forma.sex") private var sexRaw = BiologicalSex.unknown.rawValue

    var body: some View {
        @Bindable var hub = hub
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    Picker("Quelle", selection: $hub.preferredSource) {
                        ForEach(DataSourceKind.allCases.filter { $0 != .fitbit }) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Gerade aktiv", value: hub.activeSource.title)
                    LabeledContent("Letzter erfolgreicher Import", value: hub.lastUpdate.map { Format.clock($0) } ?? "noch keiner")
                    LabeledContent("Tage mit Daten", value: "\(hub.longDays.filter { $0.sleep != nil || $0.hrv != nil || ($0.steps ?? 0) > 0 }.count) von \(hub.longDays.count)")
                } header: {
                    Text("Datenquelle")
                } footer: {
                    Text("Automatisch: Apple Health, wenn freigegeben. Beispieldaten nur, wenn du sie wählst oder noch keine Daten da sind – dann immer gekennzeichnet.")
                }

                Section {
                    Picker("Geburtsjahr", selection: $birthYear) {
                        Text(hub.person.origin == .health ? "Aus Apple Health" : "Nicht angegeben").tag(0)
                        ForEach(Array((1930...Calendar.forma.component(.year, from: .now) - 14).reversed()), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    Picker("Geschlecht", selection: $sexRaw) {
                        ForEach(BiologicalSex.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } header: {
                    Text("Über dich")
                } footer: {
                    Text("Für das Körperalter. Ohne Angabe nutzt Forma die Werte aus Apple Health. Bleibt alles auf dem iPhone.")
                }
                .onChange(of: birthYear) { _, _ in hub.profileChanged() }
                .onChange(of: sexRaw) { _, _ in hub.profileChanged() }

                Section("Apple Health") {
                    Button {
                        Task { await hub.requestHealthAccess() }
                    } label: {
                        Label(hub.healthAuthorized ? "Zugriff erneut prüfen" : "Mit Apple Health verbinden", systemImage: "heart")
                    }
                }

                Section {
                    Label("Wird umgestellt", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.warning)
                    if hub.fitbit.isConnected {
                        Button("Alte Verbindung entfernen", role: .destructive) {
                            hub.fitbit.disconnect()
                            Task { await hub.refresh() }
                        }
                    }
                } header: {
                    Text("Fitbit")
                } footer: {
                    Text("Google hat die alte Fitbit-Schnittstelle am 2. November 2026 abgeschaltet. Forma wird auf die neue Google Health API umgestellt; bis dahin nutze Apple Health.")
                }

                Section("Einheiten") {
                    Picker("Gewicht", selection: $app.weightUnit) {
                        Text("Kilogramm").tag(WeightUnit.kg)
                        Text("Pfund").tag(WeightUnit.lb)
                    }
                }

                Section {
                    SecureField("API-Schlüssel (optional)", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if claudeConsent {
                        Button("Zustimmung zum Senden widerrufen", role: .destructive) { claudeConsent = false }
                    }
                    Button("Speichern") {
                        Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "anthropic.key")
                        message = apiKey.isEmpty ? "Schlüssel entfernt. Der Coach antwortet lokal." : "Gespeichert. Freie Fragen gehen jetzt an Claude."
                    }
                } header: {
                    Text("Coach")
                } footer: {
                    Text("Ohne Schlüssel rechnet der Coach komplett auf dem iPhone. Mit Schlüssel fragt Forma vor dem ersten Senden, ob deine Frage, der Chat und eine Zusammenfassung deiner Tageswerte an Anthropic gehen dürfen.")
                }

                Section("Journal") {
                    Button { dismiss(); app.showJournal = true } label: { Label("Journal öffnen", systemImage: "book") }
                }

                Section {
                    LabeledContent("Version", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0")
                } footer: {
                    Text("Forma ersetzt keine ärztliche Beratung. Alle Werte bleiben auf diesem iPhone, außer du schaltest den Claude-Coach ein.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .alert("Hinweis", isPresented: Binding(get: { message != nil || hub.lastError != nil }, set: { if !$0 { message = nil; hub.lastError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? hub.lastError ?? "")
            }
        }
    }

    private func connectFitbit() async {
        fitbitBusy = true
        defer { fitbitBusy = false }
        do {
            let url = try hub.fitbit.authorizationURL()
            let callback = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: hub.fitbit.redirectScheme, preferredBrowserSession: .ephemeral)
            try await hub.fitbit.handleCallback(callback)
            hub.preferredSource = .automatic
            await hub.refresh()
            message = "Fitbit ist verbunden."
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            message = error.localizedDescription
        }
    }
}
