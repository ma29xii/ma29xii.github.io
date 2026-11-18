import SwiftUI

enum RingKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case strain, recovery, sleep
    var id: String { rawValue }

    var title: String {
        switch self {
        case .strain: "Strain"
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        }
    }
}

/// Der animierbare Wert treibt sowohl den Bogen als auch die Ziffern pro Frame.
struct RingView: View, Animatable {
    nonisolated var value: Double
    var color: Color
    var size: CGFloat
    var lineWidth: CGFloat
    var showsNumber = true
    var numberSize: CGFloat? = nil
    var missing = false
    var suffix = ""
    var subtitle: String? = nil

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let bounded = value.isFinite ? min(100, max(0, value)) : 0
        ZStack {
            Circle()
                .strokeBorder(Theme.track, lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: missing ? 0 : bounded / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(size < 40 ? 0 : 0.32), radius: lineWidth)
            if showsNumber {
                VStack(spacing: Space.s1) {
                    Text(missing ? "–" : "\(Int(bounded.rounded()))\(suffix)")
                        .font(.system(size: numberSize ?? size * 0.3, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(missing ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(.formaMicro)
                            .tracking(1.3)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.55)
                    }
                }
                .frame(width: size * 0.80)
            }
        }
        .frame(width: size, height: size)
    }
}
