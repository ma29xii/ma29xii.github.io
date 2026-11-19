import SwiftUI

struct AchievementsView: View {
    @Environment(AchievementTracker.self) private var tracker
    @Environment(\.dynamicTypeSize) private var typeSize
    let healthScope: AchievementHealthScope?
    let isSample: Bool

    var body: some View {
        let unlocked = isSample ? tracker.sample : tracker.unlocked(scope: healthScope)
        let columns = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isSample { SampleDataBadge() }
                Text("\(unlocked.count) von \(Achievement.allCases.count) freigeschaltet")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(Achievement.allCases) { achievement in
                        AchievementTile(achievement: achievement, unlocked: unlocked.contains(achievement))
                    }
                }
            }
            .padding(16)
        }
        .formaScreen()
        .navigationTitle("Erfolge")
        .accessibilityIdentifier("achievements.grid")
    }
}

private struct AchievementTile: View {
    let achievement: Achievement
    let unlocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                AchievementBadge(achievement: achievement, unlocked: unlocked, size: 56)
                Spacer(minLength: 0)
                Image(systemName: unlocked ? "checkmark" : "lock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(unlocked ? achievement.tint : Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(achievement.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(achievement.requirement)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(unlocked ? achievement.tint.opacity(0.30) : Theme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(unlocked ? "Freigeschaltet" : "Noch offen")
        .accessibilityIdentifier("achievements.badge.\(achievement.rawValue)")
    }
}

struct AchievementBadge: View {
    let achievement: Achievement
    let unlocked: Bool
    let size: CGFloat

    var body: some View {
        let tint = unlocked ? achievement.tint : Theme.textSecondary
        let outline = BadgeOutline(achievement: achievement)
        ZStack {
            outline.fill(tint.opacity(unlocked ? 0.15 : 0.06))
            outline.stroke(tint.opacity(unlocked ? 0.68 : 0.45), lineWidth: 1)
            outline.stroke(tint.opacity(0.22), lineWidth: 1).scaleEffect(0.81)
            Image(systemName: achievement.symbol)
                .font(.system(size: size * 0.37, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .padding(1)
        .accessibilityHidden(true)
    }
}

private struct BadgeOutline: Shape {
    let achievement: Achievement

    func path(in rect: CGRect) -> Path {
        switch achievement {
        case .sleep: Circle().path(in: rect)
        case .steps: RoundedRectangle(cornerRadius: rect.width * 0.24).path(in: rect)
        case .firstRecord:
            Path { path in
                let points = [
                    CGPoint(x: rect.midX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.29),
                    CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.71),
                    CGPoint(x: rect.midX, y: rect.maxY),
                    CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.71),
                    CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.29)
                ]
                path.addLines(points)
                path.closeSubpath()
            }
        case .tracked: Capsule().path(in: rect.insetBy(dx: rect.width * 0.12, dy: 0))
        case .healthAge: Ellipse().path(in: rect.insetBy(dx: 0, dy: rect.height * 0.12))
        }
    }
}

extension Achievement {
    var title: String {
        switch self {
        case .sleep: "Gut geschlafen"
        case .steps: "In Bewegung"
        case .firstRecord: "Erste Bestleistung"
        case .tracked: "Drangeblieben"
        case .healthAge: "Health Age gesunken"
        }
    }

    var requirement: String {
        switch self {
        case .sleep: "\(AchievementEngine.streakLength) Nächte am Stück länger als deinen geschätzten Schlafbedarf geschlafen."
        case .steps: "\(AchievementEngine.streakLength) Tage am Stück mindestens \(Format.number(Double(AchievementEngine.stepGoal))) Schritte."
        case .firstRecord: "In einer Übung dein bisheriges geschätztes Maximalgewicht übertroffen."
        case .tracked: "An \(AchievementEngine.trackedDays) Tagen Werte aus Google Health erfasst."
        case .healthAge: "Health Age im Vergleich zweier Zeiträume um mindestens ein halbes Jahr gesunken."
        }
    }

    fileprivate var symbol: String {
        switch self {
        case .sleep: "moon.stars.fill"
        case .steps: "figure.walk"
        case .firstRecord: "dumbbell.fill"
        case .tracked: "calendar"
        case .healthAge: "arrow.down.right"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .sleep: Color(hex: 0xBAB0FF)
        case .steps: Color(hex: 0x91D7EE)
        case .firstRecord: Color(hex: 0xF0CB8B)
        case .tracked: Color(hex: 0xD8D8DE)
        case .healthAge: Color(hex: 0x8DDEBF)
        }
    }
}
