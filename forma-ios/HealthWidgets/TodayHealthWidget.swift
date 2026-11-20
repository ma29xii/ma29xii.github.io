import SwiftUI
import WidgetKit

struct TodayHealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Today")
        .description("Recovery, Strain und Sleep auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: .now, snapshot: Self.preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let calendar = Calendar.autoupdatingCurrent
        let entry = currentEntry(at: .now)
        guard let snapshot = entry.snapshot else {
            // Noch nichts für heute: bald wieder nachsehen, die App lädt die Zeitleiste beim Speichern ohnehin neu.
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60))))
            return
        }
        // Der Stand bleibt sichtbar, bis der Tag endet. Erst dann folgt ein leerer Eintrag („–“).
        let dayEnd = TodayWidgetEntry(date: snapshot.expiry(in: calendar), snapshot: nil)
        completion(Timeline(entries: [entry, dayEnd], policy: .after(snapshot.nextReload(after: entry.date, calendar: calendar))))
    }

    private func currentEntry(at date: Date) -> TodayWidgetEntry {
        TodayWidgetEntry(date: date, snapshot: WidgetSnapshotStore.shared.current(at: date))
    }

    /// Beispielwerte nur für die Widget-Galerie, nie für echte Anzeige.
    private static var preview: WidgetSnapshot? {
        WidgetSnapshot(recovery: 78, strain: 54, sleep: 86, updatedAt: .now, day: .now, calendar: .autoupdatingCurrent)
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let snapshot: WidgetSnapshot?

    private var style: WidgetStyle { WidgetStyle(renderingMode: renderingMode, showsBackground: showsBackground) }
    private var usesAppColors: Bool { style.usesAppColors }
    private var ink: Color { style.ink }

    private var recovery: Metric { Metric(name: "Recovery", short: "R", value: snapshot?.recovery, tint: style.recovery(snapshot?.recovery)) }
    private var strain: Metric { Metric(name: "Strain", short: "St", value: snapshot?.strain, tint: style.strain) }
    private var sleep: Metric { Metric(name: "Sleep", short: "S", value: snapshot?.sleep, tint: style.sleep) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular.containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            rectangular.containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            inline.containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            medium.containerBackground(for: .widget) { style.background() }
        default:
            small.containerBackground(for: .widget) { style.background() }
        }
    }

    // MARK: Home-Bildschirm

    /// Klein: Recovery als große Zahl im feinen Ring, darunter Strain und Sleep als Zahlen.
    private var small: some View {
        VStack(spacing: 12) {
            ring(recovery, line: 6, font: .widgetNumber(38))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 0) {
                stat(strain)
                stat(sleep)
            }
        }
        .foregroundStyle(ink)
    }

    /// Mittel: drei Ringe mit großer Zahl, Recovery etwas größer.
    private var medium: some View {
        HStack(spacing: 18) {
            labeledRing(recovery, line: 7, font: .widgetNumber(36))
            labeledRing(strain, line: 6, font: .widgetNumber(26)).frame(maxWidth: 92)
            labeledRing(sleep, line: 6, font: .widgetNumber(26)).frame(maxWidth: 92)
        }
        .foregroundStyle(ink)
    }

    private func labeledRing(_ metric: Metric, line: CGFloat, font: Font) -> some View {
        VStack(spacing: 8) {
            ring(metric, line: line, font: font)
            Text(metric.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(style.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(_ metric: Metric) -> some View {
        VStack(spacing: 1) {
            Text(verbatim: metric.display)
                .font(.widgetNumber(20))
                .foregroundStyle(usesAppColors ? metric.tint : ink)
            Text(metric.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.name)
        .accessibilityValue(metric.spoken)
        .privacySensitive()
    }

    private func ring(_ metric: Metric, line: CGFloat, font: Font) -> some View {
        ZStack {
            WidgetGauge(fraction: Double(metric.value ?? 0) / 100, tint: usesAppColors ? metric.tint : ink,
                        track: style.track, line: line)
            Text(verbatim: metric.display)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(line + 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.name)
        .accessibilityValue(metric.spoken)
        .privacySensitive()
    }

    // MARK: Sperrbildschirm

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            ring(recovery, line: 5, font: .system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .padding(4)
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            ring(recovery, line: 5, font: .system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                row(strain)
                row(sleep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ metric: Metric) -> some View {
        HStack {
            Text(metric.name).font(.caption)
            Spacer(minLength: 4)
            Text(verbatim: metric.display).font(.system(.headline, design: .rounded, weight: .semibold)).monospacedDigit()
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.name)
        .accessibilityValue(metric.spoken)
        .privacySensitive()
    }

    private var inline: some View {
        Text(verbatim: [recovery, sleep, strain].map { "\($0.short) \($0.display)" }.joined(separator: " · "))
            .accessibilityLabel([recovery, sleep, strain].map { "\($0.name): \($0.spoken)" }.joined(separator: ", "))
            .privacySensitive()
    }

    private struct Metric {
        let name: String
        let short: String
        let value: Int?
        let tint: Color

        var display: String { value.map { $0.formatted() } ?? "–" }
        var spoken: String { value.map { "\($0.formatted()) von 100" } ?? "Keine Messung" }
    }
}
