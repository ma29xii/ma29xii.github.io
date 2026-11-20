import SwiftData
import SwiftUI

/// Texte der Wochenplanung, getrennt von den Ansichten, damit sie testbar bleiben.
enum FoodPlanText {
    static func dayTitle(_ day: Date, now: Date = .now, calendar: Calendar = .forma) -> String {
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: day)
        switch calendar.dateComponents([.day], from: today, to: target).day ?? 0 {
        case 0: return "Heute"
        case 1: return "Morgen"
        default: return target.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(.german))
        }
    }

    static func energy(_ summary: FoodPlanLogic.DaySummary) -> String {
        (summary.complete ? "" : "mind. ") + FoodText.number(summary.kcal) + " kcal"
    }

    static func detail(for entry: FoodPlanEntry) -> String {
        let amount: String
        switch entry.unit {
        case .base: amount = FoodText.number(entry.amount, digits: 2) + " " + entry.product.base.rawValue
        case .servings: amount = entry.amount == 1 ? "1 Portion" : FoodText.number(entry.amount, digits: 2) + " Portionen"
        }
        return entry.meal.title + " · " + amount
    }
}

/// Tag, für den gerade etwas hinzugefügt wird (für `sheet(item:)`).
private struct PlanDay: Identifiable {
    let day: Date
    var id: Date { day }
}

// MARK: - Planung und Einkaufsliste

/// Wochenplanung fürs Essen: Mahlzeiten für die nächsten Tage planen, daraus eine Einkaufsliste ableiten
/// und am Tag mit einem Tipp ins Tagebuch übernehmen.
struct FoodPlanView: View {
    /// `true` als eigenes Blatt (mit Schließen-Knopf), `false` zum Einschieben in einen NavigationStack.
    var standalone = true
    var body: some View {
        FoodStandalone(standalone) { FoodPlanContent() }
    }
}

private struct FoodPlanContent: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case plan = "Plan", shopping = "Einkauf"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \FoodPlanItem.createdAt) private var items: [FoodPlanItem]
    @State private var mode = Mode.plan
    @State private var adding: PlanDay?
    @State private var saveError = false

    var body: some View {
        let entries = items.compactMap { $0.entry }
        let shopping = FoodPlanLogic.shoppingLines(from: entries, today: .now)
        List {
            Section {
                Picker("Ansicht", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("plan.mode")
            }

            switch mode {
            case .plan: planSections(entries)
            case .shopping: shoppingSections(shopping)
            }
        }
        .formaScreen()
        .navigationTitle(mode == .plan ? "Essen planen" : "Einkaufsliste")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $adding) { target in
            FoodPlanAddView(day: target.day)
        }
        .alert("Das hat nicht geklappt", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Der Plan konnte nicht gespeichert werden. Versuch es noch einmal.")
        }
    }

    // MARK: Plan

    @ViewBuilder private func planSections(_ entries: [FoodPlanEntry]) -> some View {
        let now = Date.now
        let overdue = FoodPlanLogic.overdue(entries, today: now)
        if !overdue.isEmpty {
            Section {
                ForEach(overdue) { entry in row(entry, showDay: true) }
            } header: {
                Text("Früher geplant").formaLabelStyle()
            } footer: {
                Text("Diese Mahlzeiten stehen noch nicht im Tagebuch.")
            }
            .listRowBackground(Theme.card)
        }

        ForEach(FoodPlanLogic.days(from: now), id: \.self) { day in
            let dayEntries = FoodPlanLogic.entries(entries, on: day)
            let open = dayEntries.filter { !$0.logged }
            let canLog = FoodPlanLogic.canLog(day: day, now: now)
            Section {
                if dayEntries.isEmpty {
                    Text("Noch nichts geplant")
                        .font(.formaBody)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44, alignment: .leading)
                }
                ForEach(dayEntries) { entry in row(entry, showDay: false) }
                if canLog && open.count > 1 {
                    Button { log(open) } label: {
                        Label("Alles eintragen (\(open.count))", systemImage: "checkmark.circle")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("plan.logAll")
                }
                Button { adding = PlanDay(day: day) } label: {
                    Label("Hinzufügen", systemImage: "plus").frame(minHeight: 44)
                }
                .accessibilityIdentifier("plan.add")
            } header: {
                HStack {
                    Text(FoodPlanText.dayTitle(day, now: now)).formaLabelStyle()
                    Spacer()
                    if !dayEntries.isEmpty {
                        Text(FoodPlanText.energy(FoodPlanLogic.summary(of: dayEntries)))
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    private func row(_ entry: FoodPlanEntry, showDay: Bool) -> some View {
        let now = Date.now
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.product.name).font(.formaRowTitle).lineLimit(2)
                Text((showDay ? FoodPlanText.dayTitle(entry.day, now: now) + " · " : "") + FoodPlanText.detail(for: entry))
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Space.s2)
            if entry.logged {
                Label("Eingetragen", systemImage: "checkmark.circle.fill")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            } else if FoodPlanLogic.canLog(day: entry.day, now: now) {
                Button("Eintragen") { log([entry]) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityLabel("\(entry.product.name) ins Tagebuch eintragen")
                    .accessibilityIdentifier("plan.log")
            } else if let kcal = entry.kcal {
                Text(FoodText.number(kcal) + " kcal").font(.formaValue).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(minHeight: 44)
        .swipeActions {
            Button(role: .destructive) { delete(entry) } label: { Label("Löschen", systemImage: "trash") }
        }
    }

    // MARK: Einkaufsliste

    @ViewBuilder private func shoppingSections(_ lines: [ShoppingLine]) -> some View {
        if lines.isEmpty {
            Section {
                Text("Plane Mahlzeiten für die nächsten Tage, dann entsteht hier deine Einkaufsliste.")
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, Space.s2)
            }
            .listRowBackground(Theme.card)
        }
        ForEach(ShoppingGroup.allCases, id: \.self) { group in
            let inGroup = lines.filter { $0.group == group }
            if !inGroup.isEmpty {
                Section {
                    ForEach(inGroup) { line in shoppingRow(line) }
                } header: {
                    Text(group.title).formaLabelStyle()
                }
                .listRowBackground(Theme.card)
            }
        }
        if lines.contains(where: { $0.bought }) {
            Section {
                Button { clearChecks() } label: {
                    Label("Häkchen entfernen", systemImage: "arrow.uturn.backward").frame(minHeight: 44)
                }
            } footer: {
                Text("Die Liste enthält nur, was noch nicht im Tagebuch steht.")
            }
            .listRowBackground(Theme.card)
        }
        let shareText = FoodPlanLogic.shoppingText(lines)
        if !shareText.isEmpty {
            Section {
                ShareLink(item: shareText) {
                    Text("Einkaufsliste teilen").frame(minHeight: 44)
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    private func shoppingRow(_ line: ShoppingLine) -> some View {
        Button { toggle(line) } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: line.bought ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(line.bought ? Theme.textPrimary : Theme.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                        .font(.formaRowTitle)
                        .strikethrough(line.bought)
                        .lineLimit(2)
                    if let brand = line.brand {
                        Text(brand).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: Space.s2)
                Text(line.quantity.text).font(.formaValue).foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: 44)
            .opacity(line.bought ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(line.name), \(line.quantity.text)")
        .accessibilityValue(line.bought ? "Gekauft" : "Offen")
        .accessibilityHint("Zum Abhaken doppeltippen")
        .accessibilityIdentifier("plan.shopping.row")
    }

    // MARK: Aktionen

    private func log(_ entries: [FoodPlanEntry]) {
        let ids = Set(entries.map(\.id))
        let chosen = items.filter { ids.contains($0.uid) }
        do { try FoodPlanStore.log(chosen, in: context) } catch { saveError = true }
    }

    private func delete(_ entry: FoodPlanEntry) {
        guard let item = items.first(where: { $0.uid == entry.id }) else { return }
        do { try FoodEntry.saveChange(in: context) { context.delete(item) } } catch { saveError = true }
    }

    private func toggle(_ line: ShoppingLine) {
        let ids = Set(line.entryIDs)
        let target = !line.bought
        do {
            try FoodEntry.saveChange(in: context) {
                for item in items where ids.contains(item.uid) { item.bought = target }
            }
        } catch { saveError = true }
    }

    private func clearChecks() {
        do {
            try FoodEntry.saveChange(in: context) {
                for item in items where item.bought { item.bought = false }
            }
        } catch { saveError = true }
    }
}

// MARK: - Hinzufügen

/// Lebensmittel für einen Tag wählen: aus „Meine“ (Favoriten, Eigene, Häufig, Zuletzt) oder per Suche.
struct FoodPlanAddView: View {
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @State private var chosenDay: Date
    @State private var meal: FoodMeal
    @State private var query = ""
    @State private var hits: [FoodSearchHit] = []
    @State private var searching = false
    @State private var searchFailed = false
    @State private var loadingCode: String?
    @State private var selection: FoodProduct?

    init(day: Date) {
        self.day = day
        _chosenDay = State(initialValue: Calendar.forma.startOfDay(for: day))
        _meal = State(initialValue: FoodMeal.current())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Tag", selection: $chosenDay) {
                        ForEach(FoodPlanLogic.days(from: .now), id: \.self) { Text(FoodPlanText.dayTitle($0)).tag($0) }
                    }
                    .frame(minHeight: 44)
                    Picker("Mahlzeit", selection: $meal) {
                        ForEach(FoodMeal.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(minHeight: 44)
                }
                .listRowBackground(Theme.card)

                if searching {
                    Section {
                        ProgressView("Suche …").listRowBackground(Theme.card)
                    }
                }
                if searchFailed {
                    Section {
                        Text("Das hat nicht geklappt. Prüf deine Verbindung und versuch es noch einmal.")
                            .font(.formaBody)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.card)
                }
                if !hits.isEmpty {
                    Section {
                        ForEach(hits) { hit in
                            Button { open(hit) } label: {
                                FoodProductLabel(name: hit.name, detail: hit.brand,
                                                 trailing: loadingCode == hit.id ? "Lädt …" : nil)
                            }
                            .buttonStyle(.plain)
                            .disabled(loadingCode != nil)
                        }
                    } header: {
                        Text("Treffer").formaLabelStyle()
                    }
                    .listRowBackground(Theme.card)
                }

                FoodMineSections { selection = $0 }
            }
            .formaScreen()
            .searchable(text: $query, prompt: "Lebensmittel suchen")
            .onSubmit(of: .search) { runSearch() }
            .navigationTitle("Planen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Schließen")
                }
            }
            .navigationDestination(item: $selection) { product in
                FoodPlanAmountView(product: product, day: chosenDay, meal: meal) { dismiss() }
            }
        }
    }

    private func runSearch() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }
        searching = true
        searchFailed = false
        Task {
            do { hits = try await FoodCatalog.shared.search(term) } catch { hits = []; searchFailed = true }
            searching = false
        }
    }

    private func open(_ hit: FoodSearchHit) {
        loadingCode = hit.id
        searchFailed = false
        Task {
            if let result = try? await FoodCatalog.shared.product(for: hit.id) {
                selection = result.product
            } else {
                searchFailed = true
            }
            loadingCode = nil
        }
    }
}

/// Menge wählen und zum Plan hinzufügen.
private struct FoodPlanAmountView: View {
    let product: FoodProduct
    let day: Date
    let meal: FoodMeal
    let onSaved: () -> Void
    @Environment(\.modelContext) private var context
    @State private var unit: FoodAmountUnit
    @State private var text: String
    @State private var saveError = false

    init(product: FoodProduct, day: Date, meal: FoodMeal, onSaved: @escaping () -> Void) {
        self.product = product
        self.day = day
        self.meal = meal
        self.onSaved = onSaved
        let start: FoodAmountUnit = product.canUseBase ? .base : .servings
        _unit = State(initialValue: start)
        _text = State(initialValue: start == .base ? "100" : "1")
    }

    private var amount: Double? { FoodText.decimal(text) }
    private var nutrients: FoodNutrients? { amount.flatMap { product.nutrients(for: $0, in: unit) } }

    var body: some View {
        List {
            Section {
                FoodProductLabel(name: product.name, detail: product.brand)
            }
            .listRowBackground(Theme.card)

            Section {
                if product.canUseBase && product.canUseServings {
                    Picker("Einheit", selection: $unit) {
                        Text(product.base.rawValue).tag(FoodAmountUnit.base)
                        Text("Portionen").tag(FoodAmountUnit.servings)
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                }
                HStack {
                    Text("Menge")
                    Spacer()
                    TextField("0", text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                        .accessibilityIdentifier("plan.amount")
                    Text(unit == .base ? product.base.rawValue : "Portion")
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(minHeight: 44)
                HStack {
                    Text("Energie")
                    Spacer()
                    Text(nutrients?.values[.energy].map { FoodText.number($0) + " kcal" } ?? "–")
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(minHeight: 44)
            } footer: {
                if nutrients == nil {
                    Text("Gib eine Menge größer als 0 ein, die zum Produkt passt.")
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Button("Zum Plan hinzufügen") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(nutrients == nil)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("plan.save")
            }
        }
        .formaScreen()
        .navigationTitle(FoodPlanText.dayTitle(day))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: unit) { _, new in text = new == .base ? "100" : "1" }
        .alert("Das hat nicht geklappt", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Der Plan konnte nicht gespeichert werden. Versuch es noch einmal.")
        }
    }

    private func save() {
        guard let amount, product.nutrients(for: amount, in: unit) != nil else { return }
        do {
            let item = try FoodPlanItem(day: day, meal: meal, product: product, amount: amount, unit: unit)
            try FoodEntry.saveChange(in: context) { context.insert(item) }
            onSaved()
        } catch {
            saveError = true
        }
    }
}

// MARK: - Karte fürs Tagebuch

/// „Für heute geplant“ mit einem Tipp ins Tagebuch. Zeigt sich nur, wenn für heute noch Einträge offen sind.
/// Zum Einbinden oben im Tagebuch (`FoodLogView`).
struct FoodPlanTodayCard: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [FoodPlanItem]
    @State private var saveError = false

    init() {
        let start = Calendar.forma.startOfDay(for: .now)
        let end = Calendar.forma.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        _items = Query(filter: #Predicate<FoodPlanItem> { $0.day >= start && $0.day < end },
                       sort: \FoodPlanItem.createdAt)
    }

    var body: some View {
        let open = items.filter { $0.loggedAt == nil }
        if !open.isEmpty {
            let entries = open.compactMap { $0.entry }
            let summary = FoodPlanLogic.summary(of: entries)
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("Für heute geplant").formaLabelStyle()
                    Spacer()
                    Text(FoodPlanText.energy(summary)).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
                Text(entries.prefix(3).map { $0.product.name }.joined(separator: ", ") + (entries.count > 3 ? " und \(entries.count - 3) weitere" : ""))
                    .font(.formaBody)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    do { try FoodPlanStore.log(open, in: context) } catch { saveError = true }
                } label: {
                    Text(open.count == 1 ? "Eintragen" : "Alles eintragen (\(open.count))")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("plan.today.logAll")
            }
            .padding(Space.s4)
            .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
            .alert("Das hat nicht geklappt", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Der Plan konnte nicht ins Tagebuch übernommen werden. Versuch es noch einmal.")
            }
        }
    }
}
