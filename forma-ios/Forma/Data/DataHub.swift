import Foundation
import SwiftUI

/// Sammelt Daten aus der gewählten Quelle und berechnet die Tageswerte.
@MainActor
@Observable
final class DataHub {
    let health = HealthService()
    let fitbit = FitbitService()

    private(set) var days: [DayMetrics] = SampleData.days()
    private(set) var activeSource: DataSourceKind = .sample
    private(set) var isLoading = false
    private(set) var lastUpdate: Date?
    private(set) var healthAuthorized = UserDefaults.standard.bool(forKey: "forma.healthAuthorized")
    var lastError: String?

    var preferredSource: DataSourceKind {
        didSet { UserDefaults.standard.set(preferredSource.rawValue, forKey: "forma.source") }
    }

    init() {
        preferredSource = DataSourceKind(rawValue: UserDefaults.standard.string(forKey: "forma.source") ?? "") ?? .automatic
        if ProcessInfo.processInfo.arguments.contains("-uitest") { preferredSource = .sample }
    }

    var isSample: Bool { activeSource == .sample }
    var today: DayMetrics { days.last ?? DayMetrics(date: .now.startOfDay) }
    var yesterday: DayMetrics? { days.count > 1 ? days[days.count - 2] : nil }
    var history: [DayMetrics] { Array(days.dropLast()) }

    /// Fitbit hat für heute noch keinen Schlaf geliefert: gestrige Werte gedimmt zeigen.
    var waitingForFitbit: Bool { activeSource == .fitbit && today.sleep == nil }

    var scores: DayScores { ScoreEngine.scores(today: today, history: history) }

    var yesterdayScores: DayScores? {
        guard days.count > 2 else { return nil }
        let y = days[days.count - 2]
        return ScoreEngine.scores(today: y, history: Array(days.dropLast(2)))
    }

    /// Werte für die Ringe (bei fehlendem Fitbit-Sync: gestern).
    var ringScores: DayScores {
        if waitingForFitbit, let y = yesterdayScores {
            var s = scores
            s.recovery = y.recovery
            s.sleep = y.sleep
            s.target = y.target
            return s
        }
        return scores
    }

    func scores(for index: Int) -> DayScores {
        ScoreEngine.scores(today: days[index], history: Array(days.prefix(index)))
    }

    func baseline(_ keyPath: KeyPath<DayMetrics, Double?>) -> ScoreEngine.Baseline? {
        ScoreEngine.baseline(history.compactMap { $0[keyPath: keyPath] })
    }

    // MARK: Laden

    func requestHealthAccess() async {
        guard health.isAvailable else { lastError = "Apple Health ist auf diesem Gerät nicht verfügbar."; return }
        do {
            try await health.requestAuthorization()
            healthAuthorized = true
            UserDefaults.standard.set(true, forKey: "forma.healthAuthorized")
            await refresh()
        } catch {
            lastError = "Zugriff auf Apple Health nicht möglich: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; lastUpdate = .now }
        let source = resolveSource()
        switch source {
        case .fitbit:
            var loaded: [DayMetrics] = []
            for offset in stride(from: 13, through: 0, by: -1) {
                loaded.append(await fitbit.loadDay(Date.now.startOfDay.adding(days: -offset)))
            }
            if loaded.contains(where: { $0.hrv != nil || $0.sleep != nil }) {
                days = loaded
                activeSource = .fitbit
            } else {
                days = SampleData.days()
                activeSource = .sample
                lastError = "Von Fitbit kamen noch keine Daten. Es werden Beispieldaten gezeigt."
            }
        case .health:
            let loaded = await health.loadDays(count: 30)
            let hasData = loaded.contains { $0.hrv != nil || $0.sleep != nil || ($0.steps ?? 0) > 0 }
            if hasData {
                days = loaded
                activeSource = .health
            } else {
                days = SampleData.days()
                activeSource = .sample
            }
        case .sample, .automatic:
            days = SampleData.days()
            activeSource = .sample
        }
    }

    private func resolveSource() -> DataSourceKind {
        switch preferredSource {
        case .sample: return .sample
        case .fitbit: return fitbit.isConnected ? .fitbit : .sample
        case .health: return healthAuthorized ? .health : .sample
        case .automatic:
            if fitbit.isConnected { return .fitbit }
            if healthAuthorized { return .health }
            return .sample
        }
    }
}
