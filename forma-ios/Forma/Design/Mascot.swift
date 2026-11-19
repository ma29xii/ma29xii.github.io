import SwiftUI

/// Stimmung des Coach-Begleiters.
enum MascotMood: String, CaseIterable, Sendable {
    /// Ruhig: das Licht atmet langsam.
    case calm
    /// Denkt nach: ein Glanz wandert über den Körper, die Lichtpunkte schauen nach oben.
    case thinking
    /// Freut sich: ein kurzer Hüpfer, das Innenleuchten wird heller.
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
}

/// Welche Stimmung der Coach-Chat zeigt. Reihenfolge: Nachdenken schlägt Freude schlägt Hinweis.
enum CoachMascotLogic {
    static func mood(thinking: Bool, justReplied: Bool, hasSuggestion: Bool) -> MascotMood {
        if thinking { return .thinking }
        if justReplied { return .happy }
        if hasSuggestion { return .hint }
        return .calm
    }

    /// Farbe des Innenleuchtens: die Recovery-Farbe von heute. Ohne Wert ein ruhiges, kühles Weiß.
    static func tint(recovery: Int?) -> Color {
        guard let recovery else { return Color(hex: 0xC9D3E3) }
        return Theme.recovery(recovery)
    }

    /// Höhe des Hüpfers von 0 bis 1 nach `elapsed` Sekunden: zwei kleine Sprünge, die abklingen.
    /// Danach (und davor) 0.
    static func hopHeight(elapsed: TimeInterval, duration: TimeInterval = 0.9) -> Double {
        guard elapsed >= 0, elapsed < duration else { return 0 }
        let p = elapsed / duration
        return abs(sin(p * 2 * .pi)) * (1 - 0.35 * p)
    }
}

/// „Lumo“: ein Körper aus dunklem Glas mit weichem Innenleuchten in der Recovery-Farbe und zwei Lichtpunkten
/// als Blick. Komplett in SwiftUI gezeichnet. Bei „Bewegung reduzieren“ (oder `animated == false`) steht er still.
struct Mascot: View {
    var mood: MascotMood = .calm
    var size: CGFloat = 96
    var tint: Color = Theme.recoveryHigh
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hopStart: Date?

    private var moves: Bool { animated && !reduceMotion }

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
        let d = size * 0.78
        let t = now?.timeIntervalSinceReferenceDate ?? 0
        var breath: CGFloat = 1
        if animatedFrame && mood != .happy { breath = 1 + 0.03 * CGFloat(sin(t * 2 * .pi / 4.2)) }
        var hop: CGFloat = 0
        var squash: CGFloat = 1
        if let now, let hopStart {
            let elapsed = now.timeIntervalSince(hopStart)
            hop = CGFloat(CoachMascotLogic.hopHeight(elapsed: elapsed))
            if elapsed >= 0 && elapsed < 0.9 { squash = 1 - 0.05 * (1 - hop) }
        }
        let tilt: Double = mood == .hint ? 8 + (animatedFrame ? 1.5 * sin(t * 2.2) : 0) : 0
        // 0…1, im Takt des Atmens; im Standbild die Mitte.
        let pulse: Double = animatedFrame ? 0.5 + 0.5 * sin(t * 2 * .pi / 4.2) : 0.5
        let lift: Double = mood == .happy ? 0.16 : (mood == .thinking ? 0.07 : 0)

        return ZStack(alignment: .bottom) {
            // Lichtschein um den Körper
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.2 + lift * 0.6 + 0.04 * pulse), .clear],
                                     center: .center, startRadius: d * 0.3, endRadius: d * 0.85))
                .frame(width: d * 1.7, height: d * 1.7)
                .offset(y: -size * 0.1)
            // Farbiges Licht auf dem Boden statt grauem Schatten
            Ellipse()
                .fill(tint.opacity(0.3 - 0.1 * Double(hop)))
                .frame(width: d * 0.6 * (1 - 0.25 * hop), height: d * 0.09)
                .blur(radius: d * 0.04)
            orb(d: d, t: t, pulse: pulse, lift: lift, animatedFrame: animatedFrame)
                .scaleEffect(x: breath / squash, y: breath * squash, anchor: .bottom)
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .offset(y: -size * 0.06 - hop * size * 0.12)
        }
        .frame(width: size, height: size * 1.1, alignment: .bottom)
    }

    private func orb(d: CGFloat, t: Double, pulse: Double, lift: Double, animatedFrame: Bool) -> some View {
        ZStack {
            // Körper: dunkles Glas mit feinem Verlauf
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x30343B), Color(hex: 0x0C0D10)], startPoint: .top, endPoint: .bottom))
            // Innenleuchten, von unten aufsteigend
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.6 + 0.14 * pulse + lift), tint.opacity(0.16), .clear],
                                     center: UnitPoint(x: 0.5, y: 0.82), startRadius: 0, endRadius: d * 0.66))
            // Warmer Kern im Leuchten
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.32 + 0.1 * pulse), .clear],
                                     center: UnitPoint(x: 0.5, y: 0.84), startRadius: 0, endRadius: d * 0.22))
            // Spiegelung oben: das Fenster im Glas
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: d * 0.6, height: d * 0.27)
                .blur(radius: d * 0.012)
                .offset(y: -d * 0.34)
            if mood == .thinking && animatedFrame {
                sweep(d: d, t: t)
            }
            lights(d: d, t: t, animatedFrame: animatedFrame)
                .offset(y: -d * 0.05)
            // Lichtkante: oben hell, unten in der Tagesfarbe
            Circle()
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.1), tint.opacity(0.55)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: max(1, d * 0.014))
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
    }

    /// Wandernder Glanz beim Nachdenken.
    private func sweep(d: CGFloat, t: Double) -> some View {
        let p = t.truncatingRemainder(dividingBy: 2.6) / 2.6
        return LinearGradient(colors: [.clear, Color.white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: d * 0.34, height: d * 1.4)
            .rotationEffect(.degrees(20))
            .offset(x: d * (p * 1.7 - 0.85))
            .frame(width: d, height: d)
            .clipShape(Circle())
            .allowsHitTesting(false)
    }

    /// Zwei Lichtpunkte statt gezeichneter Augen. Sie wandern, wenn Lumo nachdenkt, und blinzeln selten.
    private func lights(d: CGFloat, t: Double, animatedFrame: Bool) -> some View {
        let dot = d * 0.082 * (mood == .happy ? 1.2 : 1)
        let gap = d * (mood == .happy ? 0.17 : 0.2)
        var look = CGSize.zero
        switch mood {
        case .thinking:
            look = CGSize(width: d * 0.03 + (animatedFrame ? d * 0.025 * CGFloat(sin(t * 0.9)) : 0), height: -d * 0.05)
        case .hint:
            look = CGSize(width: d * 0.05, height: 0)
        case .happy:
            look = CGSize(width: 0, height: -d * 0.02)
        case .calm:
            break
        }
        // Blinzeln: alle 4,6 s kurz zu.
        let cycle = t.truncatingRemainder(dividingBy: 4.6)
        let open: CGFloat = animatedFrame && cycle > 4.45 ? max(0.15, CGFloat(abs(cycle - 4.525) / 0.075)) : 1

        return HStack(spacing: gap) {
            light(dot: dot, open: open)
            light(dot: dot, open: open)
        }
        .offset(look)
    }

    private func light(dot: CGFloat, open: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: dot, height: dot)
            .scaleEffect(y: open)
            .shadow(color: Color.white.opacity(0.85), radius: dot * 0.6)
            .shadow(color: tint.opacity(0.6), radius: dot * 1.6)
            .frame(width: dot * 1.2, height: dot * 1.2)
    }
}

/// Dezenter Lichtpunkt neben der letzten Coach-Antwort, in der Tagesfarbe. Kein Gesicht, für VoiceOver unsichtbar.
struct MascotBadge: View {
    var tint: Color = Theme.recoveryHigh
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color.white.opacity(0.9), tint, tint.opacity(0.5)],
                                 center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 6))
            .frame(width: 9, height: 9)
            .shadow(color: tint.opacity(0.55), radius: 4)
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }
}
