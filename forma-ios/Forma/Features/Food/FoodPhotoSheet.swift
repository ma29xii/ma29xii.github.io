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
    @AppStorage(CoachProviders.consentKey) private var consent = false
    @State private var phase = Phase.idle
    @State private var photo: UIImage?
    @State private var portions: [FoodPhotoPortion] = []
    @State private var meal = FoodMeal.current()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var task: Task<Void, Never>?
    @State private var saveError = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
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
            CameraPicker { data in estimate(data) }.ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                pickerItem = nil
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    phase = .failed("Das Foto ließ sich nicht laden.")
                    return
                }
                estimate(data)
            }
        }
        .onDisappear { task?.cancel() }
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
        } else {
            VStack(spacing: Space.s3) {
                if cameraAvailable {
                    Button { showCamera = true } label: {
                        Label("Foto aufnehmen", systemImage: "camera")
                            .font(.formaRowTitle)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
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

    private func estimate(_ data: Data) {
        task?.cancel()
        photo = UIImage(data: data)
        phase = .estimating
        task = Task { @MainActor in
            do {
                let guesses = try await FoodVision.estimate(photo: data)
                try Task.checkCancellation()
                portions = guesses.compactMap(FoodPhotoPortion.init(guess:))
                phase = portions.isEmpty ? .empty : .results
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                phase = .failed("Die Freigabe für die KI fehlt. Erlaube sie im Coach.")
            } catch let error as CoachProviders.ReplyError {
                phase = .failed(Self.text(for: error))
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed("Die Schätzung hat nicht geklappt. Versuch es erneut.")
            }
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
