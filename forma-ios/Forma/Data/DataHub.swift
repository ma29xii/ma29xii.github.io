import Foundation
import SwiftUI

/// Vereint den Google-Import, den gesicherten Stand und die lokalen Krafttrainings.
@MainActor
@Observable
final class DataHub {
    private let googleService = GoogleHealthService()
    private let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
    private var accountID: String?
    private var connectionFailure: String?
    private var connecting = false

    var google: GoogleConnection {
        guard googleService.isConfigured else { return .notConfigured }
        if connecting { return .connecting }
        if let connectionFailure { return .failed(connectionFailure) }
        return accountID == nil ? .disconnected : .connected(lastSync: lastUpdate)
    }

    private(set) var longDays: [DayMetrics] = []
    private(set) var hasLoaded = false
    private(set) var activeSource: DataSourceKind = .google
    private(set) var isLoading = false
    private(set) var lastUpdate: Date?
    private(set) var lastBackgroundSync: Date?
    private(set) var lastBackgroundAttempt: Date?
    private(set) var syncNote: String?
    private(set) var formaWorkouts: [WorkoutSummary] = []
    private(set) var profileRevision = 0
    private var storedHours: [Date: HourlyMetrics] = [:]
    private var historyThrough: Date?
    private var historyGaps: Set<Date> = []
    private var generation = 0
    private var connectionGeneration = 0
    private var inFlight: Task<RefreshResult, Never>?
    private var attemptID: UUID?

    var preferredSource: DataSourceKind {
        didSet {
            guard oldValue != preferredSource else { return }
            if !isUITest { UserDefaults.standard.set(preferredSource.rawValue, forKey: "forma.source") }
            invalidateRefresh()
            showPreferredSource()
            Task { await syncAndNotify(background: false) }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        preferredSource = isUITest ? .sample : Self.source(from: defaults.string(forKey: "forma.source"))
        if !isUITest {
            defaults.set(preferredSource.rawValue, forKey: "forma.source")
            defaults.removeObject(forKey: "forma.healthAuthorized")
            // Löscht nur den nicht mehr verwendbaren Eintrag, ohne ihn auszulesen.
            _ = Keychain.set(nil, for: "fitbit.tokens")
            accountID = googleService.accountID
            lastBackgroundSync = defaults.object(forKey: "forma.google.lastBackgroundSync") as? Date
            lastBackgroundAttempt = defaults.object(forKey: "forma.google.lastBackgroundAttempt") as? Date
        }
        showPreferredSource()
    }

    nonisolated static func source(from stored: String?) -> DataSourceKind {
        stored == DataSourceKind.sample.rawValue ? .sample : .google
    }

    private func showPreferredSource() {
        activeSource = preferredSource
        syncNote = nil
        if isSample {
            longDays = SampleData.days()
            hasLoaded = true
        } else if let accountID, let cached = SyncStore.load(),
                  cached.source == DataSourceKind.google.rawValue, cached.accountID == accountID {
            longDays = SyncStore.normalized(cached.days)
            storedHours = Dictionary((cached.hours ?? []).map { ($0.start, $0) }, uniquingKeysWith: { _, newer in newer })
            historyThrough = cached.historyThrough
            historyGaps = Set(cached.historyGaps ?? [])
            lastUpdate = cached.updated
            hasLoaded = true
        } else {
            longDays = []
            storedHours = [:]
            historyThrough = nil
            historyGaps = []
            hasLoaded = false
        }
    }

    func connectGoogle() async {
        guard !connecting, accountID == nil, googleService.isConfigured, !isUITest else { return }
        let generation = connectionGeneration
        connecting = true
        connectionFailure = nil
        defer { if connectionGeneration == generation { connecting = false } }
        do {
            try await googleService.connect()
            guard connectionGeneration == generation else { return }
            accountID = googleService.accountID
            clearGoogleCopy()
            connecting = false
            if preferredSource != .google {
                preferredSource = .google
            } else {
                Task { await syncAndNotify(background: false) }
            }
        } catch GoogleHealthError.cancelled {
            // Ein geschlossener Anmeldedialog lässt sich erneut öffnen.
        } catch is CancellationError {
        } catch {
            guard connectionGeneration == generation else { return }
            connectionFailure = Self.message(for: error)
        }
    }

    func disconnectGoogle() {
        guard !isUITest else { return }
        do {
            try googleService.disconnect()
            connectionGeneration += 1
            connecting = false
            accountID = nil
            connectionFailure = nil
            clearGoogleCopy()
        } catch {
            syncNote = Self.message(for: error)
        }
    }

    func deleteLocalHealthCopy() {
        guard !isUITest else { return }
        clearGoogleCopy()
    }

    private func clearGoogleCopy() {
        invalidateRefresh()
        SyncStore.clear()
        lastUpdate = nil
        lastBackgroundSync = nil
        lastBackgroundAttempt = nil
        historyThrough = nil
        historyGaps = []
        storedHours = [:]
        syncNote = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "forma.google.lastBackgroundSync")
        defaults.removeObject(forKey: "forma.google.lastBackgroundAttempt")
        if activeSource == .google { longDays = [] }
    }

    private func invalidateRefresh() {
        generation += 1
        inFlight?.cancel()
        inFlight = nil
        attemptID = nil
        isLoading = false
    }

    var todayDataNotice: String? {
        if isSample { return nil }
        if let day = longDays.last, day.date == Date.now.startOfDay, SyncStore.hasData(day) { return nil }
        if isLoading { return "Lade deine Daten …" }
        switch google {
        case .notConfigured: return "Google Health ist noch nicht eingerichtet."
        case .disconnected: return "Verbinde Google Health im Profil."
        case .connecting: return "Google Health wird verbunden …"
        case .failed(let message): return message
        case .connected: return syncNote ?? "Google Health hat für heute noch keine Messungen geliefert."
        }
    }

    var isSample: Bool { activeSource == .sample }
    var today: DayMetrics { days.last ?? DayMetrics(date: .now.startOfDay) }
    var yesterday: DayMetrics? { days.count > 1 ? days[days.count - 2] : nil }
    var history: [DayMetrics] { Array(days.dropLast()) }

    var days: [DayMetrics] {
        let recent = Array(longDays.suffix(30))
        if !isSample, let last = recent.last, last.date != Date.now.startOfDay {
            return includingFormaWorkouts(SyncStore.normalized(recent, keepDays: 30))
        }
        if !isSample, recent.isEmpty, !formaWorkouts.isEmpty {
            return includingFormaWorkouts(SyncStore.normalized([], keepDays: 30))
        }
        return includingFormaWorkouts(recent)
    }

    func dashboardHistory(recent: [DayMetrics]) -> [DayMetrics] {
        guard let first = recent.first else { return [] }
        return includingFormaWorkouts(longDays.filter { $0.date < first.date }) + recent
    }

    private func includingFormaWorkouts(_ days: [DayMetrics]) -> [DayMetrics] {
        guard !isSample, !formaWorkouts.isEmpty else { return days }
        let workoutsByDay = Dictionary(grouping: formaWorkouts) { $0.start.startOfDay }
        var result = days
        for i in result.indices {
            for workout in workoutsByDay[result[i].date] ?? [] {
                let end = workout.start.addingTimeInterval(workout.duration)
                let overlaps = result[i].workouts.contains {
                    $0.start < end && workout.start < $0.start.addingTimeInterval($0.duration)
                }
                if !overlaps { result[i].workouts.append(workout) }
            }
        }
        return result
    }

    func setFormaWorkouts(_ workouts: [WorkoutSummary]) {
        if workouts != formaWorkouts { formaWorkouts = workouts }
    }

    var person: PersonInfo {
        if isSample { return SampleData.person() }
        _ = profileRevision
        let defaults = UserDefaults.standard
        let year = defaults.integer(forKey: "forma.birthYear")
        let sex = BiologicalSex(rawValue: defaults.string(forKey: "forma.sex") ?? "") ?? .unknown
        if (1901...Calendar.forma.component(.year, from: .now)).contains(year) {
            let birth = Calendar.forma.date(from: DateComponents(year: year, month: 7, day: 1))
            return PersonInfo(birthDate: birth, sex: sex, origin: .manual)
        }
        return PersonInfo(birthDate: nil, sex: sex, origin: .missing)
    }

    func profileChanged() { profileRevision += 1 }

    var hours: [HourlyMetrics] {
        isSample ? HourlyMetrics.samples(for: today) : cachedHours(for: .now)
    }

    func cachedHours(for date: Date) -> [HourlyMetrics] {
        guard !isSample else { return [] }
        let day = date.startOfDay
        return storedHours.values.filter { $0.start.startOfDay == day }.sorted { $0.start < $1.start }
    }

    func loadHours(for date: Date) async -> [HourlyMetrics] {
        guard activeSource == .google, accountID != nil else { return [] }
        let start = date.startOfDay
        let end = min(start.adding(days: 1), .now)
        let previous = cachedHours(for: date)
        if start == Date.now.startOfDay || previous.contains(where: { $0.heartRate != nil }) { return previous }
        let current = generation
        guard let pulses = try? await googleService.loadPulse(from: start, until: end, calendar: .forma),
              current == generation, !Task.isCancelled else { return current == generation ? previous : [] }
        for pulse in pulses {
            var hour = storedHours[pulse.start] ?? pulse
            hour.heartRate = pulse.heartRate
            hour.heartRateOrigin = pulse.heartRateOrigin
            storedHours[pulse.start] = hour
        }
        return cachedHours(for: date)
    }

    var hourlyEstimates: [HourlyEstimate] {
        HourlyEstimate.timeline(hours: hours, today: today, history: history)
    }

    struct Availability: Equatable {
        var recovery: Bool
        var sleep: Bool
        var strain: Bool
    }

    var availability: Availability {
        Availability(recovery: today.hrv != nil && baseline(\.hrv) != nil
                     || today.restingHR != nil && baseline(\.restingHR) != nil,
                     sleep: today.sleep != nil, strain: today.activeEnergy != nil || !today.workouts.isEmpty)
    }

    var scores: DayScores { ScoreEngine.scores(today: today, history: history) }
    var ringScores: DayScores { scores }

    var yesterdayScores: DayScores? {
        guard let yesterday, days.count > 2 else { return nil }
        return ScoreEngine.scores(today: yesterday, history: Array(days.dropLast(2)))
    }

    func scores(for index: Int) -> DayScores {
        ScoreEngine.scores(today: days[index], history: Array(days.prefix(index)))
    }

    func hasRecoveryBasis(at index: Int) -> Bool {
        let days = self.days
        guard days.indices.contains(index) else { return false }
        let day = days[index]
        let prior = Array(days.prefix(index))
        return day.hrv != nil && ScoreEngine.baseline(for: \.hrv, today: day, history: prior) != nil
            || day.restingHR != nil && ScoreEngine.baseline(for: \.restingHR, today: day, history: prior) != nil
    }

    func baseline(_ keyPath: KeyPath<DayMetrics, Double?>) -> ScoreEngine.Baseline? {
        ScoreEngine.baseline(for: keyPath, today: today, history: history)
    }

    enum RefreshResult: Equatable {
        case updated
        case partial(Set<MetricSeries>)
        case unchanged
        case superseded
        case sample

        var isFresh: Bool {
            switch self {
            case .updated, .partial: true
            default: false
            }
        }
    }

    func backgroundRefresh() async {
        await syncAndNotify(background: true)
    }

    @discardableResult
    func syncAndNotify(background: Bool) async -> RefreshResult {
        let current = generation
        let result = await refresh(background: background)
        guard current == generation, !Task.isCancelled, !isSample, !isUITest else { return result }
        if background, accountID != nil {
            lastBackgroundAttempt = .now
            UserDefaults.standard.set(lastBackgroundAttempt, forKey: "forma.google.lastBackgroundAttempt")
        }
        if result.isFresh {
            if background {
                lastBackgroundSync = .now
                UserDefaults.standard.set(lastBackgroundSync, forKey: "forma.google.lastBackgroundSync")
            }
            CoachNotifier.afterSync(self)
        }
        return result
    }

    @discardableResult
    func refresh() async -> RefreshResult {
        await refresh(background: false)
    }

    private func refresh(background: Bool) async -> RefreshResult {
        if let inFlight {
            let current = generation
            let result = await inFlight.value
            if result == .superseded, current == generation, !Task.isCancelled, self.inFlight == nil {
                return await refresh(background: background)
            }
            return result
        }
        if isSample { return .sample }
        guard googleService.isConfigured, !connecting else { return .unchanged }
        let id = UUID()
        let current = generation
        let task = Task { @MainActor in
            defer {
                if attemptID == id {
                    attemptID = nil
                    inFlight = nil
                    isLoading = false
                    hasLoaded = true
                }
            }
            return await performRefresh(generation: current, background: background)
        }
        attemptID = id
        inFlight = task
        isLoading = true
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performRefresh(generation: Int, background: Bool) async -> RefreshResult {
        do {
            try googleService.restore()
            guard let account = googleService.accountID else { return .unchanged }
            if accountID != account {
                accountID = account
                showPreferredSource()
            }
            let calendar = Calendar.forma
            let today = calendar.startOfDay(for: .now)
            let end = today.adding(days: 1)
            let recent = today.adding(days: -6)
            let oldest = today.adding(days: -179)
            if let updated = lastUpdate, updated.startOfDay < recent {
                historyThrough = nil
                historyGaps = []
            }
            historyGaps = historyGaps.filter { $0 > oldest }
            let summary = try await googleService.load(from: recent, until: end, calendar: calendar, includePulse: true)
            try checkRefresh(generation, today: today, calendar: calendar)
            let currentHistory = historyThrough ?? recent
            let initial = merge(summary, account: account, today: today, from: recent, until: end,
                                historyThrough: currentHistory, updatesCurrent: true)
            guard initial != .unchanged || summary.failed.isEmpty else { return initial }

            // Der Hintergrund holt nach der aktuellen Woche jeweils einen älteren Abschnitt nach.
            // Im Vordergrund kann der erste Import bis zu 180 Tage vervollständigen.
            var fetchedHistory = false
            while let upper = historyThrough, upper > oldest {
                let lower = max(oldest, upper.adding(days: -14))
                let older = try await googleService.load(from: lower, until: upper, calendar: calendar, includePulse: false)
                try checkRefresh(generation, today: today, calendar: calendar)
                if older.failed.count == MetricSeries.allCases.count { break }
                if !older.failed.isEmpty { historyGaps.insert(upper) }
                let result = merge(older, account: account, today: today, from: lower, until: upper,
                                   historyThrough: lower, updatesCurrent: false)
                fetchedHistory = true
                if background || result == .unchanged { break }
            }
            if !fetchedHistory, let upper = historyGaps.max() {
                let lower = max(oldest, upper.adding(days: -14))
                let retry = try await googleService.load(from: lower, until: upper, calendar: calendar, includePulse: false)
                try checkRefresh(generation, today: today, calendar: calendar)
                if retry.failed.isEmpty { historyGaps.remove(upper) }
                _ = merge(retry, account: account, today: today, from: lower, until: upper,
                          historyThrough: historyThrough, updatesCurrent: false)
            }
            return initial
        } catch is CancellationError {
            return .superseded
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return .superseded }
            if let problem = error as? GoogleHealthError,
               problem == .reauthorize || problem == .incompleteConsent || problem == .notLinked {
                try? googleService.clearCredentials()
                accountID = nil
                // Beim nächsten Verbinden wird die Kopie vor dem ersten neuen Import entfernt.
                longDays = []
                storedHours = [:]
                lastUpdate = nil
                connectionFailure = Self.message(for: error)
            } else {
                syncNote = Self.message(for: error)
            }
            return .unchanged
        }
    }

    private func checkRefresh(_ generation: Int, today: Date, calendar: Calendar) throws {
        try Task.checkCancellation()
        guard generation == self.generation, today == Date.now.startOfDay,
              calendar.timeZone == Calendar.forma.timeZone else { throw CancellationError() }
    }

    private func merge(_ imported: GoogleHealthService.Import, account: String, today: Date,
                       from: Date, until: Date, historyThrough: Date?, updatesCurrent: Bool) -> RefreshResult {
        var failed = imported.failed
        if failed.contains(.steps) { failed.insert(.activeEnergy) }
        var new = imported.days
        if let hours = imported.hours, !failed.contains(.steps), failed.contains(.activeEnergy) {
            let matching = hours.compactMap { hour -> HourlyMetrics? in
                guard let old = storedHours[hour.start], old.energyOrigin == hour.stepOrigin,
                      old.activeEnergy != nil else { return nil }
                return old
            }
            let byDay = Dictionary(grouping: matching) { $0.start.startOfDay }
            for index in new.indices {
                let hours = byDay[new[index].date] ?? []
                let energy = hours.compactMap(\.activeEnergy)
                new[index].activeEnergy = energy.isEmpty ? nil : energy.reduce(0, +)
                new[index].setOrigins(hours.compactMap(\.energyOrigin), for: .activeEnergy)
            }
        }
        var retained = failed
        if !failed.contains(.steps) { retained.remove(.activeEnergy) }
        // Ein leeres Ergebnis bei Teilfehlern soll lesbare alte Messungen nicht löschen.
        if !new.contains(where: SyncStore.hasData), !failed.isEmpty,
           longDays.contains(where: { $0.date >= from && $0.date < until && SyncStore.hasData($0) }) {
            syncNote = partialNotice(failed)
            return .unchanged
        }
        guard case .merged(let days) = SyncStore.merge(old: longDays, new: new, failed: retained, today: today) else {
            if updatesCurrent || !failed.isEmpty {
                syncNote = failed.isEmpty ? "Google Health hat gerade keine Messungen geliefert. Du siehst den letzten Stand."
                    : partialNotice(failed)
            }
            return .unchanged
        }
        mergeHours(imported, from: from, until: until, today: today, energyFailed: failed.contains(.activeEnergy))
        longDays = days
        self.historyThrough = historyThrough
        let hasMeasurement = new.contains(where: SyncStore.hasData)
        if hasMeasurement && (updatesCurrent || lastUpdate == nil) { lastUpdate = .now }
        let snapshot = SyncStore.Snapshot(days: days, updated: lastUpdate, source: DataSourceKind.google.rawValue,
                                          accountID: account, hours: Array(storedHours.values),
                                          historyThrough: historyThrough, historyGaps: historyGaps.sorted())
        if !SyncStore.save(snapshot) {
            syncNote = "Die lokale Kopie konnte nicht gespeichert werden. Health versucht es beim nächsten Abruf erneut."
        } else if !failed.isEmpty {
            syncNote = partialNotice(failed)
        } else if updatesCurrent {
            syncNote = nil
        }
        if updatesCurrent && !hasMeasurement { return .unchanged }
        return failed.isEmpty ? .updated : .partial(failed)
    }

    private func mergeHours(_ imported: GoogleHealthService.Import, from: Date, until: Date, today: Date,
                            energyFailed: Bool) {
        if let activity = imported.hours {
            let previous = storedHours
            for start in previous.keys where start >= from && start < until {
                guard var hour = storedHours[start] else { continue }
                hour.steps = nil
                hour.stepOrigin = nil
                hour.activeEnergy = nil
                hour.energyOrigin = nil
                storedHours[start] = hour.heartRate == nil ? nil : hour
            }
            for var hour in activity {
                let old = previous[hour.start]
                hour.heartRate = old?.heartRate
                hour.heartRateOrigin = old?.heartRateOrigin
                if energyFailed, old?.energyOrigin == hour.stepOrigin {
                    hour.activeEnergy = old?.activeEnergy
                    hour.energyOrigin = old?.energyOrigin
                }
                storedHours[hour.start] = hour
            }
        }
        if let pulses = imported.pulses {
            for start in Array(storedHours.keys) where start >= today {
                guard var hour = storedHours[start] else { continue }
                hour.heartRate = nil
                hour.heartRateOrigin = nil
                storedHours[start] = hour.steps == nil ? nil : hour
            }
            for pulse in pulses {
                var hour = storedHours[pulse.start] ?? pulse
                hour.heartRate = pulse.heartRate
                hour.heartRateOrigin = pulse.heartRateOrigin
                storedHours[pulse.start] = hour
            }
        }
        let cutoff = today.adding(days: -179)
        storedHours = storedHours.filter { $0.key >= cutoff && $0.key < today.adding(days: 1) }
    }

    private func partialNotice(_ failed: Set<MetricSeries>) -> String {
        let titles = failed.map(\.title).sorted().joined(separator: ", ")
        return "Ein Teil der Daten konnte gerade nicht geladen werden. Letzter Stand für \(titles)."
    }

    private static func message(for error: any Error) -> String {
        (error as? GoogleHealthError)?.errorDescription ?? "Google Health ist gerade nicht erreichbar. Versuch es später erneut."
    }
}
