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
        case .younger: Color(hex: 0xA4FFE1)
        case .older: Color(hex: 0xFFC27A)
        case .even: Color(hex: 0xCFE9DF)
        case .none: Color(hex: 0x8E9196)
        }
    }

    var mid: Color {
        switch self {
        case .younger: Color(hex: 0x10E4A4)
        case .older: Color(hex: 0xE0703C)
        case .even: Color(hex: 0x5E8F80)
        case .none: Color(hex: 0x45484C)
        }
    }

    var deep: Color {
        switch self {
        case .younger: Color(hex: 0x0B614C)
        case .older: Color(hex: 0x2A1208)
        case .even: Color(hex: 0x111C18)
        case .none: Color(hex: 0x141517)
        }
    }
}

/// Statisches Partikelfeld mit heller Außenkante und ruhiger Mitte für die Zahl.
struct AgeOrb: View {
    let mood: OrbMood

    var body: some View {
        Canvas { context, size in
            Self.draw(in: context, size: size, mood: mood)
        }
        .accessibilityHidden(true)
    }

    struct Particle: Sendable {
        let angle: Double
        let radius: Double
        let size: Double
        let tone: Int
    }

    nonisolated static let particles: [Particle] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<3200).map { _ in
            let angle = random() * 2 * .pi
            let depth = pow(random(), 2.5)
            let ridge = sin(angle * 5 + depth * 20) * 0.016 + cos(angle * 11 - depth * 12) * 0.011
            let radius = min(0.99, 0.976 - depth * 0.51 + ridge)
            let light = random() * 0.62 + radius * 0.45 + sin(angle + 0.45) * 0.085
            let tone = min(4, max(0, Int(light * 4)))
            let size = 0.48 + pow(random(), 2.6) * (tone >= 3 ? 2.05 : 1.38)
            return Particle(angle: angle, radius: radius, size: size, tone: tone)
        }
    }()

    private static func draw(in context: GraphicsContext, size: CGSize, mood: OrbMood) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = min(size.width, size.height) / 2 - 3
        guard outer > 0 else { return }
        let disk = Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        context.fill(disk, with: .radialGradient(
            Gradient(stops: [
                .init(color: .black.opacity(0.28), location: 0),
                .init(color: .black.opacity(0.12), location: 0.52),
                .init(color: mood.deep.opacity(0.19), location: 0.86),
                .init(color: mood.deep.opacity(0.27), location: 1)
            ]),
            center: center, startRadius: 0, endRadius: outer))

        let colors = [
            mood.deep.opacity(0.32), mood.mid.opacity(0.22), mood.mid.opacity(0.52),
            mood.mid.opacity(0.88), mood.rim.opacity(0.96)
        ]
        var paths = Array(repeating: Path(), count: colors.count)
        for particle in particles {
            let radius = outer * CGFloat(particle.radius)
            let x = center.x + radius * CGFloat(cos(particle.angle))
            let y = center.y + radius * CGFloat(sin(particle.angle))
            let diameter = CGFloat(particle.size)
            paths[particle.tone].addEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2,
                                                       width: diameter, height: diameter))
        }
        for index in paths.indices {
            context.fill(paths[index], with: .color(colors[index]))
        }
    }
}
