import SwiftUI
import WidgetKit

struct TodayHealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Today")
        .description("Sieh Recovery, Strain und Sleep auf einen Blick.")
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
            let expiry = TodayWidgetEntry(date: snapshot.expiry(in: .autoupdatingCurrent), snapshot: nil)
            completion(Timeline(entries: [entry, expiry], policy: .atEnd))
        } else {
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(30 * 60))))
        }
    }

    private func currentEntry(at date: Date) -> TodayWidgetEntry {
        let snapshot = WidgetSnapshotStore.shared.read()
        return TodayWidgetEntry(date: date, snapshot: snapshot.flatMap { $0.isCurrent(at: date) ? $0 : nil })
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: WidgetSnapshot?

    private var fullColor: Bool { renderingMode == .fullColor }
    private var ink: Color { fullColor ? .white : .primary }
    private var mutedInk: Color { fullColor ? Color(red: 0.72, green: 0.73, blue: 0.73) : .secondary }
    private var recovery: Int? { snapshot?.recovery }
    private var recoveryColor: Color {
        guard fullColor, let recovery else { return ink }
        if recovery >= 67 { return Color(red: 0.49, green: 0.88, blue: 0.61) }
        if recovery >= 34 { return Color(red: 0.99, green: 0.81, blue: 0.48) }
        return Color(red: 1.00, green: 0.60, blue: 0.54)
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
            home.containerBackground(for: .widget) {
                LinearGradient(colors: [Color(white: 0.105), Color(white: 0.055)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("RECOVERY")
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(mutedInk)
                .accessibilityHidden(true)
            GeometryReader { geometry in
                if family == .systemMedium {
                    HStack(spacing: 12) {
                        homeRecovery(maxDiameter: min(geometry.size.height, geometry.size.width * 0.42))
                            .frame(width: geometry.size.width * 0.43)
                        VStack(spacing: 6) {
                            metric("Strain", value: snapshot?.strain, color: Color(red: 0.42, green: 0.71, blue: 0.98))
                            metric("Sleep", value: snapshot?.sleep, color: Color(red: 0.68, green: 0.64, blue: 1.00))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    homeRecovery(maxDiameter: min(geometry.size.height, geometry.size.width))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let snapshot {
                Text("Stand \(snapshot.updatedAt, style: .time)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Text("Keine Messung")
                    .font(.caption2)
                    .foregroundStyle(mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(ink)
    }

    private func homeRecovery(maxDiameter: CGFloat) -> some View {
        let diameter = max(0, maxDiameter)
        return ZStack {
            RecoveryArc(value: recovery, color: recoveryColor, track: ink.opacity(0.17), lineWidth: 5)
            VStack(spacing: 0) {
                Text(recovery.map { "\($0)" } ?? "–")
                    .font(.system(size: max(12, min(diameter * 0.38, 44)), weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                if recovery != nil {
                    Text("%")
                        .font(.system(size: max(8, min(diameter * 0.15, 12)), weight: .semibold))
                        .foregroundStyle(mutedInk)
                } else if snapshot != nil && diameter >= 62 {
                    Text("Keine Messung")
                        .font(.system(size: 9))
                        .foregroundStyle(mutedInk)
                        .lineLimit(1)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery")
        .accessibilityValue(recovery.map { "\($0) Prozent" } ?? "Keine Messung")
        .privacySensitive()
    }

    private func metric(_ title: String, value: Int?, color: Color) -> some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(ink.opacity(0.19))
                .overlay(alignment: .bottom) {
                    if let value, value > 0 {
                        Capsule().fill(fullColor ? color : ink).frame(height: 19 * CGFloat(value) / 100)
                    }
                }
                .frame(width: 4, height: 19)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2.weight(.semibold))
                if let value {
                    Text("\(value)")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                } else {
                    Text("Keine Messung").font(.caption2).foregroundStyle(mutedInk)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(ink.opacity(0.07), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\($0) von 100" } ?? "Keine Messung")
        .privacySensitive()
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            RecoveryArc(value: recovery, color: .primary, track: .primary.opacity(0.28), lineWidth: 2)
                .padding(5)
            Text(recovery.map { "\($0)" } ?? "–")
                .font(.system(.headline, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery")
        .accessibilityValue(recovery.map { "\($0) Prozent" } ?? "Keine Messung")
        .privacySensitive()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recovery")
                .font(.caption.weight(.semibold))
            if let recovery, let snapshot {
                Text("\(recovery) % · \(snapshot.updatedAt, style: .time)")
                    .font(.headline.monospacedDigit())
                    .privacySensitive()
            } else {
                Text("Keine Messung").font(.caption2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var inline: some View {
        Label {
            if let recovery {
                Text("Recovery \(recovery) %").privacySensitive()
            } else {
                Text("Recovery · Keine Messung")
            }
        } icon: {
            Image(systemName: "heart")
        }
    }
}

private struct RecoveryArc: View {
    let value: Int?
    let color: Color
    let track: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75).stroke(track, style: stroke)
            if let value, value > 0 {
                Circle().trim(from: 0, to: 0.75 * CGFloat(value) / 100).stroke(color, style: stroke)
                    .widgetAccentable()
            }
        }
        .rotationEffect(.degrees(135))
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: lineWidth, lineCap: .round) }
}
