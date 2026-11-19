import SwiftData
import SwiftUI

extension View {
    /// Einmal am Root der aktuell verwendeten SwiftData-Datenbank anbringen.
    @MainActor
    func achievementTracking(healthScope: AchievementHealthScope?) -> some View {
        modifier(AchievementTracking(healthScope: healthScope))
    }
}

@MainActor
private struct AchievementTracking: ViewModifier {
    @Environment(DataHub.self) private var hub
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkoutSession.start) private var sessions: [WorkoutSession]
    let healthScope: AchievementHealthScope?
    private var tracker: AchievementTracker { hub.achievementTracker }

    private struct Input: Equatable, Sendable {
        let scope: AchievementHealthScope?
        let isSample: Bool
        let isActive: Bool
        let generation: Int
        let days: [DayMetrics]
        let person: PersonInfo?
        let workouts: [AchievementWorkout]
    }

    func body(content: Content) -> some View {
        let tracksHealth = hub.isSample || healthScope != nil
        let input = Input(scope: healthScope, isSample: hub.isSample, isActive: scenePhase == .active,
                          generation: hub.generation,
                          days: tracksHealth ? hub.longDays : [], person: tracksHealth ? hub.person : nil,
                          workouts: sessions.map { session in
            var bests: [String: Double] = [:]
            for set in session.workSets where set.weight.isFinite {
                let weight = OneRepMax.epley(weight: set.weight, reps: set.reps)
                if weight.isFinite, weight > bests[set.exerciseName, default: 0] {
                    bests[set.exerciseName] = weight
                }
            }
            return AchievementWorkout(start: session.start, end: session.end, bests: bests)
        })
        let visible = tracker.visibleUnlock(scope: input.scope, isSample: input.isSample)
        let sampleDay = hub.sampleDay

        content
            .overlay(alignment: .top) {
                AchievementUnlockBanner(scope: input.scope, isSample: input.isSample)
            }
            .environment(tracker)
            .sensoryFeedback(.success, trigger: visible?.id) { _, new in new != nil }
            .onChange(of: visible?.id) { _, _ in
                if let visible {
                    AccessibilityNotification.Announcement("Erfolg freigeschaltet. \(visible.subtitle)").post()
                }
            }
            .task(id: sampleDay) {
                guard let sampleDay, sampleDay == hub.sampleDay, !Task.isCancelled else { return }
                SampleData.seedWorkouts(hub.longDays, in: context)
            }
            .task(id: input) {
                guard input.isActive, !Task.isCancelled, input.generation == hub.generation,
                      input.scope == hub.achievementHealthScope else { return }
                evaluate(input)
            }
            .task(id: visible?.id) {
                guard let id = visible?.id else { return }
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                guard !Task.isCancelled else { return }
                tracker.expireUnlock(id: id)
            }
    }

    private func evaluate(_ input: Input) {
        let now = Date.now
        var trend: (BodyAge.Estimate, BodyAge.Estimate)?
        if let person = input.person {
            let training = input.workouts.filter { $0.start <= $0.end && $0.end <= now }
                .map { (start: $0.start, minutes: $0.end.timeIntervalSince($0.start) / 60) }
            if case .ready(let result) = HealthAgeTrend.outcome(days: input.days, person: person,
                                                              sessions: training, now: now),
               let previous = result.previous, let recent = result.recent {
                trend = (previous, recent)
            }
        }
        let health = AchievementEngine.health(days: input.days, ageTrend: trend, now: now)
        let record = AchievementEngine.firstRecord(in: input.workouts, now: now)
        if input.isSample {
            tracker.updateSample(health: health, record: record)
        } else {
            _ = tracker.update(scope: input.scope, health: health, record: record, now: now)
        }
    }
}

struct AchievementUnlockBanner: View {
    @Environment(AchievementTracker.self) private var tracker: AchievementTracker?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scope: AchievementHealthScope?
    let isSample: Bool

    var body: some View {
        let unlock = tracker?.visibleUnlock(scope: scope, isSample: isSample)
        ZStack(alignment: .top) {
            if let unlock, let first = unlock.achievements.first {
                HStack(spacing: 12) {
                    AchievementBadge(achievement: first, unlocked: true, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Erfolg freigeschaltet").font(.subheadline.weight(.semibold))
                        Text(unlock.subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: 420)
                .background(Theme.cardRaised, in: .rect(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.plateEdge, lineWidth: 1) }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 0, y: -6)))
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.28), value: unlock?.id)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension AchievementUnlock {
    var subtitle: String {
        achievements.count == 1 ? (achievements.first?.title ?? "") : "\(achievements.count) neue Abzeichen"
    }
}

private extension AchievementTracker {
    func visibleUnlock(scope: AchievementHealthScope?, isSample: Bool) -> AchievementUnlock? {
        guard !isSample, let recentUnlock, recentUnlock.scope == scope else { return nil }
        return recentUnlock
    }
}
