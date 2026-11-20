import SwiftUI
import WidgetKit

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WaterWidgetStore.widgetKind, provider: WaterWidgetProvider()) { entry in
            WaterWidgetView(progress: entry.progress)
        }
        .configurationDisplayName("Wasser")
        .description("Sieh dein Tagesziel und trage mit einem Tipp 250 ml ein.")
        .supportedFamilies([.systemSmall])
    }
}

struct AddWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ma29xii.forma.add-water") {
            ControlWidgetButton(action: AddWaterIntent()) {
                Label("Wasser +250 ml", systemImage: "drop.fill")
            }
        }
        .displayName("Wasser +250 ml")
        .description("Trage mit einem Tipp ein Glas Wasser ein.")
    }
}

private struct WaterWidgetEntry: TimelineEntry {
    let date: Date
    let progress: WaterWidgetProgress?
}

private struct WaterWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterWidgetEntry {
        WaterWidgetEntry(date: .now, progress: WaterWidgetProgress(milliliters: 750, goalMilliliters: 2_500))
    }

    func getSnapshot(in context: Context, completion: @escaping (WaterWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now, calendar: .current))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterWidgetEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let current = entry(at: now, calendar: calendar)
        let nextCheck = now.addingTimeInterval(60 * 60)
        guard let midnight = calendar.dateInterval(of: .day, for: now)?.end else {
            completion(Timeline(entries: [current], policy: .after(nextCheck)))
            return
        }
        completion(Timeline(entries: [current, entry(at: midnight, calendar: calendar)],
                            policy: .after(min(midnight, nextCheck))))
    }

    private func entry(at date: Date, calendar: Calendar) -> WaterWidgetEntry {
        WaterWidgetEntry(date: date, progress: try? WaterWidgetStore.shared.progress(at: date, calendar: calendar))
    }
}

private struct WaterWidgetView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let progress: WaterWidgetProgress?

    private var style: WidgetStyle { WidgetStyle(renderingMode: renderingMode, showsBackground: showsBackground) }
    private var ink: Color { style.ink }
    private var tint: Color { style.accent }

    var body: some View {
        VStack(spacing: 2) {
            ring
            Button(intent: AddWaterIntent()) {
                Text("+250 ml")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                    .background(tint.opacity(0.15), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("250 Milliliter Wasser eintragen")
            .layoutPriority(1)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { style.background() }
    }

    private var ring: some View {
        let stroke = StrokeStyle(lineWidth: 5, lineCap: .round)
        return ZStack {
            Circle().inset(by: stroke.lineWidth / 2).stroke(style.track, style: stroke)
            if let progress, progress.fraction > 0 {
                Circle()
                    .inset(by: stroke.lineWidth / 2)
                    .trim(from: 0, to: CGFloat(progress.fraction))
                    .stroke(tint, style: stroke)
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 76, maxHeight: 76)
        .overlay {
            VStack(spacing: 1) {
                if let progress {
                    Text(progress.milliliters, format: .number.precision(.fractionLength(0)))
                        .font(.widgetNumber(24))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("ml")
                        .font(.caption2)
                } else {
                    Text("–")
                        .font(.headline)
                }
            }
            .padding(.horizontal, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wasser heute")
        .accessibilityValue(spokenProgress)
        .privacySensitive()
        .invalidatableContent()
    }

    private var spokenProgress: String {
        guard let progress else { return "Wasserstand nicht verfügbar" }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        return "\(progress.milliliters.formatted(format)) von \(progress.goalMilliliters.formatted(format)) Millilitern"
    }
}
