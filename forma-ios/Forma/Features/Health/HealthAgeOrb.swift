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

/// Partikelfeld mit heller Außenkante und ruhiger Mitte für die Zahl.
struct AgeOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    let mood: OrbMood

    var body: some View {
        let paused = reduceMotion || scenePhase != .active || !isVisible
        let mood = mood
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { tick in
            let phase = reduceMotion ? 0 : Self.phase(at: tick.date)
            Canvas { context, size in
                Self.draw(in: context, size: size, mood: mood, phase: phase)
            }
        }
        .onScrollVisibilityChange(threshold: 0.15) { isVisible = $0 }
        .accessibilityHidden(true)
    }

    private enum Depth: Int, CaseIterable {
        case inner, middle, edge

        init(radius: Double) {
            if radius < 0.69 { self = .inner }
            else if radius < 0.89 { self = .middle }
            else { self = .edge }
        }

        func motion(at phase: Double) -> (rotation: Double, scale: Double, opacity: Double) {
            switch self {
            case .inner:
                (2 * phase, 1 + 0.018 * sin(3 * phase), 0.89 + 0.11 * cos(4 * phase))
            case .middle:
                (-phase, 1 + 0.009 * sin(4 * phase), 0.92 + 0.08 * cos(3 * phase))
            case .edge:
                (phase, 1 + 0.005 * sin(2 * phase), 0.95 + 0.05 * cos(2 * phase))
            }
        }
    }

    private static func phase(at date: Date) -> Double {
        let duration: TimeInterval = 112
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration * 2 * .pi
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

    private static let referenceRadius: CGFloat = 135
    /// Die Pfade werden einmal aufgebaut. Pro Bild wandern nur die drei Schichten gegeneinander.
    private static let particlePaths: [[Path]] = {
        var paths = Array(repeating: Array(repeating: Path(), count: 5), count: Depth.allCases.count)
        for particle in particles {
            let depth = Depth(radius: particle.radius)
            let radius = referenceRadius * CGFloat(particle.radius)
            let x = radius * CGFloat(cos(particle.angle))
            let y = radius * CGFloat(sin(particle.angle))
            let diameter = CGFloat(particle.size)
            paths[depth.rawValue][particle.tone].addEllipse(
                in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)
            )
        }
        return paths
    }()

    private static func draw(in context: GraphicsContext, size: CGSize, mood: OrbMood, phase: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = min(size.width, size.height) / 2 - 3
        guard outer > 0 else { return }
        let disk = Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        context.fill(disk, with: .radialGradient(
            Gradient(stops: [
                .init(color: .black.opacity(0.28), location: 0),
                .init(color: .black.opacity(0.12), location: 0.47),
                .init(color: mood.deep.opacity(0.23), location: 0.83),
                .init(color: mood.deep.opacity(0.10), location: 1)
            ]),
            center: center, startRadius: 0, endRadius: outer))

        let colors = [
            mood.deep.opacity(0.36), mood.mid.opacity(0.26), mood.mid.opacity(0.58),
            mood.mid.opacity(0.88), mood.rim
        ]
        for depth in Depth.allCases {
            let motion = depth.motion(at: phase)
            let scale = outer / referenceRadius * CGFloat(motion.scale)
            var layer = context
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .radians(motion.rotation))
            layer.scaleBy(x: scale, y: scale)
            layer.opacity *= motion.opacity
            let paths = particlePaths[depth.rawValue]
            for index in paths.indices where !paths[index].isEmpty {
                layer.fill(paths[index], with: .color(colors[index]))
            }
        }
    }
}
