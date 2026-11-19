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
                // Leiser Umschalter: zwei Wörter, das aktive hell. Kein zweites Segment-Steuerelement auf dem Bildschirm.
                HStack(spacing: Space.s4) {
                    ForEach(BodySide.allCases) { s in
                        Button {
                            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.5)) { side = s }
                        } label: {
                            Text(s.title)
                                .font(.formaLabel).tracking(Tracking.label).textCase(.uppercase)
                                .foregroundStyle(side == s ? Theme.textPrimary : Theme.textTertiary)
                                .frame(minWidth: 64, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ansicht \(s.title.lowercased())")
                        .accessibilityAddTraits(side == s ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: side)
            }
        }
    }

    private func figure(_ side: BodySide) -> some View {
        MuscleFigure(side: side, intensity: intensity, selected: selected, tint: tint, onSelect: onSelect)
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
                ForEach(muscles) { m in
                    let level = intensity[m] ?? 0
                    let shape = BodyShape(polygons: MuscleArt.polygons(m, side) ?? [])
                    shape
                        .fill(level > 0 ? tint.opacity(0.22 + 0.78 * level) : Color.white.opacity(0.07))
                        .shadow(color: tint.opacity(level >= 0.9 ? 0.35 : 0), radius: 8)
                        .overlay { if selected == m { shape.stroke(Theme.textPrimary, lineWidth: 1.5) } }
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
            path.addEllipse(in: CGRect(x: dx + 82 * s, y: dy + 12 * s, width: 36 * s, height: 44 * s))
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

    static let silhouette: [[CGPoint]] = [
        poly([(100, 52), (111, 52), (113, 72), (100, 76)]),                                          // Hals
        poly([(100, 64), (118, 68), (146, 78), (162, 92), (152, 120), (141, 132), (141, 160), (135, 196),
              (143, 226), (141, 250), (100, 262)]),                                                     // Rumpf
        poly([(150, 82), (166, 94), (171, 124), (168, 170), (150, 180), (142, 140), (140, 108)]),       // Oberarm
        poly([(146, 176), (167, 172), (173, 206), (169, 240), (152, 243), (146, 210)]),                 // Unterarm
        poly([(152, 240), (169, 238), (173, 262), (163, 281), (152, 271), (150, 252)]),                 // Hand
        poly([(100, 240), (141, 226), (149, 268), (145, 318), (137, 348), (108, 350), (105, 300), (102, 266)]), // Oberschenkel
        poly([(107, 344), (137, 342), (143, 380), (133, 418), (113, 420), (105, 384)]),                 // Unterschenkel
        poly([(113, 414), (133, 414), (139, 436), (109, 438)])                                          // Fuß
    ]

    private static let forearm = poly([(148, 182), (162, 178), (169, 200), (166, 228), (156, 236), (150, 216), (147, 198)])
    private static let sideDelt = poly([(156, 86), (165, 96), (168, 114), (163, 126), (159, 108)])

    static let front: [Muscle: [[CGPoint]]] = [
        .traps: [poly([(110, 66), (128, 74), (142, 82), (126, 86), (112, 79)])],
        .chest: [poly([(102, 90), (124, 86), (143, 94), (146, 106), (138, 124), (118, 130), (102, 126)])],
        .frontDelts: [poly([(144, 88), (153, 90), (156, 110), (151, 124), (145, 114), (142, 100)])],
        .sideDelts: [sideDelt],
        .biceps: [poly([(146, 132), (158, 128), (164, 142), (162, 164), (154, 172), (146, 160), (143, 144)])],
        .forearms: [forearm],
        .abs: [poly([(102, 134), (117, 133), (118, 150), (102, 152)]),
               poly([(102, 156), (118, 154), (118, 174), (102, 176)]),
               poly([(102, 180), (117, 178), (116, 200), (109, 218), (102, 222)])],
        .obliques: [poly([(122, 136), (136, 130), (137, 158), (132, 188), (124, 206), (121, 176), (122, 154)])],
        .quads: [poly([(119, 244), (138, 238), (145, 268), (141, 306), (132, 334), (123, 322), (118, 290)]),
                 poly([(106, 258), (115, 250), (116, 290), (121, 326), (114, 337), (107, 320), (105, 290)])],
        .calves: [poly([(124, 360), (136, 356), (140, 382), (134, 406), (126, 410), (122, 386)])]
    ]

    static let back: [Muscle: [[CGPoint]]] = [
        .traps: [poly([(100, 60), (112, 64), (140, 82), (126, 94), (112, 120), (100, 136)])],
        .rearDelts: [poly([(138, 88), (150, 86), (156, 98), (154, 116), (146, 112), (140, 100)])],
        .sideDelts: [sideDelt],
        .triceps: [poly([(146, 128), (160, 124), (166, 140), (164, 164), (156, 174), (148, 162), (144, 144)])],
        .forearms: [forearm],
        .lats: [poly([(108, 130), (122, 110), (140, 102), (143, 120), (138, 146), (126, 170), (110, 186), (104, 166), (106, 146)])],
        .lowerBack: [poly([(101, 196), (112, 192), (120, 206), (120, 224), (110, 232), (101, 232)])],
        .glutes: [poly([(102, 240), (116, 232), (134, 232), (145, 248), (146, 266), (138, 284), (120, 290), (104, 284)])],
        .hamstrings: [poly([(125, 297), (140, 295), (143, 316), (136, 342), (127, 340), (123, 316)]),
                      poly([(107, 299), (120, 297), (120, 318), (123, 342), (114, 344), (108, 322)])],
        .calves: [poly([(110, 358), (121, 352), (124, 380), (119, 402), (112, 392)]),
                  poly([(126, 352), (138, 358), (142, 384), (132, 404), (126, 384)])]
    ]
}
