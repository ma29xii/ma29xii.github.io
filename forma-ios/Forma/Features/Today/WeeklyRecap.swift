import SwiftUI

struct WeeklyRecapLink: View {
    let period: WeeklyInsight.Period
    @Environment(DataHub.self) private var hub
    @State private var open = false

    var body: some View {
        let rows = WeeklyInsight.rows(period: period, history: InsightHistory(hub.dashboardHistory(recent: hub.days)))
        Button { open = true } label: {
            DashboardCard {
                HStack(spacing: Space.s3) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        DashboardHeading(title: "Wochenrückblick")
                        Text(Self.highlight(rows))
                            .font(.formaBody)
                            .monospacedDigit()
                    }
                    Spacer(minLength: Space.s2)
                }
                .padding(Space.s4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.weekly.open")
        .fullScreenCover(isPresented: $open) {
            WeeklyRecapStory(rows: rows, dayCount: period.dayCount)
        }
    }

    /// Größte Verbesserung der Woche als Untertitel, sonst nur „Deine Woche“.
    static func highlight(_ rows: [WeeklyInsight.Row]) -> String {
        let best = rows.compactMap { row -> (WeeklyInsight.Row, Double)? in
            guard row.metric.higherIsBetter, let change = row.change, change >= 1 else { return nil }
            return (row, change)
        }.max { $0.1 < $1.1 }
        guard let row = best?.0 else { return "Deine Woche" }
        return "\(row.metric.title) \(row.changeText)"
    }

    static func span(_ first: Date, days: Int) -> String {
        "\(Format.shortDate(first))–\(Format.shortDate(first.adding(days: days - 1)))"
    }
}

extension WeeklyInsight {
    /// Im UI-Rundgang ist der Rückblick unabhängig vom Wochentag sichtbar (letzte volle Woche).
    static func displayPeriod(at date: Date, calendar: Calendar = .forma) -> Period? {
        if let period = period(at: date, calendar: calendar) { return period }
        guard FormaApp.isUITest else { return nil }
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        guard let monday = mondayFirst.dateInterval(of: .weekOfYear, for: date)?.start,
              let morning = calendar.date(byAdding: .hour, value: 9, to: monday) else { return nil }
        return period(at: morning, calendar: calendar)
    }
}

// MARK: - Story

/// Vollbild-Story: Seiten laufen automatisch weiter, rechts tippen = weiter, links = zurück, halten = Pause.
struct WeeklyRecapStory: View {
    let rows: [WeeklyInsight.Row]
    let dayCount: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var page = 0
    @State private var progress = 0.0
    @State private var paused = false
    @State private var drag: CGFloat = 0

    private static let seconds = 5.0

    private enum Page: Hashable {
        case intro, metric(WeeklyInsight.Metric), summary
    }

    private var pages: [Page] {
        [.intro] + rows.filter { $0.current != nil }.map { .metric($0.metric) } + [.summary]
    }

    /// Ohne automatisches Weiterblättern bei reduzierter Bewegung, VoiceOver und im UI-Rundgang.
    private var autoAdvance: Bool { !reduceMotion && !voiceOver && !FormaApp.isUITest }

    var body: some View {
        let pages = self.pages
        let current = pages[min(page, pages.count - 1)]
        GeometryReader { proxy in
            ZStack {
                background(for: current)
                VStack(alignment: .leading, spacing: Space.s4) {
                    header(pages: pages)
                    Spacer(minLength: 0)
                    content(current)
                        .id(current)
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                  removal: .opacity))
                    Spacer(minLength: 0)
                    if current == .summary {
                        Button { dismiss() } label: {
                            Text("Fertig")
                                .font(.formaRowTitle)
                                .foregroundStyle(Theme.onSelection)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Theme.selection, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("weekly.done")
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.s4)
            }
            .offset(y: max(0, drag))
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                step(value.location.x > proxy.size.width * 0.33 ? 1 : -1, count: pages.count)
            })
            .simultaneousGesture(DragGesture(minimumDistance: 20)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 120 { dismiss() }
                    withAnimation(.spring(duration: 0.3)) { drag = 0 }
                })
            .onLongPressGesture(minimumDuration: 0.2, perform: {}, onPressingChanged: { paused = $0 })
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: page)
        .task(id: page) { await run(count: pages.count) }
        .accessibilityAction(named: "Weiter") { step(1, count: pages.count) }
        .accessibilityAction(named: "Zurück") { step(-1, count: pages.count) }
    }

    // MARK: Ablauf

    private func step(_ delta: Int, count: Int) {
        let target = page + delta
        if target >= count { dismiss(); return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) {
            page = max(0, target)
            progress = 0
        }
    }

    private func run(count: Int) async {
        progress = 0
        guard autoAdvance else { return }
        let tick = 0.05
        while progress < 1 {
            do { try await Task.sleep(for: .seconds(tick)) } catch { return }
            if !paused { progress = min(1, progress + tick / Self.seconds) }
        }
        if page < count - 1 { step(1, count: count) }
    }

    // MARK: Aufbau

    private func header(pages: [Page]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s1) {
                ForEach(pages.indices, id: \.self) { index in
                    let fill = index < page ? 1 : (index == page ? (autoAdvance ? progress : 1) : 0)
                    GeometryReader { bar in
                        Capsule().fill(Theme.textPrimary.opacity(0.22))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.textPrimary).frame(width: bar.size.width * fill)
                            }
                    }
                    .frame(height: 3)
                }
            }
            .accessibilityHidden(true)
            HStack {
                Text("Wochenrückblick")
                    .formaLabelStyle()
                    .accessibilityIdentifier("weekly.story")
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Theme.plate, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Schließen")
                .accessibilityIdentifier("weekly.close")
            }
        }
    }

    private func background(for page: Page) -> some View {
        let tint: Color = switch page {
        case .intro, .summary: Theme.accent
        case .metric(let metric): metric.tint
        }
        return RadialGradient(colors: [tint.opacity(0.38), tint.opacity(0.08), .clear],
                              center: .top, startRadius: 0, endRadius: 520)
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: page)
    }

    @ViewBuilder
    private func content(_ page: Page) -> some View {
        switch page {
        case .intro:
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Deine\nWoche")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(dayCount) Tage · \(rows.filter { $0.current != nil }.count) Werte")
                    .font(.formaHeadline)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        case .metric(let metric):
            if let row = rows.first(where: { $0.metric == metric }), let current = row.current {
                metricPage(row, current: current)
            }
        case .summary:
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Im Überblick")
                    .font(.formaTitle)
                    .foregroundStyle(Theme.textPrimary)
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: Space.s3) {
                            Circle().fill(row.metric.tint).frame(width: 8, height: 8)
                            Text(row.metric.title).font(.formaRowTitle)
                            Spacer(minLength: Space.s2)
                            Text(row.current.map { row.metric.formatted($0.mean) } ?? "–")
                                .font(.formaValue)
                            if row.change != nil { ChangeBadge(row: row, compact: true) }
                        }
                        .frame(minHeight: 52)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("today.weekly.\(row.metric.rawValue)")
                        if row.id != rows.last?.id { Divider().overlay(Theme.hairline) }
                    }
                }
                .padding(.horizontal, Space.s4)
                .background(Theme.plate, in: RoundedRectangle(cornerRadius: Radius.plate, style: .continuous))
            }
        }
    }

    private func metricPage(_ row: WeeklyInsight.Row, current: InsightAverage) -> some View {
        let scale = max(1, current.mean, row.previous?.mean ?? 0)
        return VStack(alignment: .leading, spacing: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(row.metric.title)
                    .formaLabelStyle(row.metric.tint)
                Text(row.metric.formatted(current.mean))
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: current.mean))
                if row.change != nil { ChangeBadge(row: row, compact: false) }
            }
            VStack(spacing: Space.s3) {
                comparison("Diese Woche", value: current, metric: row.metric, scale: scale, highlighted: true)
                if let previous = row.previous {
                    comparison("Vorwoche", value: previous, metric: row.metric, scale: scale, highlighted: false)
                }
            }
            Text("\(current.count)/\(dayCount) Tage gemessen")
                .font(.formaCaption)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.weekly.\(row.metric.rawValue)")
    }

    private func comparison(_ title: String, value: InsightAverage, metric: WeeklyInsight.Metric,
                            scale: Double, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack {
                Text(title).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(metric.formatted(value.mean)).font(.formaValue)
                    .foregroundStyle(highlighted ? Theme.textPrimary : Theme.textSecondary)
            }
            ProgressLine(fraction: value.mean / scale,
                         color: highlighted ? metric.tint : Theme.textQuaternary, height: 8)
                .accessibilityHidden(true)
        }
    }
}

/// Veränderung zur Vorwoche: Pfeil und Prozent, grün = besser, orange = schlechter, grau = neutral.
private struct ChangeBadge: View {
    let row: WeeklyInsight.Row
    let compact: Bool

    var body: some View {
        let change = row.change ?? 0
        let color: Color = abs(change) < 1 || !row.metric.directional ? Theme.textSecondary
            : (change > 0) == row.metric.higherIsBetter ? Theme.younger : Theme.older
        let icon = abs(change) < 1 ? "equal" : (change > 0 ? "arrow.up.right" : "arrow.down.right")
        HStack(spacing: Space.s1) {
            Image(systemName: icon).font(.caption.weight(.bold))
            if !compact { Text(row.changeText).font(.formaValue) }
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? Space.s2 : Space.s3)
        .padding(.vertical, Space.s1)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityLabel("Zur Vorwoche \(row.changeText)")
    }
}

extension WeeklyInsight.Row {
    /// Veränderung zur Vorwoche in Prozent; nil ohne Vergleich.
    var change: Double? {
        guard let current, let previous, previous.mean > 0 else { return nil }
        return (current.mean - previous.mean) / previous.mean * 100
    }

    var changeText: String {
        guard let change else { return "–" }
        let rounded = Int(change.rounded())
        if rounded == 0 { return "±0 %" }
        return "\(rounded > 0 ? "+" : "−")\(abs(rounded)) %"
    }
}

extension WeeklyInsight.Metric {
    var title: String {
        switch self {
        case .sleep: "Schlafdauer"
        case .recovery: "Recovery"
        case .strain: "Strain"
        case .steps: "Schritte"
        case .hrv: "HRV"
        }
    }

    /// Strain ist weder gut noch schlecht – nur Richtung zeigen, nicht bewerten.
    var directional: Bool { self != .strain }
    var higherIsBetter: Bool { directional }

    var tint: Color {
        switch self {
        case .sleep: Theme.sleep
        case .recovery: Theme.younger
        case .strain: DashboardRing.tint(kind: .strain, value: nil)
        case .steps: Theme.warning
        case .hrv: Theme.recoveryHigh
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .sleep: Format.duration(value)
        case .recovery: "\(Format.number(value)) %"
        case .strain, .steps: Format.number(value)
        case .hrv: "\(Format.number(value)) ms"
        }
    }
}
