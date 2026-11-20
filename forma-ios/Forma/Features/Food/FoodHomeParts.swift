import SwiftUI

// Bausteine des Food-Tabs (F7-05): Kopf mit einer Zahl, Wasser-und-Fasten-Leiste, Zeitleiste, Fußzeile.
// Keine Rahmen, keine Pfeile, keine Erklärtexte – Schrift, Weißraum und eine Akzentfarbe.

// MARK: - Kopf

/// „Wie stehe ich heute?“: große Zahl kcal übrig, ein dünner Balken in drei Tönen, drei kleine Zahlen.
struct FoodDayHero: View {
    let energy: FoodSum
    let protein: FoodSum
    let carbs: FoodSum
    let fat: FoodSum
    let target: Double
    let goals: FoodMacroGoals

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 92
    @State private var revealed = FormaApp.isUITest

    private var show: Bool { revealed || reduceMotion }

    var body: some View {
        let left = energy.remaining(of: target)
        let over = (left ?? 0) < 0
        let figure = left.map { abs($0) } ?? energy.known
        let shown = show ? figure : 0
        let segments = FoodMacroBar.segments(protein: protein.known, carbs: carbs.known, fat: fat.known,
                                             consumed: energy.known, target: target)
        VStack(spacing: Space.s5) {
            VStack(spacing: Space.s1) {
                Text(headline(left: left, shown: shown))
                    .font(.system(size: numberSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(over ? Theme.older : Theme.textPrimary)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: shown))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: shown)
                Text(caption(left: left, over: over))
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
            }
            FoodMacroBarView(segments: segments, grown: show)
            macros
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            revealed = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heute")
        .accessibilityValue(spoken(left: left, over: over))
    }

    private var macroList: [(title: String, sum: FoodSum, kind: FoodMacroBar.Kind)] {
        [("Protein", protein, .protein), ("Kohlenhydrate", carbs, .carbs), ("Fett", fat, .fat)]
    }

    @ViewBuilder private var macros: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(Array(macroList.enumerated()), id: \.offset) { _, item in
                    macro(item.title, item.sum, kind: item.kind, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            HStack(alignment: .top, spacing: Space.s2) {
                macro("Protein", protein, kind: .protein, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                macro("Kohlenhydrate", carbs, kind: .carbs, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                macro("Fett", fat, kind: .fat, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func macro(_ title: String, _ sum: FoodSum, kind: FoodMacroBar.Kind, alignment: HorizontalAlignment) -> some View {
        let shown = show ? sum.known : 0
        return VStack(alignment: alignment, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Self.text(sum, shown: shown))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .formaNumberTransition(shown)
                Text("g")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            HStack(spacing: 5) {
                Circle().fill(FoodMacroBarView.color(kind)).frame(width: 6, height: 6)
                Text(title)
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// Ohne bekannten Wert „–“, mit Lücken „≥ n“ – wie bisher in der App.
    static func text(_ sum: FoodSum, shown: Double) -> String {
        if sum.known == 0 && !sum.complete { return "–" }
        return (sum.complete ? "" : "≥ ") + FoodText.number(shown)
    }

    private func headline(left: Double?, shown: Double) -> String {
        left == nil ? Self.text(energy, shown: shown) : FoodText.number(shown)
    }

    private func caption(left: Double?, over: Bool) -> String {
        guard left != nil else { return "kcal erfasst" }
        return over ? "kcal zu viel" : "kcal übrig"
    }

    private func spoken(left: Double?, over: Bool) -> String {
        var parts: [String] = []
        if let left {
            parts.append("\(FoodText.number(abs(left))) Kilokalorien \(over ? "zu viel" : "übrig")")
        } else {
            parts.append("\(energy.complete ? "" : "mindestens ")\(FoodText.number(energy.known)) Kilokalorien erfasst")
        }
        let list: [(String, FoodSum, Double)] = [("Protein", protein, goals.protein),
                                                 ("Kohlenhydrate", carbs, goals.carbs), ("Fett", fat, goals.fat)]
        for (title, sum, goal) in list {
            parts.append("\(title) \(sum.complete ? "" : "mindestens ")\(FoodText.number(sum.known)) von \(FoodText.number(goal)) Gramm")
        }
        return parts.joined(separator: ", ")
    }
}

/// Ein dünner, durchgehender Balken; die Segmente wachsen beim Erscheinen von links.
struct FoodMacroBarView: View {
    let segments: [FoodMacroBar.Segment]
    let grown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func color(_ kind: FoodMacroBar.Kind) -> Color {
        switch kind {
        case .protein: Theme.accent
        case .carbs: Theme.accent.opacity(0.6)
        case .fat: Theme.accent.opacity(0.32)
        case .unknown: Theme.textTertiary
        }
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scale = grown ? 1.0 : 0.0
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                HStack(spacing: 2) {
                    ForEach(segments, id: \.kind) { segment in
                        Capsule()
                            .fill(Self.color(segment.kind))
                            .frame(width: max(0, width * segment.fraction * scale))
                    }
                }
            }
            .clipShape(Capsule())
            .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: scale)
            .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: segments)
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Wasser und Fasten

/// Eine schmale Leiste: links Wasser (Tippen = +250 ml), rechts Fasten (zeigt die Restzeit).
struct FoodDayStrip: View {
    let waterMl: Double
    let waterTarget: Double
    let fast: (start: Date, hours: Double)?
    let canRemoveWater: Bool
    let addWater: () -> Void
    let removeWater: () -> Void
    let open: (FoodHomeRoute) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = FormaApp.isUITest

    private var show: Bool { revealed || reduceMotion }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    waterButton
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    fastButton
                }
            } else {
                HStack(spacing: 0) {
                    waterButton
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 28)
                    fastButton
                }
            }
        }
        .background(Theme.card)
        .clipShape(shape)
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            revealed = true
        }
    }

    private func fill(_ fraction: Double) -> some View {
        let value = show ? min(1, max(0, fraction.isFinite ? fraction : 0)) : 0
        return GeometryReader { geo in
            Rectangle()
                .fill(Theme.accent.opacity(0.16))
                .frame(width: geo.size.width * CGFloat(value))
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: value)
    }

    private var waterButton: some View {
        let fraction = waterTarget > 0 ? waterMl / waterTarget : 0
        return Button(action: addWater) {
            HStack(spacing: Space.s2) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(FoodText.liters(waterMl))
                    .font(.formaValue)
                    .formaNumberTransition(waterMl)
                Text("/ " + FoodText.liters(waterTarget))
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Space.s3)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(alignment: .leading) { fill(fraction) }
            .contentShape(Rectangle())
        }
        .buttonStyle(FormaPressStyle(scale: 0.97))
        .contextMenu {
            Button { open(.water) } label: { Label("Wasser öffnen", systemImage: "drop") }
            if canRemoveWater {
                Button(role: .destructive, action: removeWater) {
                    Label("Letztes Glas entfernen", systemImage: "minus.circle")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wasser")
        .accessibilityValue("\(FoodText.liters(waterMl)) von \(FoodText.liters(waterTarget))")
        .accessibilityHint("Fügt 250 Milliliter hinzu")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Wasser öffnen")) { open(.water) }
        .accessibilityAction(named: Text("Letztes Glas entfernen")) { if canRemoveWater { removeWater() } }
        .accessibilityIdentifier("food.water")
    }

    private var fastButton: some View {
        TimelineView(.everyMinute) { tick in
            let state = fast.map { FoodTracking.fast(start: $0.start, end: nil, hours: $0.hours, now: tick.date) }
            let text = state.map { $0.reached ? "Ziel erreicht" : "noch " + FoodText.hours($0.remaining) } ?? "Fasten"
            Button { open(.fasting) } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "timer")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(state == nil ? Theme.textTertiary : Theme.accent)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.formaValue)
                        .foregroundStyle(state == nil ? Theme.textSecondary : Theme.textPrimary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, Space.s3)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(alignment: .leading) { fill(state?.fraction ?? 0) }
                .contentShape(Rectangle())
            }
            .buttonStyle(FormaPressStyle(scale: 0.97))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fasten")
            .accessibilityValue(spoken(state))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("food.fasting")
        }
    }

    private func spoken(_ state: FoodTracking.Fast?) -> String {
        guard let state else { return "Nicht aktiv" }
        if state.reached { return "Ziel erreicht" }
        let minutes = Int(state.remaining / 60)
        return "Noch \(minutes / 60) Stunden \(minutes % 60) Minuten"
    }
}

// MARK: - Zeitleiste

/// Eine Zeile der Zeitleiste: Uhrzeit, Punkt auf der Linie, Name, kcal.
/// Geplante Gerichte stehen blass mit hohlem Punkt da; ein Tipp trägt sie als gegessen ein.
struct FoodTimelineRow: View {
    let item: FoodTimelineItem
    let isFirst: Bool
    let isLast: Bool
    let prominent: Bool

    @ScaledMetric(relativeTo: .callout) private var pad: CGFloat = 12
    @ScaledMetric(relativeTo: .callout) private var halfLine: CGFloat = 10.5
    @ScaledMetric(relativeTo: .title3) private var padLarge: CGFloat = 20
    @ScaledMetric(relativeTo: .title3) private var halfLineLarge: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var timeWidth: CGFloat = 46

    private static let markerSlot: CGFloat = 28
    private static let dot: CGFloat = 9

    var body: some View {
        let top = prominent ? padLarge : pad
        let centerY = top + (prominent ? halfLineLarge : halfLine)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(Format.clock(item.time))
                .font(.formaCaption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .frame(width: timeWidth, alignment: .trailing)
            Text(item.title)
                .font(prominent ? Font.system(.title3, design: .rounded, weight: .semibold) : Font.formaRowTitle)
                .lineLimit(prominent ? 3 : 2)
                .padding(.leading, Self.markerSlot)
                .frame(maxWidth: .infinity, alignment: .leading)
            kcal
        }
        .foregroundStyle(item.isPlanned ? Theme.textSecondary : Theme.textPrimary)
        .padding(.vertical, top)
        .background(alignment: .topLeading) { rail(centerY: centerY) }
        .contentShape(Rectangle())
    }

    private var kcal: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(item.kcal.map { FoodText.number($0) } ?? "–")
                .font(prominent ? Font.formaNumber : Font.formaValue)
            Text("kcal")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.leading, Space.s2)
    }

    /// Senkrechte Haarlinie mit Punkt. Die erste Zeile beginnt am Punkt, die letzte endet dort.
    private func rail(centerY: CGFloat) -> some View {
        let x = timeWidth + Self.markerSlot / 2
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1)
                .padding(.top, isFirst ? centerY : 0)
                .frame(maxHeight: isLast ? centerY : CGFloat.infinity, alignment: .top)
            Group {
                if item.isPlanned {
                    Circle()
                        .fill(Theme.background)
                        .overlay(Circle().strokeBorder(Theme.textTertiary, lineWidth: 1.2))
                } else {
                    Circle().fill(Theme.accent)
                }
            }
            .frame(width: Self.dot, height: Self.dot)
            .offset(x: -Self.dot / 2 + 0.5, y: centerY - Self.dot / 2)
        }
        .padding(.leading, x)
    }
}

// MARK: - Fußzeile

/// Gewicht, Plan und Einkaufsliste: drei Symbole in einer ruhigen Zeile.
struct FoodDayFooter: View {
    let weightText: String?
    let open: (FoodHomeRoute) -> Void

    var body: some View {
        HStack(spacing: 0) {
            item("scalemass", weightText ?? "Gewicht", route: .weight, id: "food.weight")
            item("calendar", "Plan", route: .plan, id: "food.plan")
            item("cart", "Einkauf", route: .shopping, id: "food.shopping")
        }
    }

    private func item(_ symbol: String, _ title: String, route: FoodHomeRoute, id: String) -> some View {
        Button { open(route) } label: {
            VStack(spacing: Space.s1) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.formaCaption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(FormaPressStyle(scale: 0.95))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(symbol == "scalemass" ? "Gewicht" : title)
        .accessibilityValue(symbol == "scalemass" ? (weightText ?? "Kein Eintrag") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }
}
