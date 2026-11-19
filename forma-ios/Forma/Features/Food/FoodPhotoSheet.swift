import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Essen fotografieren → Schätzung → Liste prüfen und anpassen → eintragen.
struct FoodPhotoSheet: View {
    private enum Phase {
        case idle, estimating, results, empty, failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    // Freigaben immer aus dem echten Speicher, auch in der Vorschau.
    @AppStorage(CoachProviders.consentKey, store: .standard) private var consent = false
    /// Eigene Foto-Freigabe der Essensanalyse, getrennt vom Coach.
    @AppStorage(FoodSettings.photoConsentKey, store: .standard) private var photoConsent = false
    @State private var phase = Phase.idle
    @State private var photo: UIImage?
    @State private var portions: [FoodPhotoPortion] = []
    @State private var meal = FoodMeal.current()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var task: Task<Void, Never>?
    @State private var saveError = false
    @State private var camera = CameraAccess.State.unavailable
    private var chosen: [FoodPhotoPortion] { portions.filter(\.included) }
    private var totalKcal: Double { chosen.compactMap { $0.nutrients?.values[.energy] }.reduce(0, +) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    preview
                    switch phase {
                    case .idle: sources
                    case .estimating: estimating
                    case .results: results
                    case .empty: message("Auf dem Foto wurde kein Essen erkannt.", retry: true)
                    case .failed(let text): message(text, retry: true)
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.s6)
            }
            .formaScreen()
            .navigationTitle("Essen fotografieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Schließen")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if case .results = phase, !portions.isEmpty {
                    Button(action: save) {
                        Text(chosen.isEmpty ? "Nichts ausgewählt" : "\(chosen.count) eintragen · \(FoodText.number(totalKcal)) kcal")
                            .font(.formaRowTitle)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(chosen.isEmpty || chosen.contains { $0.nutrients == nil })
                    .padding(.horizontal, Space.page)
                    .padding(.vertical, Space.s2)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in run { data } }.ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            // Laden gehört zum selben abbrechbaren Ablauf wie die Schätzung.
            run { try await item.loadTransferable(type: Data.self) }
        }
        .onAppear { camera = CameraAccess.current }
        .onDisappear {
            task?.cancel()
            task = nil
        }
        .alert("Konnte nicht gespeichert werden", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Deine Auswahl ist noch da. Versuch es erneut.")
        }
    }

    @ViewBuilder private var preview: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: Radius.plate))
                .overlay {
                    if case .estimating = phase {
                        RoundedRectangle(cornerRadius: Radius.plate).fill(.black.opacity(0.35))
                    }
                }
                .accessibilityLabel("Dein Essensfoto")
                .padding(.top, Space.s3)
        } else {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 180)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var sources: some View {
        if !consent {
            VStack(alignment: .leading, spacing: Space.s2) {
                Label("Freigabe fehlt", systemImage: "lock")
                    .font(.formaRowTitle)
                Text("Die Schätzung schickt das Foto an Anthropic, bei Ausfall an OpenAI. Erlaube das zuerst im Coach.")
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
        } else if !photoConsent {
            VStack(alignment: .leading, spacing: Space.s3) {
                Label("Fotos an die KI senden?", systemImage: "photo.badge.checkmark")
                    .font(.formaRowTitle)
                Text("Nur für die Essensanalyse: Anthropic erhält das ausgewählte Foto, bei Ausfall OpenAI. Eingetragen wird erst nach deiner Bestätigung. Die Foto-Freigabe des Coachs bleibt davon getrennt.")
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
                Button("Erlauben") { photoConsent = true }
                    .buttonStyle(.glassProminent)
                    .frame(minHeight: 44)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
        } else {
            VStack(spacing: Space.s3) {
                switch camera {
                case .ready, .needsRequest:
                    Button(action: openCamera) {
                        Label("Foto aufnehmen", systemImage: "camera")
                            .font(.formaRowTitle)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                case .denied:
                    CameraDeniedNotice()
                        .padding(Space.s4)
                        .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
                case .unavailable:
                    EmptyView()
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Aus Fotos wählen", systemImage: "photo.on.rectangle")
                        .font(.formaRowTitle)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glass)
                Text("Das Foto geht zur Schätzung an Anthropic, bei Ausfall an OpenAI. Eingetragen wird erst nach deiner Bestätigung.")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var estimating: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Schätze Lebensmittel und Mengen …")
                .font(.formaBody)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("Erkannt").formaLabelStyle()
                Spacer()
                Picker("Mahlzeit", selection: $meal) {
                    ForEach(FoodMeal.allCases) { Text($0.title).tag($0) }
                }
                .tint(Theme.textPrimary)
            }
            ForEach($portions) { $portion in
                FoodPhotoRow(portion: $portion)
            }
            Text("Schätzung. Prüf die Mengen vor dem Eintragen.")
                .font(.formaCaption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func message(_ text: String, retry: Bool) -> some View {
        VStack(spacing: Space.s3) {
            Text(text)
                .font(.formaBody)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if retry {
                Button("Anderes Foto") { reset() }
                    .buttonStyle(.glass)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
    }

    private func reset() {
        task?.cancel()
        photo = nil
        portions = []
        phase = .idle
    }

    private func openCamera() {
        Task { @MainActor in
            camera = await CameraAccess.request()
            if camera == .ready { showCamera = true }
        }
    }

    /// Foto laden und schätzen in einem Task. Schließen oder „Anderes Foto“ bricht beides ab.
    private func run(_ load: @escaping @Sendable () async throws -> Data?) {
        task?.cancel()
        phase = .estimating
        task = Task { @MainActor in
            do {
                let keys = try CoachProviders.externalCredentials()
                let (_, guesses) = try await FoodPhotoFlow.run(
                    load: load, anthropicKey: keys.anthropic, openAIKey: keys.openAI,
                    allowed: { CoachProviders.allowsExternalData() && FoodSettings.photoAnalysisAllowed() },
                    onLoaded: { data in await MainActor.run { photo = UIImage(data: data) } }
                )
                try Task.checkCancellation()
                portions = guesses.compactMap(FoodPhotoPortion.init(guess:))
                phase = portions.isEmpty ? .empty : .results
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.text(for: error))
            }
        }
    }

    static func text(for error: Error) -> String {
        switch error {
        case FoodPhotoFlow.FlowError.loadFailed: "Das Foto ließ sich nicht laden."
        case is CancellationError: "Die Freigabe für die Essensanalyse fehlt."
        case let reply as CoachProviders.ReplyError: text(for: reply)
        default: "Die Schätzung hat nicht geklappt. Versuch es erneut."
        }
    }

    static func text(for error: CoachProviders.ReplyError) -> String {
        switch error {
        case .missingCredentials: "Für die Foto-Erkennung fehlt ein KI-Schlüssel."
        case .invalidImage: "Das Foto ließ sich nicht lesen."
        case .invalidResponse: "Die Schätzung war unbrauchbar. Versuch ein anderes Foto."
        default: "Die Schätzung hat nicht geklappt. Versuch es erneut."
        }
    }

    private func save() {
        let entries = chosen.compactMap { portion in
            portion.nutrients.map {
                FoodEntry(meal: meal, product: portion.product, amount: portion.grams, in: .base, nutrients: $0)
            }
        }
        guard entries.count == chosen.count else { return }
        do {
            try FoodEntry.saveChange(in: context) { entries.forEach { context.insert($0) } }
            dismiss()
        } catch {
            saveError = true
        }
    }
}

private struct FoodPhotoRow: View {
    @Binding var portion: FoodPhotoPortion

    var body: some View {
        let kcal = portion.nutrients?.values[.energy]
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Button { portion.included.toggle() } label: {
                    Image(systemName: portion.included ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(portion.included ? Theme.younger : Theme.textTertiary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(portion.included ? "\(portion.product.name) ausgewählt" : "\(portion.product.name) nicht ausgewählt")
                Text(portion.product.name)
                    .font(.formaRowTitle)
                    .foregroundStyle(portion.included ? Theme.textPrimary : Theme.textTertiary)
                Spacer()
                Text(kcal.map { "\(FoodText.number($0)) kcal" } ?? "—")
                    .font(.formaValue)
                    .formaNumberTransition(kcal ?? 0)
            }
            HStack(spacing: Space.s3) {
                Slider(value: $portion.grams, in: 5...max(1_000, portion.grams), step: 5)
                    .tint(Theme.textPrimary)
                    .accessibilityLabel("Menge von \(portion.product.name)")
                    .accessibilityValue("\(FoodText.number(portion.grams)) Gramm")
                Text("\(FoodText.number(portion.grams)) g")
                    .font(.formaValue)
                    .monospacedDigit()
                    .frame(minWidth: 56, alignment: .trailing)
            }
            .disabled(!portion.included)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
    }
}

extension FoodMeal {
    /// Mahlzeit nach Uhrzeit vorschlagen.
    static func current(_ date: Date = .now) -> FoodMeal {
        switch Calendar.forma.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 17..<22: .dinner
        default: .snack
        }
    }
}

/// Laden → Schätzen ohne UI. Nach Abbruch oder ohne Freigabe geht keine einzige Anfrage raus.
enum FoodPhotoFlow {
    enum FlowError: Error { case loadFailed }

    static func run(
        load: @Sendable () async throws -> Data?, anthropicKey: String?, openAIKey: String?,
        allowed: @escaping @Sendable () -> Bool, onLoaded: @Sendable (Data) async -> Void = { _ in },
        send: @escaping CoachProviders.Transport = CoachProviders.fetch
    ) async throws -> (Data, [FoodGuess]) {
        let loaded: Data?
        do { loaded = try await load() } catch { throw FlowError.loadFailed }
        guard let data = loaded else { throw FlowError.loadFailed }
        try Task.checkCancellation()
        await onLoaded(data)
        let guesses = try await FoodVision.estimate(
            photo: data, anthropicKey: anthropicKey, openAIKey: openAIKey,
            maySend: { !Task.isCancelled && allowed() }, send: send
        )
        return (data, guesses)
    }
}
