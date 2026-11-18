import SwiftUI

/// Dezente Strichfigur, die eine Grundübung langsam vormacht. Reduce Motion: Standbild mit Start- und Endstellung.
struct ExerciseMotionView: View {
    let motion: ExerciseMotion
    var tint: Color = Theme.strain
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let scene = MotionScene.scene(for: motion)
        Group {
            if reduceMotion {
                Canvas { ctx, size in scene.draw(in: &ctx, size: size, t: 1, ghost: true, tint: tint) }
            } else {
                KeyframeAnimator(initialValue: 0.0, repeating: true) { t in
                    Canvas { ctx, size in scene.draw(in: &ctx, size: size, t: t, ghost: false, tint: tint) }
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(1, duration: 1.2)
                        LinearKeyframe(1, duration: 0.35)
                        CubicKeyframe(0, duration: 1.6)
                        LinearKeyframe(0, duration: 0.45)
                    }
                }
            }
        }
        .frame(height: 190)
        .accessibilityHidden(true)
    }
}

/// Stellung der Figur in Seitenansicht: Kopf, Schulter, Ellbogen, Hand, Hüfte, Knie, Knöchel, Zehen (+ optional hinteres Bein).
struct Pose: Sendable {
    let joints: [CGPoint]
    var rearLeg: [CGPoint]? = nil

    init(_ j: [(CGFloat, CGFloat)], rear: [(CGFloat, CGFloat)]? = nil) {
        joints = j.map { CGPoint(x: $0.0, y: $0.1) }
        rearLeg = rear?.map { CGPoint(x: $0.0, y: $0.1) }
    }

    private init(joints: [CGPoint], rearLeg: [CGPoint]?) {
        self.joints = joints
        self.rearLeg = rearLeg
    }

    var allPoints: [CGPoint] { joints + (rearLeg ?? []) }

    func mixed(with other: Pose, _ t: CGFloat) -> Pose {
        func lerp(_ a: [CGPoint], _ b: [CGPoint]) -> [CGPoint] {
            zip(a, b).map { CGPoint(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) }
        }
        let rearA = rearLeg ?? Array(joints[5...7]), rearB = other.rearLeg ?? Array(other.joints[5...7])
        let hasRear = rearLeg != nil || other.rearLeg != nil
        return Pose(joints: lerp(joints, other.joints), rearLeg: hasRear ? lerp(rearA, rearB) : nil)
    }
}

struct MotionScene: Sendable {
    enum Load: Sendable { case none, barbell, dumbbell, cable(CGPoint) }
    enum Fixture: Sendable { case floor(CGFloat), bench(CGRect), bar(CGFloat) }

    let start: Pose
    let end: Pose
    var load: Load = .none
    var fixtures: [Fixture] = []
    /// Vorderansicht: Figur wird an dieser x-Achse gespiegelt (z. B. Seitheben).
    var mirrorX: CGFloat? = nil

    // MARK: Zeichnen

    func draw(in ctx: inout GraphicsContext, size: CGSize, t: Double, ghost: Bool, tint: Color) {
        let bounds = contentBounds
        let pad: CGFloat = 14
        let s = min((size.width - 2 * pad) / bounds.width, (size.height - 2 * pad) / bounds.height)
        let ox = (size.width - bounds.width * s) / 2 - bounds.minX * s
        let oy = (size.height - bounds.height * s) / 2 - bounds.minY * s
        let map = { (p: CGPoint) in CGPoint(x: ox + p.x * s, y: oy + p.y * s) }
        let line = StrokeStyle(lineWidth: max(2.5, 3.2 * s), lineCap: .round, lineJoin: .round)

        for fixture in fixtures {
            switch fixture {
            case .floor(let y):
                var p = Path()
                p.move(to: map(CGPoint(x: bounds.minX, y: y)))
                p.addLine(to: map(CGPoint(x: bounds.maxX, y: y)))
                ctx.stroke(p, with: .color(Theme.hairline), lineWidth: 1)
            case .bench(let r):
                let rect = CGRect(origin: map(r.origin), size: CGSize(width: r.width * s, height: r.height * s))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2 * s), with: .color(Color.white.opacity(0.10)))
            case .bar(let y):
                var p = Path()
                p.move(to: map(CGPoint(x: bounds.minX + 6, y: y)))
                p.addLine(to: map(CGPoint(x: bounds.maxX - 6, y: y)))
                ctx.stroke(p, with: .color(Theme.textTertiary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }

        if ghost {
            figure(start, ctx: &ctx, map: map, style: line, s: s, color: Theme.textQuaternary, tint: Theme.textQuaternary)
        }
        figure(start.mixed(with: end, CGFloat(t)), ctx: &ctx, map: map, style: line, s: s, color: Theme.textPrimary, tint: tint)
    }

    private func figure(_ pose: Pose, ctx: inout GraphicsContext, map: @escaping (CGPoint) -> CGPoint, style: StrokeStyle,
                        s: CGFloat, color: Color, tint: Color) {
        let j = pose.joints
        var sides: [(CGPoint) -> CGPoint] = [map]
        if let mx = mirrorX { sides.append { map(CGPoint(x: 2 * mx - $0.x, y: $0.y)) } }

        // Last zuerst, damit die Hand darüber liegt.
        for m in sides {
            switch load {
            case .none: break
            case .barbell:
                let c = m(j[3]), r = 7.5 * s
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(tint.opacity(0.28)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(tint), lineWidth: 1.5)
            case .dumbbell:
                let c = m(j[3])
                let rect = CGRect(x: c.x - 5 * s, y: c.y - 2.5 * s, width: 10 * s, height: 5 * s)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5 * s), with: .color(tint))
            case .cable(let anchor):
                var p = Path()
                p.move(to: m(anchor))
                p.addLine(to: m(j[3]))
                ctx.stroke(p, with: .color(tint.opacity(0.7)), lineWidth: 1.2)
            }
        }

        var body = Path()
        for m in sides {
            body.move(to: m(j[1])); body.addLine(to: m(j[2])); body.addLine(to: m(j[3]))     // Arm
            body.move(to: m(j[1])); body.addLine(to: m(j[4]))                                 // Rumpf
            body.move(to: m(j[4])); body.addLine(to: m(j[5])); body.addLine(to: m(j[6])); body.addLine(to: m(j[7]))
            if let rear = pose.rearLeg {
                body.move(to: m(j[4])); body.addLine(to: m(rear[0])); body.addLine(to: m(rear[1])); body.addLine(to: m(rear[2]))
            }
        }
        if mirrorX != nil, sides.count == 2 {
            body.move(to: sides[0](j[1])); body.addLine(to: sides[1](j[1]))
            body.move(to: sides[0](j[4])); body.addLine(to: sides[1](j[4]))
        }
        ctx.stroke(body, with: .color(color), style: style)

        let h = map(j[0]), r = 5.5 * s
        ctx.fill(Path(ellipseIn: CGRect(x: h.x - r, y: h.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }

    private var contentBounds: CGRect {
        var pts = start.allPoints + end.allPoints
        if let mx = mirrorX { pts += pts.map { CGPoint(x: 2 * mx - $0.x, y: $0.y) } }
        if case .cable(let a) = load { pts.append(a) }
        for f in fixtures {
            if case .bench(let r) = f { pts += [r.origin, CGPoint(x: r.maxX, y: r.maxY)] }
        }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let minX = (xs.min() ?? 0) - 8, maxX = (xs.max() ?? 100) + 8
        let minY = (ys.min() ?? 0) - 8, maxY = (ys.max() ?? 100) + 4
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    // MARK: Szenen (Einheiten ≈ Zentimeter in Seitenansicht, Blick nach rechts)

    private static let standing: [(CGFloat, CGFloat)] = [(50, 13), (50, 24), (51, 38), (52, 51), (50, 52), (51, 72), (50, 91), (58, 91)]

    static func scene(for motion: ExerciseMotion) -> MotionScene {
        switch motion {
        case .squat:
            MotionScene(start: Pose([(50, 13), (50, 24), (43, 31), (49, 23), (50, 52), (51, 72), (50, 91), (58, 91)]),
                        end: Pose([(54, 33), (49, 43), (42, 50), (48, 42), (36, 66), (57, 70), (50, 91), (58, 91)]),
                        load: .barbell, fixtures: [.floor(91)])
        case .deadlift:
            MotionScene(start: Pose([(68, 49), (60, 55), (60, 69), (60, 83), (38, 66), (58, 74), (50, 91), (58, 91)]),
                        end: Pose(standing), load: .barbell, fixtures: [.floor(91)])
        case .romanianDeadlift:
            MotionScene(start: Pose([(50, 13), (50, 24), (51, 38), (52, 51), (50, 52), (52, 72), (50, 91), (58, 91)]),
                        end: Pose([(73, 37), (64, 42), (64, 56), (64, 70), (40, 53), (54, 72), (50, 91), (58, 91)]),
                        load: .barbell, fixtures: [.floor(91)])
        case .benchPress:
            MotionScene(start: Pose([(18, 63), (29, 65), (30, 51), (31, 37), (57, 65), (73, 68), (76, 91), (84, 91)]),
                        end: Pose([(18, 63), (29, 65), (21, 68), (30, 55), (57, 65), (73, 68), (76, 91), (84, 91)]),
                        load: .barbell, fixtures: [.bench(CGRect(x: 12, y: 69, width: 60, height: 6)), .floor(91)])
        case .overheadPress:
            MotionScene(start: Pose([(50, 13), (50, 24), (57, 33), (54, 22), (50, 52), (51, 72), (50, 91), (58, 91)]),
                        end: Pose([(50, 13), (50, 24), (53, 10), (52, -4), (50, 52), (51, 72), (50, 91), (58, 91)]),
                        load: .barbell, fixtures: [.floor(91)])
        case .pullUp:
            MotionScene(start: Pose([(55, 14), (50, 24), (50, 10), (50, -5), (50, 52), (54, 70), (49, 86), (55, 89)]),
                        end: Pose([(56, -9), (50, 1), (40, 8), (50, -5), (50, 29), (54, 47), (49, 63), (55, 66)]),
                        fixtures: [.bar(-5)])
        case .latPulldown:
            MotionScene(start: Pose([(46, 23), (45, 34), (46, 20), (47, 6), (44, 62), (64, 62), (64, 82), (70, 84)]),
                        end: Pose([(40, 24), (42, 34), (36, 44), (46, 32), (44, 62), (64, 62), (64, 82), (70, 84)]),
                        load: .cable(CGPoint(x: 47, y: -12)), fixtures: [.bench(CGRect(x: 32, y: 63, width: 24, height: 4)), .floor(84)])
        case .barbellRow:
            MotionScene(start: Pose([(73, 42), (64, 46), (64, 60), (64, 73), (40, 58), (55, 73), (50, 91), (58, 91)]),
                        end: Pose([(73, 42), (64, 46), (52, 50), (60, 60), (40, 58), (55, 73), (50, 91), (58, 91)]),
                        load: .barbell, fixtures: [.floor(91)])
        case .cableRow:
            MotionScene(start: Pose([(52, 36), (46, 45), (58, 52), (70, 58), (38, 70), (56, 60), (72, 68), (74, 61)]),
                        end: Pose([(38, 34), (38, 44), (28, 54), (44, 58), (38, 70), (56, 60), (72, 68), (74, 61)]),
                        load: .cable(CGPoint(x: 92, y: 62)), fixtures: [.bench(CGRect(x: 24, y: 72, width: 26, height: 5))])
        case .curl:
            MotionScene(start: Pose([(50, 13), (50, 24), (50, 38), (51, 52), (50, 52), (51, 72), (50, 91), (58, 91)]),
                        end: Pose([(50, 13), (50, 24), (50, 38), (59, 27), (50, 52), (51, 72), (50, 91), (58, 91)]),
                        load: .dumbbell, fixtures: [.floor(91)])
        case .pushdown:
            MotionScene(start: Pose([(53, 13), (51, 24), (53, 38), (63, 30), (49, 52), (51, 72), (50, 91), (58, 91)]),
                        end: Pose([(53, 13), (51, 24), (53, 38), (55, 52), (49, 52), (51, 72), (50, 91), (58, 91)]),
                        load: .cable(CGPoint(x: 66, y: -6)), fixtures: [.floor(91)])
        case .lateralRaise:
            MotionScene(start: Pose([(50, 12), (58, 24), (60, 38), (61, 51), (55, 52), (55, 72), (55, 91), (58, 91)]),
                        end: Pose([(50, 12), (58, 24), (71, 26), (84, 27), (55, 52), (55, 72), (55, 91), (58, 91)]),
                        load: .dumbbell, fixtures: [.floor(91)], mirrorX: 50)
        case .splitSquat:
            MotionScene(start: Pose([(40, 13), (40, 24), (41, 38), (42, 51), (40, 52), (52, 70), (56, 91), (64, 91)],
                                    rear: [(30, 70), (18, 86), (14, 91)]),
                        end: Pose([(40, 29), (40, 40), (41, 54), (42, 67), (40, 68), (57, 72), (56, 91), (64, 91)],
                                  rear: [(32, 88), (18, 86), (14, 91)]),
                        load: .dumbbell, fixtures: [.floor(91)])
        case .hipThrust:
            MotionScene(start: Pose([(19, 53), (28, 58), (36, 68), (45, 76), (46, 78), (60, 70), (66, 91), (74, 91)]),
                        end: Pose([(18, 57), (28, 58), (38, 52), (49, 57), (50, 58), (66, 69), (66, 91), (74, 91)]),
                        load: .barbell, fixtures: [.bench(CGRect(x: 4, y: 60, width: 24, height: 8)), .floor(91)])
        case .pushUp:
            MotionScene(start: Pose([(21, 62), (30, 66), (30, 79), (30, 91), (60, 72), (75, 79), (90, 86), (93, 91)]),
                        end: Pose([(21, 80), (30, 82), (40, 78), (30, 91), (60, 84), (75, 87), (90, 89), (93, 91)]),
                        fixtures: [.floor(91)])
        }
    }
}
