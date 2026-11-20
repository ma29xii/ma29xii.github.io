import SwiftUI

/// Texte der unteren Food-Karten, getrennt von der Ansicht, damit sie testbar bleiben.
enum FoodHomeCardsText {
    enum Trend: Equatable { case up, down, flat }

    /// Unterschied zum vorigen Wert; unter 0,05 kg gilt als gleich.
    static func weightTrend(latest: Double, previous: Double?) -> (trend: Trend, delta: Double)? {
        guard let previous, latest.isFinite, previous.isFinite else { return nil }
        let delta = latest - previous
        if abs(delta) < 0.05 { return (.flat, 0) }
        return (delta > 0 ? .up : .down, abs(delta))
    }

    static func nextPlanned(_ entries: [FoodPlanEntry], today: Date, calendar: Calendar = .forma) -> FoodPlanEntry? {
        let start = calendar.startOfDay(for: today)
        let order = Dictionary(uniqueKeysWithValues: FoodMeal.allCases.enumerated().map { ($1, $0) })
        return entries.filter { !$0.logged && $0.day >= start }
            .min { l, r in
                l.day != r.day ? l.day < r.day : (order[l.meal] ?? 0) < (order[r.meal] ?? 0)
            }
    }
}

/// „Heute“ mit Wasser und Fasten als große Karten, darunter Plan und Gewicht. Gleiche Höhen je Reihe, keine Pfeile.
struct FoodHomeBottom: View {
    let waterMl: Double
    let waterTarget: Double
    let fast: (start: Date, hours: Double)?
    let nextPlanned: FoodPlanEntry?
    let latestWeight: Double?
    let previousWeight: Double?
    let open: (FoodHomeRoute) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    init(waterMl: Double, waterTarget: Double, fast: (start: Date, hours: Double)?, nextPlanned: FoodPlanEntry?,
         latestWeight: Double?, previousWeight: Double?, open: @escaping (FoodHomeRoute) -> Void) {
        self.waterMl = waterMl
        self.waterTarget = waterTarget
        self.fast = fast
        self.nextPlanned = nextPlanned
        self.latestWeight = latestWeight
        self.previousWeight = previousWeight
        self.open = open
    }

    private var showProgress: Bool { revealed || reduceMotion }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Space.gap), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Text("Heute").formaLabelStyle().padding(.horizontal, Space.s1)
            LazyVGrid(columns: columns, spacing: Space.gap) {
                waterCard
                fastCard
            }
            LazyVGrid(columns: columns, spacing: Space.gap) {
                planCard
                weightCard
            }
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            revealed = true
        }
    }

    // MARK: Große Karten

    private var waterCard: some View {
        let fraction = waterTarget > 0 ? waterMl / waterTarget : 0
        let value = waterMl > 0 ? FoodText.liters(waterMl) : "0 l"
        return card("Wasser", icon: "drop.fill", tint: Theme.strain, minHeight: 148, route: .water,
                    spoken: "\(value) von \(FoodText.liters(waterTarget))") {
            HStack(spacing: Space.s3) {
                FoodRing(fraction: showProgress ? fraction : 0, tint: Theme.strain, lineWidth: 8) {
                    Text("\(Int((min(1, max(0, fraction)) * 100).rounded()))")
                        .font(.formaCaptionStrong.monospacedDigit())
                        .formaNumberTransition(showProgress ? fraction * 100 : 0)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.formaNumber)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .formaNumberTransition(waterMl)
                    Text("von \(FoodText.liters(waterTarget))")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var fastCard: some View {
        TimelineView(.everyMinute) { tick in
            let state = fast.map { FoodTracking.fast(start: $0.start, end: nil, hours: $0.hours, now: tick.date) }
            let fraction = state?.fraction ?? 0
            let value = state.map { FoodText.clock($0.elapsed) } ?? "–"
            let goal = fast.map { "von \(FoodText.number($0.hours)) h" } ?? "Nicht aktiv"
            card("Fasten", icon: "timer", tint: Theme.warning, minHeight: 148, route: .fasting,
                 spoken: state == nil ? "Kein Fasten aktiv" : "\(value) \(goal)") {
                HStack(spacing: Space.s3) {
                    FoodRing(fraction: showProgress ? fraction : 0, tint: Theme.warning, lineWidth: 8) {
                        Image(systemName: state == nil ? "moon.zzz" : "timer")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.warning)
                            .accessibilityHidden(true)
                    }
                    .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value)
                            .font(.formaNumber)
                            .foregroundStyle(state == nil ? Theme.textTertiary : Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(goal)
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }

    // MARK: Plan und Gewicht

    private var planCard: some View {
        let now = Date.now
        let spoken = nextPlanned.map {
            "\($0.product.name), \(FoodPlanText.dayTitle($0.day, now: now))" + ($0.kcal.map { ", \(FoodText.number($0)) Kilokalorien" } ?? "")
        } ?? "Nichts geplant"
        return card("Plan", icon: "calendar", tint: Theme.sleep, minHeight: 112, route: .plan, spoken: spoken) {
            if let entry = nextPlanned {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.product.name)
                        .font(.formaRowTitle)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(FoodPlanText.dayTitle(entry.day, now: now) + (entry.kcal.map { " · \(FoodText.number($0)) kcal" } ?? ""))
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text("–").font(.formaNumber).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var weightCard: some View {
        let trend = latestWeight.flatMap { FoodHomeCardsText.weightTrend(latest: $0, previous: previousWeight) }
        let value = latestWeight.map { "\(FoodText.number($0, digits: 1)) kg" }
        var spoken = value ?? "Kein Eintrag"
        if let trend {
            switch trend.trend {
            case .up: spoken += ", \(FoodText.number(trend.delta, digits: 1)) Kilogramm mehr als zuvor"
            case .down: spoken += ", \(FoodText.number(trend.delta, digits: 1)) Kilogramm weniger als zuvor"
            case .flat: spoken += ", unverändert"
            }
        }
        return card("Gewicht", icon: "scalemass.fill", tint: Theme.older, minHeight: 112, route: .weight, spoken: spoken) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value ?? "–")
                    .font(.formaNumber)
                    .foregroundStyle(value == nil ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .formaNumberTransition(latestWeight ?? 0)
                if let trend {
                    HStack(spacing: Space.s1) {
                        Image(systemName: trend.trend == .up ? "arrow.up.right" : (trend.trend == .down ? "arrow.down.right" : "arrow.right"))
                            .font(.system(size: 11, weight: .semibold))
                        Text(trend.trend == .flat ? "gleich" : "\(FoodText.number(trend.delta, digits: 1)) kg")
                    }
                    .font(.formaCaption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: Karte

    private func card<Content: View>(_ title: String, icon: String, tint: Color, minHeight: CGFloat,
                                     route: FoodHomeRoute, spoken: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        let inner = content()
        return Button { open(route) } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Label(title, systemImage: icon)
                        .font(.formaCaptionStrong)
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                    inner
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            }
            .contentShape(.rect(cornerRadius: Radius.plate))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken)
        .accessibilityAddTraits(.isButton)
    }
}
