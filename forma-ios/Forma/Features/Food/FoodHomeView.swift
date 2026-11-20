import SwiftData
import SwiftUI
import UIKit

/// Tagesziele und Mahlzeiten zuerst, die Werkzeuge darunter.
struct FoodHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var app
    @State private var today = Date.now.startOfDay
    @State private var ringEntrance = 0

    var body: some View {
        NavigationStack {
            FoodHomeContent(day: today, ringEntrance: ringEntrance)
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
        .onChange(of: app.selectedTab, initial: true) { _, tab in
            if tab == .food, !reduceMotion { ringEntrance += 1 }
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
    let ringEntrance: Int
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
    @State private var route: FoodHomeRoute?
    @State private var showTrack = false
    @State private var trackMeal: FoodMeal?
    @State private var deleteError = false

    init(day: Date, ringEntrance: Int) {
        self.day = day
        self.ringEntrance = ringEntrance
        let end = Calendar.forma.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= day && $0.date < end },
                         sort: \FoodEntry.date, order: .reverse)
        _water = Query(filter: #Predicate<FoodWaterEntry> { $0.date >= day && $0.date < end })
        _planned = Query(filter: #Predicate<FoodPlanItem> { $0.day >= day && $0.day < end })
    }

    private var goal: FoodGoal {
        // In der Vorschau kommen Profilwerte aus dem getrennten Beispielspeicher (FoodSettings.previewDefaults).
        let measuredToday = hub.today
        let activity = measuredToday.date == day ? measuredToday.activeEnergy : nil
        return FoodGoal.forDay(day, birthYear: birthYear, weight: weight, height: height, sex: sex, activeEnergy: activity)
    }

    var body: some View {
        let target = goal.target
        // Eigene Ziele aus „Ziele“ gehen vor; sonst die berechneten aus Gewicht und Kalorienziel.
        let proteinTarget = proteinGoal > 0 ? proteinGoal : goal.proteinGrams
        let carbTarget = carbsGoal > 0 ? carbsGoal : goal.carbGrams
        let planOpen = planned.filter { $0.loggedAt == nil }.count
        ScrollViewReader { proxy in
            List {
                Section {
                    Button { route = .goals } label: {
                        FoodHero(entries: entries, target: target, proteinGoal: proteinTarget, carbGoal: carbTarget)
                            .id(ringEntrance)
                    }
                    .buttonStyle(.plain)
                    .id("food.top")
                    .accessibilityHint("Öffnet die Ziele")
                    if hub.isSample { SampleDataBadge() }
                    fiberCard(goal: goal.fiberGrams)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                ForEach(FoodMeal.allCases) { meal in
                    mealSection(meal)
                }

                if planOpen > 0 {
                    Section { FoodPlanTodayCard() }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    DashboardCard {
                        VStack(spacing: 0) {
                            utilityRows(planOpen: planOpen)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .contentMargins(.top, Space.s1, for: .scrollContent)
            .listStyle(.plain)
            .contentMargins(.horizontal, Space.page, for: .scrollContent)
            .listSectionSpacing(Space.s3)
            .formaScreen()
            .refreshable { await hub.syncAndNotify(background: false) }
            // Doppeltipp auf den Tab bringt das System nach oben; das hier fängt nur den Wechsel des Tages auf.
            .onChange(of: day) { _, _ in proxy.scrollTo("food.top", anchor: .top) }
        }
        .navigationDestination(item: $route) { route in
            switch route {
            case .water: FoodWaterView()
            case .fasting: FoodFastingView()
            case .weight: FoodWeightView()
            case .plan: FoodPlanView(standalone: false)
            case .goals: FoodGoalsView(target: target, proteinAuto: goal.proteinGrams, carbsAuto: goal.carbGrams)
            }
        }
        .sheet(isPresented: $showTrack) { FoodTrackSheet(meal: trackMeal) }
        .alert("Eintrag konnte nicht gelöscht werden", isPresented: $deleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Der Eintrag bleibt im Tagebuch. Versuch es erneut.")
        }
    }

    private func fiberCard(goal: Double) -> some View {
        let values = entries.map(\.fiber)
        let total = FoodSum(values).known
        return DashboardCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Ballaststoffe", systemImage: "leaf")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Space.s2)
                    Text("\(FoodAmountText.text(values)) von \(FoodText.number(goal)) g")
                        .font(.formaValue.monospacedDigit())
                }
                ProgressLine(fraction: goal > 0 ? total / goal : 0, color: Theme.younger, height: 4)
            }
            .padding(Space.s4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ballaststoffe")
        .accessibilityValue("\(FoodAmountText.text(values)) von \(FoodText.number(goal)) Gramm")
    }

    @ViewBuilder private func utilityRows(planOpen: Int) -> some View {
        let drunk = water.reduce(0) { $0 + $1.milliliters }
        let active = fasts.first { $0.end == nil }
        utility("Wasser", icon: "drop.fill", tint: Theme.strain, value: FoodText.liters(drunk), destination: .water)
        RowDivider()
        TimelineView(.everyMinute) { tick in
            let state = active.map { FoodTracking.fast(start: $0.start, end: nil, hours: $0.targetHours, now: tick.date) }
            utility("Fasten", icon: "timer", tint: Theme.warning, value: state.map { FoodText.clock($0.elapsed) }, destination: .fasting)
        }
        RowDivider()
        utility("Plan", icon: "calendar", tint: Theme.sleep, value: planOpen > 0 ? "\(planOpen) offen" : nil, destination: .plan)
        RowDivider()
        utility("Gewicht", icon: "scalemass.fill", tint: Theme.older,
                value: weights.first.map { "\(FoodText.number($0.kilograms, digits: 1)) kg" }, destination: .weight)
    }

    private func utility(_ title: String, icon: String, tint: Color, value: String?, destination: FoodHomeRoute) -> some View {
        Button { route = destination } label: {
            HStack(spacing: Space.s3) {
                Label(title, systemImage: icon).foregroundStyle(tint)
                Spacer(minLength: Space.s2)
                if let value { Text(value).foregroundStyle(Theme.textSecondary).monospacedDigit() }
            }
            .font(.formaCaptionStrong)
            .padding(.horizontal, Space.s4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mealSection(_ meal: FoodMeal) -> some View {
        let items = entries.filter { $0.meal == meal }
        let logged = FoodAmountText.text(items.map(\.energy))
        let plannedItems = planned.filter { $0.meal == meal }
        let plannedKcal = plannedItems.isEmpty ? nil : FoodAmountText.text(plannedItems.map { $0.entry?.kcal })
        return Section {
            mealHeader(meal, logged: logged, planned: plannedKcal)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
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
        }
    }

    private func mealHeader(_ meal: FoodMeal, logged: String, planned: String?) -> some View {
        DashboardCard {
            HStack(spacing: Space.s2) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(meal.title).font(.formaRowTitle)
                    Text("\(logged) kcal erfasst").font(.formaCaptionStrong.monospacedDigit())
                    if let planned {
                        Text("\(planned) kcal geplant").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: Space.s1)
                Button {
                    trackMeal = meal
                    showTrack = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("\(meal.title) hinzufügen")
            }
            .padding(.leading, Space.s4)
            .padding(.trailing, Space.s2)
            .padding(.vertical, Space.s2)
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
    let proteinGoal: Double
    let carbGoal: Double
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var showProgress: Bool { revealed || reduceMotion }

    var body: some View {
        let energy = FoodSum(entries.map(\.energy))
        let protein = FoodSum(entries.map(\.protein))
        let carbs = FoodSum(entries.map(\.carbohydrates))
        VStack(spacing: Space.s3) {
            rings(energy, protein, carbs)
            let logged = FoodAmountText.text(entries.map(\.energy))
            Text(target > 0 ? "\(logged) von \(FoodText.number(target)) kcal erfasst" : "\(logged) kcal erfasst")
                .font(.formaCaptionStrong.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, Space.s2)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            revealed = true
        }
    }

    private func rings(_ energy: FoodSum, _ protein: FoodSum, _ carbs: FoodSum) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: Space.s4) {
                    calories(energy, size: 180)
                    HStack(alignment: .top, spacing: Space.s4) {
                        macro("Protein", protein, values: entries.map(\.protein), goal: proteinGoal, tint: Theme.younger, size: 110)
                        macro("Kohlenhydrate", carbs, values: entries.map(\.carbohydrates), goal: carbGoal, tint: Theme.warning, size: 110)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    row(energy, protein, carbs, side: 92, middle: 152, spacing: Space.s1)
                    row(energy, protein, carbs, side: 80, middle: 132, spacing: Space.s1)
                }
            }
        }
    }

    private func row(_ energy: FoodSum, _ protein: FoodSum, _ carbs: FoodSum,
                     side: CGFloat, middle: CGFloat, spacing: CGFloat) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            macro("Protein", protein, values: entries.map(\.protein), goal: proteinGoal, tint: Theme.younger, size: side)
            calories(energy, size: middle)
            macro("Kohlenhydrate", carbs, values: entries.map(\.carbohydrates), goal: carbGoal, tint: Theme.warning, size: side)
        }
    }

    private func calories(_ energy: FoodSum, size: CGFloat) -> some View {
        let consumed = energy.known
        let left = energy.remaining(of: target)
        let over = (left ?? 0) < 0
        return FoodRing(fraction: showProgress && target > 0 ? consumed / target : 0,
                        tint: over ? Theme.older : Theme.strain, lineWidth: size > 150 ? 14 : 11) {
            VStack(spacing: 2) {
                Text(!showProgress && energy.complete ? "0" : (left.map { FoodText.number(abs($0)) } ?? FoodAmountText.text(entries.map(\.energy))))
                    .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .formaNumberTransition(showProgress ? abs(left ?? consumed) : 0)
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

    private func macro(_ title: String, _ sum: FoodSum, values: [Double?], goal: Double, tint: Color, size: CGFloat) -> some View {
        let grams = sum.known
        return VStack(spacing: Space.s2) {
            FoodRing(fraction: showProgress && goal > 0 ? grams / goal : 0, tint: tint, lineWidth: size > 100 ? 11 : 9) {
                Text(!showProgress && sum.complete ? "0" : FoodAmountText.text(values))
                    .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .formaNumberTransition(showProgress ? grams : 0)
                    .padding(.horizontal, Space.s2)
            }
            .frame(width: size, height: size)
            Text(title)
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(sum.complete ? "" : "mindestens ")\(FoodText.number(grams)) von \(FoodText.number(goal)) Gramm")
    }
}

/// Summen mit Lücken: ohne Einträge „0“, ganz unbekannt „–“, teilweise bekannt „≥ n“.
enum FoodAmountText {
    static func text(_ values: [Double?]) -> String {
        guard !values.isEmpty else { return "0" }
        let known = values.compactMap { $0 }.filter(\.isFinite)
        guard !known.isEmpty else { return "–" }
        return (isPartial(values) ? "≥ " : "") + FoodText.number(known.reduce(0, +))
    }

    /// Mindestens ein Eintrag hat keinen (gültigen) Wert.
    static func isPartial(_ values: [Double?]) -> Bool {
        !values.isEmpty && !values.allSatisfy { $0?.isFinite == true }
    }
}
