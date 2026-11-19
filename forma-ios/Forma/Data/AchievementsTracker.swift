import CryptoKit
import Foundation
import Observation

struct AchievementHealthScope: Equatable, Sendable {
    fileprivate let storageKey: String

    init(accountID: String) {
        let digest = SHA256.hash(data: Data(accountID.utf8))
        storageKey = "forma.achievements.google.v1." + Data(digest).base64EncodedString()
    }
}

struct AchievementUnlock: Identifiable, Sendable {
    let id = UUID()
    let scope: AchievementHealthScope?
    let achievements: [Achievement]
}

/// Behält nur die Abzeichen-Kennungen für abgeschlossene Erfolge.
@MainActor
@Observable
final class AchievementTracker {
    private let defaults: UserDefaults
    private let trainingKey = "forma.achievements.training.v1"
    private var training: Set<Achievement> = []
    private var health: Set<Achievement> = []
    private var healthScope: AchievementHealthScope?
    private(set) var sample: Set<Achievement> = []
    private(set) var recentUnlock: AchievementUnlock?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func unlocked(scope: AchievementHealthScope?) -> Set<Achievement> {
        scope == healthScope ? training.union(health) : training
    }

    func updateSample(health: [Achievement: Date], record: Date?) {
        sample = Set(health.keys)
        if record != nil { sample.insert(.firstRecord) }
        recentUnlock = nil
    }

    func update(scope: AchievementHealthScope?, health evidence: [Achievement: Date], record: Date?,
                now: Date, calendar: Calendar = .forma) -> [Achievement] {
        let records: [Achievement: Date] = record.map { [.firstRecord: $0] } ?? [:]
        let trainingUpdate = merge(records, key: trainingKey, now: now, calendar: calendar)
        training = trainingUpdate.unlocked
        healthScope = scope
        let healthUpdate = scope.map { merge(evidence, key: $0.storageKey, now: now, calendar: calendar) }
        health = healthUpdate?.unlocked ?? []
        let new = trainingUpdate.new.union(healthUpdate?.new ?? [])
        let ordered = Achievement.allCases.filter { new.contains($0) }
        if !ordered.isEmpty {
            recentUnlock = AchievementUnlock(scope: scope, achievements: ordered)
        } else if recentUnlock?.scope != scope {
            recentUnlock = nil
        }
        return ordered
    }

    func expireUnlock(id: UUID) {
        if recentUnlock?.id == id { recentUnlock = nil }
    }

    func deleteHealth(scope: AchievementHealthScope) {
        defaults.removeObject(forKey: scope.storageKey)
        if healthScope == scope { health.removeAll() }
        if recentUnlock?.scope == scope { recentUnlock = nil }
    }

    private func merge(_ evidence: [Achievement: Date], key: String, now: Date,
                       calendar: Calendar) -> (unlocked: Set<Achievement>, new: Set<Achievement>) {
        let stored = defaults.stringArray(forKey: key)
        let prior = Set((stored ?? []).compactMap(Achievement.init(rawValue:)))
        let eligible = evidence.filter { $0.value <= now }
        let unlocked = prior.union(eligible.keys)
        if stored == nil || prior != unlocked {
            defaults.set(unlocked.map(\.rawValue).sorted(), forKey: key)
        }
        let new = stored == nil ? [] : Set(eligible.keys.filter { achievement in
            guard !prior.contains(achievement), let date = eligible[achievement] else { return false }
            return calendar.isDate(date, inSameDayAs: now)
        })
        return (unlocked, new)
    }
}
