import SwiftData
import SwiftUI
import UIKit

struct FoodLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Date.now.startOfDay
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            FoodDayView(day: today)
                .navigationTitle("Ernährung")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Schließen")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { showScanner = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Lebensmittel hinzufügen")
                    }
                }
        }
        .sheet(isPresented: $showScanner) { FoodScanSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in updateDay() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in updateDay() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { updateDay() }
        }
    }

    private func updateDay() { today = Date.now.startOfDay }
}

private struct FoodDayView: View {
    let day: Date
    @Query private var entries: [FoodEntry]
    @Environment(\.modelContext) private var context
    @Environment(DataHub.self) private var hub
    @AppStorage("forma.birthYear") private var birthYear = 0
    @AppStorage("forma.sex") private var sex = BiologicalSex.unknown.rawValue
    @AppStorage("forma.bodyWeightKg") private var weight = 0.0
    @AppStorage(FoodGoal.heightKey) private var height = 0.0
    @State private var deleteError = false

    init(day: Date) {
        self.day = day
        let end = Calendar.forma.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        _entries = Query(
            filter: #Predicate<FoodEntry> { $0.date >= day && $0.date < end },
            sort: \FoodEntry.date, order: .reverse
        )
    }

    private var goal: FoodGoal {
        if hub.isSample {
            return FoodGoal(weightKg: 0, heightCm: 0, age: nil, sex: .unknown, activeEnergy: nil)
        }
        let currentYear = Calendar.forma.component(.year, from: day)
        let age = (1900...currentYear).contains(birthYear) ? currentYear - birthYear : nil
        let measuredToday = hub.today
        let activity = measuredToday.date == day ? measuredToday.activeEnergy : nil
        return FoodGoal(weightKg: weight, heightCm: height, age: age,
                        sex: BiologicalSex(rawValue: sex) ?? .unknown, activeEnergy: activity)
    }

    var body: some View {
        List {
            if hub.isSample {
                Section {
                    SampleDataBadge()
                    Text("Einträge aus der Vorschau werden nicht dauerhaft gespeichert.")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.card)
            }
            Section {
                FoodEnergyCard(entries: entries, goal: goal, isPreview: hub.isSample)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                FoodMacroCard(entries: entries)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ForEach(FoodMeal.allCases) { meal in
                mealSection(meal)
            }
        }
        .formaScreen()
        .alert("Eintrag konnte nicht gelöscht werden", isPresented: $deleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Der Eintrag bleibt im Tagebuch. Versuch es erneut.")
        }
    }

    private func mealSection(_ meal: FoodMeal) -> some View {
        let items = entries.filter { $0.meal == meal }
        return Section {
            if items.isEmpty {
                Text("Noch nichts eingetragen")
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 34)
                    .listRowBackground(Theme.card)
            }
            ForEach(items) { entry in
                FoodLogRow(entry: entry)
                    .listRowBackground(Theme.card)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { delete(entry) } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                    .accessibilityAction(named: Text("Löschen")) { delete(entry) }
            }
        } header: {
            Text(meal.title).formaLabelStyle()
        }
    }

    private func delete(_ entry: FoodEntry) {
        do {
            try FoodEntry.saveChange(in: context) { context.delete(entry) }
        } catch {
            deleteError = true
        }
    }
}

private struct FoodEnergyCard: View {
    let entries: [FoodEntry]
    let goal: FoodGoal
    let isPreview: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var knownEnergy: [Double] { entries.compactMap(\.energy) }
    private var consumed: Double { knownEnergy.reduce(0, +) }
    private var hasMissingEnergy: Bool { knownEnergy.count < entries.count }
    private var consumedText: String {
        hasMissingEnergy && knownEnergy.isEmpty ? "—" : FoodText.number(consumed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Kalorien heute").formaLabelStyle()

            if typeSize.isAccessibilitySize {
                VStack(spacing: Space.s3) {
                    ring.frame(width: 150, height: 150)
                        .accessibilityHidden(true)
                    values
                }
                .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    ring.frame(width: 198, height: 198)
                        .accessibilityHidden(true)
                    values.padding(.horizontal, Space.s4)
                }
                .frame(maxWidth: .infinity)
            }

            if hasMissingEnergy {
                Text("Nicht jeder Eintrag enthält Kalorien.")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: Space.s2) {
                if goal.isPersonalized {
                    LabeledContent("Geschätzter Ruhebedarf", value: "\(FoodText.number(goal.base)) kcal")
                } else if isPreview {
                    Text("Beispielziel: 2.000 kcal")
                } else {
                    Text("Richtwert: 2.000 kcal. Für eine persönliche Schätzung brauchst du vollständige Body-Angaben und musst mindestens 18 sein.")
                }
                if let active = goal.activeEnergy {
                    LabeledContent("Aktive Energie · Google Health", value: "+\(FoodText.number(active)) kcal")
                }
            }
            .font(.formaCaption)
            .foregroundStyle(Theme.textSecondary)

            if !isPreview {
                NavigationLink {
                    FoodHeightView()
                } label: {
                    Label("Körpergröße", systemImage: "ruler")
                        .font(.formaRowTitle)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
    }

    private var ring: some View {
        let fraction = min(1, max(0, consumed / goal.target))
        return ZStack {
            Circle().strokeBorder(Theme.track, lineWidth: 12)
            if fraction > 0 {
                Circle()
                    .inset(by: 6)
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(Theme.younger, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: fraction)
    }

    private var values: some View {
        VStack(spacing: Space.s1) {
            Text(consumedText)
                .font(.formaDisplay)
                .formaNumberTransition(consumed)
            Text("von \(FoodText.number(goal.target)) kcal")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eingetragene Kalorien")
        .accessibilityValue(consumedText == "—"
                            ? "Keine Angabe, Ziel \(FoodText.number(goal.target)) Kilokalorien"
                            : "\(hasMissingEnergy ? "Mindestens " : "")\(consumedText) von \(FoodText.number(goal.target)) Kilokalorien")
    }
}

private struct FoodMacroCard: View {
    let entries: [FoodEntry]

    private struct Macro: Identifiable {
        let nutrient: FoodNutrient
        let values: [Double]
        let energyPerGram: Double
        let tint: Color

        var id: FoodNutrient { nutrient }
        var grams: Double { values.reduce(0, +) }
        var energy: Double { grams * energyPerGram }
    }

    var body: some View {
        let macros = [
            Macro(nutrient: .protein, values: entries.compactMap(\.protein), energyPerGram: 4, tint: Theme.younger),
            Macro(nutrient: .carbohydrates, values: entries.compactMap(\.carbohydrates), energyPerGram: 4, tint: Theme.warning),
            Macro(nutrient: .fat, values: entries.compactMap(\.fat), energyPerGram: 9, tint: Theme.sleep)
        ]
        let total = macros.reduce(0) { $0 + $1.energy }
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Makros").formaLabelStyle()
            ForEach(macros) { macro in
                let hasValue = !macro.values.isEmpty || entries.isEmpty
                let value = hasValue ? "\(FoodText.number(macro.grams, digits: 1)) g" : "—"
                VStack(alignment: .leading, spacing: Space.s2) {
                    LabeledContent(macro.nutrient.title, value: value)
                        .font(.formaBody)
                        .monospacedDigit()
                    ProgressLine(fraction: total > 0 ? macro.energy / total : 0, color: macro.tint, height: 5)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(macro.nutrient.title)
                .accessibilityValue(hasValue ? "\(FoodText.number(macro.grams, digits: 1)) Gramm" : "Keine Angabe")
            }
            if total > 0 {
                Text("Balken zeigen den Anteil an der erfassten Energie aus Eiweiß, Kohlenhydraten und Fett.")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if macros.contains(where: { $0.values.count < entries.count }) {
                Text("Für einige Einträge fehlen Nährwerte.")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
    }
}

private struct FoodLogRow: View {
    let entry: FoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            LabeledContent {
                if let energy = entry.energy {
                    Text("\(FoodText.number(energy)) kcal").font(.formaValue)
                } else {
                    Text("— kcal")
                        .font(.formaValue)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel("Keine Kalorienangabe")
                }
            } label: {
                Text(entry.name).font(.formaRowTitle)
            }
            let unit = entry.unit == "Portion" && entry.amount > 1 ? "Portionen" : entry.unit
            Text("\(FoodText.number(entry.amount, digits: 2)) \(unit)")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct FoodHeightView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FoodGoal.heightKey) private var height = 0.0
    @State private var input = ""
    @State private var invalidHeight = false

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Nicht angegeben", text: $input)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Körpergröße")
                    Text("cm").foregroundStyle(Theme.textSecondary)
                }
                .frame(minHeight: 44)
                Button("Speichern", action: save).frame(minHeight: 44)
            } header: {
                Text("Körpergröße").formaLabelStyle()
            } footer: {
                Text(invalidHeight
                     ? "Gib 80 bis 250 cm ein oder lass das Feld leer."
                     : "Gewicht, Geburtsjahr und Geschlecht findest du unter Profil → Body.")
            }
            .listRowBackground(Theme.card)
        }
        .formaScreen()
        .navigationTitle("Kalorienziel")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { input = FoodGoal.heightRange.contains(height) ? FoodText.input(height) : "" }
        .onChange(of: input) { _, _ in invalidHeight = false }
    }

    private func save() {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            height = 0
        } else if let number = FoodText.decimal(input), FoodGoal.heightRange.contains(number) {
            height = number
        } else {
            invalidHeight = true
            return
        }
        dismiss()
    }
}
