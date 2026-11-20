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

    private var usesAppColors: Bool { renderingMode == .fullColor && showsBackground }
    private var ink: Color { usesAppColors ? .white : .primary }

    private var recovery: Metric { Metric(name: "Recovery", short: "R", value: snapshot?.recovery, tint: recoveryTint) }
    private var strain: Metric { Metric(name: "Strain", short: "St", value: snapshot?.strain, tint: color(0x0093E7)) }
    private var sleep: Metric { Metric(name: "Sleep", short: "S", value: snapshot?.sleep, tint: color(0x8E8CFF)) }

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
        case .systemMedium:
            medium.containerBackground(for: .widget) { color(0x0D0E0F) }
        default:
            small.containerBackground(for: .widget) { color(0x0D0E0F) }
        }
    }

    // MARK: Home-Bildschirm

    /// Klein: Recovery groß, darunter Strain und Sleep als Kapseln.
    private var small: some View {
        VStack(spacing: 10) {
            ring(recovery, line: 9, font: .system(size: 30, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                capsule(strain)
                capsule(sleep)
            }
        }
        .foregroundStyle(ink)
    }

    /// Mittel: drei Ringe mit Zahl, Recovery etwas größer.
    private var medium: some View {
        HStack(spacing: 14) {
            labeledRing(recovery, line: 9, font: .system(size: 30, weight: .bold, design: .rounded))
            labeledRing(strain, line: 7, font: .system(size: 22, weight: .semibold, design: .rounded)).frame(maxWidth: 82)
            labeledRing(sleep, line: 7, font: .system(size: 22, weight: .semibold, design: .rounded)).frame(maxWidth: 82)
        }
        .foregroundStyle(ink)
    }

    private func labeledRing(_ metric: Metric, line: CGFloat, font: Font) -> some View {
        VStack(spacing: 6) {
            ring(metric, line: line, font: font)
            Text(metric.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(usesAppColors ? metric.tint : ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func capsule(_ metric: Metric) -> some View {
        HStack(spacing: 5) {
            Circle().fill(usesAppColors ? metric.tint : ink).frame(width: 6, height: 6)
            Text(verbatim: metric.display)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(ink.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.name)
        .accessibilityValue(metric.spoken)
        .privacySensitive()
    }

    private func ring(_ metric: Metric, line: CGFloat, font: Font) -> some View {
        let stroke = StrokeStyle(lineWidth: line, lineCap: .round)
        let tint = usesAppColors ? metric.tint : ink
        return ZStack {
            Circle().inset(by: line / 2).stroke(ink.opacity(0.16), style: stroke)
            if let value = metric.value, value > 0 {
                Circle()
                    .inset(by: line / 2)
                    .trim(from: 0, to: CGFloat(value) / 100)
                    .stroke(tint, style: stroke)
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
            Text(verbatim: metric.display)
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(line + 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.name)
        .accessibilityValue(metric.spoken)
        .privacySensitive()
    }

    // MARK: Sperrbildschirm

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            ring(recovery, line: 5, font: .system(size: 17, weight: .bold, design: .rounded))
                .padding(4)
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            ring(recovery, line: 5, font: .system(size: 17, weight: .bold, design: .rounded))
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

    private func color(_ hex: UInt32) -> Color {
        // Gleiche sRGB-Werte wie in der App, deren Theme im Widget-Target nicht verfügbar ist.
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
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
