import Foundation
import SwiftUI

/// Sammelt Daten aus der gewählten Quelle und berechnet die Tageswerte.
@MainActor
@Observable
final class DataHub {
    let health = HealthService()
    let fitbit = FitbitService()

    /// Bis zu 180 Tage für das Körperalter.
    private(set) var longDays: [DayMetrics] = SampleData.days()
    /// Die letzten 30 Tage für Ringe und Trends.
    var days: [DayMetrics] { Array(longDays.suffix(30)) }
    private(set) var healthPerson: (birthDate: Date?, sex: BiologicalSex) = (nil, .unknown)
    /// Fitbit erlaubt etwa 150 Anfragen pro Stunde: ältere Tage nur einmal laden.
    private var fitbitCache: [Date: DayMetrics] = [:]
    private(set) var activeSource: DataSourceKind = .sample
    private(set) var isLoading = false
    private(set) var lastUpdate: Date?
    private(set) var healthAuthorized = UserDefaults.standard.bool(forKey: "forma.healthAuthorized")
    var lastError: String?

    /// Manuelle Angaben aus dem Profil haben Vorrang, dann Apple Health, bei Beispieldaten eine Annahme.
    var person: PersonInfo {
        _ = profileRevision
        let defaults = UserDefaults.standard
        let year = defaults.integer(forKey: "forma.birthYear")
        let manualSex = BiologicalSex(rawValue: defaults.string(forKey: "forma.sex") ?? "") ?? .unknown
        let sex = manualSex != .unknown ? manualSex : healthPerson.sex
        if year > 1900 {
            let birth = Calendar.forma.date(from: DateComponents(year: year, month: 7, day: 1))
            return PersonInfo(birthDate: birth, sex: sex, origin: .manual)
        }
        if let birth = healthPerson.birthDate { return PersonInfo(birthDate: birth, sex: sex, origin: .health) }
        if isSample {
            return PersonInfo(birthDate: Date.now.addingTimeInterval(-30 * 365.2425 * 86_400),
                              sex: sex == .unknown ? .male : sex, origin: .assumed)
        }
        return PersonInfo(birthDate: nil, sex: sex, origin: .missing)
    }

    /// Wird von der Profilseite gesetzt, damit abhängige Ansichten neu rechnen.
    private(set) var profileRevision = 0
    func profileChanged() { profileRevision += 1 }

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
                let date = Date.now.startOfDay.adding(days: -offset)
                // Heute und gestern immer frisch, ältere Tage aus dem Zwischenspeicher.
                if offset > 1, let cached = fitbitCache[date] {
                    loaded.append(cached)
                } else {
                    let day = await fitbit.loadDay(date).sanitized()
                    // Bei erreichtem Limit nichts zwischenspeichern, sonst bleiben leere Tage hängen.
                    if !fitbit.isRateLimited { fitbitCache[date] = day }
                    loaded.append(fitbitCache[date] ?? day)
                }
            }
            if loaded.contains(where: { $0.hrv != nil || $0.sleep != nil }) {
                longDays = loaded
                activeSource = .fitbit
            } else {
                longDays = SampleData.days()
                activeSource = .sample
                lastError = "Von Fitbit kamen noch keine Daten. Es werden Beispieldaten gezeigt."
            }
        case .health:
            let loaded = await health.loadDays(count: 180).map { $0.sanitized() }
            healthPerson = await health.person()
            let hasData = loaded.suffix(30).contains { $0.hrv != nil || $0.sleep != nil || ($0.steps ?? 0) > 0 }
            if hasData {
                longDays = loaded
                activeSource = .health
            } else {
                longDays = SampleData.days()
                activeSource = .sample
            }
        case .sample, .automatic:
            longDays = SampleData.days()
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
