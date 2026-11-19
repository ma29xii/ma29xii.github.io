import SwiftUI
import WidgetKit

struct TodayHealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Today")
        .description("Recovery, Sleep und Strain auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let entry = currentEntry(at: .now)
        if let snapshot = entry.snapshot {
            let cutoff = snapshot.timelineExpiry(forEntryAt: entry.date, calendar: .autoupdatingCurrent)
            let expiry = TodayWidgetEntry(date: cutoff, snapshot: nil)
            completion(Timeline(entries: [entry, expiry], policy: .after(cutoff)))
        } else {
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(30 * 60))))
        }
    }

    private func currentEntry(at date: Date) -> TodayWidgetEntry {
        TodayWidgetEntry(date: date, snapshot: WidgetSnapshotStore.shared.current(at: date))
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let snapshot: WidgetSnapshot?

    private var usesAppColors: Bool {
        renderingMode == .fullColor && showsBackground
    }

    private var ink: Color { usesAppColors ? .white : .primary }

    private var metrics: [Metric] {
        [
            Metric(name: "Recovery", abbreviation: "R", value: snapshot?.recovery, tint: recoveryTint),
            Metric(name: "Sleep", abbreviation: "S", value: snapshot?.sleep, tint: color(0x8E8CFF)),
            Metric(name: "Strain", abbreviation: "St", value: snapshot?.strain, tint: color(0x0093E7))
        ]
    }

    private var recoveryTint: Color {
        guard let value = snapshot?.recovery else { return ink }
        if value >= 67 { return color(0x16EC06) }
        if value >= 34 { return color(0xFFDE00) }
        return color(0xFF0026)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular.containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            rectangular.containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            inline.containerBackground(for: .widget) { Color.clear }
        default:
            home(labeled: family == .systemMedium)
                .containerBackground(for: .widget) { color(0x0D0E0F) }
        }
    }

    private func home(labeled: Bool) -> some View {
        HStack(spacing: labeled ? 12 : 5) {
            ForEach(metrics) { metric in
                VStack(spacing: 6) {
                    ring(for: metric, labeled: labeled)
                    Text(labeled ? metric.name : metric.abbreviation)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(!labeled && usesAppColors && metric.value != nil ? metric.tint : ink)
                }
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(metric.name)
                .accessibilityValue(metric.spokenValue)
                .privacySensitive()
            }
        }
        .foregroundStyle(ink)
    }

    private func ring(for metric: Metric, labeled: Bool) -> some View {
        let stroke = StrokeStyle(lineWidth: labeled ? 3 : 2, lineCap: .round)
        let tint = usesAppColors ? metric.tint : ink
        let track = metric.value == 0 ? tint.opacity(0.55) : ink.opacity(0.20)
        return ZStack {
            Circle().strokeBorder(track, style: stroke)
            if let value = metric.value, value > 0 {
                Circle()
                    .inset(by: stroke.lineWidth / 2)
                    .trim(from: 0, to: CGFloat(value) / 100)
                    .stroke(tint, style: stroke)
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: labeled ? 64 : 44)
        .overlay {
            Text(verbatim: metric.displayValue)
                .font(.system(labeled ? .title3 : .subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, labeled ? 7 : 5)
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                ForEach(metrics) { metric in
                    number(metric, text: metric.compactDisplayValue,
                           font: .system(size: 11, weight: .semibold, design: .rounded))
                }
            }
            .padding(3)
        }
    }

    private var rectangular: some View {
        HStack(spacing: 4) {
            ForEach(metrics) { metric in
                VStack(spacing: 2) {
                    number(metric, font: .system(.headline, design: .rounded, weight: .semibold))
                    Text(metric.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var inline: some View {
        Text(verbatim: metrics.map(\.compactDisplayValue).joined(separator: " · "))
            .accessibilityLabel(metrics.map { "\($0.name): \($0.spokenValue)" }.joined(separator: ", "))
            .privacySensitive()
    }

    private func number(_ metric: Metric, text: String? = nil, font: Font) -> some View {
        Text(verbatim: text ?? metric.displayValue)
            .font(font.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(metric.name)
            .accessibilityValue(metric.spokenValue)
            .privacySensitive()
    }

    private func color(_ hex: UInt32) -> Color {
        // Gleiche sRGB-Werte wie in der App, deren Theme im Widget-Target nicht verfügbar ist.
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    private struct Metric: Identifiable {
        let name: String
        let abbreviation: String
        let value: Int?
        let tint: Color

        var id: String { name }
        var displayValue: String { value.map { $0.formatted() } ?? "–" }
        var compactDisplayValue: String { "\(abbreviation) \(displayValue)" }
        var spokenValue: String { value.map { "\($0.formatted()) von 100" } ?? "Keine Messung" }
    }
}
