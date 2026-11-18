import Foundation
import SwiftUI

/// Sammelt Daten aus der gewählten Quelle und berechnet die Tageswerte.
@MainActor
@Observable
final class DataHub {
    let health = HealthService()
    let fitbit = FitbitService()

    /// Bis zu 180 Tage für das Körperalter.
    private(set) var longDays: [DayMetrics]
    /// Wurde seit dem Start schon einmal erfolgreich geladen? Vorher keine Beispielwerte vortäuschen.
    private(set) var hasLoaded = false
    /// Die letzten 30 Tage für Ringe und Trends, inklusive Forma-Krafttrainings (zählen in die Belastung).
    var days: [DayMetrics] {
        var recent = Array(longDays.suffix(30))
        guard !formaWorkouts.isEmpty else { return recent }
        for i in recent.indices {
            let day = recent[i].date
            for w in formaWorkouts where w.start.startOfDay == day {
                let end = w.start.addingTimeInterval(w.duration)
                // Nicht doppelt zählen, wenn dasselbe Training auch in Apple Health steht.
                let overlaps = recent[i].workouts.contains { h in h.start < end && w.start < h.start.addingTimeInterval(h.duration) }
                if !overlaps { recent[i].workouts.append(w) }
            }
        }
        return recent
    }

    /// Trainings aus Forma (SwiftData), gesetzt von der Oberfläche.
    private(set) var formaWorkouts: [WorkoutSummary] = []
    func setFormaWorkouts(_ workouts: [WorkoutSummary]) {
        if workouts != formaWorkouts { formaWorkouts = workouts }
    }
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
        var source = DataSourceKind(rawValue: UserDefaults.standard.string(forKey: "forma.source") ?? "") ?? .automatic
        // Die alte Fitbit-Schnittstelle ist abgeschaltet (Google, 2.11.2026).
        if source == .fitbit { source = .automatic }
        if ProcessInfo.processInfo.arguments.contains("-uitest") { source = .sample }
        preferredSource = source
        let expectsRealData = source != .sample && UserDefaults.standard.bool(forKey: "forma.healthAuthorized")
        longDays = expectsRealData ? [] : SampleData.days()
        hasLoaded = !expectsRealData
    }

    /// Welche Ringe haben heute eine echte Grundlage? (Codex R-01-03)
    struct Availability: Equatable {
        var recovery: Bool
        var sleep: Bool
        var strain: Bool
    }

    var availability: Availability {
        let t = waitingForFitbit ? (yesterday ?? today) : today
        return Availability(
            recovery: t.hrv != nil || t.restingHR != nil,
            sleep: t.sleep != nil,
            strain: today.activeEnergy != nil || !today.workouts.isEmpty || today.steps != nil)
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
            if preferredSource == .sample { preferredSource = .automatic }
            UserDefaults.standard.set(true, forKey: "forma.healthAuthorized")
            await refresh()
        } catch {
            lastError = "Zugriff auf Apple Health nicht möglich: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
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
                lastUpdate = .now
                lastError = nil
            } else {
                longDays = SampleData.days()
                activeSource = .sample
                lastError = "Von Fitbit kamen noch keine Daten. Es werden Beispieldaten gezeigt."
            }
        case .health:
            let loaded = await health.loadDays(count: 180).map { $0.sanitized() }
            healthPerson = await health.person()
            let hasData = loaded.suffix(30).contains { $0.hrv != nil || $0.sleep != nil || ($0.steps ?? 0) > 0 }
            // Keine stillen Beispieldaten mehr, wenn Apple Health freigegeben ist (Codex R-01-03):
            // leere Tage bleiben leer und werden als „keine Daten“ gezeigt.
            longDays = loaded
            activeSource = .health
            if hasData {
                lastUpdate = .now
                lastError = nil
            } else {
                lastError = "In Apple Health wurden für die letzten 30 Tage keine Schlaf-, Herz- oder Schrittdaten gefunden. Prüfe in der Health-App unter Profilbild → Apps → Forma, ob alles freigegeben ist."
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
            if healthAuthorized { return .health }
            return .sample
        }
    }
}
