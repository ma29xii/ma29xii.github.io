import SwiftUI

/// Stimmung des Coach-Begleiters.
enum MascotMood: String, CaseIterable, Sendable {
    /// Ruhig, atmet langsam.
    case calm
    /// Denkt nach: ein Glanz wandert über den Körper, der Blick wandert nach oben.
    case thinking
    /// Freut sich: ein kurzer Hüpfer, lächelnde Augen.
    case happy
    /// Hat einen Hinweis: neigt sich zur Seite.
    case hint

    var accessibilityText: String {
        switch self {
        case .calm: "Dein Coach ist bereit"
        case .thinking: "Dein Coach denkt nach"
        case .happy: "Dein Coach freut sich"
        case .hint: "Dein Coach hat einen Vorschlag"
        }
    }

    /// Farbe des Lichtscheins hinter der Figur. Dezent, die Figur selbst bleibt hell und neutral.
    var halo: Color {
        switch self {
        case .calm: Color.white
        case .thinking: Theme.sleep
        case .happy: Theme.younger
        case .hint: Theme.warning
        }
    }
}

/// Welche Stimmung der Coach-Chat zeigt. Reihenfolge: Nachdenken schlägt Freude schlägt Hinweis.
enum CoachMascotLogic {
    static func mood(thinking: Bool, justReplied: Bool, hasSuggestion: Bool) -> MascotMood {
        if thinking { return .thinking }
        if justReplied { return .happy }
        if hasSuggestion { return .hint }
        return .calm
    }

    /// Höhe des Hüpfers von 0 bis 1 nach `elapsed` Sekunden: zwei kleine Sprünge, die abklingen.
    /// Danach (und davor) 0.
    static func hopHeight(elapsed: TimeInterval, duration: TimeInterval = 0.9) -> Double {
        guard elapsed >= 0, elapsed < duration else { return 0 }
        let p = elapsed / duration
        return abs(sin(p * 2 * .pi)) * (1 - 0.35 * p)
    }
}

/// „Lumo“: ein runder Licht-Begleiter aus Glanz und Schatten, komplett in SwiftUI gezeichnet.
/// Bei „Bewegung reduzieren“ (oder `animated == false`) steht er als ruhiges Standbild da.
struct Mascot: View {
    var mood: MascotMood = .calm
    var size: CGFloat = 96
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hopStart: Date?

    private var moves: Bool { animated && !reduceMotion }
    private let ink = Theme.onSelection

    var body: some View {
        Group {
            if moves {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    figure(now: context.date, animatedFrame: true)
                }
            } else {
                figure(now: nil, animatedFrame: false)
            }
        }
        .frame(width: size, height: size * 1.1)
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: mood)
        .onChange(of: mood, initial: true) { _, new in
            hopStart = (new == .happy && moves) ? .now : nil
        }
    }

    // MARK: Zeichnung

    private func figure(now: Date?, animatedFrame: Bool) -> some View {
        let d = size * 0.8
        let t = now?.timeIntervalSinceReferenceDate ?? 0
        var breath: CGFloat = 1
        if animatedFrame && mood != .happy { breath = 1 + 0.035 * CGFloat(sin(t * 2 * .pi / 4.2)) }
        var hop: CGFloat = 0
        var squash: CGFloat = 1
        if let now, let hopStart {
            let elapsed = now.timeIntervalSince(hopStart)
            hop = CGFloat(CoachMascotLogic.hopHeight(elapsed: elapsed))
            if elapsed >= 0 && elapsed < 0.9 { squash = 1 - 0.05 * (1 - hop) }
        }
        let tilt = mood == .hint ? 9 + (animatedFrame ? 1.5 * sin(t * 2.2) : 0) : 0

        return ZStack(alignment: .bottom) {
            // Lichtschein
            Circle()
                .fill(RadialGradient(colors: [mood.halo.opacity(0.22), .clear],
                                     center: .center, startRadius: d * 0.35, endRadius: d * 0.78))
                .frame(width: d * 1.55, height: d * 1.55)
                .offset(y: -size * 0.1)
            // Schatten am Boden
            Ellipse()
                .fill(Color.black.opacity(0.38 - 0.12 * Double(hop)))
                .frame(width: d * 0.62 * (1 - 0.25 * hop), height: d * 0.1)
                .blur(radius: d * 0.025)
            orb(d: d, t: t, animatedFrame: animatedFrame)
                .scaleEffect(x: breath / squash, y: breath * squash, anchor: .bottom)
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .offset(y: -size * 0.06 - hop * size * 0.12)
        }
        .frame(width: size, height: size * 1.1, alignment: .bottom)
    }

    private func orb(d: CGFloat, t: Double, animatedFrame: Bool) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xD9DBE0), Color(hex: 0xA3A6AF)],
                                     center: UnitPoint(x: 0.36, y: 0.28), startRadius: 0, endRadius: d * 0.85))
            Circle()
                .fill(LinearGradient(colors: [.clear, Color.black.opacity(0.2)], startPoint: .center, endPoint: .bottom))
            Circle()
                .strokeBorder(Color.white.opacity(0.55), lineWidth: max(1, d * 0.012))
            // Glanzpunkt
            Ellipse()
                .fill(Color.white.opacity(0.6))
                .frame(width: d * 0.3, height: d * 0.14)
                .rotationEffect(.degrees(-28))
                .blur(radius: d * 0.012)
                .offset(x: -d * 0.2, y: -d * 0.3)
            if mood == .thinking && animatedFrame {
                sweep(d: d, t: t)
            }
            face(d: d, t: t, animatedFrame: animatedFrame)
                .offset(y: -d * 0.02)
        }
        .frame(width: d, height: d)
    }

    /// Wandernder Glanz beim Nachdenken.
    private func sweep(d: CGFloat, t: Double) -> some View {
        let p = t.truncatingRemainder(dividingBy: 2.6) / 2.6
        return LinearGradient(colors: [.clear, Color.white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: d * 0.38, height: d * 1.4)
            .rotationEffect(.degrees(20))
            .offset(x: d * (p * 1.7 - 0.85))
            .frame(width: d, height: d)
            .clipShape(Circle())
            .allowsHitTesting(false)
    }

    private func face(d: CGFloat, t: Double, animatedFrame: Bool) -> some View {
        let eyeW = d * 0.1
        let eyeH = d * 0.17
        let gap = d * 0.22
        let look: CGSize
        switch mood {
        case .thinking: look = CGSize(width: d * 0.03 + (animatedFrame ? d * 0.03 * CGFloat(sin(t * 0.9)) : 0), height: -d * 0.045)
        case .hint: look = CGSize(width: d * 0.045, height: 0)
        default: look = .zero
        }
        // Blinzeln: alle 4,6 s kurz zu.
        let cycle = t.truncatingRemainder(dividingBy: 4.6)
        let open: CGFloat = animatedFrame && cycle > 4.45 ? max(0.12, CGFloat(abs(cycle - 4.525) / 0.075)) : 1

        return VStack(spacing: d * 0.07) {
            HStack(spacing: gap) {
                eye(width: eyeW, height: eyeH, open: open)
                eye(width: eyeW, height: eyeH, open: open)
            }
            .offset(look)
            smile(d: d)
        }
    }

    @ViewBuilder private func eye(width: CGFloat, height: CGFloat, open: CGFloat) -> some View {
        if mood == .happy {
            EyeArc()
                .stroke(ink, style: StrokeStyle(lineWidth: width * 0.5, lineCap: .round))
                .frame(width: width * 1.5, height: height * 0.4)
                .frame(width: width, height: height)
        } else {
            Capsule()
                .fill(ink)
                .frame(width: width, height: height * open)
                .frame(width: width, height: height)
        }
    }

    private func smile(d: CGFloat) -> some View {
        let wide: CGFloat
        let deep: CGFloat
        switch mood {
        case .happy: wide = d * 0.24; deep = d * 0.1
        case .calm: wide = d * 0.14; deep = d * 0.04
        case .hint: wide = d * 0.12; deep = d * 0.03
        case .thinking: wide = d * 0.08; deep = d * 0.012
        }
        return Smile()
            .stroke(ink, style: StrokeStyle(lineWidth: max(1.5, d * 0.028), lineCap: .round))
            .frame(width: wide, height: max(deep, 1))
            .frame(width: d * 0.24, height: d * 0.1, alignment: .top)
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2))
        return p
    }
}

/// Geschlossenes, lächelndes Auge (^).
private struct EyeArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: 2 * rect.minY - rect.maxY))
        return p
    }
}

/// Kleine, stille Version neben Chat-Antworten (Standbild, für VoiceOver unsichtbar).
struct MascotBadge: View {
    var mood: MascotMood = .calm
    var size: CGFloat = 28
    var body: some View {
        Mascot(mood: mood, size: size, animated: false)
            .accessibilityHidden(true)
    }
}
