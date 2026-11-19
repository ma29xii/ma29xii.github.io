import SwiftData
import SwiftUI

// MARK: - Eigenes Lebensmittel

struct FoodCustomFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var base = FoodBase.grams
    @State private var fields: [FoodNutrient: String] = [:]
    @State private var serving = ""
    @State private var saveError = false

    private static let shown: [FoodNutrient] = [.energy, .protein, .carbohydrates, .fat, .sugar, .fiber, .salt]

    private var product: FoodProduct? {
        var values: [FoodNutrient: Double] = [:]
        for nutrient in Self.shown {
            let text = (fields[nutrient] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard let value = FoodText.decimal(text) else { return nil }
            values[nutrient] = value
        }
        let servingText = serving.trimmingCharacters(in: .whitespacesAndNewlines)
        let servingSize = servingText.isEmpty ? nil : FoodText.decimal(servingText)
        if !servingText.isEmpty && servingSize == nil { return nil }
        return FoodRecipeMath.custom(code: "custom-" + UUID().uuidString, name: name, base: base,
                                     per100: values, servingSize: servingSize)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name, z. B. Omas Kartoffelsalat", text: $name)
                    .frame(minHeight: 44)
                Picker("Bezug", selection: $base) {
                    Text("je 100 g").tag(FoodBase.grams)
                    Text("je 100 ml").tag(FoodBase.milliliters)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
            }
            .listRowBackground(Theme.card)

            Section {
                ForEach(Self.shown) { nutrient in
                    HStack {
                        Text(nutrient.title)
                        Spacer()
                        TextField(nutrient == .energy ? "Pflicht" : "–", text: binding(nutrient))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                            .accessibilityLabel("\(nutrient.title) je 100 \(base.rawValue)")
                        Text(nutrient.unit).foregroundStyle(Theme.textSecondary).frame(width: 34, alignment: .leading)
                    }
                    .frame(minHeight: 44)
                }
            } header: {
                Text("Nährwerte je 100 \(base.rawValue)").formaLabelStyle()
            }
            .listRowBackground(Theme.card)

            Section {
                HStack {
                    Text("Portion")
                    Spacer()
                    TextField("optional", text: $serving)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                        .accessibilityLabel("Portionsgröße in \(base.rawValue)")
                    Text(base.rawValue).foregroundStyle(Theme.textSecondary).frame(width: 34, alignment: .leading)
                }
                .frame(minHeight: 44)
            }
            .listRowBackground(Theme.card)
        }
        .formaScreen()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Eigenes Lebensmittel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save).disabled(product == nil)
            }
        }
        .alert("Konnte nicht gespeichert werden", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func binding(_ nutrient: FoodNutrient) -> Binding<String> {
        Binding(get: { fields[nutrient] ?? "" }, set: { fields[nutrient] = $0 })
    }

    private func save() {
        guard let product else { return }
        do {
            let item = try FoodLibraryItem(product: product, kind: .custom)
            try FoodEntry.saveChange(in: context) { context.insert(item) }
            dismiss()
        } catch {
            saveError = true
        }
    }
}

// MARK: - Rezept

struct FoodRecipeView: View {
    private struct Draft: Identifiable {
        let id = UUID()
        let product: FoodProduct
        var amount: String

        var unit: FoodAmountUnit { product.canUseBase ? .base : .servings }
        var ingredient: FoodRecipeIngredient? {
            FoodText.decimal(amount).map { FoodRecipeIngredient(product: product, amount: $0, unit: unit) }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var servings = 2
    @State private var drafts: [Draft] = []
    @State private var picking = false
    @State private var saveError = false

    private var recipe: FoodProduct? {
        let ingredients = drafts.compactMap(\.ingredient)
        guard ingredients.count == drafts.count else { return nil }
        return FoodRecipeMath.product(code: "recipe-" + UUID().uuidString, name: name, servings: servings,
                                      ingredients: ingredients)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name, z. B. Porridge", text: $name).frame(minHeight: 44)
                Stepper("\(servings) \(servings == 1 ? "Portion" : "Portionen")", value: $servings, in: 1...20)
                    .frame(minHeight: 44)
            }
            .listRowBackground(Theme.card)

            Section {
                ForEach($drafts) { $draft in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.product.name).font(.formaRowTitle)
                            Text(draft.ingredient?.nutrients?.values[.energy].map { "\(FoodText.number($0)) kcal" } ?? "—")
                                .font(.formaCaption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        TextField("Menge", text: $draft.amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 70)
                            .accessibilityLabel("Menge \(draft.product.name)")
                        Text(draft.unit == .base ? draft.product.base.rawValue : "Port.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(minHeight: 48)
                }
                .onDelete { drafts.remove(atOffsets: $0) }
                Button { picking = true } label: {
                    Label("Zutat hinzufügen", systemImage: "plus").frame(minHeight: 44)
                }
            } header: {
                Text("Zutaten").formaLabelStyle()
            }
            .listRowBackground(Theme.card)

            if let recipe, let kcal = recipe.perServing.values[.energy] {
                Section {
                    LabeledContent("Je Portion") {
                        Text("\(FoodText.number(kcal)) kcal").font(.formaNumber).formaNumberTransition(kcal)
                    }
                    ForEach([FoodNutrient.protein, .carbohydrates, .fat]) { nutrient in
                        LabeledContent(nutrient.title,
                                       value: recipe.perServing.values[nutrient].map { "\(FoodText.number($0, digits: 1)) g" } ?? "—")
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .formaScreen()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Rezept")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save).disabled(recipe == nil)
            }
        }
        .sheet(isPresented: $picking) {
            FoodProductPicker { product in
                drafts.append(Draft(product: product, amount: product.canUseBase ? "100" : "1"))
            }
        }
        .alert("Konnte nicht gespeichert werden", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func save() {
        let ingredients = drafts.compactMap(\.ingredient)
        guard let recipe, ingredients.count == drafts.count else { return }
        do {
            let item = try FoodLibraryItem(product: recipe, kind: .recipe, servings: servings, ingredients: ingredients)
            try FoodEntry.saveChange(in: context) { context.insert(item) }
            dismiss()
        } catch {
            saveError = true
        }
    }
}

/// Bekannte Lebensmittel (eigene, zuletzt eingetragene, zuletzt geöffnete) als Zutat wählen.
private struct FoodProductPicker: View {
    let onPick: (FoodProduct) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodLibraryItem.createdAt, order: .reverse) private var library: [FoodLibraryItem]
    @Query(FoodLibrary.recentDescriptor) private var entries: [FoodEntry]
    @State private var cached: [FoodProduct] = []
    @State private var query = ""

    private var products: [FoodProduct] {
        let own = library.filter { $0.kind != .recipe }.compactMap(\.product)
        let eaten = FoodTracking.recent(entries, limit: 30).compactMap(\.reusableProduct)
        var seen = Set<String>()
        let all = (own + eaten + cached).filter { seen.insert($0.name.lowercased()).inserted }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? all : all.filter { $0.name.localizedStandardContains(term) }
    }

    var body: some View {
        NavigationStack {
            List {
                if products.isEmpty {
                    Text("Trag zuerst ein Lebensmittel ein oder lege ein eigenes an.")
                        .font(.formaBody)
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.card)
                }
                ForEach(products) { product in
                    Button {
                        onPick(product)
                        dismiss()
                    } label: {
                        FoodProductLabel(name: product.name, detail: product.brand)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                }
            }
            .formaScreen()
            .searchable(text: $query, prompt: "Lebensmittel")
            .navigationTitle("Zutat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Schließen")
                }
            }
            .task { cached = await FoodCatalog.shared.recentProducts() }
        }
    }
}

// MARK: - Gemeinsames

enum FoodLibrary {
    /// Die letzten 400 Einträge reichen für Zuletzt, Häufig und die Serie.
    static var recentDescriptor: FetchDescriptor<FoodEntry> {
        var descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 400
        return descriptor
    }
}

struct FoodProductLabel: View {
    let name: String
    var detail: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.formaRowTitle)
                if let detail {
                    Text(detail).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Space.s2)
            if let trailing {
                Text(trailing).font(.formaValue).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Stern zum Merken eines Produkts als Favorit.
struct FoodFavoriteButton: View {
    let product: FoodProduct
    @Environment(\.modelContext) private var context
    @Query private var matches: [FoodLibraryItem]

    init(product: FoodProduct) {
        self.product = product
        let code = product.code
        let favorite = FoodLibraryKind.favorite.rawValue
        _matches = Query(filter: #Predicate<FoodLibraryItem> { $0.code == code && $0.kindRaw == favorite })
    }

    var body: some View {
        let isFavorite = !matches.isEmpty
        Button(action: toggle) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Theme.warning : Theme.textPrimary)
        }
        .sensoryFeedback(.selection, trigger: isFavorite)
        .accessibilityLabel(isFavorite ? "Aus Favoriten entfernen" : "Als Favorit merken")
    }

    private func toggle() {
        let existing = matches
        do {
            if existing.isEmpty {
                let item = try FoodLibraryItem(product: product, kind: .favorite)
                try FoodEntry.saveChange(in: context) { context.insert(item) }
            } else {
                try FoodEntry.saveChange(in: context) { existing.forEach { context.delete($0) } }
            }
        } catch {
            // Stern bleibt im alten Zustand; nichts geht verloren.
        }
    }
}

// MARK: - Meine Lebensmittel im Scanner

/// Favoriten, eigene Lebensmittel und Rezepte, Zuletzt und Häufig – ohne Netz sofort da.
struct FoodMineSections: View {
    let onPick: (FoodProduct) -> Void
    @Query(sort: \FoodLibraryItem.createdAt, order: .reverse) private var library: [FoodLibraryItem]
    @Query(FoodLibrary.recentDescriptor) private var entries: [FoodEntry]

    var body: some View {
        let favorites = library.filter { $0.kind == .favorite }.compactMap(\.product)
        let own = library.filter { $0.kind != .favorite }
        let recent = FoodTracking.recent(entries, limit: 6)
        let frequent = FoodTracking.frequent(entries, limit: 6)

        Section {
            NavigationLink { FoodCustomFoodView() } label: {
                Label("Eigenes Lebensmittel", systemImage: "square.and.pencil").frame(minHeight: 44)
            }
            NavigationLink { FoodRecipeView() } label: {
                Label("Rezept", systemImage: "list.bullet.rectangle").frame(minHeight: 44)
            }
        }
        .listRowBackground(Theme.card)

        products("Favoriten", favorites.map { ($0, Self.energyText($0)) })
        products("Eigene und Rezepte", own.compactMap { item in
            item.product.map { ($0, Self.energyText($0)) }
        })
        products("Häufig", frequent.compactMap { entry in
            entry.reusableProduct.map { ($0, entry.energy.map { "\(FoodText.number($0)) kcal" }) }
        })
        products("Zuletzt", recent.compactMap { entry in
            entry.reusableProduct.map { ($0, entry.energy.map { "\(FoodText.number($0)) kcal" }) }
        })

        if library.isEmpty && entries.isEmpty {
            Section {
                Text("Hier erscheinen Favoriten, eigene Lebensmittel und was du oft isst.")
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.card)
        }
    }

    @ViewBuilder
    private func products(_ title: String, _ items: [(FoodProduct, String?)]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button { onPick(item.0) } label: {
                        FoodProductLabel(name: item.0.name, detail: item.0.brand, trailing: item.1)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(title).formaLabelStyle()
            }
            .listRowBackground(Theme.card)
        }
    }

    /// Energie je Portion, sonst je 100 g/ml.
    static func energyText(_ product: FoodProduct) -> String? {
        if let kcal = product.perServing.values[.energy] { return "\(FoodText.number(kcal)) kcal/Port." }
        if let kcal = product.per100.values[.energy] { return "\(FoodText.number(kcal)) kcal/100 \(product.base.rawValue)" }
        return nil
    }
}
