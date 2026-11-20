import ActivityKit
import SwiftUI
import WidgetKit

struct FastingLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingAttributes.self) { context in
            FastingPresentation(context).summary
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .activityBackgroundTint(Color(white: 0.09))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let presentation = FastingPresentation(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    presentation.summary
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                presentation.ring.frame(width: 21, height: 21)
            } compactTrailing: {
                presentation.timer
                    .font(.caption2.weight(.semibold))
                    .frame(width: 53, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            } minimal: {
                presentation.ring.frame(width: 21, height: 21)
            }
        }
    }
}

private struct FastingPresentation {
    let attributes: FastingAttributes
    let state: FastingAttributes.ContentState
    let progress: FastingAttributes.Progress

    init(_ context: ActivityViewContext<FastingAttributes>) {
        let now = Date.now
        let attributes = context.attributes
        self.attributes = attributes
        state = context.state
        let date = context.isStale && context.state.end == nil ? max(now, attributes.timerInterval.upperBound) : now
        progress = attributes.progress(at: date, state: context.state)
    }

    // Dieselben Akzente wie in der Fasten-Ansicht der App.
    private var tint: Color {
        progress.reached
            ? Color(red: 61 / 255.0, green: 220 / 255.0, blue: 151 / 255.0)
            : Color(red: 1, green: 181 / 255.0, blue: 71 / 255.0)
    }

    var summary: some View {
        HStack(spacing: 12) {
            ring.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.reached ? "Ziel erreicht" : "Fasten")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                timer.font(.title2.weight(.semibold))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Text("\(attributes.targetHours, format: .number) h")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel("Ziel: \(attributes.targetHours, format: .number) Stunden")
        }
    }

    var ring: some View {
        Group {
            if state.end == nil, !progress.reached {
                ProgressView(timerInterval: attributes.timerInterval, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: progress.fraction)
            }
        }
        .progressViewStyle(.circular)
        .tint(tint)
        .accessibilityLabel("Fastenfortschritt")
    }

    var timer: some View {
        Group {
            if progress.reached {
                if let end = state.end {
                    Text(timerInterval: attributes.start...end, countsDown: false)
                } else {
                    Text(.currentDate, format: .stopwatch(startingAt: attributes.start, maxPrecision: .seconds(1)))
                }
            } else {
                Text(timerInterval: attributes.timerInterval,
                     pauseTime: state.end.map { max($0, attributes.start) }, countsDown: true)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}
