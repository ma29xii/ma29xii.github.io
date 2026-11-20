import SwiftUI
import WidgetKit

struct FastingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FastingWidgetStore.widgetKind, provider: FastingWidgetProvider()) { entry in
            FastingWidgetView(entry: entry)
        }
        .configurationDisplayName("Fasten")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct FastingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ma29xii.forma.toggle-fasting") {
            ControlWidgetButton(action: ToggleFastingIntent()) {
                Label("Fasten starten/beenden", systemImage: "timer")
            }
        }
        .displayName("Fasten starten/beenden")
    }
}

private struct FastingWidgetEntry: TimelineEntry {
    let date: Date
    let state: FastingWidgetStore.State?

    var presentation: FastingWidgetStore.Presentation? { state?.presentation(at: date) }
}

private struct FastingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingWidgetEntry {
        FastingWidgetEntry(date: .now, state: .init())
    }

    func getSnapshot(in context: Context, completion: @escaping (FastingWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context)
                   : FastingWidgetEntry(date: .now, state: try? FastingWidgetStore.shared.state()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingWidgetEntry>) -> Void) {
        let now = Date.now
        let state = try? FastingWidgetStore.shared.state()
        let current = FastingWidgetEntry(date: now, state: state)
        var entries = [current]
        if case .countdown(let session)? = current.presentation {
            let goal = session.timerInterval.upperBound
            // Der Text läuft live. Wenige vorher berechnete Einträge reichen für den gezeichneten Ring.
            let step = max(15 * 60, goal.timeIntervalSince(session.start) / 32)
            let remaining = goal.timeIntervalSince(now)
            for offset in stride(from: step, through: remaining - 5 * 60, by: step) {
                entries.append(FastingWidgetEntry(date: now.addingTimeInterval(offset), state: state))
            }
            entries.append(FastingWidgetEntry(date: goal, state: state))
        }
        let policy: TimelineReloadPolicy = state == nil ? .after(now.addingTimeInterval(15 * 60)) : .never
        completion(Timeline(entries: entries, policy: policy))
    }
}

private struct FastingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: FastingWidgetEntry

    private var isAccessory: Bool { family == .accessoryCircular }
    private var usesAppColors: Bool { !isAccessory && renderingMode == .fullColor && showsBackground }
    private var ink: Color { usesAppColors ? .white : .primary }
    private var controlsLabel: String { entry.state?.active == nil ? "Fasten starten" : "Fasten beenden" }
    private var tint: Color {
        guard usesAppColors else { return ink }
        if case .elapsed? = entry.presentation {
            return Color(red: 61 / 255.0, green: 220 / 255.0, blue: 151 / 255.0)
        }
        return Color(red: 1, green: 181 / 255.0, blue: 71 / 255.0)
    }

    var body: some View {
        Group {
            if isAccessory {
                if let state = entry.state {
                    Button(intent: ToggleFastingIntent(expectedActive: state.active != nil)) {
                        ring.contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(controlsLabel)
                } else {
                    ring
                }
            } else {
                VStack(spacing: 2) {
                    ring.frame(maxWidth: 76, maxHeight: 76)
                    if let state = entry.state {
                        Button(intent: ToggleFastingIntent(expectedActive: state.active != nil)) {
                            Text(state.active == nil ? "Starten" : "Beenden")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                                .background(tint.opacity(0.15), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(controlsLabel)
                        .layoutPriority(1)
                    }
                }
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            if !isAccessory { Color(red: 13 / 255.0, green: 14 / 255.0, blue: 15 / 255.0) }
        }
    }

    private var ring: some View {
        let stroke = StrokeStyle(lineWidth: 3, lineCap: .round)
        let fraction = entry.state?.active?.progress(at: entry.date, state: .init(end: nil)).fraction ?? 0
        return ZStack {
            Circle().strokeBorder(ink.opacity(0.20), style: stroke)
            if fraction > 0 {
                Circle()
                    .inset(by: stroke.lineWidth / 2)
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(tint, style: stroke)
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            ringText
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, isAccessory ? 4 : 7)
        }
        .accessibilityElement(children: .combine)
        .privacySensitive()
        .invalidatableContent()
    }

    @ViewBuilder
    private var ringText: some View {
        switch entry.presentation {
        case .idle(let planHours):
            Text("\(planHours, format: .number):\(max(0, 24 - planHours), format: .number)")
                .font(isAccessory ? .caption2.weight(.semibold) : .headline)
        case .countdown(let session):
            timeAndGoal(Text(timerInterval: session.timerInterval, countsDown: true), session: session)
        case .elapsed(let session):
            timeAndGoal(Text(.currentDate, format: .stopwatch(startingAt: session.start, maxPrecision: .seconds(1))),
                        session: session)
        case nil:
            Text("–").accessibilityLabel("Fastenstatus nicht verfügbar")
        }
    }

    private func timeAndGoal(_ timer: Text, session: FastingAttributes) -> some View {
        VStack(spacing: 1) {
            timer.font(isAccessory ? .system(.caption2, design: .rounded, weight: .semibold)
                        : .system(.subheadline, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
            Text("\(session.targetHours, format: .number) h")
                .font(isAccessory ? .system(size: 8) : .caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Ziel: \(session.targetHours, format: .number) Stunden")
        }
    }
}
