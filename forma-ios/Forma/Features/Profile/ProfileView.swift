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

    var body: some View {
        @Bindable var hub = hub
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    Picker("Quelle", selection: $hub.preferredSource) {
                        ForEach(DataSourceKind.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Gerade aktiv", value: hub.activeSource.title)
                    if let last = hub.lastUpdate {
                        LabeledContent("Aktualisiert", value: Format.clock(last))
                    }
                } header: {
                    Text("Datenquelle")
                } footer: {
                    Text("Automatisch: Fitbit, wenn verbunden, sonst Apple Health. Ohne Berechtigung oder Daten zeigt Forma gekennzeichnete Beispieldaten.")
                }

                Section("Apple Health") {
                    Button {
                        Task { await hub.requestHealthAccess() }
                    } label: {
                        Label(hub.healthAuthorized ? "Zugriff erneut prüfen" : "Mit Apple Health verbinden", systemImage: "heart")
                    }
                }

                Section {
                    if hub.fitbit.isConnected {
                        Label("Verbunden", systemImage: "checkmark.circle")
                        Button("Trennen", role: .destructive) {
                            hub.fitbit.disconnect()
                            Task { await hub.refresh() }
                        }
                    } else {
                        Button {
                            Task { await connectFitbit() }
                        } label: {
                            HStack {
                                Label("Mit Fitbit verbinden", systemImage: "link")
                                if fitbitBusy { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(fitbitBusy)
                    }
                } header: {
                    Text("Fitbit")
                } footer: {
                    Text(hub.fitbit.isConfigured
                         ? "Liest Schlaf, HRV, Ruhepuls, Aktivität, SpO₂ und Atemfrequenz über die Fitbit Web API."
                         : "Noch nicht eingerichtet: Die Fitbit-Client-ID fehlt in Config.xcconfig (Anleitung im README).")
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
                    Button("Speichern") {
                        Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "anthropic.key")
                        message = apiKey.isEmpty ? "Schlüssel entfernt. Der Coach antwortet lokal." : "Gespeichert. Freie Fragen gehen jetzt an Claude."
                    }
                } header: {
                    Text("Coach")
                } footer: {
                    Text("Ohne Schlüssel rechnet der Coach komplett auf dem iPhone. Mit Schlüssel werden deine Frage und eine kurze Zusammenfassung deiner Tageswerte an die Anthropic-API gesendet.")
                }

                Section("Journal") {
                    Button { dismiss(); app.showJournal = true } label: { Label("Journal öffnen", systemImage: "book") }
                }

                Section {
                    LabeledContent("Version", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0")
                } footer: {
                    Text("Forma ersetzt keine ärztliche Beratung. Alle Werte bleiben auf diesem iPhone, außer du nutzt Fitbit oder den Claude-Coach.")
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
