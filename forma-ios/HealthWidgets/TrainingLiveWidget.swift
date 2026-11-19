import ActivityKit
import SwiftUI
import WidgetKit

struct TrainingLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveTrainingAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Training", systemImage: "dumbbell.fill")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PauseStatus(state: context.state, isStale: context.isStale)
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    exercise(context.state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 3)
                }
            } compactLeading: {
                Image(systemName: pauseInterval(context) == nil ? "dumbbell.fill" : "timer")
                    .accessibilityLabel(pauseInterval(context) == nil ? "Training" : "Pause")
            } compactTrailing: {
                compactStatus(context)
            } minimal: {
                Image(systemName: pauseInterval(context) == nil ? "dumbbell.fill" : "timer")
                    .accessibilityLabel(pauseInterval(context) == nil ? "Training" : "Pause")
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<LiveTrainingAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("TRAINING", systemImage: "dumbbell.fill")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Color(white: 0.76))
                Spacer(minLength: 4)
                PauseStatus(state: context.state, isStale: context.isStale)
                    .font(.subheadline.weight(.semibold))
            }
            exercise(context.state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(.white)
        .activityBackgroundTint(Color(white: 0.09))
        .activitySystemActionForegroundColor(.white)
    }

    private func exercise(_ state: LiveTrainingAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let name = state.exerciseName {
                Text(name).font(.headline).lineLimit(2)
            } else {
                Text("Training läuft").font(.headline)
            }
            if state.isWarmup {
                Text("Aufwärmen").font(.caption).foregroundStyle(.secondary)
            } else if let setNumber = state.setNumber {
                Text("Satz \(setNumber)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .privacySensitive()
    }

    @ViewBuilder
    private func compactStatus(_ context: ActivityViewContext<LiveTrainingAttributes>) -> some View {
        if let interval = pauseInterval(context) {
            PauseCountdown(interval: interval).font(.caption.weight(.semibold))
        } else if context.state.pauseEndsAt != nil {
            Text("Weiter").font(.caption.weight(.semibold))
        } else if let setNumber = context.state.setNumber {
            Text("Satz \(setNumber)").font(.caption.weight(.semibold).monospacedDigit()).privacySensitive()
        } else if context.state.isWarmup {
            Text("Aufwärmen").font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75).privacySensitive()
        } else {
            Text("Live").font(.caption.weight(.semibold))
        }
    }

    private func pauseInterval(_ context: ActivityViewContext<LiveTrainingAttributes>) -> ClosedRange<Date>? {
        context.isStale ? nil : context.state.pauseInterval(at: .now)
    }
}

private struct PauseStatus: View {
    let state: LiveTrainingAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if !isStale, let interval = state.pauseInterval(at: .now) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Text("Pause")
                    PauseCountdown(interval: interval)
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .combine)
                PauseCountdown(interval: interval)
            }
        } else if state.pauseEndsAt != nil {
            Text("Pause vorbei").lineLimit(1)
        }
    }
}

private struct PauseCountdown: View {
    let interval: ClosedRange<Date>

    var body: some View {
        Text(timerInterval: interval, countsDown: true,
             showsHours: interval.upperBound.timeIntervalSince(interval.lowerBound) >= 3600)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: true, vertical: false)
    }
}
