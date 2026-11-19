import SwiftData
import SwiftUI
import UIKit

/// Tab „Food“ im Today-Stil: in der Mitte groß die Kalorien, links Protein, rechts Kohlenhydrate.
/// Darunter Wasser, Fasten, Plan und Gewicht als Kacheln, dann die Mahlzeiten des Tages.
struct FoodHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Date.now.startOfDay

    var body: some View {
        NavigationStack {
            FoodHomeContent(day: today)
                .navigationTitle("Food")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
                }
        }
        .foodSettingsStore()
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in updateDay() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in updateDay() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { updateDay() }
        }
    }

    private func updateDay() { today = Date.now.startOfDay }
}

private enum FoodHomeRoute: Hashable, Identifiable {
    case water, fasting, weight, plan, goals
    var id: Self { self }
}

private struct FoodHomeContent: View {
    let day: Date
    @Query private var entries: [FoodEntry]
    @Query private var water: [FoodWaterEntry]
    @Query private var planned: [FoodPlanItem]
    @Query(sort: \FoodFast.start, order: .reverse) private var fasts: [FoodFast]
    @Query(sort: \FoodWeightEntry.date, order: .reverse) private var weights: [FoodWeightEntry]
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
    @State private var route: FoodHomeRoute?
    @State private var showTrack = false
    @State private var deleteError = false

    init(day: Date) {
        self.day = day
        let end = Calendar.forma.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= day && $0.date < end },
                         sort: \FoodEntry.date, order: .reverse)
        _water = Query(filter: #Predicate<FoodWaterEntry> { $0.date >= day && $0.date < end })
        _planned = Query(filter: #Predicate<FoodPlanItem> { $0.day >= day && $0.day < end })
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
        let planOpen = planned.filter { $0.loggedAt == nil }.count
        ScrollViewReader { proxy in
            List {
                if hub.isSample {
                    Section { SampleDataBadge() }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    Button { route = .goals } label: {
                        FoodHero(entries: entries, target: target, macros: macros)
                    }
                    .buttonStyle(.plain)
                    .id("food.top")
                    .accessibilityHint("Öffnet die Ziele")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if planOpen > 0 {
                    Section { FoodPlanTodayCard() }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 2), spacing: Space.s2) {
                        habitTiles(planOpen: planOpen)
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
            // Doppeltipp auf den Tab bringt das System nach oben; das hier fängt nur den Wechsel des Tages auf.
            .onChange(of: day) { _, _ in proxy.scrollTo("food.top", anchor: .top) }
        }
        .navigationDestination(item: $route) { route in
            switch route {
            case .water: FoodWaterView()
            case .fasting: FoodFastingView()
            case .weight: FoodWeightView()
            case .plan: FoodPlanView(standalone: false)
            case .goals: FoodGoalsView(target: target)
            }
        }
        .sheet(isPresented: $showTrack) { FoodTrackSheet() }
        .alert("Eintrag konnte nicht gelöscht werden", isPresented: $deleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Der Eintrag bleibt im Tagebuch. Versuch es erneut.")
        }
    }

    @ViewBuilder private func habitTiles(planOpen: Int) -> some View {
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
        FoodHabitTile(title: "Plan", icon: "calendar", tint: Theme.sleep,
                      value: planOpen > 0 ? "\(planOpen) offen" : "Planen", fraction: nil) { route = .plan }
        FoodHabitTile(title: "Gewicht", icon: "scalemass.fill", tint: Theme.older,
                      value: weights.first.map { "\(FoodText.number($0.kilograms, digits: 1)) kg" } ?? "–",
                      fraction: nil) { route = .weight }
    }

    private func mealSection(_ meal: FoodMeal) -> some View {
        let items = entries.filter { $0.meal == meal }
        let kcal = FoodSum(items.map(\.energy))
        return Section {
            ForEach(items) { entry in
                FoodLogRow(entry: entry)
                    .listRowBackground(Theme.card)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { delete(entry) } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                    .contextMenu {
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
                Button { showTrack = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("\(meal.title) hinzufügen")
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

/// Mitte groß die Kalorien, links Protein, rechts Kohlenhydrate. Bei sehr großer Schrift untereinander.
private struct FoodHero: View {
    let entries: [FoodEntry]
    let target: Double
    let macros: FoodMacroGoals
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let energy = FoodSum(entries.map(\.energy))
        let protein = FoodSum(entries.map(\.protein))
        let carbs = FoodSum(entries.map(\.carbohydrates))
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: Space.s4) {
                    calories(energy, size: 180)
                    HStack(alignment: .top, spacing: Space.s4) {
                        macro("Protein", protein, goal: macros.protein, tint: Theme.younger, size: 110)
                        macro("Kohlenhydrate", carbs, goal: macros.carbs, tint: Theme.warning, size: 110)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    row(energy, protein, carbs, side: 92, middle: 152, spacing: Space.s1)
                    row(energy, protein, carbs, side: 80, middle: 132, spacing: Space.s1)
                }
            }
        }
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func row(_ energy: FoodSum, _ protein: FoodSum, _ carbs: FoodSum,
                     side: CGFloat, middle: CGFloat, spacing: CGFloat) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            macro("Protein", protein, goal: macros.protein, tint: Theme.younger, size: side)
            calories(energy, size: middle)
            macro("Kohlenhydrate", carbs, goal: macros.carbs, tint: Theme.warning, size: side)
        }
    }

    private func calories(_ energy: FoodSum, size: CGFloat) -> some View {
        let consumed = energy.known
        let left = energy.remaining(of: target)
        let over = (left ?? 0) < 0
        return FoodRing(fraction: target > 0 ? consumed / target : 0,
                        tint: over ? Theme.older : Theme.strain, lineWidth: size > 150 ? 14 : 11) {
            VStack(spacing: 2) {
                Text(FoodText.number(abs(left ?? consumed)))
                    .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .formaNumberTransition(abs(left ?? consumed))
                Text(left == nil ? "kcal" : (over ? "kcal zu viel" : "kcal übrig"))
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, Space.s3)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kalorien")
        .accessibilityValue("\(energy.complete ? "" : "mindestens ")\(FoodText.number(consumed)) von \(FoodText.number(target)) Kilokalorien gegessen")
    }

    private func macro(_ title: String, _ sum: FoodSum, goal: Double, tint: Color, size: CGFloat) -> some View {
        let grams = sum.known
        return VStack(spacing: Space.s2) {
            FoodRing(fraction: goal > 0 ? grams / goal : 0, tint: tint, lineWidth: size > 100 ? 11 : 9) {
                Text(FoodText.number(grams))
                    .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, Space.s2)
            }
            .frame(width: size, height: size)
            Text(title)
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(sum.complete ? "" : "mindestens ")\(FoodText.number(grams)) von \(FoodText.number(goal)) Gramm")
    }
}
