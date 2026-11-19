import SwiftUI

/// Farbwelt des Partikelkreises: grün = jünger, warm = älter, Graphit ohne Wert.
enum OrbMood: Equatable, Sendable {
    case younger, older, even, none

    init(difference: Double?) {
        guard let difference else {
            self = .none
            return
        }
        if abs(difference) < 0.05 {
            self = .even
        } else {
            self = difference < 0 ? .younger : .older
        }
    }

    /// Rand (hell), Mitte des Verlaufs, Tiefe (fast schwarz).
    var rim: Color {
        switch self {
        case .younger: Color(hex: 0x7CF5C0)
        case .older: Color(hex: 0xFFC27A)
        case .even: Color(hex: 0xCFE9DF)
        case .none: Color(hex: 0x8E9196)
        }
    }

    var mid: Color {
        switch self {
        case .younger: Color(hex: 0x1FA67A)
        case .older: Color(hex: 0xE0703C)
        case .even: Color(hex: 0x5E8F80)
        case .none: Color(hex: 0x45484C)
        }
    }

    var deep: Color {
        switch self {
        case .younger: Color(hex: 0x06261C)
        case .older: Color(hex: 0x2A1208)
        case .even: Color(hex: 0x111C18)
        case .none: Color(hex: 0x141517)
        }
    }
}

/// Kreis aus vielen feinen Lichtpunkten, zum Rand hin dichter, ruhig schwebend. Reduce Motion: steht still.
struct AgeOrb: View {
    let mood: OrbMood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tick in
            let t = reduceMotion ? 0 : tick.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.draw(in: &context, size: size, time: t, mood: mood)
            }
        }
        .accessibilityHidden(true)
    }

    struct Particle: Sendable {
        let angle: Double
        /// 0 = Mitte, 1 = Rand.
        let radius: Double
        let size: Double
        let brightness: Double
        let speed: Double
        let phase: Double
        let light: Bool
    }

    /// Feste Verteilung (gleiches Bild bei jedem Start): viele Punkte am Rand, nach innen ausdünnend.
    static let particles: [Particle] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<1100).map { _ in
            // pow(…, 3) drückt die meisten Punkte an den Rand; innen bleibt es dunkel.
            let depth = pow(random(), 3)
            return Particle(angle: random() * 2 * .pi,
                            radius: 1 - depth * 0.62,
                            size: 0.6 + random() * random() * 2.4,
                            brightness: 0.25 + random() * 0.75,
                            speed: 0.15 + random() * 0.45,
                            phase: random() * 2 * .pi,
                            light: random() < 0.18)
        }
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, mood: OrbMood) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = min(size.width, size.height) / 2 * 0.94
        // Zarter Lichtsaum unter den Punkten.
        let halo = Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        context.fill(halo, with: .radialGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0.55),
                .init(color: mood.mid.opacity(0.22), location: 0.9),
                .init(color: .clear, location: 1)
            ]),
            center: center, startRadius: 0, endRadius: outer))
        for p in particles {
            // Jeder Punkt schwebt auf einer eigenen kleinen Bahn und flimmert leicht.
            let drift = sin(t * p.speed + p.phase)
            let angle = p.angle + drift * 0.012 + t * 0.004
            let radius = outer * CGFloat(min(1, p.radius + cos(t * p.speed * 0.8 + p.phase) * 0.012))
            let x = center.x + radius * CGFloat(cos(angle))
            let y = center.y + radius * CGFloat(sin(angle))
            let twinkle = 0.65 + 0.35 * sin(t * p.speed * 2.2 + p.phase * 3)
            let opacity = p.brightness * twinkle * (0.35 + 0.65 * p.radius)
            let d = CGFloat(p.size)
            context.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                         with: .color((p.light ? mood.rim : mood.mid).opacity(opacity)))
        }
    }
}
