import SwiftUI

enum BodySide: String, CaseIterable, Identifiable, Sendable {
    case front, back
    var id: String { rawValue }
    var title: String { self == .front ? "Vorne" : "Hinten" }
}

/// Interaktive Muskelkarte: Körper vorne und hinten, Muskeln leuchten nach Stärke (0…1).
/// Eigene Formen, auf einem 200 × 440-Raster gezeichnet und gespiegelt.
struct MuscleMapView: View {
    let intensity: [Muscle: Double]
    var selected: Muscle? = nil
    var showsBoth = false
    var tint: Color = Theme.strain
    var onSelect: ((Muscle) -> Void)? = nil
    @State private var side: BodySide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(intensity: [Muscle: Double], selected: Muscle? = nil, showsBoth: Bool = false,
         tint: Color = Theme.strain, onSelect: ((Muscle) -> Void)? = nil) {
        self.intensity = intensity
        self.selected = selected
        self.showsBoth = showsBoth
        self.tint = tint
        self.onSelect = onSelect
        _side = State(initialValue: MuscleMapView.preferredSide(for: intensity))
    }

    /// Die Seite, auf der die meisten markierten Muskeln liegen.
    static func preferredSide(for intensity: [Muscle: Double]) -> BodySide {
        let front = intensity.filter { $0.key.onFront && !$0.key.onBack }.values.reduce(0, +)
        let back = intensity.filter { $0.key.onBack && !$0.key.onFront }.values.reduce(0, +)
        return back > front ? .back : .front
    }

    var body: some View {
        if showsBoth {
            HStack(alignment: .top, spacing: Space.s5) {
                ForEach(BodySide.allCases) { s in
                    VStack(spacing: Space.s2) {
                        figure(s)
                        Text(s.title)
                            .font(.formaMicro).tracking(Tracking.micro).textCase(.uppercase)
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: Space.s3) {
                ZStack {
                    figure(side)
                        .id(side)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(FlipTransition()))
                }
                .frame(maxWidth: .infinity)
                QuietSegments(options: BodySide.allCases.map { ($0, $0.title) }, selection: $side,
                              animation: reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.5))
            }
        }
    }

    private func figure(_ side: BodySide) -> some View {
        MuscleFigure(side: side, intensity: intensity, selected: selected, tint: tint, onSelect: onSelect)
    }
}

/// Leiser Umschalter: Wörter in Großbuchstaben, das aktive hell. Ersetzt ein zweites Segment-Steuerelement.
struct QuietSegments<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var animation: Animation = .smooth(duration: 0.35)

    var body: some View {
        HStack(spacing: Space.s4) {
            ForEach(options, id: \.0) { option in
                Button {
                    withAnimation(animation) { selection = option.0 }
                } label: {
                    Text(option.1)
                        .font(.formaLabel).tracking(Tracking.label).textCase(.uppercase)
                        .foregroundStyle(selection == option.0 ? Theme.textPrimary : Theme.textTertiary)
                        .frame(minWidth: 64, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Dreht die Körperansicht wie eine Karte um die Hochachse.
private struct FlipTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .rotation3DEffect(.degrees(phase == .willAppear ? -90 : (phase == .didDisappear ? 90 : 0)),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// Eine Körperseite mit allen Muskeln.
private struct MuscleFigure: View {
    let side: BodySide
    let intensity: [Muscle: Double]
    let selected: Muscle?
    let tint: Color
    let onSelect: ((Muscle) -> Void)?

    private var muscles: [Muscle] { Muscle.allCases.filter { MuscleArt.polygons($0, side) != nil } }

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            ZStack {
                // Einzeln gefüllt: überlappende Körperteile dürfen sich nicht gegenseitig ausstanzen.
                ForEach(MuscleArt.silhouette.indices, id: \.self) { i in
                    BodyShape(polygons: [MuscleArt.silhouette[i]], head: i == 0).fill(Theme.cardRaised)
                }
                // Gedämpfte Akzentfarbe, fein nach Belastung abgestuft; nur Hauptmuskeln leuchten leise.
                let muted = tint.mix(with: Color(white: 0.62), by: 0.3)
                ForEach(muscles) { m in
                    let level = intensity[m] ?? 0
                    let shape = BodyShape(polygons: MuscleArt.polygons(m, side) ?? [])
                    shape
                        .fill(level > 0 ? muted.opacity(0.14 + 0.46 * level) : Color.white.opacity(0.045))
                        .shadow(color: tint.opacity(level >= 0.9 ? 0.3 : 0), radius: 6)
                        .overlay { if selected == m { shape.stroke(Theme.textPrimary.opacity(0.85), lineWidth: 1) } }
                        .animation(.smooth(duration: 0.4), value: level)
                        .animation(.smooth(duration: 0.25), value: selected)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onSelect, let hit = MuscleArt.muscle(at: location, side: side, in: rect) else { return }
                onSelect(hit)
            }
        }
        .aspectRatio(MuscleArt.size.width / MuscleArt.size.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityActions {
            ForEach(onSelect == nil ? [] : muscles) { m in
                Button(m.name) { onSelect?(m) }
            }
        }
    }

    private var accessibilityText: String {
        let shown = muscles.filter { (intensity[$0] ?? 0) > 0 }
        let strong = shown.filter { (intensity[$0] ?? 0) >= 0.7 }.map(\.name)
        let light = shown.filter { (intensity[$0] ?? 0) < 0.7 }.map(\.name)
        var parts = ["Muskelkarte \(side.title.lowercased())"]
        if !strong.isEmpty { parts.append("stark: " + strong.joined(separator: ", ")) }
        if !light.isEmpty { parts.append("leicht: " + light.joined(separator: ", ")) }
        if shown.isEmpty { parts.append("keine Muskeln markiert") }
        return parts.joined(separator: ". ")
    }
}

/// Weiche, geschlossene Formen aus Stützpunkten, rechte Körperhälfte wird gespiegelt.
struct BodyShape: Shape {
    let polygons: [[CGPoint]]
    var head = false

    func path(in rect: CGRect) -> Path {
        let (s, dx, dy) = MuscleArt.layout(in: rect)
        let map = { (p: CGPoint, mirror: Bool) in MuscleArt.point(p, mirror: mirror, in: rect) }
        var path = Path()
        if head {
            path.addEllipse(in: CGRect(x: dx + 85 * s, y: dy + 8 * s, width: 30 * s, height: 42 * s))
        }
        for poly in polygons {
            for mirror in [false, true] {
                // Gespiegelt in umgekehrter Reihenfolge, damit die Drehrichtung gleich bleibt (keine Löcher an der Mittellinie).
                Self.addSmooth((mirror ? Array(poly.reversed()) : poly).map { map($0, mirror) }, to: &path)
            }
        }
        return path
    }

    /// Catmull-Rom durch alle Punkte, als geschlossene Kurve.
    private static func addSmooth(_ p: [CGPoint], to path: inout Path) {
        let n = p.count
        guard n > 2 else { return }
        path.move(to: p[0])
        for i in 0..<n {
            let p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
    }
}

/// Stützpunkte der Körperformen (rechte Bildhälfte, x ≥ 100; Mitte bei x = 100).
enum MuscleArt {
    static let size = CGSize(width: 200, height: 440)

    static func polygons(_ muscle: Muscle, _ side: BodySide) -> [[CGPoint]]? {
        side == .front ? front[muscle] : back[muscle]
    }

    /// Maßstab und Versatz für ein mittig eingepasstes 200 × 440-Raster.
    static func layout(in rect: CGRect) -> (s: CGFloat, dx: CGFloat, dy: CGFloat) {
        let s = min(rect.width / size.width, rect.height / size.height)
        return (s, rect.minX + (rect.width - size.width * s) / 2, rect.minY + (rect.height - size.height * s) / 2)
    }

    static func point(_ p: CGPoint, mirror: Bool, in rect: CGRect) -> CGPoint {
        let (s, dx, dy) = layout(in: rect)
        return CGPoint(x: dx + (mirror ? size.width - p.x : p.x) * s, y: dy + p.y * s)
    }

    /// Treffer beim Antippen. Liegt der Finger daneben, gilt der nächste Muskel im Umkreis von 22 pt:
    /// so hat auch die schmale Schulter eine unsichtbare Tippfläche von mindestens 44 pt.
    static func muscle(at location: CGPoint, side: BodySide, in rect: CGRect, tolerance: CGFloat = 22) -> Muscle? {
        let candidates = Muscle.allCases.compactMap { m in polygons(m, side).map { (m, $0) } }
        if let hit = candidates.first(where: { BodyShape(polygons: $0.1).path(in: rect).contains(location) }) {
            return hit.0
        }
        let nearest = candidates
            .map { c in (c.0, c.1.flatMap { poly in [false, true].map { distance(location, to: poly, mirror: $0, in: rect) } }.min() ?? CGFloat.infinity) }
            .min { $0.1 < $1.1 }
        guard let nearest, nearest.1 <= tolerance else { return nil }
        return nearest.0
    }

    /// Abstand zum Umriss (Strecken zwischen den Stützpunkten; die Kurve läuft durch sie hindurch).
    private static func distance(_ p: CGPoint, to poly: [CGPoint], mirror: Bool, in rect: CGRect) -> CGFloat {
        let pts = poly.map { point($0, mirror: mirror, in: rect) }
        guard pts.count > 1 else { return .infinity }
        var best = CGFloat.infinity
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let len2 = ab.x * ab.x + ab.y * ab.y
            let t = len2 > 0 ? max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / len2)) : 0
            let q = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
            best = min(best, hypot(p.x - q.x, p.y - q.y))
        }
        return best
    }

    private static func poly(_ pts: [(CGFloat, CGFloat)]) -> [CGPoint] { pts.map { CGPoint(x: $0.0, y: $0.1) } }

    /// Ein durchgehender Umriss je Körperhälfte: schlank, Arme leicht abgesetzt, kleine Hände und Füße.
    static let silhouette: [[CGPoint]] = [
        poly([(100, 48), (107, 50), (109, 58), (116, 64), (130, 70), (142, 75), (150, 82), (154, 94),
              (155, 118), (155, 146), (156, 166), (159, 190), (160, 214), (159, 230), (161, 244), (159, 258),
              (154, 263), (150, 252), (150, 238), (151, 228), (147, 200), (143, 172), (141, 144), (139, 114),
              (136, 112), (136, 132), (132, 160), (128, 182), (131, 206), (136, 228), (138, 256), (136, 292),
              (131, 328), (134, 354), (131, 386), (124, 412), (127, 428), (121, 437), (109, 437), (107, 418),
              (105, 390), (106, 360), (106, 336), (104, 300), (103, 270), (100, 256), (100, 150)])
    ]

    private static let forearm = poly([(147, 174), (154, 172), (157, 192), (157, 214), (154, 224), (150, 206), (147, 190)])
    private static let sideDelt = poly([(149, 82), (153, 92), (154, 106), (151, 113), (149, 98)])

    static let front: [Muscle: [[CGPoint]]] = [
        .traps: [poly([(109, 61), (122, 67), (137, 74), (125, 76), (112, 70)])],
        .chest: [poly([(102, 84), (118, 80), (134, 82), (141, 90), (140, 103), (131, 113), (115, 116), (102, 113)])],
        .frontDelts: [poly([(139, 79), (146, 82), (148, 94), (146, 108), (142, 104), (140, 92)])],
        .sideDelts: [sideDelt],
        .biceps: [poly([(143, 118), (150, 115), (153, 131), (152, 152), (148, 162), (144, 150), (142, 132)])],
        .forearms: [forearm],
        .abs: [poly([(102, 120), (113, 119), (114, 136), (102, 137)]),
               poly([(102, 141), (114, 140), (114, 158), (102, 159)]),
               poly([(102, 163), (113, 162), (112, 184), (107, 204), (102, 208)])],
        .obliques: [poly([(118, 122), (131, 118), (133, 138), (129, 164), (122, 186), (118, 164), (118, 140)])],
        .quads: [poly([(117, 236), (133, 231), (136, 262), (133, 298), (126, 322), (119, 306), (116, 272)]),
                 poly([(106, 248), (112, 243), (114, 280), (118, 318), (112, 326), (107, 306), (105, 276)])],
        .calves: [poly([(122, 346), (130, 344), (132, 368), (128, 394), (123, 396), (120, 372)])]
    ]

    static let back: [Muscle: [[CGPoint]]] = [
        .traps: [poly([(100, 56), (110, 60), (136, 74), (124, 84), (112, 106), (100, 124)])],
        .rearDelts: [poly([(138, 78), (146, 81), (148, 94), (146, 108), (142, 104), (139, 91)])],
        .sideDelts: [sideDelt],
        .triceps: [poly([(142, 116), (150, 114), (153, 130), (152, 152), (148, 162), (144, 150), (142, 132)])],
        .forearms: [forearm],
        .lats: [poly([(106, 120), (117, 100), (131, 88), (135, 100), (134, 124), (127, 148), (113, 166), (104, 154), (104, 136)])],
        .lowerBack: [poly([(101, 176), (110, 172), (118, 186), (118, 204), (110, 210), (101, 210)])],
        .glutes: [poly([(102, 222), (114, 215), (128, 216), (135, 232), (136, 250), (130, 266), (114, 270), (102, 264)])],
        .hamstrings: [poly([(122, 278), (133, 276), (134, 300), (129, 322), (122, 320), (120, 298)]),
                      poly([(106, 280), (116, 278), (117, 300), (119, 322), (112, 324), (106, 302)])],
        .calves: [poly([(108, 344), (117, 340), (119, 364), (116, 388), (109, 378)]),
                  poly([(122, 340), (131, 346), (132, 368), (127, 390), (122, 368)])]
    ]
}
