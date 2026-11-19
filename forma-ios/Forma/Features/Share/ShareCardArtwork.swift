import SwiftUI

enum ShareCardFormat: String, CaseIterable, Identifiable, Sendable {
    case story, square

    var id: String { rawValue }
    var title: String { self == .story ? "Story" : "Quadratisch" }
    var height: CGFloat { self == .story ? 640 : 360 }
    var aspectRatio: CGFloat { 360 / height }
}

struct ShareCardArtwork: View {
    let display: ShareCardContent.Display
    let format: ShareCardFormat

    private var usesMetricRows: Bool { display.metrics.count > 1 }

    private var motifSize: CGFloat {
        if format == .story { return 208 }
        return usesMetricRows ? 88 : 124
    }

    private var tint: Color {
        switch display.kind {
        case .today: Color(hex: 0xBDB2FF)
        case .training: Color(hex: 0xEDC48B)
        case .healthAge: Color(hex: 0xA5D7C9)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("HEALTH").tracking(3.2)
                Spacer()
                if display.isSample { Text("BEISPIELDATEN").tracking(1.3) }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(hex: 0xC2C1C7))

            Spacer(minLength: 12)
            ShareCardMotif(kind: display.kind, tint: tint)
                .frame(width: motifSize, height: motifSize)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 12)

            Text(display.kind.title)
                .font(.system(size: format == .story ? 51 : 42, weight: .semibold))
                .tracking(-1.6)
            if let date = display.date {
                Text(date)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xC2C1C7))
                    .padding(.top, 4)
            }
            if !display.metrics.isEmpty {
                stats.padding(.top, usesMetricRows ? 14 : 18)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, format == .story ? 84 : 24)
        .frame(width: 360, height: format.height, alignment: .topLeading)
        .foregroundStyle(Color(hex: 0xF8F6F3))
        .background {
            Color(hex: 0x111113)
            RadialGradient(colors: [tint.opacity(0.23), .clear],
                           center: UnitPoint(x: 0.52, y: 0.42), startRadius: 14, endRadius: 252)
        }
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(tint.opacity(0.43)).frame(height: 1)
            if usesMetricRows {
                VStack(spacing: 5) {
                    ForEach(display.metrics) { metric in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            metricLabel(metric)
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                            metricValue(metric, size: 22)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else if let metric = display.metrics.first {
                VStack(alignment: .leading, spacing: 5) {
                    metricValue(metric, size: 28)
                    metricLabel(metric)
                }
            }
        }
    }

    private func metricValue(_ metric: ShareCardContent.Metric, size: CGFloat) -> some View {
        Text(metric.value)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }

    private func metricLabel(_ metric: ShareCardContent.Metric) -> some View {
        Text(metric.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(hex: 0xC2C1C7))
    }
}

/// Die Grafik bleibt unabhängig von Messwerten, auch im Format ohne Werte.
private struct ShareCardMotif: View {
    let kind: ShareCardContent.Kind
    let tint: Color

    var body: some View {
        ZStack {
            Circle().strokeBorder(tint.opacity(0.24), lineWidth: 1)
            Circle().inset(by: 9).strokeBorder(tint.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
            content.padding(17)
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .today:
            ZStack {
                orbit(angle: -26, color: tint)
                orbit(angle: 34, color: Color(hex: 0xA9E3C8))
                orbit(angle: 93, color: Color(hex: 0x8FC4EE))
                Circle().fill(Color.white.opacity(0.84)).frame(width: 5, height: 5)
            }
        case .training:
            ZStack {
                ForEach(0..<5) { index in
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tint.opacity(0.9 - Double(index) * 0.12), lineWidth: 1)
                        .rotationEffect(.degrees(45 - Double(index) * 7))
                        .padding(14 + CGFloat(index) * 5)
                }
            }
        case .healthAge:
            ZStack {
                Circle().fill(RadialGradient(colors: [tint.opacity(0.44), tint.opacity(0.04)],
                                              center: .topLeading, startRadius: 3, endRadius: 105))
                Circle().strokeBorder(tint.opacity(0.75), lineWidth: 1)
                ForEach(0..<5) { index in
                    Ellipse().strokeBorder(tint.opacity(0.28 + Double(index) * 0.08), lineWidth: 1)
                        .scaleEffect(x: 1, y: 0.22 + CGFloat(index) * 0.17)
                        .rotationEffect(.degrees(-24))
                }
            }
        }
    }

    private func orbit(angle: Double, color: Color) -> some View {
        Ellipse().trim(from: 0.02, to: 0.93)
            .stroke(color.opacity(0.86), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            .scaleEffect(x: 0.96, y: 0.51)
            .rotationEffect(.degrees(angle))
    }
}
