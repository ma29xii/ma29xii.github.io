import Foundation
import SwiftUI

/// Vereint den Google-Import, den gesicherten Stand und die lokalen Krafttrainings.
@MainActor
@Observable
final class DataHub {
    private let googleService: any GoogleHealthImporting
    private let defaults: UserDefaults
    private let cacheURL: URL?
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let notify: (@MainActor (DataHub, CivilDay?, Int) async -> String?)?
    private let manageSystemState: Bool
    private let isUITest: Bool
    let achievementTracker: AchievementTracker
    private var accountID: String?
    private var connectionFailure: String?
    private var connecting = false
    private var loginInFlight = false
    private var revocationAttempt: UUID?
    private static let pendingDeletionKey = "forma.google.pendingLocalDeletion"
    private static let pendingDisconnectKey = "forma.google.pendingCredentialDeletion"
    private static let revocationKey = "forma.google.revocationStatus"

    var google: GoogleConnection {
        guard googleService.isConfigured else { return .notConfigured }
        if connecting { return .connecting }
        if let connectionFailure {
            return .failed([connectionFailure, localCopyNote, revocationStatus?.notice].compactMap { $0 }.joined(separator: " "))
        }
        return accountID == nil ? .disconnected : .connected(lastSync: lastUpdate)
    }

    private var storedDays: [DayMetrics] = []
    private var displayTimeZone: TimeZone?
    var longDays: [DayMetrics] {
        let calendar = calendar()
        if isSample {
            let today = calendar.startOfDay(for: now())
            if storedDays.last?.date == today, displayTimeZone == calendar.timeZone { return storedDays }
            return SampleData.days(endingAt: today, calendar: calendar)
        }
        guard !storedDays.isEmpty, displayTimeZone != calendar.timeZone else { return storedDays }
        return SyncStore.normalized(storedDays, today: calendar.startOfDay(for: now()), calendar: calendar)
    }
    private(set) var hasLoaded = false
    private(set) var activeSource: DataSourceKind = .google
    private(set) var isLoading = false
    private(set) var lastUpdate: Date?
    private(set) var lastBackgroundSync: Date?
    private(set) var lastBackgroundAttempt: Date?
    private var syncWarning: String?
    private var localCopyNote: String?
    private var widgetCopyNote: String?
    @ObservationIgnored private var widgetDeletionPending = false
    private(set) var revocationStatus: GoogleRevocation?
    private(set) var lastBackgroundIssue: String?
    private(set) var notificationIssue: String?
    var syncNote: String? {
        let notes = [localCopyNote, widgetCopyNote, revocationStatus?.notice, syncWarning, notificationIssue, lastBackgroundIssue]
            .compactMap { $0 }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }
    private(set) var formaWorkouts: [WorkoutSummary] = []
    private(set) var profileRevision = 0
    private var storedHours: [Date: HourlyMetrics] = [:]
    private var historyThrough: CivilDay?
    private var historyGaps: Set<CivilDay> = []
    private(set) var generation = 0
    private(set) var seriesFreshness: [MetricSeries: SeriesFreshness] = [:]
    private var latestRecentCheck: Date?
    private var recentFailed: Set<MetricSeries> = []
    private var recentPulseFailed = false
    private var connectionGeneration = 0
    private var inFlight: Task<RefreshResult, Never>?
    private var attemptID: UUID?
    private var waiters: Set<UUID> = []
    private var historyTask: Task<Void, Never>?
    @ObservationIgnored private var sampleRollover: Task<Void, Never>?

    var preferredSource: DataSourceKind {
        didSet {
            guard oldValue != preferredSource else { return }
            if !isUITest { defaults.set(preferredSource.rawValue, forKey: "forma.source") }
            invalidateRefresh()
            showPreferredSource(invalidateWidgetTimeline: true)
            Task { await syncAndNotify(background: false) }
        }
    }

    convenience init() {
        self.init(googleService: GoogleHealthService(), defaults: .standard, cacheURL: SyncStore.fileURL,
                  isUITest: ProcessInfo.processInfo.arguments.contains("-uitest"), manageSystemState: true,
                  notify: CoachNotifier.afterSync)
    }

    init(googleService: any GoogleHealthImporting, defaults: UserDefaults, cacheURL: URL?,
         now: @escaping () -> Date = { .now }, calendar: @escaping () -> Calendar = { .forma },
         isUITest: Bool = false, manageSystemState: Bool = false,
         notify: (@MainActor (DataHub, CivilDay?, Int) async -> String?)? = nil) {
        self.googleService = googleService
        self.defaults = defaults
        self.cacheURL = cacheURL
        self.now = now
        self.calendar = calendar
        self.isUITest = isUITest
        self.manageSystemState = manageSystemState
        self.notify = notify
        achievementTracker = AchievementTracker(defaults: defaults)
        preferredSource = isUITest ? .sample : Self.source(from: defaults.string(forKey: "forma.source"))
        if !isUITest {
            defaults.set(preferredSource.rawValue, forKey: "forma.source")
            if manageSystemState {
                CoachProviders.monitorConsent()
                defaults.removeObject(forKey: "forma.healthAuthorized")
                _ = Keychain.set(nil, for: "fitbit.tokens")
            }
            switch defaults.string(forKey: Self.revocationKey) {
            case "inProgress", "unconfirmed": revocationStatus = .unconfirmed
            default: break
            }
            if defaults.bool(forKey: Self.pendingDisconnectKey) { retryCredentialDeletion() }
            if defaults.bool(forKey: Self.pendingDeletionKey) { _ = deleteCache() }
            if !defaults.bool(forKey: Self.pendingDisconnectKey) { accountID = googleService.accountID }
            lastBackgroundSync = defaults.object(forKey: "forma.google.lastBackgroundSync") as? Date
            lastBackgroundAttempt = defaults.object(forKey: "forma.google.lastBackgroundAttempt") as? Date
            lastBackgroundIssue = defaults.string(forKey: "forma.google.lastBackgroundIssue")
        }
        showPreferredSource()
        if manageSystemState, !isUITest, isSample || accountID == nil {
            CoachNotifier.removeCoachNotifications(now: now())
        }
    }

    nonisolated static func source(from stored: String?) -> DataSourceKind {
        stored == DataSourceKind.sample.rawValue ? .sample : .google
    }

    private func showPreferredSource(invalidateWidgetTimeline: Bool = false) {
        defer { publishWidgets(invalidateTimeline: invalidateWidgetTimeline) }
        sampleRollover?.cancel()
        sampleRollover = nil
        activeSource = preferredSource
        syncWarning = nil
        resetSnapshot()
        if isSample {
            storedDays = []
            refreshSampleData()
            hasLoaded = true
        } else if !defaults.bool(forKey: Self.pendingDeletionKey),
                  let accountID, let cached = SyncStore.load(from: cacheURL),
                  cached.source == DataSourceKind.google.rawValue, cached.accountID == accountID {
            let calendar = calendar()
            var legacyCalendar = calendar
            if let zone = cached.dayTimeZone.flatMap(TimeZone.init(identifier:)) { legacyCalendar.timeZone = zone }
            storedDays = SyncStore.normalized(cached.days.map { $0.sanitized() }, today: calendar.startOfDay(for: now()),
                                              calendar: calendar, legacyCalendar: legacyCalendar)
            displayTimeZone = calendar.timeZone
            storedHours = Dictionary((cached.hours ?? []).map { ($0.start, $0) }, uniquingKeysWith: { _, newer in newer })
            historyThrough = cached.historyThroughDay ?? cached.historyThrough.map { CivilDay($0, in: legacyCalendar) }
            historyGaps = Set(cached.historyGapDays ?? (cached.historyGaps ?? []).map { CivilDay($0, in: legacyCalendar) })
            seriesFreshness = cached.series ?? [:]
            lastUpdate = cached.series == nil ? nil : cached.updated
            latestRecentCheck = seriesFreshness.values.map(\.checkedAt).max() ?? cached.updated
            recentFailed = cached.recentFailed ?? []
            recentPulseFailed = cached.recentPulseFailed ?? false
            if !recentFailed.isEmpty || recentPulseFailed {
                syncWarning = partialNotice(recentFailed, pulseFailed: recentPulseFailed)
            }
            if cached.dayTimeZone == nil || cached.days.contains(where: { $0.civilDay == nil }) {
                var migrated = cached
                migrated.days = storedDays
                migrated.updated = lastUpdate
                migrated.historyThroughDay = historyThrough
                migrated.historyGapDays = historyGaps.sorted()
                migrated.dayTimeZone = calendar.timeZone.identifier
                if !SyncStore.save(migrated, to: cacheURL) {
                    syncWarning = "Die lokale Kopie konnte nicht aktualisiert werden. Health versucht es beim nächsten Abruf erneut."
                }
            }
            hasLoaded = true
        } else {
            hasLoaded = false
        }
    }

    func connectGoogle() async {
        guard !loginInFlight, accountID == nil, googleService.isConfigured, !isUITest else { return }
        if defaults.bool(forKey: Self.pendingDisconnectKey) { retryCredentialDeletion() }
        guard !defaults.bool(forKey: Self.pendingDisconnectKey), deleteCache() else { return }
        let generation = connectionGeneration
        loginInFlight = true
        connecting = true
        connectionFailure = nil
        defer {
            loginInFlight = false
            if connectionGeneration == generation { connecting = false }
        }
        do {
            try await googleService.connect()
            guard connectionGeneration == generation else { return }
            accountID = googleService.accountID
            invalidateRefresh()
            revocationAttempt = nil
            setRevocationStatus(nil)
            localCopyNote = nil
            connecting = false
            if preferredSource != .google {
                preferredSource = .google
            } else {
                Task { await syncAndNotify(background: false) }
            }
        } catch GoogleHealthError.cancelled {
            // Ein geschlossener Anmeldedialog lässt sich erneut öffnen.
        } catch GoogleHealthError.loginRevocationUnconfirmed(let reason) {
            setRevocationStatus(.unconfirmed)
            if connectionGeneration == generation { connectionFailure = reason }
        } catch is CancellationError {
        } catch {
            guard connectionGeneration == generation else { return }
            connectionFailure = Self.message(for: error)
        }
    }

    func disconnectGoogle() {
        guard !isUITest else { return }
        let disconnectedAccount = accountID
        connectionGeneration += 1
        connecting = false
        accountID = nil
        connectionFailure = nil
        defaults.set(true, forKey: Self.pendingDisconnectKey)
        clearGoogleCopy(for: disconnectedAccount)
        retryCredentialDeletion()
    }

    private func retryCredentialDeletion() {
        do {
            let revocation = try googleService.disconnect()
            defaults.removeObject(forKey: Self.pendingDisconnectKey)
            connectionFailure = nil
            guard let revocation else { return }
            setRevocationStatus(.inProgress)
            let attempt = UUID()
            revocationAttempt = attempt
            Task {
                let status = await revocation.value
                guard revocationAttempt == attempt else { return }
                setRevocationStatus(status)
                revocationAttempt = nil
            }
        } catch {
            connectionFailure = Self.message(for: error)
        }
    }

    private func setRevocationStatus(_ status: GoogleRevocation?) {
        revocationStatus = status
        switch status {
        case .inProgress: defaults.set("inProgress", forKey: Self.revocationKey)
        case .unconfirmed: defaults.set("unconfirmed", forKey: Self.revocationKey)
        case .confirmed, nil: defaults.removeObject(forKey: Self.revocationKey)
        }
    }

    func deleteLocalHealthCopy() {
        guard !isUITest else { return }
        clearGoogleCopy(for: accountID)
    }

    private func clearGoogleCopy(for account: String?) {
        invalidateRefresh()
        if let account { achievementTracker.deleteHealth(scope: AchievementHealthScope(accountID: account)) }
        resetSnapshot()
        publishWidgets(invalidateTimeline: true)
        _ = deleteCache()
        syncWarning = nil
        notificationIssue = nil
        recordBackgroundIssue(nil)
        lastBackgroundSync = nil
        lastBackgroundAttempt = nil
        defaults.removeObject(forKey: "forma.google.lastBackgroundSync")
        defaults.removeObject(forKey: "forma.google.lastBackgroundAttempt")
    }

    @discardableResult
    private func deleteCache() -> Bool {
        defaults.set(true, forKey: Self.pendingDeletionKey)
        do {
            try SyncStore.clear(at: cacheURL)
            defaults.removeObject(forKey: Self.pendingDeletionKey)
            localCopyNote = "Die lokale Gesundheitskopie ist gelöscht."
            return true
        } catch {
            localCopyNote = "Die lokale Gesundheitskopie konnte nicht gelöscht werden. Versuche es im Profil erneut."
            return false
        }
    }

    private func resetSnapshot() {
        lastUpdate = nil
        latestRecentCheck = nil
        seriesFreshness = [:]
        recentFailed = []
        recentPulseFailed = false
        historyThrough = nil
        historyGaps = []
        storedHours = [:]
        if !isSample { storedDays = [] }
    }

    private func invalidateRefresh() {
        generation += 1
        inFlight?.cancel()
        inFlight = nil
        historyTask?.cancel()
        historyTask = nil
        attemptID = nil
        waiters = []
        isLoading = false
        if manageSystemState && !isUITest {
            CoachProviders.invalidateConversation()
            CoachNotifier.removeCoachNotifications(now: now())
        }
    }

    var todayDataNotice: String? {
        if isSample { return nil }
        if let warning = syncWarning ?? localCopyNote ?? revocationStatus?.notice { return warning }
        if let day = longDays.last, day.date == calendar().startOfDay(for: now()), SyncStore.hasData(day) { return nil }
        if isLoading { return "Lade deine Daten …" }
        switch google {
        case .notConfigured: return "Google Health ist noch nicht eingerichtet."
        case .disconnected: return "Verbinde Google Health im Profil."
        case .connecting: return "Google Health wird verbunden …"
        case .failed(let message): return message
        case .connected: return "Google Health hat für heute noch keine Messungen geliefert."
        }
    }

    var isSample: Bool { activeSource == .sample }

    /// Auch von der flüchtigen Trainingsvorschau als Aktualisierungsschlüssel verwendbar.
    var sampleDay: Date? {
        isSample ? calendar().startOfDay(for: now()) : nil
    }

    private func refreshSampleData() {
        guard isSample else { return }
        let calendar = calendar()
        let current = now()
        let today = calendar.startOfDay(for: current)
        if storedDays.last?.date != today || calendar.timeZone != displayTimeZone {
            storedDays = SampleData.days(endingAt: today, calendar: calendar)
            displayTimeZone = calendar.timeZone
        }
        sampleRollover?.cancel()
        guard manageSystemState, let tomorrow = calendar.startOfDay(offsetBy: 1, from: today) else { return }
        sampleRollover = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0.1, tomorrow.timeIntervalSince(current)))) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.refreshSampleData()
        }
    }

    /// Erfolge gelten je Google-Konto; mit Beispieldaten werden keine gesammelt.
    var achievementHealthScope: AchievementHealthScope? {
        guard !isSample, !storedDays.isEmpty, let accountID else { return nil }
        return AchievementHealthScope(accountID: accountID)
    }
    var today: DayMetrics { days.last ?? DayMetrics(date: calendar().startOfDay(for: now())) }
    var yesterday: DayMetrics? { days.count > 1 ? days[days.count - 2] : nil }
    var history: [DayMetrics] { Array(days.dropLast()) }

    var stepGoalToday: Int? {
        let recent = days
        guard let day = recent.last else { return nil }
        let snapshot = DashboardDay(day: day, history: Array(recent.dropLast()))
        return StepGoal.target(on: day.date, history: snapshot.history, recovery: snapshot.recovery,
                               sleepScore: snapshot.sleepScore, sleepDebt: ScoreEngine.sleepDebt(history: snapshot.history),
                               strainTarget: snapshot.recovery.map { ScoreEngine.target(recovery: $0) }, calendar: calendar())
    }

    var days: [DayMetrics] {
        let recent = Array(longDays.suffix(30))
        let calendar = calendar()
        let today = calendar.startOfDay(for: now())
        if !isSample, let last = recent.last, last.date != today {
            return includingFormaWorkouts(SyncStore.normalized(recent, today: today, keepDays: 30, calendar: calendar))
        }
        if !isSample, recent.isEmpty, !formaWorkouts.isEmpty {
            return includingFormaWorkouts(SyncStore.normalized([], today: today, keepDays: 30, calendar: calendar))
        }
        return includingFormaWorkouts(recent)
    }

    func dashboardHistory(recent: [DayMetrics]) -> [DayMetrics] {
        guard let first = recent.first else { return [] }
        return includingFormaWorkouts(longDays.filter { $0.date < first.date }) + recent
    }

    private func includingFormaWorkouts(_ days: [DayMetrics]) -> [DayMetrics] {
        guard !isSample, !formaWorkouts.isEmpty else { return days }
        let calendar = calendar()
        let workoutsByDay = Dictionary(grouping: formaWorkouts) { calendar.startOfDay(for: $0.start) }
        var result = days
        for i in result.indices {
            for workout in workoutsByDay[result[i].date] ?? [] {
                if !result[i].workouts.contains(where: { workout.isDuplicate(of: $0) }) {
                    result[i].workouts.append(workout)
                }
            }
        }
        return result
    }

    func setFormaWorkouts(_ workouts: [WorkoutSummary]) {
        guard workouts != formaWorkouts else { return }
        formaWorkouts = workouts
        publishWidgets()
    }

    private func publishWidgets(invalidateTimeline: Bool = false) {
        guard manageSystemState, !isUITest else { return }
        let calendar = calendar()
        let currentTime = now()
        let today = CivilDay(currentTime, in: calendar)
        // Bei Teilabrufen kann ein Teil des sichtbaren Stands älter sein.
        let checkedAt = seriesFreshness.values
            .filter { $0.latestMeasurementDay == today && calendar.isDate($0.checkedAt, inSameDayAs: currentTime) }
            .map(\.checkedAt).min()
        var snapshot: WidgetSnapshot?
        if !isSample, accountID != nil, let checkedAt {
            let recent = days
            if let day = recent.last {
                let dashboard = DashboardDay(day: day, history: dashboardHistory(recent: recent))
                snapshot = WidgetBridge.snapshot(for: dashboard, checkedAt: checkedAt, calendar: calendar)
            }
        }
        updateWidgetCopy(snapshot, invalidateTimeline: invalidateTimeline)
    }

    private func updateWidgetCopy(_ snapshot: WidgetSnapshot?, invalidateTimeline: Bool = false) {
        let saved = WidgetBridge.publish(snapshot, invalidateTimeline: invalidateTimeline)
        widgetDeletionPending = !saved && (snapshot == nil || widgetDeletionPending)
        widgetCopyNote = saved ? nil : (snapshot == nil
            ? "Die Widget-Kopie konnte nicht gelöscht werden. Health versucht es erneut."
            : "Das Widget konnte nicht aktualisiert werden.")
    }

    var person: PersonInfo {
        if isSample { return SampleData.person(at: now(), calendar: calendar()) }
        _ = profileRevision
        let year = defaults.integer(forKey: "forma.birthYear")
        let sex = BiologicalSex(rawValue: defaults.string(forKey: "forma.sex") ?? "") ?? .unknown
        if (1901...Calendar.forma.component(.year, from: .now)).contains(year) {
            return PersonInfo(birthDate: nil, sex: sex, origin: .manual, birthYear: year)
        }
        return PersonInfo(birthDate: nil, sex: sex, origin: .missing)
    }

    func profileChanged() {
        profileRevision += 1
        guard manageSystemState, !isUITest else { return }
        let current = generation
        Task {
            let issue = await CoachNotifier.reconcileBedtime(self, generation: current)
            if generation == current { notificationIssue = issue }
        }
    }

    func canScheduleCoach(_ generation: Int) -> Bool {
        generation == self.generation && accountID != nil && activeSource == .google && !Task.isCancelled
    }

    var bedtimeBasisIsConfirmedMissing: Bool {
        let calendar = calendar()
        guard let latestRecentCheck, calendar.isDate(latestRecentCheck, inSameDayAs: now()) else { return false }
        let strainMissing = !availability.strain && recentFailed.isDisjoint(with: [.activeEnergy, .workouts])
        let sleepHistoryMissing = !ScoreEngine.hasSleepHistory(history) && !recentFailed.contains(.sleep)
        return strainMissing || sleepHistoryMissing
    }

    func reportNotificationIssue(_ issue: String?, generation: Int) {
        if generation == self.generation { notificationIssue = issue }
    }

    var hours: [HourlyMetrics] {
        isSample ? HourlyMetrics.samples(for: today) : cachedHours(for: now())
    }

    func cachedHours(for date: Date) -> [HourlyMetrics] {
        guard !isSample else { return [] }
        let calendar = calendar()
        let day = calendar.startOfDay(for: date)
        return storedHours.values.filter { calendar.startOfDay(for: $0.start) == day }.sorted { $0.start < $1.start }
    }

    func loadHours(for date: Date) async -> [HourlyMetrics] {
        guard activeSource == .google, accountID != nil else { return [] }
        let calendar = calendar()
        let start = calendar.startOfDay(for: date)
        let end = min(calendar.startOfDay(offsetBy: 1, from: start) ?? start, now())
        let previous = cachedHours(for: date)
        if start == calendar.startOfDay(for: now()) || previous.contains(where: { $0.heartRate != nil }) { return previous }
        let current = generation
        guard let pulses = try? await googleService.loadPulse(from: start, until: end, calendar: calendar),
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

    var measuredSleepNeed: TimeInterval? {
        CoachEngine.measuredSleepNeed(scores, strainAvailable: availability.strain, history: history)
    }
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
        case storageFailed
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

    struct SeriesFreshness: Equatable, Codable, Sendable {
        let checkedAt: Date
        let latestMeasurementDay: CivilDay?
    }

    func backgroundRefresh() async {
        await syncAndNotify(background: true)
    }

    @discardableResult
    func refresh() async -> RefreshResult {
        await syncAndNotify(background: false)
    }

    @discardableResult
    func syncAndNotify(background: Bool) async -> RefreshResult {
        if widgetDeletionPending { updateWidgetCopy(nil) }
        if isSample {
            refreshSampleData()
            return .sample
        }
        guard !Task.isCancelled, googleService.isConfigured, !loginInFlight,
              !defaults.bool(forKey: Self.pendingDisconnectKey),
              !defaults.bool(forKey: Self.pendingDeletionKey) else { return .unchanged }
        let current = generation
        if background {
            lastBackgroundAttempt = now()
            defaults.set(lastBackgroundAttempt, forKey: "forma.google.lastBackgroundAttempt")
        }

        let waiter = UUID()
        let task: Task<RefreshResult, Never>
        if let inFlight, !inFlight.isCancelled {
            task = inFlight
        } else {
            task = startRecentRefresh(generation: current)
        }
        waiters.insert(waiter)
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.releaseWaiter(waiter) }
        }
        releaseWaiter(waiter)
        guard generation == current else { return .superseded }
        if Task.isCancelled {
            if background { recordBackgroundIssue("Der letzte Hintergrundabruf wurde unterbrochen.") }
            return .superseded
        }
        if background {
            switch result {
            case .updated, .partial:
                let today = CivilDay(now(), in: calendar())
                if seriesFreshness.values.contains(where: { $0.checkedAt == latestRecentCheck && $0.latestMeasurementDay == today }) {
                    lastBackgroundSync = latestRecentCheck
                    defaults.set(lastBackgroundSync, forKey: "forma.google.lastBackgroundSync")
                    recordBackgroundIssue(nil)
                } else {
                    recordBackgroundIssue("Der letzte Hintergrundabruf hat keine Messungen für heute bestätigt.")
                }
            case .storageFailed, .unchanged:
                recordBackgroundIssue("Der letzte Hintergrundabruf konnte keine aktuellen Daten sichern.")
            case .superseded:
                recordBackgroundIssue("Der letzte Hintergrundabruf wurde unterbrochen.")
            case .sample: break
            }
        } else if result.isFresh || (result == .unchanged && syncWarning == nil) {
            startHistoryIfNeeded(generation: current)
        }
        return result
    }

    private func recordBackgroundIssue(_ issue: String?) {
        lastBackgroundIssue = issue
        defaults.set(issue, forKey: "forma.google.lastBackgroundIssue")
    }

    private func releaseWaiter(_ id: UUID) {
        guard waiters.remove(id) != nil, waiters.isEmpty else { return }
        inFlight?.cancel()
    }

    private func startRecentRefresh(generation: Int) -> Task<RefreshResult, Never> {
        let id = UUID()
        let task = Task { @MainActor in
            defer {
                if attemptID == id {
                    attemptID = nil
                    inFlight = nil
                    waiters = []
                    isLoading = false
                    hasLoaded = true
                }
            }
            return await performRecentRefresh(generation: generation)
        }
        attemptID = id
        inFlight = task
        isLoading = true
        return task
    }

    private enum RefreshWindowChange: Error { case localDayChanged }

    private func performRecentRefresh(generation: Int, canRetryWindow: Bool = true) async -> RefreshResult {
        do {
            try googleService.restore()
            guard let account = googleService.accountID else { return .unchanged }
            if accountID != account {
                if manageSystemState {
                    CoachProviders.invalidateConversation()
                    CoachNotifier.removeCoachNotifications(now: now())
                }
                accountID = account
                showPreferredSource(invalidateWidgetTimeline: true)
            }
            let calendar = calendar()
            let today = calendar.startOfDay(for: now())
            guard let end = calendar.startOfDay(offsetBy: 1, from: today),
                  let recent = calendar.startOfDay(offsetBy: -6, from: today),
                  let oldest = calendar.startOfDay(offsetBy: -179, from: today) else { return .unchanged }
            let recentDay = CivilDay(recent, in: calendar)
            let oldestDay = CivilDay(oldest, in: calendar)
            let summary = try await googleService.load(from: recent, until: end, calendar: calendar, includePulse: true)
            try checkRefresh(generation, account: account, today: today, calendar: calendar)
            let lastCheckIsOld = latestRecentCheck.map { CivilDay($0, in: calendar) < recentDay } ?? false
            let through = lastCheckIsOld ? recentDay : min(historyThrough ?? recentDay, recentDay)
            let gaps: Set<CivilDay> = lastCheckIsOld ? [] : historyGaps.filter { $0 > oldestDay }
            let result = merge(summary, account: account, today: today, calendar: calendar, from: recent, until: end,
                               through: through, gaps: gaps, updatesCurrent: true)

            if result.isFresh, let notify {
                let todayKey = CivilDay(today, in: calendar)
                let confirmedSleep = !summary.failed.contains(.sleep) && summary.days.contains {
                    ($0.civilDay ?? CivilDay($0.date, in: calendar)) == todayKey && $0.sanitized().hasMeasurement(for: .sleep)
                }
                let issue = await notify(self, confirmedSleep ? todayKey : nil, generation)
                try Task.checkCancellation()
                guard generation == self.generation else { return .superseded }
                notificationIssue = issue
            }
            return result
        } catch RefreshWindowChange.localDayChanged {
            guard canRetryWindow else { return .superseded }
            return await performRecentRefresh(generation: generation, canRetryWindow: false)
        } catch is CancellationError {
            return .superseded
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return .superseded }
            handleImportError(error)
            return .unchanged
        }
    }

    private func startHistoryIfNeeded(generation: Int) {
        guard historyTask == nil, let accountID, let historyThrough else { return }
        let calendar = calendar()
        let today = calendar.startOfDay(for: now())
        guard let oldest = calendar.startOfDay(offsetBy: -179, from: today),
              historyThrough > CivilDay(oldest, in: calendar) || !historyGaps.isEmpty else { return }
        historyTask = Task {
            defer { if self.generation == generation { historyTask = nil } }
            do {
                try await fillHistory(account: accountID, generation: generation, today: today, oldest: oldest,
                                      calendar: calendar)
            } catch is CancellationError {
            } catch RefreshWindowChange.localDayChanged {
            } catch {
                if self.generation == generation { handleImportError(error) }
            }
        }
    }

    private func fillHistory(account: String, generation: Int, today: Date, oldest: Date,
                             calendar: Calendar) async throws {
        while let upper = historyThrough?.start(in: calendar), upper > oldest {
            guard let start = calendar.startOfDay(offsetBy: -14, from: upper) else { return }
            let lower = max(oldest, start)
            let imported = try await googleService.load(from: lower, until: upper, calendar: calendar, includePulse: false)
            try checkRefresh(generation, account: account, today: today, calendar: calendar)
            var gaps = historyGaps
            if !imported.failed.isEmpty { gaps.insert(CivilDay(upper, in: calendar)) }
            let result = merge(imported, account: account, today: today, calendar: calendar, from: lower, until: upper,
                               through: CivilDay(lower, in: calendar), gaps: gaps, updatesCurrent: false)
            guard result.isFresh else { return }
        }
        guard let gap = historyGaps.max(), let upper = gap.start(in: calendar), upper > oldest,
              let start = calendar.startOfDay(offsetBy: -14, from: upper) else { return }
        let lower = max(oldest, start)
        let imported = try await googleService.load(from: lower, until: upper, calendar: calendar, includePulse: false)
        try checkRefresh(generation, account: account, today: today, calendar: calendar)
        var gaps = historyGaps
        if imported.failed.isEmpty { gaps.remove(gap) }
        _ = merge(imported, account: account, today: today, calendar: calendar, from: lower, until: upper,
                  through: historyThrough, gaps: gaps, updatesCurrent: false)
    }

    private func handleImportError(_ error: any Error) {
        if let problem = error as? GoogleHealthError,
           problem == .reauthorize || problem == .incompleteConsent || problem == .notLinked {
            disconnectGoogle()
            let details = [Self.message(for: error), connectionFailure].compactMap { $0 }
            connectionFailure = details.joined(separator: " ")
        } else {
            syncWarning = Self.message(for: error)
        }
    }

    private func checkRefresh(_ generation: Int, account: String, today: Date, calendar: Calendar) throws {
        try Task.checkCancellation()
        guard generation == self.generation, account == accountID else { throw CancellationError() }
        guard today == calendar.startOfDay(for: now()), calendar.timeZone == self.calendar().timeZone else {
            throw RefreshWindowChange.localDayChanged
        }
    }

    private func merge(_ imported: GoogleHealthService.Import, account: String, today: Date, calendar: Calendar,
                       from: Date, until: Date, through: CivilDay?, gaps: Set<CivilDay>,
                       updatesCurrent: Bool) -> RefreshResult {
        var failed = imported.failed
        if failed.contains(.steps), imported.unpairedEnergy == nil { failed.insert(.activeEnergy) }
        var retained = failed
        if !failed.contains(.steps) { retained.remove(.activeEnergy) }
        let current = storedDays
        let energyHours = imported.unpairedEnergy.map {
            GoogleHealthMerge.hours(steps: [], energy: $0, from: from, until: min(until, now()), calendar: calendar,
                                    cachedStepOrigins: storedHours.compactMapValues(\.stepOrigin))
        }
        let hours = mergedHours(imported, from: from, until: until, today: today, calendar: calendar,
                                energyHours: energyHours, energyFailed: failed.contains(.activeEnergy))
        var new = imported.days
        let confirmed = Set(MetricSeries.allCases).subtracting(failed)
        if energyHours != nil || (!failed.contains(.steps) && failed.contains(.activeEnergy) && imported.hours != nil) {
            let byDay = Dictionary(grouping: hours.values.filter { $0.activeEnergy != nil }) {
                calendar.startOfDay(for: $0.start)
            }
            for index in new.indices {
                let activity = byDay[new[index].date] ?? []
                new[index].activeEnergy = activity.isEmpty ? nil : activity.compactMap(\.activeEnergy).reduce(0, +)
                new[index].setOrigins(activity.compactMap(\.energyOrigin), for: .activeEnergy)
            }
        }
        new = new.map { $0.sanitized() }
        let confirmedDays = new.filter { day in confirmed.contains(where: { day.hasMeasurement(for: $0) }) }
        let pulseFailed = updatesCurrent && imported.pulses == nil
        if confirmed.isEmpty && imported.pulses == nil {
            if updatesCurrent { syncWarning = partialNotice(failed, pulseFailed: pulseFailed) }
            return .unchanged
        }
        let days: [DayMetrics]
        if confirmed.isEmpty {
            // Tagesreihen fehlgeschlagen. Der unabhängige Pulsabruf kann trotzdem erfolgreich sein.
            days = SyncStore.normalized(current, today: today, calendar: calendar)
        } else if case .merged(let values) = SyncStore.merge(old: current, new: new, failed: retained,
                                                            confirmedEmpty: true, today: today, calendar: calendar) {
            days = values
        } else {
            return .unchanged
        }
        let checkTime = now()
        let todayKey = CivilDay(today, in: calendar)
        let hasCurrentMeasurement = confirmedDays.contains { ($0.civilDay ?? CivilDay($0.date, in: calendar)) == todayKey }
        let fullyCurrent = updatesCurrent && hasCurrentMeasurement && failed.isEmpty && !pulseFailed
        let updated = fullyCurrent ? checkTime : lastUpdate
        var freshness = seriesFreshness
        if updatesCurrent {
            for series in confirmed {
                let latest = new.filter { $0.hasMeasurement(for: series) }
                    .map { $0.civilDay ?? CivilDay($0.date, in: calendar) }.max()
                freshness[series] = SeriesFreshness(checkedAt: checkTime, latestMeasurementDay: latest)
            }
        }
        let snapshot = SyncStore.Snapshot(days: days, updated: updated, source: DataSourceKind.google.rawValue,
                                          accountID: account, hours: Array(hours.values),
                                          historyThroughDay: through, historyGapDays: gaps.sorted(),
                                          dayTimeZone: calendar.timeZone.identifier, series: freshness,
                                          recentFailed: updatesCurrent ? failed : recentFailed,
                                          recentPulseFailed: updatesCurrent ? pulseFailed : recentPulseFailed)
        guard SyncStore.save(snapshot, to: cacheURL) else {
            syncWarning = "Die lokale Kopie konnte nicht gespeichert werden. Du siehst den letzten gespeicherten Stand."
            return .storageFailed
        }
        // Auch ein Rückimport kann die fehlende Vergleichsbasis für Today liefern.
        defer { publishWidgets() }

        storedDays = days
        displayTimeZone = calendar.timeZone
        storedHours = hours
        historyThrough = through
        historyGaps = gaps
        seriesFreshness = freshness
        lastUpdate = updated
        localCopyNote = nil
        if updatesCurrent {
            latestRecentCheck = checkTime
            recentFailed = failed
            recentPulseFailed = pulseFailed
            syncWarning = failed.isEmpty && !pulseFailed ? nil : partialNotice(failed, pulseFailed: pulseFailed)
        }
        return failed.isEmpty && !pulseFailed ? .updated : .partial(failed)
    }

    private func mergedHours(_ imported: GoogleHealthService.Import, from: Date, until: Date, today: Date,
                             calendar: Calendar, energyHours: [HourlyMetrics]?, energyFailed: Bool) -> [Date: HourlyMetrics] {
        var result = storedHours
        if let activity = imported.hours ?? energyHours {
            let byStart = Dictionary(activity.map { ($0.start, $0) }, uniquingKeysWith: { _, latest in latest })
            let previous = storedHours.keys.filter { $0 >= from && $0 < until }
            for start in Set(previous).union(byStart.keys) {
                guard var hour = byStart[start] ?? storedHours[start] else { continue }
                let old = storedHours[start]
                hour.steps = imported.hours == nil ? old?.steps : byStart[start]?.steps
                hour.stepOrigin = imported.hours == nil ? old?.stepOrigin : byStart[start]?.stepOrigin
                hour.activeEnergy = byStart[start]?.activeEnergy
                hour.energyOrigin = byStart[start]?.energyOrigin
                hour.heartRate = old?.heartRate
                hour.heartRateOrigin = old?.heartRateOrigin
                if energyFailed, hour.stepOrigin == nil || old?.energyOrigin == hour.stepOrigin {
                    hour.activeEnergy = old?.activeEnergy
                    hour.energyOrigin = old?.energyOrigin
                }
                result[start] = hour.hasMeasurement ? hour : nil
            }
        }
        if let pulses = imported.pulses {
            for start in Array(result.keys) where start >= today {
                guard var hour = result[start] else { continue }
                hour.heartRate = nil
                hour.heartRateOrigin = nil
                result[start] = hour.hasMeasurement ? hour : nil
            }
            for pulse in pulses {
                var hour = result[pulse.start] ?? pulse
                hour.heartRate = pulse.heartRate
                hour.heartRateOrigin = pulse.heartRateOrigin
                result[pulse.start] = hour
            }
        }
        let cutoff = calendar.startOfDay(offsetBy: -179, from: today) ?? .distantPast
        let limit = calendar.startOfDay(offsetBy: 1, from: today) ?? .distantFuture
        return result.filter { $0.key >= cutoff && $0.key < limit }
    }

    private func partialNotice(_ failed: Set<MetricSeries>, pulseFailed: Bool) -> String {
        let titles = (failed.map(\.title) + (pulseFailed ? ["Tagespuls"] : [])).sorted().joined(separator: ", ")
        return "Ein Teil der Daten konnte gerade nicht geladen werden. Letzter Stand für \(titles)."
    }

    private static func message(for error: any Error) -> String {
        (error as? GoogleHealthError)?.errorDescription ?? "Google Health ist gerade nicht erreichbar. Versuch es später erneut."
    }
}
