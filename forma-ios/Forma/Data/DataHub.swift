import Foundation
import SwiftUI
import UIKit

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
    /// Letzter erfolgreicher Import (überlebt Neustarts).
    private(set) var lastUpdate: Date? = UserDefaults.standard.object(forKey: "forma.lastUpdate") as? Date {
        didSet { UserDefaults.standard.set(lastUpdate, forKey: "forma.lastUpdate") }
    }
    /// Letzter Abruf, den iOS im Hintergrund ausgelöst hat.
    private(set) var lastBackgroundSync: Date? = UserDefaults.standard.object(forKey: "forma.lastBackgroundSync") as? Date {
        didSet { UserDefaults.standard.set(lastBackgroundSync, forKey: "forma.lastBackgroundSync") }
    }
    /// Kam während eines Abrufs ein neuer Anstoß, wird danach noch einmal geladen (nichts geht verloren).
    private var refreshPending = false
    private var inFlight: Task<RefreshResult, Never>?
    private var lastResult: RefreshResult = .unchanged
    /// Zählt Quellenwechsel; Abrufe einer überholten Quelle werden verworfen (Codex R-02-14).
    private var generation = 0
    /// Wartet ein Abruf auf das Entsperren des iPhones?
    private(set) var waitingForUnlock = false
    /// Letzter Versuch im Hintergrund (auch ohne neue Daten).
    private(set) var lastBackgroundAttempt: Date? = UserDefaults.standard.object(forKey: "forma.lastBackgroundAttempt") as? Date {
        didSet { UserDefaults.standard.set(lastBackgroundAttempt, forKey: "forma.lastBackgroundAttempt") }
    }
    /// Hinweis, falls Apple Health die Hintergrundzustellung nicht erlaubt.
    private(set) var observerNote: String?
    private var debounce: Task<Void, Never>?
    private(set) var healthAuthorized = UserDefaults.standard.bool(forKey: "forma.healthAuthorized")
    var lastError: String?
    /// Kurzer Hinweis zum Sync-Zustand (gesperrt, letzter Stand …), wird im Profil gezeigt.
    private(set) var syncNote: String?

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
        didSet {
            UserDefaults.standard.set(preferredSource.rawValue, forKey: "forma.source")
            guard oldValue != preferredSource else { return }
            generation += 1
            Task { await self.refresh() }
        }
    }

    /// Löscht die lokale Kopie der Gesundheitsdaten (Codex R-02-02). Apple Health selbst bleibt unberührt.
    func deleteLocalHealthCopy() {
        SyncStore.clear()
        lastUpdate = nil
        lastBackgroundSync = nil
        lastBackgroundAttempt = nil
        syncNote = nil
        if activeSource == .health { longDays = SyncStore.normalized([]) }
    }

    init() {
        var source = DataSourceKind(rawValue: UserDefaults.standard.string(forKey: "forma.source") ?? "") ?? .automatic
        // Die alte Fitbit-Schnittstelle ist abgeschaltet (Google, 2.11.2026).
        if source == .fitbit { source = .automatic }
        if ProcessInfo.processInfo.arguments.contains("-uitest") { source = .sample }
        preferredSource = source
        let expectsRealData = source != .sample && UserDefaults.standard.bool(forKey: "forma.healthAuthorized")
        if expectsRealData, let cached = SyncStore.load() {
            // Sofort mit dem letzten Stand starten, auch offline oder wenn Health gerade gesperrt ist.
            // Auf heute normalisiert: Ein Stand von gestern erscheint nicht als „heute“ (Codex R-02-24).
            longDays = SyncStore.normalized(cached.days)
            activeSource = .health
            hasLoaded = true
        } else {
            longDays = expectsRealData ? [] : SampleData.days()
            hasLoaded = !expectsRealData
        }
        if expectsRealData && !FormaApp.isUITest { startBackgroundSync() }
        // Nach dem Entsperren sofort nachholen, was im gesperrten Zustand nicht lesbar war (Codex R-02-06).
        _ = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.waitingForUnlock else { return }
                await self.syncAndNotify(background: true)
            }
        }
    }

    /// Ergebnis eines Abrufs (Codex R-02-06): Nur echte Aktualisierungen lösen den Coach aus.
    enum RefreshResult: Equatable {
        case updated
        case partial(Set<MetricSeries>)
        case unchanged       // nichts Neues übernommen (alles fehlgeschlagen oder verdächtig leer)
        case locked          // iPhone gesperrt, Apple Health gibt nichts heraus
        case superseded      // Quelle wurde während des Abrufs gewechselt, Ergebnis verworfen
        case sample
        var isFresh: Bool { self == .updated || { if case .partial = self { return true }; return false }() }
    }

    // MARK: Hintergrund

    /// Startet die Apple-Health-Beobachter. Wird bei jedem App-Start aufgerufen,
    /// auch wenn iOS die App nur im Hintergrund für neue Daten weckt.
    func startBackgroundSync() {
        Task { [health] in
            let failed = await health.startObserving { [weak self] in
                await self?.scheduleRefresh(background: true)
            }
            if !failed.isEmpty {
                self.observerNote = "Hintergrundzustellung nicht verfügbar für: \(failed.joined(separator: ", ")). Forma aktualisiert diese Werte beim Öffnen und über den regelmäßigen Hintergrundabruf."
            } else {
                self.observerNote = nil
            }
        }
    }

    /// Mehrere Anstöße kurz hintereinander (z. B. Schlaf + HRV nach dem Aufwachen) werden gebündelt.
    func scheduleRefresh(background: Bool) async {
        debounce?.cancel()
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncAndNotify(background: background)
        }
        debounce = task
        await task.value
    }

    /// Hintergrundabruf durch iOS (BGAppRefreshTask).
    func backgroundRefresh() async {
        await syncAndNotify(background: true)
    }

    /// Ein Weg für alle Abrufe: laden, Zeitpunkte führen, Coach nur bei frischen Daten (Codex R-02-06/07).
    @discardableResult
    func syncAndNotify(background: Bool) async -> RefreshResult {
        let result = await refresh()
        if background { lastBackgroundAttempt = .now }
        if result.isFresh {
            if background { lastBackgroundSync = .now }
            CoachNotifier.afterSync(self)
        }
        return result
    }

    /// Welche Ringe haben heute eine echte Grundlage? (Codex R-01-03)
    struct Availability: Equatable {
        var recovery: Bool
        var sleep: Bool
        var strain: Bool
    }

    /// Erholung braucht einen heutigen Herzwert **mit** Vergleichsbasis (mind. 4 frühere Werte).
    /// Belastung braucht aktive Energie oder ein Training – Schritte gehen nicht in die Formel ein (Codex R-02-03).
    var availability: Availability {
        let t = waitingForFitbit ? (yesterday ?? today) : today
        let hrvOK = t.hrv != nil && baseline(\.hrv) != nil
        let rhrOK = t.restingHR != nil && baseline(\.restingHR) != nil
        return Availability(
            recovery: hrvOK || rhrOK,
            sleep: t.sleep != nil,
            strain: today.activeEnergy != nil || !today.workouts.isEmpty)
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

    /// Hat Tag `index` einen Herzwert mit Vergleichsbasis aus den Tagen davor?
    func hasRecoveryBasis(at index: Int) -> Bool {
        let d = days
        guard d.indices.contains(index) else { return false }
        let prior = d.prefix(index)
        let hrvOK = d[index].hrv != nil && ScoreEngine.baseline(prior.compactMap(\.hrv)) != nil
        let rhrOK = d[index].restingHR != nil && ScoreEngine.baseline(prior.compactMap(\.restingHR)) != nil
        return hrvOK || rhrOK
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
            startBackgroundSync()
            await syncAndNotify(background: false)
        } catch {
            lastError = "Zugriff auf Apple Health nicht möglich: \(error.localizedDescription)"
        }
    }

    /// Lädt die gewählte Quelle. Läuft schon ein Abruf, wartet der Aufrufer darauf und es folgt
    /// genau ein weiterer Durchlauf – kein Anstoß geht verloren (Codex R-02-06).
    @discardableResult
    func refresh() async -> RefreshResult {
        if let running = inFlight {
            refreshPending = true
            return await running.value
        }
        repeat {
            refreshPending = false
            let task = Task { @MainActor in await self.performRefresh() }
            inFlight = task
            isLoading = true
            lastResult = await task.value
            inFlight = nil
        } while refreshPending
        isLoading = false
        hasLoaded = true
        return lastResult
    }

    private func performRefresh() async -> RefreshResult {
        let myGeneration = generation
        let source = resolveSource()
        switch source {
        case .fitbit:
            var loaded: [DayMetrics] = []
            for offset in stride(from: 13, through: 0, by: -1) {
                let date = Date.now.startOfDay.adding(days: -offset)
                if offset > 1, let cached = fitbitCache[date] {
                    loaded.append(cached)
                } else {
                    let day = await fitbit.loadDay(date).sanitized()
                    if !fitbit.isRateLimited { fitbitCache[date] = day }
                    loaded.append(fitbitCache[date] ?? day)
                }
            }
            guard myGeneration == generation else { return .superseded }
            if loaded.contains(where: { $0.hrv != nil || $0.sleep != nil }) {
                longDays = loaded
                activeSource = .fitbit
                lastUpdate = .now
                lastError = nil
                return .updated
            }
            return .unchanged
        case .health:
            // Bei gesperrtem iPhone gibt Apple Health nichts heraus. Dann nichts überschreiben (später erneut).
            guard UIApplication.shared.isProtectedDataAvailable else {
                waitingForUnlock = true
                syncNote = "iPhone gesperrt – Forma holt die Daten nach dem Entsperren."
                return .locked
            }
            waitingForUnlock = false
            let imported = await health.loadDays(count: 180)
            let person = await health.person()
            guard myGeneration == generation else { return .superseded }
            healthPerson = person
            let fresh = imported.days.map { $0.sanitized() }
            let previous = activeSource == .health ? longDays : (SyncStore.load().map { SyncStore.normalized($0.days) } ?? [])
            activeSource = .health
            switch SyncStore.merge(old: previous, new: fresh, failed: imported.failed) {
            case .rejectedEmpty:
                if !previous.isEmpty { longDays = SyncStore.normalized(previous) }
                syncNote = imported.failed.count == MetricSeries.allCases.count
                    ? "Apple Health war gerade nicht lesbar. Du siehst den letzten Stand."
                    : "Apple Health liefert gerade keine Daten mehr (Zugriff geändert?). Du siehst den letzten Stand."
                return .unchanged
            case .merged(let merged):
                longDays = merged
                let hasData = merged.suffix(30).contains(where: SyncStore.hasData)
                guard hasData else {
                    // Keine stillen Beispieldaten, wenn Apple Health freigegeben ist (Codex R-01-03).
                    lastError = "In Apple Health wurden für die letzten 30 Tage keine Schlaf-, Herz- oder Schrittdaten gefunden. Prüfe in der Health-App unter Profilbild → Apps → Forma, ob alles freigegeben ist."
                    return .unchanged
                }
                lastUpdate = .now
                lastError = nil
                let saved = SyncStore.save(.init(days: merged, updated: .now, source: "health"))
                if !imported.failed.isEmpty {
                    syncNote = "Teilweise aktualisiert. Nicht lesbar: \(imported.failed.map(\.title).sorted().joined(separator: ", ")) – dort gilt der letzte Stand."
                } else {
                    syncNote = saved ? nil : "Die lokale Kopie konnte nicht gespeichert werden. Beim nächsten Start lädt Forma neu aus Apple Health."
                }
                return imported.failed.isEmpty ? .updated : .partial(imported.failed)
            }
        case .sample, .automatic:
            guard myGeneration == generation else { return .superseded }
            longDays = SampleData.days()
            activeSource = .sample
            return .sample
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
