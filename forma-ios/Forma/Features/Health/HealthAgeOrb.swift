import SwiftUI

/// Farbwelt der Kugel: grün = jünger, warm = älter, Graphit ohne Schätzung.
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

/// Leuchtende, langsam atmende Kugel hinter dem Health Age. Reduce Motion: steht still.
struct AgeOrb: View {
    let mood: OrbMood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.35
            orb(phase: t)
        }
        .accessibilityHidden(true)
    }

    private func orb(phase t: Double) -> some View {
        let blob = OrbBlob(phase: t)
        return ZStack {
            // Weiches Leuchten nach außen.
            blob
                .fill(mood.mid)
                .blur(radius: 36)
                .opacity(0.5)
                .scaleEffect(1.06)
            // Körper: heller Rand, dunkle Mitte, die Mitte wandert ganz leicht.
            MeshGradient(width: 3, height: 3, points: meshPoints(t), colors: [
                mood.rim, mood.mid, mood.rim,
                mood.mid, mood.deep, mood.mid,
                mood.rim, mood.mid, mood.rim
            ])
            .clipShape(blob)
            // Dunkle Mitte, damit die Zahl ruhig lesbar bleibt.
            blob.fill(RadialGradient(colors: [Color.black.opacity(0.82), Color.black.opacity(0.45), .clear],
                                     center: .center, startRadius: 0, endRadius: 118))
            // Glanzlicht oben links.
            blob.fill(RadialGradient(colors: [Color.white.opacity(0.10), .clear],
                                     center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 80))
            // Lichtsaum.
            blob.stroke(mood.rim.opacity(0.45), lineWidth: 7).blur(radius: 9)
            blob.stroke(mood.rim.opacity(0.85), lineWidth: 1.1)
        }
        .compositingGroup()
    }

    private func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        let dx = Float(0.10 * sin(t * 0.9))
        let dy = Float(0.10 * cos(t * 0.7))
        return [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.5), SIMD2<Float>(0.5 + dx, 0.5 + dy), SIMD2<Float>(1, 0.5),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1)
        ]
    }
}

/// Organischer Umriss: sieben Stützpunkte auf einem Kreis, deren Radius sanft schwankt.
struct OrbBlob: Shape {
    var phase: Double

    func path(in rect: CGRect) -> Path {
        let count = 7
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let points: [CGPoint] = (0..<count).map { i in
            let index = Double(i)
            let angle = index / Double(count) * 2 * Double.pi
            let wobble = 0.045 * sin(phase + index * 2.1) + 0.03 * sin(phase * 0.7 + index * 3.7)
            let r = radius * CGFloat(0.92 + wobble)
            return CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
        }
        return Self.smoothClosed(points)
    }

    /// Geschlossene Catmull-Rom-Kurve durch alle Punkte, als kubische Bézier-Abschnitte.
    static func smoothClosed(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard p.count > 2 else { return path }
        let n = p.count
        path.move(to: p[0])
        for i in 0..<n {
            let p0 = p[(i - 1 + n) % n]
            let p1 = p[i]
            let p2 = p[(i + 1) % n]
            let p3 = p[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}
