import SwiftUI

/// Stimmung des Coach-Begleiters.
enum MascotMood: String, CaseIterable, Sendable {
    /// Ruhig: das Licht atmet langsam.
    case calm
    /// Denkt nach: das Licht atmet schneller, feine Ringe laufen nach außen.
    case thinking
    /// Freut sich: ein kurzes Aufleuchten mit einem Ring, ein kleiner Auftrieb.
    case happy
    /// Hat einen Hinweis: ein kleiner Lichtpunkt umkreist ihn.
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

    /// Farbe des Lichts: die Recovery-Farbe von heute. Ohne Wert ein ruhiges, kühles Weiß.
    static func tint(recovery: Int?) -> Color {
        guard let recovery else { return Color(hex: 0xC9D3E3) }
        return Theme.recovery(recovery)
    }

    /// Höhe des Auftriebs von 0 bis 1 nach `elapsed` Sekunden: zwei kleine Wellen, die abklingen.
    /// Danach (und davor) 0.
    static func hopHeight(elapsed: TimeInterval, duration: TimeInterval = 0.9) -> Double {
        guard elapsed >= 0, elapsed < duration else { return 0 }
        let p = elapsed / duration
        return abs(sin(p * 2 * .pi)) * (1 - 0.35 * p)
    }
}

/// „Lumo“: ein ruhiger, atmender Lichtpunkt ohne Gesicht. Eine Kugel in der Tagesfarbe mit weichem Schein.
/// Beim Nachdenken atmet er schneller und sendet feine Ringe aus. Komplett in SwiftUI gezeichnet.
/// Bei „Bewegung reduzieren“ (oder `animated == false`) steht er still.
struct Mascot: View {
    var mood: MascotMood = .calm
    var size: CGFloat = 96
    var tint: Color = Theme.accent
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hopStart: Date?

    private var moves: Bool { animated && !reduceMotion }

    var body: some View {
        Group {
            if moves {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    figure(now: context.date)
                }
            } else {
                figure(now: nil)
            }
        }
        .frame(width: size, height: size * 1.1)
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: mood)
        .onChange(of: mood, initial: true) { _, new in
            hopStart = (new == .happy && moves) ? .now : nil
        }
    }

    // MARK: Zeichnung

    private func figure(now: Date?) -> some View {
        let d = size * 0.46
        let t = now?.timeIntervalSinceReferenceDate ?? 0
        let animatedFrame = now != nil
        let period: Double = mood == .thinking ? 2.2 : 4.2
        // 0…1 im Takt des Atmens; im Standbild die Mitte.
        let pulse: Double = animatedFrame ? 0.5 + 0.5 * sin(t * 2 * .pi / period) : 0.5
        let breath = CGFloat(1 + 0.06 * (pulse - 0.5))

        var lift = 0.0
        var rise: CGFloat = 0
        var happyRing: Double?
        if let now, let hopStart {
            let elapsed = now.timeIntervalSince(hopStart)
            lift = CoachMascotLogic.hopHeight(elapsed: elapsed)
            rise = CGFloat(lift)
            if elapsed >= 0 && elapsed < 1.2 { happyRing = elapsed / 1.2 }
        }
        let glow = 0.34 + 0.14 * pulse + 0.18 * lift + (mood == .thinking ? 0.06 : 0)

        return ZStack {
            // Schein
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(glow), .clear],
                                     center: .center, startRadius: d * 0.25, endRadius: d * 1.05))
                .frame(width: d * 2.1, height: d * 2.1)
            // Ringe: beim Nachdenken zwei versetzt, bei Freude einer
            if animatedFrame && mood == .thinking {
                ring(d: d, progress: (t / 2.4).truncatingRemainder(dividingBy: 1))
                ring(d: d, progress: ((t + 1.2) / 2.4).truncatingRemainder(dividingBy: 1))
            }
            if let happyRing { ring(d: d, progress: happyRing) }
            // Hinweis: ein kleiner Lichtpunkt auf der Bahn
            if mood == .hint {
                let angle = animatedFrame ? t * 2 * .pi / 6 : -.pi / 4
                Circle()
                    .fill(Color.white)
                    .frame(width: d * 0.12, height: d * 0.12)
                    .shadow(color: tint.opacity(0.9), radius: d * 0.08)
                    .offset(x: d * 0.78 * CGFloat(cos(angle)), y: d * 0.78 * CGFloat(sin(angle)))
            }
            orb(d: d)
                .scaleEffect(breath)
        }
        .offset(y: -size * 0.05 * rise)
        .frame(width: size, height: size * 1.1)
    }

    /// Kugel: Tagesfarbe, oben links ein weicher Lichtfleck, am Rand etwas Tiefe.
    private func orb(d: CGFloat) -> some View {
        Circle()
            .fill(tint)
            .overlay(
                Circle().fill(RadialGradient(colors: [Color.white.opacity(0.6), .clear],
                                             center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: d * 0.55))
            )
            .overlay(
                Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.32)],
                                             center: .center, startRadius: d * 0.22, endRadius: d * 0.52))
            )
            .frame(width: d, height: d)
            .shadow(color: tint.opacity(0.5), radius: d * 0.3)
    }

    /// Feiner Ring, der sich ausdehnt und dabei verblasst.
    private func ring(d: CGFloat, progress: Double) -> some View {
        Circle()
            .strokeBorder(tint.opacity((1 - progress) * 0.5), lineWidth: 1.2)
            .frame(width: d * (1 + 0.9 * CGFloat(progress)), height: d * (1 + 0.9 * CGFloat(progress)))
    }
}

/// Dezenter Lichtpunkt neben der letzten Coach-Antwort, in der Tagesfarbe. Kein Gesicht, für VoiceOver unsichtbar.
struct MascotBadge: View {
    var tint: Color = Theme.accent
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
