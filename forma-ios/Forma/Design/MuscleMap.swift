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
    var muscleTints: [Muscle: Color] = [:]
    var onSelect: ((Muscle) -> Void)? = nil
    @State private var side: BodySide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(intensity: [Muscle: Double], selected: Muscle? = nil, showsBoth: Bool = false,
         tint: Color = Theme.strain, muscleTints: [Muscle: Color] = [:], onSelect: ((Muscle) -> Void)? = nil) {
        self.intensity = intensity
        self.selected = selected
        self.showsBoth = showsBoth
        self.tint = tint
        self.muscleTints = muscleTints
        self.onSelect = onSelect
        _side = State(initialValue: MuscleMapView.preferredSide(for: intensity))
    }

    /// Füllfarbe eines Muskels: gedämpfte Akzentfarbe, Stärke nach Stufe (0 = neutral grau).
    static func fill(_ level: Double, tint: Color = Theme.strain) -> Color {
        level > 0 ? tint.mix(with: Color(white: 0.62), by: 0.18).opacity(0.12 + 0.88 * level) : Color.white.opacity(0.035)
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
        MuscleFigure(side: side, intensity: intensity, selected: selected, tint: tint, muscleTints: muscleTints, onSelect: onSelect)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let side: BodySide
    let intensity: [Muscle: Double]
    let selected: Muscle?
    let tint: Color
    let muscleTints: [Muscle: Color]
    let onSelect: ((Muscle) -> Void)?

    private var muscles: [Muscle] { Muscle.allCases.filter { MuscleArt.polygons($0, side) != nil } }

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let outline = BodyShape(polygons: MuscleArt.silhouette, isOutline: true)
            ZStack {
                ZStack {
                    Rectangle().fill(LinearGradient(colors: [Theme.cardRaised, Theme.card],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                    ForEach(muscles) { m in
                        let level = intensity[m] ?? 0
                        let shape = BodyShape(polygons: MuscleArt.polygons(m, side) ?? [])
                        let color = muscleTints[m] ?? tint
                        let fill = MuscleMapView.fill(level, tint: color)
                        let edge = level > 0 ? color.opacity(0.27) : Color.white.opacity(0.12)
                        shape
                            .fill(LinearGradient(colors: [fill, fill.opacity(0.66)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay { shape.stroke(edge, lineWidth: 0.65) }
                            .overlay { if selected == m { shape.stroke(Theme.textPrimary.opacity(0.9), lineWidth: 1.2) } }
                            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: level)
                            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selected)
                    }
                }
                .clipShape(outline)
                outline.stroke(Color.white.opacity(0.23), lineWidth: 0.85)
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
    var isOutline = false

    func path(in rect: CGRect) -> Path {
        if !isOutline {
            var path = halfPath(in: rect, mirrored: false)
            path.addPath(halfPath(in: rect, mirrored: true))
            return path
        }
        var path = Path()
        for half in polygons {
            let right = half.map { MuscleArt.point($0, mirror: false, in: rect) }
            let left = half.dropFirst().dropLast().reversed().map { MuscleArt.point($0, mirror: true, in: rect) }
            Self.addSmooth(right + left, to: &path)
        }
        return path
    }

    func contains(_ location: CGPoint, in rect: CGRect) -> Bool {
        for mirrored in [false, true] {
            let half = halfPath(in: rect, mirrored: mirrored)
            if half.boundingRect.contains(location), half.cgPath.contains(location) { return true }
        }
        return false
    }

    private func halfPath(in rect: CGRect, mirrored: Bool) -> Path {
        var path = Path()
        for poly in polygons {
            let points = mirrored ? Array(poly.reversed()) : poly
            Self.addSmooth(points.map { MuscleArt.point($0, mirror: mirrored, in: rect) }, to: &path)
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
        if let hit = candidates.last(where: { BodyShape(polygons: $0.1).contains(location, in: rect) }) {
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

    // Beide Umrisse beginnen und enden auf der Mittelachse. Die Spiegelung schließt sie ohne Naht.
    static let silhouette: [[CGPoint]] = [
        poly([(100, 7), (111, 10), (116, 20), (115, 36), (112, 46), (105, 53), (100, 54)]),
        poly([(100, 58), (109, 56), (114, 65), (125, 70), (141, 74), (154, 81), (164, 96), (166, 112),
              (164, 131), (158, 154), (160, 172), (166, 194), (171, 215), (174, 229), (177, 240), (174, 255),
              (167, 260), (162, 253), (162, 239), (155, 225), (149, 202), (144, 180), (140, 160), (140, 139),
              (137, 122), (132, 144), (128, 167), (128, 187), (134, 211), (140, 235), (142, 260), (140, 290),
              (133, 322), (132, 342), (138, 365), (136, 388), (128, 417), (131, 427), (136, 433), (131, 438),
              (114, 438), (108, 433), (109, 421), (107, 399), (105, 375), (106, 350), (105, 333), (103, 304),
              (102, 276), (100, 252)])
    ]

    private static let forearm = poly([(145, 172), (155, 171), (162, 189), (167, 212), (165, 230),
                                       (159, 231), (153, 215), (148, 197)])
    private static let sideDelt = poly([(149, 82), (157, 87), (164, 98), (164, 110), (158, 123), (153, 113)])

    static let front: [Muscle: [[CGPoint]]] = [
        .chest: [poly([(101, 86), (111, 80), (126, 78), (139, 84), (144, 94), (141, 106), (130, 115),
                      (116, 120), (103, 115)])],
        .frontDelts: [poly([(138, 77), (147, 79), (153, 90), (155, 105), (150, 115), (143, 107), (145, 94)])],
        .sideDelts: [sideDelt],
        .biceps: [poly([(146, 121), (154, 120), (160, 130), (156, 149), (151, 166), (145, 161), (142, 142)])],
        .forearms: [forearm],
        .abs: [poly([(101, 124), (110, 120), (117, 124), (119, 143), (118, 165), (115, 188),
                    (108, 211), (101, 218)])],
        .obliques: [poly([(121, 124), (136, 115), (133, 137), (128, 156), (126, 177), (128, 194),
                         (123, 207), (116, 205), (121, 174)])],
        .traps: [poly([(107, 58), (115, 67), (128, 71), (139, 76), (132, 79), (118, 75), (110, 70)])],
        .quads: [poly([(117, 222), (129, 216), (136, 233), (138, 255), (136, 282), (131, 306), (123, 330),
                      (116, 328), (114, 306), (116, 278), (114, 249)]),
                 poly([(103, 266), (109, 251), (113, 277), (111, 309), (116, 328), (110, 337), (106, 316)])],
        .calves: [poly([(121, 350), (131, 350), (135, 365), (132, 387), (124, 412), (118, 407), (118, 380)]),
                  poly([(108, 353), (116, 348), (116, 371), (115, 391), (108, 401), (107, 383)])]
    ]

    static let back: [Muscle: [[CGPoint]]] = [
        .rearDelts: [poly([(136, 79), (147, 79), (154, 90), (155, 105), (151, 111), (144, 103), (140, 91)])],
        .sideDelts: [sideDelt],
        .triceps: [poly([(145, 113), (154, 114), (160, 126), (157, 145), (152, 162), (146, 169), (143, 155), (142, 134)])],
        .forearms: [forearm],
        .traps: [poly([(100, 57), (113, 63), (125, 68), (139, 75), (128, 83), (120, 95), (109, 111), (100, 132)])],
        .lats: [poly([(105, 136), (115, 116), (125, 100), (136, 86), (140, 99), (138, 118), (133, 140),
                     (126, 157), (116, 174), (107, 182)])],
        .lowerBack: [poly([(101, 160), (109, 183), (119, 178), (126, 172), (127, 193), (132, 212),
                          (121, 218), (109, 216), (101, 211)])],
        .glutes: [poly([(101, 223), (112, 218), (126, 218), (136, 231), (139, 247), (135, 262), (126, 272),
                       (111, 271), (105, 262), (101, 248)])],
        .hamstrings: [poly([(121, 279), (135, 272), (137, 289), (132, 313), (127, 336), (118, 331), (116, 307)]),
                      poly([(103, 281), (115, 277), (113, 296), (114, 315), (117, 335), (110, 340), (105, 319)])],
        .calves: [poly([(106, 349), (117, 344), (120, 363), (118, 383), (113, 404), (107, 397), (106, 375)]),
                  poly([(122, 349), (131, 347), (136, 362), (134, 384), (126, 408), (121, 390), (120, 366)])]
    ]
}
