import Charts
import SwiftData
import SwiftUI

/// Als eigenes Sheet (aus Plus) mit Navigationsleiste und Schließen-Knopf, sonst nur der Inhalt.
struct FoodStandalone<Content: View>: View {
    let standalone: Bool
    let content: Content
    @Environment(\.dismiss) private var dismiss

    init(_ standalone: Bool, @ViewBuilder content: () -> Content) {
        self.standalone = standalone
        self.content = content()
    }

    var body: some View {
        if standalone {
            NavigationStack {
                content.toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Schließen")
                    }
                }
            }
        } else {
            content
        }
    }
}

/// Großer Ring mit Fortschritt; Mitte frei für Zahlen.
struct FoodRing<Center: View>: View {
    let fraction: Double
    let tint: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let value = min(1, max(0, fraction.isFinite ? fraction : 0))
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(value))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(value > 0 ? 0.35 : 0), radius: 8)
            center
        }
        .padding(lineWidth / 2)
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: value)
    }
}

// MARK: - Wasser

struct FoodWaterView: View {
    var standalone = false
    @Environment(\.modelContext) private var context
    @AppStorage(FoodSettings.waterGoalKey) private var goal = FoodSettings.defaultWaterMl
    @Query private var entries: [FoodWaterEntry]
    @State private var saveError = false

    init(standalone: Bool = false) {
        self.standalone = standalone
        let start = Date.now.startOfDay
        _entries = Query(filter: #Predicate<FoodWaterEntry> { $0.date >= start }, sort: \FoodWaterEntry.date)
    }

    private var total: Double { entries.reduce(0) { $0 + $1.milliliters } }
    private var safeGoal: Double { FoodSettings.waterRange.contains(goal) ? goal : FoodSettings.defaultWaterMl }
    private var glasses: Int { Int((safeGoal / FoodSettings.glassMl).rounded(.up)) }
    private var filled: Int { Int((total / FoodSettings.glassMl).rounded(.down)) }

    var body: some View {
        FoodStandalone(standalone) {
            ScrollView {
                VStack(spacing: Space.s6) {
                    FoodRing(fraction: total / safeGoal, tint: Theme.strain) {
                        VStack(spacing: Space.s1) {
                            Text(FoodText.liters(total))
                                .font(.formaDisplay)
                                .formaNumberTransition(total)
                            Text("von \(FoodText.liters(safeGoal))")
                                .font(.formaCaption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Wasser heute")
                        .accessibilityValue("\(FoodText.liters(total)) von \(FoodText.liters(safeGoal))")
                    }
                    .frame(width: 220, height: 220)
                    .padding(.top, Space.s4)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 5),
                              spacing: Space.s3) {
                        ForEach(0..<max(glasses, filled + 1), id: \.self) { index in
                            Button { tapGlass(index) } label: {
                                Image(systemName: index < filled ? "drop.fill" : "drop")
                                    .font(.system(size: 26, weight: .regular))
                                    .foregroundStyle(index < filled ? Theme.strain : Theme.textQuaternary)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(index < filled ? "Glas \(index + 1), getrunken" : "Glas \(index + 1)")
                            .accessibilityHint(index < filled ? "Entfernt das letzte Glas" : "Fügt ein Glas hinzu")
                        }
                    }
                    .padding(Space.s4)
                    .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
                    .sensoryFeedback(.increase, trigger: filled)

                    HStack(spacing: Space.s3) {
                        Button { remove() } label: {
                            Image(systemName: "minus").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)
                        .disabled(entries.isEmpty)
                        .accessibilityLabel("Letztes Glas entfernen")
                        Button { add() } label: {
                            Label("Glas · 250 ml", systemImage: "plus")
                                .font(.formaRowTitle)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)
                    }

                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Tagesziel").formaLabelStyle()
                        Stepper(value: $goal, in: FoodSettings.waterRange, step: FoodSettings.glassMl) {
                            Text(FoodText.liters(safeGoal)).font(.formaValue)
                        }
                        .frame(minHeight: 44)
                        .padding(.horizontal, Space.s4)
                        .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.s6)
            }
            .formaScreen()
            .navigationTitle("Wasser")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Konnte nicht gespeichert werden", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func tapGlass(_ index: Int) {
        index < filled ? remove() : add()
    }

    private func add() {
        let entry = FoodWaterEntry(milliliters: FoodSettings.glassMl)
        change { context.insert(entry) }
    }

    private func remove() {
        guard let last = entries.last else { return }
        change { context.delete(last) }
    }

    private func change(_ block: () -> Void) {
        do { try FoodEntry.saveChange(in: context, block) } catch { saveError = true }
    }
}

// MARK: - Fasten

struct FoodFastingView: View {
    var standalone = false
    @Environment(\.modelContext) private var context
    @AppStorage(FoodSettings.fastHoursKey) private var hours = 16.0
    @Query(sort: \FoodFast.start, order: .reverse) private var fasts: [FoodFast]
    @State private var saveError = false

    init(standalone: Bool = false) {
        self.standalone = standalone
    }

    private var active: FoodFast? { fasts.first { $0.end == nil } }
    private var plan: Double { FoodSettings.fastRange.contains(hours) ? hours : 16 }

    var body: some View {
        FoodStandalone(standalone) {
            ScrollView {
                VStack(spacing: Space.s6) {
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        timer(now: tick.date)
                    }
                    .frame(width: 240, height: 240)
                    .padding(.top, Space.s4)

                    Button(action: toggle) {
                        Text(active == nil ? "Fasten starten" : "Fasten beenden")
                            .font(.formaRowTitle)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(active == nil ? Theme.younger : Theme.older)
                    .sensoryFeedback(.success, trigger: active == nil)

                    if active == nil { planPicker }

                    if fasts.contains(where: { $0.end != nil }) { history }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.s6)
            }
            .formaScreen()
            .navigationTitle("Fasten")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Konnte nicht gespeichert werden", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func timer(now: Date) -> some View {
        let state = active.map { FoodTracking.fast(start: $0.start, end: nil, hours: $0.targetHours, now: now) }
        let tint = state?.reached == true ? Theme.younger : Theme.warning
        return FoodRing(fraction: state?.fraction ?? 0, tint: tint, lineWidth: 16) {
            VStack(spacing: Space.s1) {
                if let state, let fast = active {
                    Text(FoodText.clock(state.elapsed))
                        .font(.formaDisplay)
                        .monospacedDigit()
                    Text(state.reached ? "Ziel erreicht" : "noch \(FoodText.hours(state.remaining))")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(state.reached ? Theme.younger : Theme.textSecondary)
                    Text("seit \(Format.clock(fast.start))")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Text("\(FoodText.number(plan)):\(FoodText.number(24 - min(24, plan)))")
                        .font(.formaDisplay)
                        .monospacedDigit()
                    Text("bereit")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var planPicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Plan").formaLabelStyle()
            HStack(spacing: Space.s2) {
                ForEach(FoodSettings.fastPlans, id: \.self) { value in
                    Button { hours = value } label: {
                        Text("\(FoodText.number(value)):\(FoodText.number(24 - min(24, value)))")
                            .font(.formaValue)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(plan == value ? Theme.onSelection : Theme.textPrimary)
                    .background(plan == value ? Theme.selection : Theme.card,
                                in: .rect(cornerRadius: Radius.small, style: .continuous))
                    .accessibilityAddTraits(plan == value ? .isSelected : [])
                }
            }
            Stepper(value: $hours, in: FoodSettings.fastRange, step: 1) {
                Text("Eigene Dauer: \(FoodText.number(plan)) h").font(.formaBody)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, Space.s4)
            .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Verlauf").formaLabelStyle()
            VStack(spacing: 0) {
                ForEach(Array(fasts.filter { $0.end != nil }.prefix(7).enumerated()), id: \.offset) { index, fast in
                    let state = FoodTracking.fast(start: fast.start, end: fast.end, hours: fast.targetHours)
                    if index > 0 { RowDivider() }
                    HStack {
                        Text(Format.shortDate(fast.start)).font(.formaBody)
                        Spacer()
                        Text(FoodText.hours(state.elapsed)).font(.formaValue)
                        Image(systemName: state.reached ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(state.reached ? Theme.younger : Theme.textTertiary)
                            .accessibilityLabel(state.reached ? "Ziel erreicht" : "Ziel nicht erreicht")
                    }
                    .padding(.horizontal, Space.s4)
                    .frame(minHeight: 48)
                }
            }
            .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
        }
    }

    private func toggle() {
        do {
            if let active {
                try FoodEntry.saveChange(in: context) { active.end = .now }
            } else {
                let fast = FoodFast(targetHours: plan)
                try FoodEntry.saveChange(in: context) { context.insert(fast) }
            }
        } catch {
            saveError = true
        }
    }
}

// MARK: - Gewicht

struct FoodWeightView: View {
    var standalone = false
    @Environment(\.modelContext) private var context
    @AppStorage(FoodSettings.weightGoalKey) private var goal = 0.0
    @AppStorage(FoodSettings.bodyWeightKey) private var bodyWeight = 0.0
    @Query(sort: \FoodWeightEntry.date, order: .reverse) private var entries: [FoodWeightEntry]
    @State private var input = ""
    @State private var goalInput = ""
    @State private var invalid = false
    @State private var saveError = false
    @FocusState private var focused: Bool

    init(standalone: Bool = false) {
        self.standalone = standalone
    }

    private var latest: FoodWeightEntry? { entries.first }
    private var hasGoal: Bool { FoodSettings.weightRange.contains(goal) }

    var body: some View {
        FoodStandalone(standalone) {
            List {
                Section { header }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                if entries.count >= 2 {
                    Section { chart.padding(.vertical, Space.s3) }
                        .listRowBackground(Theme.card)
                }

                Section {
                    HStack {
                        TextField("Gewicht", text: $input)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .font(.formaNumber)
                            .accessibilityLabel("Gewicht in Kilogramm")
                        Text("kg").foregroundStyle(Theme.textSecondary)
                        Button("Eintragen", action: add)
                            .buttonStyle(.glassProminent)
                            .disabled(input.isEmpty)
                    }
                    .frame(minHeight: 44)
                    HStack {
                        TextField("Ziel", text: $goalInput)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .accessibilityLabel("Zielgewicht in Kilogramm")
                        Text("kg Ziel").foregroundStyle(Theme.textSecondary)
                        Button("Sichern", action: saveGoal)
                            .buttonStyle(.glass)
                    }
                    .frame(minHeight: 44)
                } footer: {
                    if invalid { Text("Gib 20 bis 400 kg ein.") }
                }
                .listRowBackground(Theme.card)

                if !entries.isEmpty {
                    Section {
                        ForEach(entries.prefix(30)) { entry in
                            LabeledContent(Format.shortDate(entry.date)) {
                                Text("\(FoodText.number(entry.kilograms, digits: 1)) kg").font(.formaValue)
                            }
                            .frame(minHeight: 40)
                            .swipeActions {
                                Button(role: .destructive) { delete(entry) } label: { Label("Löschen", systemImage: "trash") }
                            }
                            .accessibilityAction(named: Text("Löschen")) { delete(entry) }
                        }
                    } header: {
                        Text("Verlauf").formaLabelStyle()
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .formaScreen()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Gewicht")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { goalInput = hasGoal ? FoodText.input(goal) : "" }
            .onChange(of: input) { _, _ in invalid = false }
            .alert("Konnte nicht gespeichert werden", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var header: some View {
        let change = FoodTracking.weeklyWeightChange(entries.map { (date: $0.date, kg: $0.kilograms) })
        return VStack(spacing: Space.s1) {
            Text(latest.map { FoodText.number($0.kilograms, digits: 1) } ?? "–")
                .font(.formaHero)
                .formaNumberTransition(latest?.kilograms ?? 0)
            Text("kg").font(.formaCaption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: Space.s3) {
                if let change {
                    Text("\(change >= 0 ? "+" : "−")\(FoodText.number(abs(change), digits: 1)) kg/Woche")
                }
                if hasGoal, let latest {
                    let left = latest.kilograms - goal
                    Text(abs(left) < 0.05 ? "Ziel erreicht" : "noch \(FoodText.number(abs(left), digits: 1)) kg")
                        .foregroundStyle(abs(left) < 0.05 ? Theme.younger : Theme.textSecondary)
                }
            }
            .font(.formaCaptionStrong)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, Space.s1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        let points = entries.prefix(90).reversed()
        let values = points.map(\.kilograms) + (hasGoal ? [goal] : [])
        let low = (values.min() ?? 0) - 1
        let high = (values.max() ?? 1) + 1
        return Chart {
            ForEach(Array(points)) { entry in
                LineMark(x: .value("Datum", entry.date), y: .value("kg", entry.kilograms))
                    .foregroundStyle(Theme.textPrimary)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Datum", entry.date), y: .value("kg", entry.kilograms))
                    .foregroundStyle(Theme.textPrimary)
                    .symbolSize(16)
            }
            if hasGoal {
                RuleMark(y: .value("Ziel", goal))
                    .foregroundStyle(Theme.younger)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Ziel").font(.formaMicro).foregroundStyle(Theme.younger)
                    }
            }
        }
        .chartYScale(domain: low...high)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Gewichtsverlauf, \(points.count) Einträge")
    }

    private func add() {
        guard let kg = FoodText.decimal(input), FoodSettings.weightRange.contains(kg) else {
            invalid = true
            return
        }
        let entry = FoodWeightEntry(kilograms: kg)
        do {
            try FoodEntry.saveChange(in: context) { context.insert(entry) }
            bodyWeight = kg
            input = ""
            focused = false
        } catch {
            saveError = true
        }
    }

    private func saveGoal() {
        let text = goalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            goal = 0
        } else if let kg = FoodText.decimal(text), FoodSettings.weightRange.contains(kg) {
            goal = kg
        } else {
            invalid = true
            return
        }
        focused = false
    }

    private func delete(_ entry: FoodWeightEntry) {
        do { try FoodEntry.saveChange(in: context) { context.delete(entry) } } catch { saveError = true }
    }
}
