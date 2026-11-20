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
    @AppStorage(FoodSettings.waterGoalKey) private var waterGoal = FoodSettings.defaultWaterMl
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // Eingerückte Gruppen statt `.plain`: dort zeichnete die Liste Abschnittslinien über und unter dem Kopf.
            List {
                Section {
                    VStack(spacing: Space.s5) {
                        Button { route = .goals } label: {
                            FoodHero(entries: entries, target: target, proteinGoal: proteinTarget, carbGoal: carbTarget)
                                .id(ringEntrance)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Öffnet die Ziele")
                        fiberLine(goal: goal.fiberGrams)
                        if hub.isSample { SampleDataBadge() }
                    }
                    .padding(.top, Space.s2)
                    .padding(.bottom, Space.s3)
                    .id("food.top")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(FoodMeal.allCases) { meal in
                    mealSection(meal)
                }

                if planOpen > 0 {
                    Section { FoodPlanTodayCard() }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section { actionTiles(planOpen: planOpen) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Space.gap)
            .formaScreen()
            .refreshable { await hub.syncAndNotify(background: false) }
            .sensoryFeedback(trigger: entries.count) { old, new in new > old ? .success : nil }
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

    /// Ballaststoffe dezent als schmale Zeile unter den Ringen.
    private func fiberLine(goal: Double) -> some View {
        let values = entries.map(\.fiber)
        let total = FoodSum(values).known
        return HStack(spacing: Space.s3) {
            Text("Ballaststoffe")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
            ProgressLine(fraction: goal > 0 ? total / goal : 0, color: Theme.textSecondary, height: 3)
                .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: total)
            Text("\(FoodAmountText.text(values)) / \(FoodText.number(goal)) g")
                .font(.formaCaption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .formaNumberTransition(total)
        }
        .padding(.horizontal, Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ballaststoffe")
        .accessibilityValue("\(FoodAmountText.text(values)) von \(FoodText.number(goal)) Gramm")
    }

    /// Wasser, Fasten, Plan und Gewicht als gleich hohe Kacheln, zwei pro Reihe.
    private func actionTiles(planOpen: Int) -> some View {
        let drunk = water.reduce(0) { $0 + $1.milliliters }
        let waterTarget = FoodSettings.waterRange.contains(waterGoal) ? waterGoal : FoodSettings.defaultWaterMl
        let active = fasts.first { $0.end == nil }
        let columns = Array(repeating: GridItem(.flexible(), spacing: Space.gap),
                            count: typeSize.isAccessibilitySize ? 1 : 2)
        return LazyVGrid(columns: columns, spacing: Space.gap) {
            tile("Wasser", icon: "drop.fill", tint: Theme.strain,
                 value: drunk > 0 ? FoodText.liters(drunk) : nil,
                 progress: drunk / waterTarget, destination: .water)
            TimelineView(.everyMinute) { tick in
                let state = active.map { FoodTracking.fast(start: $0.start, end: nil, hours: $0.targetHours, now: tick.date) }
                tile("Fasten", icon: "timer", tint: Theme.warning,
                     value: state.map { FoodText.clock($0.elapsed) },
                     progress: state?.fraction,
                     destination: .fasting)
            }
            tile("Plan", icon: "calendar", tint: Theme.sleep,
                 value: planOpen > 0 ? "\(planOpen) offen" : nil, progress: nil, destination: .plan)
            tile("Gewicht", icon: "scalemass.fill", tint: Theme.older,
                 value: weights.first.map { "\(FoodText.number($0.kilograms, digits: 1)) kg" },
                 progress: nil, destination: .weight)
        }
    }

    private func tile(_ title: String, icon: String, tint: Color, value: String?,
                      progress: Double?, destination: FoodHomeRoute) -> some View {
        Button { route = destination } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Label(title, systemImage: icon)
                        .font(.formaCaptionStrong)
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                    Text(value ?? "–")
                        .font(.formaNumber)
                        .foregroundStyle(value == nil ? Theme.textTertiary : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    // Gleiche Höhe für alle Kacheln: ohne Fortschritt bleibt die Linie unsichtbar.
                    ProgressLine(fraction: progress ?? 0, color: tint, height: 3)
                        .opacity(progress == nil ? 0 : 1)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: progress ?? 0)
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            }
            .contentShape(.rect(cornerRadius: Radius.plate))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value ?? "Kein Eintrag")
    }

    private func mealSection(_ meal: FoodMeal) -> some View {
        let items = entries.filter { $0.meal == meal }
        let plannedItems = planned.filter { $0.meal == meal }
        let plannedKcal = plannedItems.isEmpty ? nil : FoodAmountText.text(plannedItems.map { $0.entry?.kcal })
        return Section {
            mealHeader(meal, items: items, planned: plannedKcal)
                .listRowInsets(EdgeInsets(top: Space.s2, leading: Space.s4, bottom: Space.s2, trailing: Space.s1))
            ForEach(items) { entry in
                FoodLogRow(entry: entry)
                    .listRowInsets(EdgeInsets(top: Space.s2, leading: Space.s4, bottom: Space.s2, trailing: Space.s4))
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
        .listRowBackground(Theme.card)
        .listRowSeparatorTint(Theme.hairline)
    }

    /// Kopf einer Mahlzeitenkarte: Titel, erfasste kcal groß, geplante klein daneben, rechts der Knopf.
    private func mealHeader(_ meal: FoodMeal, items: [FoodEntry], planned: String?) -> some View {
        let energy = items.map(\.energy)
        let logged = FoodAmountText.text(energy)
        return HStack(spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(meal.title).formaLabelStyle()
                HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                    Text(logged)
                        .font(.formaNumber)
                        .foregroundStyle(items.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                        .formaNumberTransition(FoodSum(energy).known)
                    Text("kcal")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textSecondary)
                    if let planned {
                        Text("/ \(planned) geplant")
                            .font(.formaCaption.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.leading, Space.s1)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(meal.title)
            .accessibilityValue("\(logged) Kilokalorien erfasst" + (planned.map { ", \($0) geplant" } ?? ""))
            Spacer(minLength: Space.s1)
            Button {
                trackMeal = meal
                showTrack = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Theme.cardRaised, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(meal.title) hinzufügen")
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
        rings(energy, protein, carbs)
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
        // Unterste Textzeilen auf einer Linie: die kleinen Ringe sitzen dadurch fast mittig neben dem großen.
        HStack(alignment: .lastTextBaseline, spacing: spacing) {
            macro("Protein", protein, values: entries.map(\.protein), goal: proteinGoal, tint: Theme.younger, size: side)
            calories(energy, size: middle)
            macro("Kohlenhydrate", carbs, values: entries.map(\.carbohydrates), goal: carbGoal, tint: Theme.warning, size: side)
        }
    }

    private func calories(_ energy: FoodSum, size: CGFloat) -> some View {
        let consumed = energy.known
        let left = energy.remaining(of: target)
        let over = (left ?? 0) < 0
        return VStack(spacing: Space.s2) {
            FoodRing(fraction: showProgress && target > 0 ? consumed / target : 0,
                     tint: over ? Theme.older : Theme.strain, lineWidth: size > 150 ? 14 : 11) {
                VStack(spacing: 2) {
                    Text(!showProgress && energy.complete ? "0" : (left.map { FoodText.number(abs($0)) } ?? FoodAmountText.text(entries.map(\.energy))))
                        .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
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
            Text(target > 0 ? "\(FoodAmountText.text(entries.map(\.energy))) / \(FoodText.number(target)) kcal" : " ")
                .font(.formaCaption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .formaNumberTransition(showProgress ? consumed : 0)
        }
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
            VStack(spacing: 2) {
                Text(title)
                    .font(.formaCaptionStrong)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goal > 0 ? "von \(FoodText.number(goal)) g" : " ")
                    .font(.formaCaption.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
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
