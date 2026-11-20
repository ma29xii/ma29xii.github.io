import SwiftData
import SwiftUI
import UIKit

struct FoodLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Date.now.startOfDay
    @State private var showScanner = false
    @State private var showPhoto = false

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
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { showPhoto = true } label: { Image(systemName: "camera") }
                            .accessibilityLabel("Essen fotografieren")
                        Button { showScanner = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Lebensmittel hinzufügen")
                    }
                }
        }
        .sheet(isPresented: $showScanner) { FoodScanSheet() }
        .sheet(isPresented: $showPhoto) { FoodPhotoSheet() }
        // Nach den Blättern, damit auch sie in der Vorschau den getrennten Speicher nutzen.
        .foodSettingsStore()
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in updateDay() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in updateDay() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { updateDay() }
        }
    }

    private func updateDay() { today = Date.now.startOfDay }
}

private enum FoodRoute: Hashable, Identifiable {
    case water, fasting, weight, goals
    var id: Self { self }
}

/// Tagesübersicht: ein Ring, drei Makro-Balken, Wasser/Fasten/Gewicht kompakt, darunter die Mahlzeiten.
private struct FoodDayView: View {
    let day: Date
    @Query private var entries: [FoodEntry]
    @Query private var water: [FoodWaterEntry]
    @Query(sort: \FoodFast.start, order: .reverse) private var fasts: [FoodFast]
    @Query(sort: \FoodWeightEntry.date, order: .reverse) private var weights: [FoodWeightEntry]
    @Query(FoodLibrary.recentDescriptor) private var history: [FoodEntry]
    @Environment(\.modelContext) private var context
    @Environment(DataHub.self) private var hub
    @AppStorage("forma.birthYear") private var birthYear = 0
    @AppStorage("forma.sex") private var sex = BiologicalSex.unknown.rawValue
    @AppStorage(FoodSettings.bodyWeightKey) private var weight = 0.0
    @AppStorage(FoodGoal.heightKey) private var height = 0.0
    @AppStorage(FoodSettings.proteinGoalKey) private var proteinGoal = 0.0
    @AppStorage(FoodSettings.carbsGoalKey) private var carbsGoal = 0.0
    @AppStorage(FoodSettings.fatGoalKey) private var fatGoal = 0.0
    @AppStorage(FoodSettings.waterGoalKey) private var waterGoal = FoodSettings.defaultWaterMl
    @State private var route: FoodRoute?
    @State private var deleteError = false

    init(day: Date) {
        self.day = day
        let end = Calendar.forma.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        _entries = Query(
            filter: #Predicate<FoodEntry> { $0.date >= day && $0.date < end },
            sort: \FoodEntry.date, order: .reverse
        )
        _water = Query(filter: #Predicate<FoodWaterEntry> { $0.date >= day && $0.date < end })
    }

    private var goal: FoodGoal {
        // In der Vorschau kommen Profilwerte aus dem getrennten Beispielspeicher (FoodSettings.previewDefaults).
        let currentYear = Calendar.forma.component(.year, from: day)
        let age = (1900...currentYear).contains(birthYear) ? currentYear - birthYear : nil
        let measuredToday = hub.today
        let activity = measuredToday.date == day ? measuredToday.activeEnergy : nil
        return FoodGoal(weightKg: weight, heightCm: height, age: age,
                        sex: BiologicalSex(rawValue: sex) ?? .unknown, activeEnergy: activity)
    }

    var body: some View {
        let target = goal.target
        let macros = FoodMacroGoals.resolve(kcal: target, protein: proteinGoal, carbs: carbsGoal, fat: fatGoal)
        List {
            if hub.isSample {
                Section { SampleDataBadge() }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                Button { route = .goals } label: {
                    FoodLogDayHero(entries: entries, target: target, macros: macros,
                                streak: FoodTracking.streak(dates: history.map(\.date)))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Öffnet die Ziele")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.s2) { habitTiles }
                    VStack(spacing: Space.s2) { habitTiles }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ForEach(FoodMeal.allCases) { meal in
                mealSection(meal)
            }
        }
        .listSectionSpacing(Space.s3)
        .formaScreen()
        .navigationDestination(item: $route) { route in
            switch route {
            case .water: FoodWaterView()
            case .fasting: FoodFastingView()
            case .weight: FoodWeightView()
            case .goals: FoodGoalsView(target: target)
            }
        }
        .alert("Eintrag konnte nicht gelöscht werden", isPresented: $deleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Der Eintrag bleibt im Tagebuch. Versuch es erneut.")
        }
    }

    @ViewBuilder private var habitTiles: some View {
        let drunk = water.reduce(0) { $0 + $1.milliliters }
        let safeWater = FoodSettings.waterRange.contains(waterGoal) ? waterGoal : FoodSettings.defaultWaterMl
        let active = fasts.first { $0.end == nil }
        FoodHabitTile(title: "Wasser", icon: "drop.fill", tint: Theme.strain,
                      value: FoodText.liters(drunk), fraction: drunk / safeWater) { route = .water }
        TimelineView(.everyMinute) { tick in
            let state = active.map { FoodTracking.fast(start: $0.start, end: nil, hours: $0.targetHours, now: tick.date) }
            FoodHabitTile(title: "Fasten", icon: "timer", tint: state?.reached == true ? Theme.younger : Theme.warning,
                          value: state.map { FoodText.clock($0.elapsed) } ?? "Start",
                          fraction: state?.fraction ?? 0) { route = .fasting }
        }
        FoodHabitTile(title: "Gewicht", icon: "scalemass.fill", tint: Theme.sleep,
                      value: weights.first.map { "\(FoodText.number($0.kilograms, digits: 1)) kg" } ?? "–",
                      fraction: nil) { route = .weight }
    }

    private func mealSection(_ meal: FoodMeal) -> some View {
        let items = entries.filter { $0.meal == meal }
        let kcal = FoodSum(items.map(\.energy))
        return Section {
            if items.isEmpty {
                Text("Noch nichts eingetragen")
                    .font(.formaBody)
                    .foregroundStyle(Theme.textTertiary)
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
            HStack {
                Text(meal.title).formaLabelStyle()
                Spacer()
                if kcal.known > 0 {
                    Text("\(kcal.complete ? "" : "≥ ")\(FoodText.number(kcal.known)) kcal")
                        .font(.formaCaptionStrong)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
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

/// Kalorienring mit Restmenge, drei Makro-Balken gegen ihre Ziele, Serie.
private struct FoodLogDayHero: View {
    let entries: [FoodEntry]
    let target: Double
    let macros: FoodMacroGoals
    let streak: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Fehlende Energie zählt nicht als 0: Summe ist dann ein Mindestwert, das Restbudget bleibt offen.
        let energy = FoodSum(entries.map(\.energy))
        let consumed = energy.known
        let left = energy.remaining(of: target)
        let size: CGFloat = typeSize.isAccessibilitySize ? 160 : 196
        VStack(spacing: Space.s5) {
            HStack {
                Text("Heute").formaLabelStyle()
                Spacer()
                if streak > 0 {
                    Label("\(streak) \(streak == 1 ? "Tag" : "Tage")", systemImage: "flame.fill")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.warning)
                        .accessibilityLabel("Serie: \(streak) Tage in Folge")
                }
            }
            FoodRing(fraction: target > 0 ? consumed / target : 0,
                     tint: left.map { $0 < 0 ? Theme.older : Theme.younger } ?? Theme.textSecondary, lineWidth: 14) {
                VStack(spacing: 2) {
                    if let left {
                        Text(FoodText.number(abs(left)))
                            .font(.formaDisplay)
                            .formaNumberTransition(left)
                        Text(left < 0 ? "kcal zu viel" : "kcal übrig")
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text((energy.complete ? "" : "≥ ") + FoodText.number(consumed))
                            .font(.formaDisplay)
                            .formaNumberTransition(consumed)
                        Text(energy.complete ? "kcal gegessen" : "kcal, nicht alle Angaben bekannt")
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Space.s4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kalorien")
                .accessibilityValue("\(energy.complete ? "" : "mindestens ")\(FoodText.number(consumed)) von \(FoodText.number(target)) Kilokalorien gegessen")
            }
            .frame(width: size, height: size)

            HStack(spacing: Space.s6) {
                stat("Gegessen", consumed, atLeast: !energy.complete)
                stat("Ziel", target)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Space.s4) { macroBars }
                VStack(spacing: Space.s3) { macroBars }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
        .contentShape(Rectangle())
    }

    private func stat(_ title: String, _ value: Double, atLeast: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text((atLeast ? "≥ " : "") + FoodText.number(value)).font(.formaValue).monospacedDigit()
            Text(title)
                .font(.formaMicro)
                .tracking(Tracking.micro)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var macroBars: some View {
        macro("Eiweiß", FoodSum(entries.map(\.protein)), goal: macros.protein, tint: Theme.younger)
        macro("Kohlenhydrate", FoodSum(entries.map(\.carbohydrates)), goal: macros.carbs, tint: Theme.warning)
        macro("Fett", FoodSum(entries.map(\.fat)), goal: macros.fat, tint: Theme.sleep)
    }

    private func macro(_ title: String, _ sum: FoodSum, goal: Double, tint: Color) -> some View {
        let grams = sum.known
        let prefix = sum.complete ? "" : "≥ "
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.formaCaption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            ProgressLine(fraction: goal > 0 ? grams / goal : 0, color: tint, height: 5)
            Text("\(prefix)\(FoodText.number(grams)) / \(FoodText.number(goal)) g")
                .font(.formaCaptionStrong)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(sum.complete ? "" : "mindestens ")\(FoodText.number(grams)) von \(FoodText.number(goal)) Gramm")
    }
}

struct FoodHabitTile: View {
    let title: String
    let icon: String
    let tint: Color
    let value: String
    let fraction: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(value)
                    .font(.formaSection.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(title).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                if let fraction {
                    ProgressLine(fraction: min(1, max(0, fraction.isFinite ? fraction : 0)), color: tint, height: 3)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityAddTraits(.isButton)
    }
}

/// Kalorien- und Makro-Ziele, Körpergröße.
struct FoodGoalsView: View {
    let target: Double
    /// Berechnete Tagesziele (Gewicht, Kalorienziel); ohne Angabe gilt die einfache Aufteilung.
    var proteinAuto: Double?
    var carbsAuto: Double?

    init(target: Double, proteinAuto: Double? = nil, carbsAuto: Double? = nil) {
        self.target = target
        self.proteinAuto = proteinAuto
        self.carbsAuto = carbsAuto
    }
    @AppStorage(FoodSettings.proteinGoalKey) private var protein = 0.0
    @AppStorage(FoodSettings.carbsGoalKey) private var carbs = 0.0
    @AppStorage(FoodSettings.fatGoalKey) private var fat = 0.0

    var body: some View {
        let split = FoodMacroGoals.automatic(kcal: target)
        let auto = FoodMacroGoals(protein: proteinAuto ?? split.protein, carbs: carbsAuto ?? split.carbs, fat: split.fat)
        Form {
            Section {
                LabeledContent("Kalorien", value: "\(FoodText.number(target)) kcal")
                NavigationLink("Körpergröße") { FoodHeightView() }
                    .frame(minHeight: 44)
            } header: {
                Text("Energie").formaLabelStyle()
            }
            .listRowBackground(Theme.card)

            Section {
                goalRow("Eiweiß", value: $protein, automatic: auto.protein)
                goalRow("Kohlenhydrate", value: $carbs, automatic: auto.carbs)
                goalRow("Fett", value: $fat, automatic: auto.fat)
                if protein > 0 || carbs > 0 || fat > 0 {
                    Button("Automatisch berechnen") {
                        protein = 0
                        carbs = 0
                        fat = 0
                    }
                    .frame(minHeight: 44)
                }
            } header: {
                Text("Makros pro Tag").formaLabelStyle()
            }
            .listRowBackground(Theme.card)
        }
        .formaScreen()
        .navigationTitle("Ziele")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func goalRow(_ title: String, value: Binding<Double>, automatic: Double) -> some View {
        let shown = value.wrappedValue > 0 ? value.wrappedValue : automatic.rounded()
        return Stepper(value: Binding(get: { shown }, set: { value.wrappedValue = min(1_000, max(5, $0)) }),
                       in: 5...1_000, step: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(FoodText.number(shown)) g").font(.formaValue).monospacedDigit()
                if value.wrappedValue <= 0 {
                    Text("auto").font(.formaMicro).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(minHeight: 44)
    }
}

struct FoodLogRow: View {
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
