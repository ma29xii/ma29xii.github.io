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

    /// Füllfarbe eines Muskels: gedämpfte Akzentfarbe, Stärke nach Stufe (0 = neutral grau).
    static func fill(_ level: Double, tint: Color = Theme.strain) -> Color {
        level > 0 ? tint.mix(with: Color(white: 0.62), by: 0.3).opacity(0.08 + 0.92 * level) : Color.white.opacity(0.05)
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
            let outline = BodyShape(polygons: MuscleArt.silhouette, head: true)
            ZStack {
                // Muskeln liegen wie Platten auf dem Körper, getrennt durch feine Konturen, am Umriss beschnitten.
                ZStack {
                    Rectangle().fill(Theme.cardRaised)
                    ForEach(muscles) { m in
                        let level = intensity[m] ?? 0
                        let shape = BodyShape(polygons: MuscleArt.polygons(m, side) ?? [])
                        shape
                            .fill(MuscleMapView.fill(level, tint: tint))
                            .overlay { shape.stroke(Color.black.opacity(0.32), lineWidth: 0.8) }
                            .overlay { if selected == m { shape.stroke(Theme.textPrimary.opacity(0.9), lineWidth: 1.2) } }
                            .animation(.smooth(duration: 0.4), value: level)
                            .animation(.smooth(duration: 0.25), value: selected)
                    }
                }
                .clipShape(outline)
                outline.stroke(Color.white.opacity(0.14), lineWidth: 0.75)
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
            path.addEllipse(in: CGRect(x: dx + 86 * s, y: dy + 8 * s, width: 28 * s, height: 39 * s))
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
        // Zuletzt gezeichnet liegt oben: von hinten suchen.
        if let hit = candidates.last(where: { BodyShape(polygons: $0.1).path(in: rect).contains(location) }) {
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
    /// Ein durchgehender Umriss je Körperhälfte: athletisch-schlank, Arme leicht abgesetzt.
    static let silhouette: [[CGPoint]] = [
        poly([(100, 46), (108, 48), (110, 58), (118, 64), (132, 70), (144, 74), (152, 80), (157, 90), (159, 104),
              (160, 120), (160, 140), (159, 160), (160, 170), (163, 186), (165, 204), (163, 222), (161, 232),
              (164, 244), (163, 258), (158, 266), (152, 262), (151, 248), (151, 236), (151, 230), (149, 210),
              (147, 190), (145, 172), (143, 150), (142, 128), (141, 116), (139, 112), (139, 124), (136, 146),
              (131, 168), (129, 184), (131, 202), (136, 222), (140, 240), (142, 262), (140, 290), (136, 316),
              (133, 334), (134, 344), (138, 362), (137, 384), (131, 406), (127, 420), (128, 428), (131, 436),
              (124, 440), (110, 440), (108, 428), (109, 418), (107, 400), (105, 378), (106, 358), (107, 346),
              (106, 336), (104, 312), (103, 286), (102, 262), (100, 252), (100, 150)])
    ]

    private static let forearm = poly([(145, 174), (159, 171), (164, 190), (165, 212), (162, 230), (152, 232), (148, 212), (146, 192)])
    private static let sideDelt = poly([(150, 80), (157, 89), (160, 104), (158, 118), (153, 106)])

    static let front: [Muscle: [[CGPoint]]] = [
        .chest: [poly([(100, 82), (110, 77), (124, 76), (136, 80), (143, 88), (145, 100), (140, 112), (128, 120), (113, 123), (100, 121)])],
        .frontDelts: [poly([(137, 78), (148, 78), (153, 86), (156, 100), (155, 114), (148, 118), (143, 106), (140, 90)])],
        .sideDelts: [sideDelt],
        .biceps: [poly([(142, 120), (152, 118), (160, 126), (161, 146), (158, 166), (150, 170), (144, 160), (142, 138)])],
        .forearms: [forearm],
        .abs: [poly([(100, 125), (114, 125), (116, 142), (100, 143)]),
               poly([(100, 146), (116, 145), (116, 163), (100, 164)]),
               poly([(100, 167), (116, 166), (115, 186), (100, 187)]),
               poly([(100, 190), (115, 189), (113, 206), (106, 222), (100, 226)])],
        .obliques: [poly([(119, 126), (141, 116), (139, 132), (135, 152), (131, 172), (130, 188), (126, 206), (118, 214), (118, 186), (119, 150)])],
        .traps: [poly([(107, 57), (118, 63), (134, 70), (145, 75), (134, 77), (118, 74), (109, 67)])],
        .quads: [poly([(117, 232), (130, 225), (140, 237), (143, 262), (141, 292), (136, 318), (128, 336), (119, 333), (114, 316), (115, 280)]),
                 poly([(105, 266), (111, 250), (114, 284), (116, 318), (118, 334), (110, 339), (105, 320), (103, 292)])],
        .calves: [poly([(122, 350), (134, 354), (138, 370), (135, 394), (127, 410), (121, 396), (120, 372)]),
                  poly([(108, 352), (116, 350), (118, 372), (115, 396), (109, 394), (106, 374)])]
    ]

    static let back: [Muscle: [[CGPoint]]] = [
        .rearDelts: [poly([(138, 80), (149, 78), (154, 86), (156, 100), (155, 114), (147, 112), (141, 98)])],
        .sideDelts: [sideDelt],
        .triceps: [poly([(142, 118), (155, 116), (161, 128), (161, 150), (157, 168), (149, 170), (144, 156), (142, 134)])],
        .forearms: [forearm],
        .traps: [poly([(100, 50), (110, 54), (124, 64), (143, 74), (134, 82), (121, 98), (109, 120), (100, 132)])],
        .lats: [poly([(103, 138), (112, 122), (125, 102), (136, 86), (141, 104), (140, 124), (135, 148), (128, 170), (115, 184), (104, 180)])],
        .lowerBack: [poly([(100, 184), (114, 190), (129, 182), (131, 200), (133, 218), (118, 223), (100, 224)])],
        .glutes: [poly([(100, 229), (116, 224), (132, 226), (140, 240), (142, 258), (136, 276), (120, 282), (104, 280), (100, 262)])],
        .hamstrings: [poly([(122, 287), (138, 283), (141, 300), (137, 322), (130, 338), (122, 334), (119, 310)]),
                      poly([(102, 291), (117, 287), (117, 312), (120, 336), (110, 340), (104, 320)])],
        .calves: [poly([(106, 350), (119, 345), (121, 366), (117, 392), (110, 394), (105, 374)]),
                  poly([(122, 345), (134, 351), (138, 367), (134, 390), (126, 400), (121, 372)])]
    ]
}
