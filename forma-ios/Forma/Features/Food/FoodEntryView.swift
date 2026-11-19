import SwiftData
import SwiftUI

enum FoodText {
    static func number(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).locale(.german))
    }

    static func input(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(.german))
    }

    static func liters(_ milliliters: Double) -> String {
        number(milliliters / 1_000, digits: 2) + " l"
    }

    /// Dauer als „h:mm“ für Fasten-Zeiten.
    static func clock(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func hours(_ seconds: TimeInterval) -> String {
        clock(seconds) + " h"
    }

    static func decimal(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[0-9]+(?:[.,][0-9]+)?$"#, options: .regularExpression) != nil,
              let result = Double(value.replacingOccurrences(of: ",", with: ".")), result.isFinite else { return nil }
        return result
    }
}

struct FoodEntryView: View {
    private enum Basis: Hashable { case amount, reference, serving }

    let product: FoodProduct
    let fromCache: Bool
    let onSave: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(DataHub.self) private var hub
    @FocusState private var editingAmount: Bool
    @State private var amountText: String
    @State private var unit: FoodAmountUnit
    @State private var meal: FoodMeal
    @State private var basis = Basis.amount
    @State private var saving = false
    @State private var saveError = false

    /// `meal`: vorgewählte Mahlzeit (z. B. aus „Frühstück hinzufügen“); ohne Angabe nach Uhrzeit.
    init(product: FoodProduct, fromCache: Bool, meal: FoodMeal? = nil, onSave: @escaping () -> Void) {
        self.product = product
        self.fromCache = fromCache
        self.onSave = onSave
        _meal = State(initialValue: meal ?? .current())
        _amountText = State(initialValue: product.canUseServings ? "1" : "100")
        _unit = State(initialValue: product.canUseServings ? .servings : .base)
    }

    private var amount: Double? { FoodText.decimal(amountText) }
    private var nutrients: FoodNutrients? { amount.flatMap { product.nutrients(for: $0, in: unit) } }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(product.name).font(.formaHeadline).accessibilityAddTraits(.isHeader)
                    if let brand = product.brand {
                        Text(brand).font(.formaBody).foregroundStyle(Theme.textSecondary)
                    }
                    if fromCache {
                        Label("Auf dem iPhone gespeichert", systemImage: "arrow.down.circle")
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if hub.isSample {
                        Text("Vorschau · Der Eintrag wird nicht dauerhaft gespeichert.")
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, Space.s2)
            }
            .listRowBackground(Theme.card)

            amountSection

            Section {
                Picker("Mahlzeit", selection: $meal) {
                    ForEach(FoodMeal.allCases) { meal in
                        Text(meal.title).tag(meal)
                    }
                }
                .frame(minHeight: 44)
            }
            .listRowBackground(Theme.card)

            nutritionSection
        }
        .formaScreen()
        .navigationTitle("Eintragen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { FoodFavoriteButton(product: product) }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text("Eintragen")
                    .font(.formaRowTitle)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(nutrients == nil || saving)
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s2)
            .background(.bar)
        }
        .onChange(of: unit) { _, current in
            let converted = amount.flatMap { currentAmount in
                product.servingSize.map { current == .base ? currentAmount * $0 : currentAmount / $0 }
            }
            setAmount(converted ?? (current == .base ? 100 : 1))
        }
        .alert("Eintrag konnte nicht gespeichert werden", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Deine Eingaben sind noch da. Versuch es erneut.")
        }
    }

    private var amountSection: some View {
        Section {
            if product.canUseBase && product.canUseServings {
                Picker("Einheit", selection: $unit) {
                    Text(product.base.title).tag(FoodAmountUnit.base)
                    Text("Portionen").tag(FoodAmountUnit.servings)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
            }
            HStack(spacing: Space.s2) {
                TextField("Menge", text: $amountText)
                    .font(.formaNumber)
                    .keyboardType(.decimalPad)
                    .focused($editingAmount)
                    .accessibilityLabel("Menge")
                    .frame(minHeight: 44)
                Text(unit == .base ? product.base.rawValue : "Portionen")
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
                Stepper("Menge ändern", onIncrement: { adjust(increasing: true) },
                        onDecrement: { adjust(increasing: false) })
                    .labelsHidden()
                    .fixedSize()
                    .frame(minHeight: 44)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s2) { suggestions }
                VStack(alignment: .leading, spacing: Space.s2) { suggestions }
            }
            if unit == .servings, let size = product.servingSize {
                Text("1 Portion = \(FoodText.number(size, digits: 2)) \(product.base.rawValue)")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Menge").formaLabelStyle()
        } footer: {
            if nutrients == nil, !amountText.isEmpty {
                Text("Gib eine Menge größer als null ein. Höchstens \(FoodText.number(product.amountLimit(in: unit), digits: 2)) \(unit == .base ? product.base.rawValue : "Portionen").")
            }
        }
        .listRowBackground(Theme.card)
    }

    private var suggestions: some View {
        ForEach(unit == .base ? [50.0, 100, 150] : [0.5, 1, 2], id: \.self) { value in
            if value <= product.amountLimit(in: unit) {
                Button { setAmount(value) } label: {
                    Text(suggestionLabel(value))
                        .font(.formaCaptionStrong)
                        .padding(.horizontal, Space.s1)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.glass)
                .accessibilityAddTraits(amount == value ? .isSelected : [])
            }
        }
    }

    private var nutritionSection: some View {
        Section {
            if let energy = nutrients?.values[.energy] {
                LabeledContent("Für deine Menge") {
                    Text("\(FoodText.number(energy)) kcal")
                        .font(.formaNumber)
                        .formaNumberTransition(energy)
                }
            } else if nutrients != nil {
                Text("Für diese Menge fehlen die Kalorien. Du kannst das Produkt trotzdem eintragen.")
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
            }
            DisclosureGroup("Alle Nährwerte") {
                Picker("Bezugsmenge", selection: $basis) {
                    Text("Deine Menge").tag(Basis.amount)
                    Text("Je 100 \(product.base.rawValue)").tag(Basis.reference)
                    if product.canUseServings { Text("Je Portion").tag(Basis.serving) }
                }
                .frame(minHeight: 44)
                ForEach(FoodNutrient.allCases) { nutrient in
                    LabeledContent(nutrient.title) {
                        if let value = shownNutrients?.values[nutrient] {
                            Text("\(FoodText.number(value, digits: nutrient == .energy ? 0 : 2)) \(nutrient.unit)")
                                .font(.formaValue)
                        } else {
                            Text("—")
                                .foregroundStyle(Theme.textSecondary)
                                .accessibilityLabel("Keine Angabe")
                        }
                    }
                    .frame(minHeight: 32)
                }
            }
            .frame(minHeight: 44)
        } header: {
            Text("Nährwerte").formaLabelStyle()
        }
        .listRowBackground(Theme.card)
    }

    private var shownNutrients: FoodNutrients? {
        switch basis {
        case .amount: nutrients
        case .reference: product.per100
        case .serving: product.perServing
        }
    }

    private func suggestionLabel(_ value: Double) -> String {
        let suffix = unit == .base ? product.base.rawValue : (value > 1 ? "Portionen" : "Portion")
        return "\(FoodText.number(value, digits: 1)) \(suffix)"
    }

    private func adjust(increasing: Bool) {
        let step = unit == .base ? 5.0 : 0.25
        let current = amount ?? 0
        let next = current + (increasing ? step : -step)
        if next > 0 { setAmount(next) }
    }

    private func setAmount(_ value: Double) {
        editingAmount = false
        // Abrunden, damit eine gerundete Portion an der Obergrenze gültig bleibt.
        let limit = (product.amountLimit(in: unit) * 100).rounded(.down) / 100
        amountText = FoodText.input(min(limit, max(0.01, value)))
    }

    private func save() {
        guard !saving, let amount, let nutrients else { return }
        saving = true
        let entry = FoodEntry(meal: meal, product: product, amount: amount, in: unit, nutrients: nutrients)
        do {
            try FoodEntry.saveChange(in: context) { context.insert(entry) }
            onSave()
        } catch {
            saving = false
            saveError = true
        }
    }
}
