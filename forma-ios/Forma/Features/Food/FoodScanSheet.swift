import AVFoundation
import SwiftUI
import UIKit
import VisionKit

struct FoodScanSheet: View {
    private enum Mode: String, CaseIterable {
        case scanner = "Barcode", search = "Produktsuche"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var searchFocused: Bool
    @State private var mode: Mode
    @State private var query = ""
    @State private var hits: [FoodSearchHit] = []
    @State private var recent: [FoodProduct] = []
    @State private var cachedMatches: [FoodProduct] = []
    @State private var selection: FoodProduct?
    @State private var fromCache = false
    @State private var cameraEnabled = false
    @State private var cameraDenied = false
    @State private var requestingCamera = false
    @State private var operation: Task<Void, Never>?
    @State private var status: String?

    private let catalog = FoodCatalog.shared

    init(startInSearch: Bool = false) {
        _mode = State(initialValue: startInSearch ? .search : .scanner)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Lebensmittel finden", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if mode == .scanner && operation == nil {
                    cameraSection
                } else if mode == .search {
                    searchSections
                }

                if operation != nil {
                    Section {
                        ProgressView(mode == .search ? "Lade Produkte …" : "Lade Nährwerte …")
                            .listRowBackground(Theme.card)
                    }
                } else if let status {
                    Section {
                        Text(status)
                            .font(.formaBody)
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Theme.card)
                    }
                }

                if mode == .search {
                    results
                }

                Section {
                    Link("Nährwertdaten von Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org/")!)
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44, alignment: .leading)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .formaScreen()
            .navigationTitle("Lebensmittel hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Schließen")
                }
            }
            .navigationDestination(item: $selection) { product in
                FoodEntryView(product: product, fromCache: fromCache) { dismiss() }
            }
        }
        .task {
            recent = await catalog.recentProducts()
            if mode == .scanner, AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
               DataScannerViewController.isSupported {
                cameraEnabled = true
            }
        }
        .onChange(of: mode) { _, _ in
            cancelOperation()
            cameraEnabled = false
            clearResults()
        }
        .onChange(of: query) { _, _ in
            cancelOperation()
            clearResults()
        }
        .onDisappear {
            cameraEnabled = false
            cancelOperation()
        }
    }

    private var cameraSection: some View {
        Section {
            if cameraEnabled, scenePhase == .active, selection == nil {
                FoodBarcodeScanner(onCode: { code in
                    guard cameraEnabled, mode == .scanner, scenePhase == .active else { return }
                    cameraEnabled = false
                    loadProduct(code)
                }, onUnavailable: {
                    Task { @MainActor in
                        guard cameraEnabled, mode == .scanner, scenePhase == .active else { return }
                        cameraEnabled = false
                        status = "Die Kamera ist gerade nicht verfügbar. Du kannst nach dem Produktnamen suchen."
                    }
                })
                .frame(height: 250)
                .clipShape(.rect(cornerRadius: Radius.plate))
                .accessibilityLabel("Kameravorschau für den Barcode")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else if operation == nil {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Label("Barcode scannen", systemImage: "barcode.viewfinder")
                        .font(.formaSection)
                    Text(cameraDenied
                         ? "Erlaube den Kamerazugriff in den Einstellungen oder nutze die Produktsuche."
                         : "Halte den Barcode der Verpackung in die Kamera.")
                        .font(.formaBody)
                        .foregroundStyle(Theme.textSecondary)
                    if cameraDenied {
                        Button("Einstellungen öffnen") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                        .frame(minHeight: 44)
                    } else {
                        Button { enableCamera() } label: {
                            Text("Kamera starten").frame(minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(requestingCamera)
                    }
                }
                .padding(.vertical, Space.s2)
                .listRowBackground(Theme.card)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active,
               AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                cameraDenied = false
            }
        }
    }

    private var searchSections: some View {
        Section {
            TextField("Produktname, z. B. Haferflocken", text: $query)
                .accessibilityLabel("Produktname")
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit(search)
                .frame(minHeight: 44)
                .listRowBackground(Theme.card)
            Button(action: search) {
                Label("Suchen", systemImage: "magnifyingglass")
                    .frame(minHeight: 44)
            }
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || operation != nil)
            .listRowBackground(Theme.card)
        }
    }

    @ViewBuilder
    private var results: some View {
        if !hits.isEmpty {
            Section {
                ForEach(hits) { hit in
                    resultButton(name: hit.name, brand: hit.brand) { loadProduct(hit.id) }
                        .disabled(operation != nil)
                }
            } header: {
                Text("Treffer").formaLabelStyle()
            }
        } else {
            let showRecent = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let products = showRecent ? recent : cachedMatches
            if !products.isEmpty {
                Section {
                    ForEach(products) { product in
                        resultButton(name: product.name, brand: product.brand) {
                            searchFocused = false
                            fromCache = true
                            selection = product
                        }
                        .disabled(operation != nil)
                    }
                } header: {
                    Text(showRecent ? "Zuletzt geöffnet" : "Auf dem iPhone gespeichert").formaLabelStyle()
                }
            }
        }
    }

    private func resultButton(name: String, brand: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(name).font(.formaRowTitle)
                    if let brand {
                        Text(brand).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.formaMicro)
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.card)
    }

    private func enableCamera() {
        searchFocused = false
        status = nil
        guard DataScannerViewController.isSupported else {
            status = "Dieses Gerät unterstützt den Barcode-Scanner nicht. Nutze die Produktsuche."
            return
        }
        requestingCamera = true
        Task { @MainActor in
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            requestingCamera = false
            guard mode == .scanner else { return }
            cameraDenied = !authorized
            if authorized {
                cameraEnabled = true
            }
        }
    }

    private func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2, operation == nil else { return }
        searchFocused = false
        clearResults()
        operation = Task { @MainActor in
            do {
                let found = try await catalog.search(term)
                try Task.checkCancellation()
                hits = found
                if found.isEmpty { status = "Keine Produkte gefunden. Versuche einen kürzeren Namen." }
            } catch {
                let saved = await catalog.recentProducts()
                guard !Task.isCancelled else { return }
                cachedMatches = saved.filter {
                    $0.name.localizedStandardContains(term) || $0.brand?.localizedStandardContains(term) == true
                }
                status = error.localizedDescription
            }
            operation = nil
        }
    }

    private func loadProduct(_ code: String) {
        guard operation == nil else { return }
        searchFocused = false
        status = nil
        operation = Task { @MainActor in
            do {
                let result = try await catalog.product(for: code)
                let saved = await catalog.recentProducts()
                try Task.checkCancellation()
                recent = saved
                fromCache = result.fromCache
                selection = result.product
            } catch {
                guard !Task.isCancelled else { return }
                status = error.localizedDescription
            }
            operation = nil
        }
    }

    private func clearResults() {
        status = nil
        hits = []
        cachedMatches = []
    }

    private func cancelOperation() {
        operation?.cancel()
        operation = nil
    }
}
