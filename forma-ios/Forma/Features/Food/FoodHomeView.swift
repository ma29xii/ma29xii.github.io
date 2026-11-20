import SwiftData
import SwiftUI
import UIKit

/// Food-Tab (F7-05): eine Frage – „Wie stehe ich heute?“. Oben eine Zahl, darunter die Zeitleiste des Tages,
/// unten ein einziger „Erfassen“-Knopf.
struct FoodHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var app
    @State private var today = Date.now.startOfDay
    @State private var entrance = 0

    var body: some View {
        NavigationStack {
            FoodHomeContent(day: today, entrance: entrance)
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
            if tab == .food, !reduceMotion { entrance += 1 }
        }
    }

    private func updateDay() { today = Date.now.startOfDay }
}

enum FoodHomeRoute: Hashable, Identifiable {
    case water, fasting, weight, plan, shopping, goals
    var id: Self { self }
}

private enum FoodCaptureMethod: String, Identifiable {
    case scan, photo, search
    var id: String { rawValue }
}

private struct FoodHomeContent: View {
    let day: Date
    let entrance: Int
    @Query private var entries: [FoodEntry]
    @Query private var water: [FoodWaterEntry]
    @Query private var planned: [FoodPlanItem]
    @Query(sort: \FoodFast.start, order: .reverse) private var fasts: [FoodFast]
    @Query(sort: \FoodWeightEntry.date, order: .reverse) private var weights: [FoodWeightEntry]
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @AppStorage("forma.birthYear") private var birthYear = 0
    @AppStorage("forma.sex") private var sex = BiologicalSex.unknown.rawValue
    @AppStorage(FoodSettings.bodyWeightKey) private var weight = 0.0
    @AppStorage(FoodGoal.heightKey) private var height = 0.0
    @AppStorage(FoodSettings.proteinGoalKey) private var proteinGoal = 0.0
    @AppStorage(FoodSettings.carbsGoalKey) private var carbsGoal = 0.0
    @AppStorage(FoodSettings.fatGoalKey) private var fatGoal = 0.0
    @AppStorage(FoodSettings.waterGoalKey) private var waterGoal = FoodSettings.defaultWaterMl
    @AppStorage(MealPlanSettings.mealsKey) private var mealsPerDay = MealPlanSettings.defaultMeals
    @State private var route: FoodHomeRoute?
    @State private var capture: FoodCaptureMethod?
    @State private var waterTaps = 0
    @State private var deleteError = false
    @State private var saveError = false

    init(day: Date, entrance: Int) {
        self.day = day
        self.entrance = entrance
        let end = Calendar.forma.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= day && $0.date < end },
                         sort: \FoodEntry.date, order: .forward)
        _water = Query(filter: #Predicate<FoodWaterEntry> { $0.date >= day && $0.date < end },
                       sort: \FoodWaterEntry.date)
        _planned = Query(filter: #Predicate<FoodPlanItem> { $0.day >= day && $0.day < end && $0.loggedAt == nil })
    }

    private var goal: FoodGoal {
        // In der Vorschau kommen Profilwerte aus dem getrennten Beispielspeicher (FoodSettings.previewDefaults).
        let measuredToday = hub.today
        let activity = measuredToday.date == day ? measuredToday.activeEnergy : nil
        return FoodGoal.forDay(day, birthYear: birthYear, weight: weight, height: height, sex: sex, activeEnergy: activity)
    }

    private static func entryID(_ entry: FoodEntry) -> String { "entry-\(String(describing: entry.persistentModelID))" }

    var body: some View {
        let current = goal
        let target = current.target
        let macroGoals = FoodMacroGoals.resolve(kcal: target, protein: proteinGoal, carbs: carbsGoal, fat: fatGoal)
        // Eigene Ziele aus „Ziele“ gehen vor; sonst die berechneten aus Gewicht und Kalorienziel.
        let goals = FoodMacroGoals(protein: proteinGoal > 0 ? proteinGoal : current.proteinGrams,
                                   carbs: carbsGoal > 0 ? carbsGoal : current.carbGrams, fat: macroGoals.fat)
        let loggedItems = entries.map {
            FoodTimelineItem(id: Self.entryID($0), kind: .logged, time: $0.date, title: $0.name, kcal: $0.energy)
        }
        let items = FoodTimeline.merge(loggedItems, FoodTimeline.planned(planned.compactMap { $0.entry }))
        let prominent = FoodTimeline.isProminent(itemCount: items.count, mealsPerDay: mealsPerDay)
        let drunk = water.reduce(0) { $0 + $1.milliliters }
        let waterTarget = FoodSettings.waterRange.contains(waterGoal) ? waterGoal : FoodSettings.defaultWaterMl
        let activeFast = fasts.first { $0.end == nil }

        List {
            VStack(spacing: Space.s4) {
                if hub.isSample { SampleDataBadge() }
                Button { route = .goals } label: {
                    FoodDayHero(energy: FoodSum(entries.map(\.energy)),
                                protein: FoodSum(entries.map(\.protein)),
                                carbs: FoodSum(entries.map(\.carbohydrates)),
                                fat: FoodSum(entries.map(\.fat)),
                                target: target, goals: goals)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Öffnet die Ziele")
                .accessibilityIdentifier("food.hero")
            }
            .id(entrance)
            .formaAppear(index: 0)
            .foodRow(top: Space.s3, bottom: Space.s5)

            FoodDayStrip(waterMl: drunk, waterTarget: waterTarget,
                         fast: activeFast.map { (start: $0.start, hours: $0.targetHours) },
                         canRemoveWater: !water.isEmpty,
                         addWater: addWater, removeWater: removeWater, open: { route = $0 })
                .id(entrance)
                .formaAppear(index: 1)
                .foodRow(top: 0, bottom: Space.s5)

            if items.isEmpty {
                Text("Noch nichts erfasst")
                    .font(.formaBody)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .foodRow()
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    timelineRow(item, index: index, count: items.count, prominent: prominent)
                }
            }

            FoodDayFooter(weightText: weights.first.map { "\(FoodText.number($0.kilograms, digits: 1)) kg" },
                          open: { route = $0 })
                .foodRow(top: Space.s5, bottom: Space.s2)
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, 1)
        .formaScreen()
        .animation(reduceMotion ? nil : FormaMotion.appear, value: items.map(\.id))
        .refreshable { await hub.syncAndNotify(background: false) }
        .sensoryFeedback(trigger: entries.count) { old, new in new > old ? .success : nil }
        .sensoryFeedback(.increase, trigger: waterTaps)
        .safeAreaInset(edge: .bottom) { captureButton }
        .navigationDestination(item: $route) { route in
            switch route {
            case .water: FoodWaterView()
            case .fasting: FoodFastingView()
            case .weight: FoodWeightView()
            case .plan: FoodPlanView(standalone: false)
            case .shopping: FoodPlanView(standalone: false, startInShopping: true)
            case .goals: FoodGoalsView(target: target, proteinAuto: current.proteinGrams, carbsAuto: current.carbGrams)
            }
        }
        .sheet(item: $capture) { method in
            switch method {
            case .scan: FoodScanSheet()
            case .photo: FoodPhotoSheet()
            case .search: FoodScanSheet(startInSearch: true)
            }
        }
        .alert("Eintrag konnte nicht gelöscht werden", isPresented: $deleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Der Eintrag bleibt im Tagebuch. Versuch es erneut.")
        }
        .alert("Das hat nicht geklappt", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Die Änderung konnte nicht gespeichert werden. Versuch es noch einmal.")
        }
    }

    // MARK: Zeitleiste

    @ViewBuilder private func timelineRow(_ item: FoodTimelineItem, index: Int, count: Int, prominent: Bool) -> some View {
        let row = FoodTimelineRow(item: item, isFirst: index == 0, isLast: index == count - 1, prominent: prominent)
        if item.isPlanned {
            let plan = planned.first { "plan-" + $0.uid.uuidString == item.id }
            Button { if let plan { confirm(plan) } } label: { row }
                .buttonStyle(FormaPressStyle(scale: 0.98))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Geplant: \(item.title)")
                .accessibilityValue(spoken(item))
                .accessibilityHint("Trägt es als gegessen ein")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("food.planned")
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { if let plan { remove(plan) } } label: {
                        Label("Aus Plan nehmen", systemImage: "trash")
                    }
                }
                .transition(.opacity)
                .foodRow()
        } else {
            let entry = entries.first { Self.entryID($0) == item.id }
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityValue(spoken(item))
                .accessibilityIdentifier("food.entry")
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { if let entry { delete(entry) } } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) { if let entry { delete(entry) } } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
                .accessibilityAction(named: Text("Löschen")) { if let entry { delete(entry) } }
                .transition(.move(edge: .top).combined(with: .opacity))
                .foodRow()
        }
    }

    private func spoken(_ item: FoodTimelineItem) -> String {
        let kcal = item.kcal.map { "\(FoodText.number($0)) Kilokalorien" } ?? "keine Kalorienangabe"
        return "\(Format.clock(item.time)), \(kcal)"
    }

    // MARK: Erfassen

    /// Der eine schwebende Knopf: Scannen, Foto oder Suchen als kleines Menü.
    private var captureButton: some View {
        Menu {
            Button { capture = .scan } label: { Label("Scannen", systemImage: "barcode.viewfinder") }
            Button { capture = .photo } label: { Label("Foto", systemImage: "camera.viewfinder") }
            Button { capture = .search } label: { Label("Suchen", systemImage: "magnifyingglass") }
        } label: {
            Label("Erfassen", systemImage: "plus")
                .labelStyle(.titleAndIcon)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .padding(.horizontal, Space.s5)
                .frame(minHeight: 56)
        }
        .buttonStyle(.glassProminent)
        .padding(.bottom, Space.s2)
        .accessibilityIdentifier("food.capture")
    }

    // MARK: Aktionen

    private func addWater() {
        let entry = FoodWaterEntry(milliliters: FoodSettings.glassMl)
        changeWater { context.insert(entry) }
        waterTaps += 1
    }

    private func removeWater() {
        guard let last = water.last else { return }
        changeWater { context.delete(last) }
    }

    private func changeWater(_ block: () -> Void) {
        do {
            try FoodEntry.saveChange(in: context, block)
            // Widget und Kontrollzentrum zeigen denselben Tagesstand.
            WaterWidgetSync.sync(in: context, enabled: !app.isDemo)
        } catch {
            saveError = true
        }
    }

    private func confirm(_ item: FoodPlanItem) {
        do { try FoodPlanStore.log([item], in: context) } catch { saveError = true }
    }

    private func remove(_ item: FoodPlanItem) {
        do {
            try FoodEntry.saveChange(in: context) { context.delete(item) }
        } catch {
            saveError = true
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

private extension View {
    /// Zeile ohne Fläche, Linie und Standardabstand: der Inhalt bestimmt alles.
    func foodRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: Space.page, bottom: bottom, trailing: Space.page))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
