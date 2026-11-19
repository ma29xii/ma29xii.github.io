import Foundation
import XCTest
@testable import Forma

final class Fix03Tests: XCTestCase {
    private let watch = GoogleMetricOrigin(family: .appleWatch, device: "Watch")

    func testEnergyOnlyHourSurvivesWithoutInventingStepsOrStress() throws {
        let day = Date.now.startOfDay
        let hour = try XCTUnwrap(GoogleHealthMerge.hours(
            steps: [], energy: [.amount(120, start: day, end: day.addingTimeInterval(3600), source: watch)],
            pulse: [.pulse(145, time: day.addingTimeInterval(60), source: watch)],
            from: day, until: day.addingTimeInterval(3600), calendar: .forma
        ).first)
        XCTAssertNil(hour.steps)
        XCTAssertEqual(hour.activeEnergy, 120)
        XCTAssertEqual(hour.heartRate, 145)
        let estimate = try XCTUnwrap(HourlyEstimate.timeline(
            hours: [hour], today: DayMetrics(date: day), history: []
        ).first)
        XCTAssertNotNil(estimate.strain)
        XCTAssertNil(estimate.stress)
        XCTAssertNil(estimate.energy)
    }

    func testConflictingSleepPhasesRetainDurationWithoutDoubleCounting() throws {
        let start = Date.now.startOfDay
        let end = start.addingTimeInterval(3600)
        let night = try XCTUnwrap(DayMetrics(date: start, sleep: .init(start: start, end: end, segments: [
            .init(stage: .deep, start: start, end: start.addingTimeInterval(2700)),
            .init(stage: .rem, start: start.addingTimeInterval(900), end: end)
        ])).sanitized().sleep)
        XCTAssertEqual(night.asleep, 3600)
        XCTAssertEqual(night.total(.deep), 900)
        XCTAssertEqual(night.total(.rem), 900)
        XCTAssertEqual(night.total(.unspecified), 1800)
    }

    func testFirstNightHasDurationWithoutPersonalNeedOrScore() {
        let day = Date.now.startOfDay
        let night = SleepNight(start: day.addingTimeInterval(-3600), end: day.addingTimeInterval(7 * 3600),
                               segments: [], reportedAsleep: 8 * 3600)
        let snapshot = DashboardDay(day: DayMetrics(date: day, sleep: night), history: [])
        XCTAssertEqual(snapshot.day.sleep?.asleep, 8 * 3600)
        XCTAssertNil(snapshot.sleepNeed)
        XCTAssertNil(snapshot.sleepScore)
    }

    @MainActor
    func testPullToRefreshConfirmsSleepButPartialImportKeepsOldSleepWithoutANewReport() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        fixture.google.steps = 100
        fixture.google.sleep = true
        let hub = fixture.makeHub()

        let first = await hub.refresh()
        XCTAssertEqual(first, .updated)
        let savedDate = try XCTUnwrap(hub.lastUpdate)
        XCTAssertEqual(fixture.confirmedSleep, [CivilDay(fixture.now, in: fixture.calendar)])
        let sleepCheck = hub.seriesFreshness[.sleep]

        fixture.now = fixture.now.addingTimeInterval(600)
        fixture.google.steps = 200
        fixture.google.sleep = false
        fixture.google.failed = [.sleep]
        let partial = await hub.syncAndNotify(background: true)

        XCTAssertEqual(partial, .partial([.sleep]))
        XCTAssertEqual(hub.today.steps, 200)
        XCTAssertEqual(hub.today.sleep?.asleep, 7 * 3600)
        XCTAssertEqual(hub.lastUpdate, savedDate)
        XCTAssertEqual(hub.seriesFreshness[.sleep], sleepCheck)
        XCTAssertEqual(hub.seriesFreshness[.steps]?.checkedAt, fixture.now)
        XCTAssertEqual(fixture.confirmedSleep.count, 2)
        XCTAssertNil(fixture.confirmedSleep.last ?? nil)
        XCTAssertTrue(hub.todayDataNotice?.contains("Schlaf") == true)
        let reopened = fixture.makeHub()
        XCTAssertEqual(reopened.today.steps, 200)
        XCTAssertTrue(reopened.todayDataNotice?.contains("Schlaf") == true)
    }

    @MainActor
    func testStorageFailureLeavesDayAndCoachUnpublished() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.cache, withIntermediateDirectories: false)
        fixture.google.steps = 200
        fixture.google.sleep = true
        fixture.google.failed = [.vo2max]
        let hub = fixture.makeHub()

        let result = await hub.syncAndNotify(background: true)
        XCTAssertEqual(result, .storageFailed)
        XCTAssertNil(hub.today.steps)
        XCTAssertNil(hub.lastUpdate)
        XCTAssertNil(hub.lastBackgroundSync)
        XCTAssertTrue(hub.seriesFreshness.isEmpty)
        XCTAssertTrue(fixture.confirmedSleep.isEmpty)
        XCTAssertTrue(hub.todayDataNotice?.contains("nicht gespeichert") == true)
    }

    @MainActor
    func testTravelAndPartialImportKeepTheSameCivilDayAndPhysicalHour() async throws {
        let fixture = try HubFixture(zone: "Europe/Berlin")
        defer { fixture.cleanup() }
        fixture.google.sleep = true
        fixture.google.steps = 100
        fixture.google.activityHour = GoogleHealthTime.parse("2026-06-11T03:30:00Z")
        let hub = fixture.makeHub()
        let first = await hub.syncAndNotify(background: true)
        XCTAssertEqual(first, .updated)
        let originalSleep = try XCTUnwrap(hub.today.sleep)
        let originalHour = try XCTUnwrap(hub.hours.first?.start)

        fixture.calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let reopened = fixture.makeHub()
        XCTAssertEqual(reopened.today.sleep?.end, originalSleep.end)
        XCTAssertEqual(reopened.today.civilDay, CivilDay(fixture.now, in: fixture.calendar))
        XCTAssertEqual(reopened.yesterday.flatMap { reopened.cachedHours(for: $0.date).first?.start }, originalHour)
        fixture.google.activityHour = nil
        fixture.google.sleep = false
        fixture.google.failed = [.sleep]
        fixture.google.steps = 300
        let partial = await reopened.syncAndNotify(background: true)
        XCTAssertEqual(partial, .partial([.sleep]))
        XCTAssertEqual(reopened.today.sleep?.end, originalSleep.end)
        XCTAssertEqual(reopened.today.steps, 300)
    }

    @MainActor
    func testDisconnectionDuringImportRemovesCacheAndIgnoresLateDataAfterRestart() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        fixture.google.steps = 100
        let hub = fixture.makeHub()
        _ = await hub.syncAndNotify(background: true)
        XCTAssertNotNil(SyncStore.load(from: fixture.cache))

        let stream = AsyncStream<Void>.makeStream()
        fixture.google.beforeRecentResponse = {
            await withCheckedContinuation { continuation in
                fixture.google.resumeResponse = continuation
                stream.continuation.yield(())
                stream.continuation.finish()
            }
        }
        fixture.google.steps = 200
        let task = Task { await hub.syncAndNotify(background: true) }
        var started = stream.stream.makeAsyncIterator()
        _ = await started.next()
        hub.disconnectGoogle()
        fixture.google.resumeResponse?.resume()
        fixture.google.resumeResponse = nil
        fixture.google.beforeRecentResponse = nil
        let result = await task.value

        XCTAssertEqual(result, .superseded)
        XCTAssertNil(hub.today.steps)
        XCTAssertNil(SyncStore.load(from: fixture.cache))
        let reopened = fixture.makeHub()
        XCTAssertEqual(reopened.google, .disconnected)
        XCTAssertNil(reopened.today.steps)
    }

    @MainActor
    func testCancellingFirstRefreshCallerDoesNotCancelTheOtherOrScheduleTwice() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        fixture.google.steps = 123
        fixture.google.sleep = true
        let stream = AsyncStream<Void>.makeStream()
        fixture.google.beforeRecentResponse = {
            await withCheckedContinuation { continuation in
                fixture.google.resumeResponse = continuation
                stream.continuation.yield(())
                stream.continuation.finish()
            }
        }
        let hub = fixture.makeHub()
        let first = Task { await hub.refresh() }
        var started = stream.stream.makeAsyncIterator()
        _ = await started.next()
        let second = Task { await hub.syncAndNotify(background: true) }
        while hub.lastBackgroundAttempt == nil { await Task.yield() }
        first.cancel()
        fixture.google.resumeResponse?.resume()
        fixture.google.resumeResponse = nil
        fixture.google.beforeRecentResponse = nil
        let stopped = await first.value
        let completed = await second.value
        XCTAssertEqual(stopped, .superseded)
        XCTAssertEqual(completed, .updated)
        XCTAssertEqual(hub.today.steps, 123)
        XCTAssertEqual(fixture.confirmedSleep.count, 1)
    }

    @MainActor
    func testRejectedGoogleAccountClearsTheCacheAndReportsUnconfirmedRevocation() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        fixture.google.steps = 55
        let hub = fixture.makeHub()
        _ = await hub.syncAndNotify(background: true)
        let revoking = AsyncStream<Void>.makeStream()
        fixture.google.revokeResult = {
            await withCheckedContinuation { continuation in
                fixture.google.resumeRevocation = continuation
                revoking.continuation.yield(())
                revoking.continuation.finish()
            }
        }
        fixture.google.importError = .reauthorize
        _ = await hub.syncAndNotify(background: true)
        var started = revoking.stream.makeAsyncIterator()
        _ = await started.next()
        XCTAssertEqual(hub.revocationStatus, .inProgress)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cache.path))
        XCTAssertNil(hub.today.steps)
        fixture.google.resumeRevocation?.resume(returning: .unconfirmed)
        fixture.google.resumeRevocation = nil
        for _ in 0..<100 where hub.revocationStatus == .inProgress { await Task.yield() }
        XCTAssertEqual(hub.revocationStatus, .unconfirmed)
        XCTAssertEqual(fixture.makeHub().revocationStatus, .unconfirmed)
    }

    @MainActor
    func testFailedCacheDeletionIsVisibleAndRetriedOnStartup() throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.cache, withIntermediateDirectories: false)
        let hub = fixture.makeHub()
        hub.disconnectGoogle()
        XCTAssertTrue(hub.syncNote?.contains("nicht gelöscht") == true)
        XCTAssertTrue(fixture.makeHub().syncNote?.contains("nicht gelöscht") == true)

        try FileManager.default.removeItem(at: fixture.cache)
        XCTAssertTrue(fixture.makeHub().syncNote?.contains("ist gelöscht") == true)
    }

    @MainActor
    func testRevocationDistinguishesNetworkFailureAndHTTPStatus() async {
        let offline = await GoogleHealthService.revoke("fixture") { _ in throw URLError(.notConnectedToInternet) }
        let refused = await GoogleHealthService.revoke("fixture") { _ in 503 }
        let confirmed = await GoogleHealthService.revoke("fixture") { _ in 200 }

        XCTAssertEqual(offline, .unconfirmed)
        XCTAssertEqual(refused, .unconfirmed)
        XCTAssertEqual(confirmed, .confirmed)
    }

    func testRedirectDelegateDeclinesDestinationWithoutStartingNetwork() throws {
        let endpoint = try XCTUnwrap(URL(string: "https://oauth2.googleapis.com/revoke"))
        let other = try XCTUnwrap(URL(string: "https://example.invalid/"))
        let response = try XCTUnwrap(HTTPURLResponse(url: endpoint, statusCode: 307, httpVersion: nil,
                                                    headerFields: ["Location": other.absoluteString]))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let checked = expectation(description: "Redirect abgelehnt")
        CoachProviders.NoRedirects().urlSession(
            session, task: session.dataTask(with: endpoint), willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: other)
        ) { redirect in
            XCTAssertNil(redirect)
            checked.fulfill()
        }
        wait(for: [checked], timeout: 1)
    }

    func testWorkoutMergeKeepsShortOverlapsAndDifferentActivities() throws {
        let day = Date.now.startOfDay
        let fitbit = GoogleMetricOrigin(family: .fitbit, device: "Fitbit")
        let walk = WorkoutSummary(name: "Gang", start: day, duration: 1800, energy: nil, activityType: "WALKING")
        let mirrored = WorkoutSummary(name: "Walk", start: day.addingTimeInterval(30), duration: 1800,
                                      energy: nil, activityType: "WALKING")
        let second = WorkoutSummary(name: "Spaziergang", start: day.addingTimeInterval(1740), duration: 1800,
                                    energy: nil, activityType: "WALKING")
        let weights = WorkoutSummary(name: "Kraft", start: day, duration: 1800, energy: nil, isStrength: true)
        let days = GoogleHealthMerge.days(points: [.exercise: [
            .workout(walk, source: watch), .workout(mirrored, source: fitbit),
            .workout(second, source: fitbit), .workout(weights, source: fitbit)
        ]], from: day, until: day.adding(days: 1), calendar: .forma)

        XCTAssertEqual(Set(try XCTUnwrap(days.first).workouts.map(\.id)), Set([walk.id, second.id, weights.id]))
        XCTAssertEqual(DashboardDay.workoutTime(try XCTUnwrap(days.first)), 3540)
    }

    func testPaceNeedsLongComparableHistoryAndStopsAtDeviceChange() throws {
        let now = Date.now.startOfDay
        let person = PersonInfo(birthDate: nil, sex: .unknown, origin: .manual, birthYear: 1990)
        let strength = BodyAge.StrengthMinutes(perWeek: 0, recentPerWeek: 0, hasRecord: false)
        let days = (1...180).reversed().map { offset in
            var day = DayMetrics(date: now.adding(days: -offset), restingHR: 60)
            day.setOrigins([watch], for: .restingHR)
            return day
        }
        func estimate(_ inputs: [DayMetrics]) throws -> BodyAge.Result {
            guard case .ready(let result) = BodyAge.evaluate(days: inputs, person: person, strength: strength, now: now) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return result
        }

        let full = try estimate(days)
        XCTAssertTrue(full.ageIsApproximate)
        XCTAssertEqual(try XCTUnwrap(full.pace), 1, accuracy: 0.01)
        XCTAssertNil(try estimate(Array(days.suffix(60))).pace)
        var changed = days
        changed[0].setOrigins([GoogleMetricOrigin(family: .appleWatch, device: "Other")], for: .restingHR)
        XCTAssertNil(try estimate(changed).pace)
    }

    @MainActor
    func testNewConversationCannotSendPriorAccountMessagesOrAcceptAnOldQuestion() async throws {
        let prior = ChatMessage(role: .user, text: "alter Gesundheitsverlauf")
        CoachProviders.invalidateConversation()
        let current = ChatMessage(role: .user, text: "Guten Morgen")
        let response = try await CoachProviders.replyInCurrentConversation(
            context: "", history: [prior, current], anthropicKey: "fixture", openAIKey: nil,
            maySend: { true }
        ) { request in
            let data = try XCTUnwrap(request.httpBody)
            let body = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(body.contains("alter Gesundheitsverlauf"))
            XCTAssertTrue(body.contains("Guten Morgen"))
            return Data(#"{"content":[{"type":"text","text":"Guten Morgen."}]}"#.utf8)
        }
        XCTAssertEqual(response, "Guten Morgen.")
        do {
            _ = try await CoachProviders.replyInCurrentConversation(
                context: "", history: [prior], anthropicKey: "fixture", openAIKey: nil, maySend: { true }
            ) { _ in
                XCTFail("Die alte Frage darf das Gerät nicht verlassen.")
                return Data()
            }
            XCTFail("Alte Frage wurde angenommen.")
        } catch is CancellationError {
            return
        }
    }

    func testWakeTimeDistinguishesMissingAndMidnightAndResolvesDSTByDay() throws {
        let name = "Forma.Fix03.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(CoachNotifier.wakeMinutes(in: defaults), 415)
        defaults.set(0, forKey: CoachNotifier.wakeKey)
        XCTAssertEqual(CoachNotifier.wakeMinutes(in: defaults), 0)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let beforeSpring = try XCTUnwrap(GoogleHealthTime.parse("2026-03-28T11:00:00Z"))
        let plan = try XCTUnwrap(CoachNotifier.bedtimePlan(sleepNeed: 8 * 3600, now: beforeSpring, wakeMinutes: 150,
                                                           calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: plan.wake), 29)
        XCTAssertEqual(calendar.component(.hour, from: plan.wake), 3)
    }

    func testTextConsentDoesNotPermitCoachPhotos() throws {
        let name = "Forma.Fix03.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: CoachProviders.consentKey)
        XCTAssertTrue(CoachProviders.allowsCoachReply(withPhotos: false, defaults: defaults))
        XCTAssertFalse(CoachProviders.allowsCoachReply(withPhotos: true, defaults: defaults))
        defaults.set(true, forKey: CoachProviders.photoConsentKey)
        XCTAssertTrue(CoachProviders.allowsCoachReply(withPhotos: true, defaults: defaults))
        defaults.set(false, forKey: CoachProviders.consentKey)
        XCTAssertFalse(CoachProviders.allowsCoachReply(withPhotos: true, defaults: defaults))
    }

    func testLocalCoachSeparatesMeasuredStrainFromRecoveryBasedTargets() {
        let day = DayMetrics(date: .now, activeEnergy: 400)
        var context = CoachEngine.Context(
            scores: ScoreEngine.scores(today: day, history: []), today: day, hrvDelta: nil, rhrDelta: nil,
            plannedRoutine: nil, trainedToday: true, isSample: false, hour: 12, recoveryAvailable: false
        )
        let recap = CoachEngine.dailyLine(context)
        XCTAssertTrue(recap.contains("Training abgeschlossen"))
        XCTAssertFalse(recap.contains("Zielbereich"))
        context.recoveryAvailable = true
        context.strainAvailable = false
        let answer = CoachEngine.localAnswer(to: "Wie hoch ist meine Belastung?", context)
        XCTAssertTrue(answer.contains("Belastung: keine Messung"))
        XCTAssertTrue(answer.contains("Zielbereich"))
    }
}

@MainActor
private final class HubFixture {
    let google = GoogleFixture()
    let root: URL
    var cache: URL { root.appendingPathComponent("sync.json") }
    let suite = "Forma.Fix03.\(UUID())"
    let defaults: UserDefaults
    var calendar = Calendar(identifier: .gregorian)
    var now: Date
    var confirmedSleep: [CivilDay?] = []

    init(zone: String = "UTC") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        now = try XCTUnwrap(GoogleHealthTime.parse("2026-06-11T09:00:00Z"))
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    func makeHub() -> DataHub {
        DataHub(googleService: google, defaults: defaults, cacheURL: cache,
                now: { self.now }, calendar: { self.calendar }, notify: { _, sleepDay, _ in
                    self.confirmedSleep.append(sleepDay)
                    return nil
                })
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class GoogleFixture: GoogleHealthImporting {
    let isConfigured = true
    var accountID: String? = "fixture-account"
    var steps: Double?
    var sleep = false
    var failed: Set<MetricSeries> = []
    var activityHour: Date?
    var importError: GoogleHealthError?
    var revokeResult: (@MainActor () async -> GoogleRevocation)?
    var resumeRevocation: CheckedContinuation<GoogleRevocation, Never>?
    var beforeRecentResponse: (@MainActor () async -> Void)?
    var resumeResponse: CheckedContinuation<Void, Never>?

    func restore() throws {}
    func connect() async throws { accountID = "fixture-account" }
    func disconnect() throws -> Task<GoogleRevocation, Never>? {
        accountID = nil
        return revokeResult.map { body in Task { await body() } }
    }

    func load(from: Date, until: Date, calendar: Calendar, includePulse: Bool) async throws -> GoogleHealthService.Import {
        guard includePulse else {
            return .init(days: [], hours: nil, pulses: nil, failed: Set(MetricSeries.allCases))
        }
        if let importError { throw importError }
        await beforeRecentResponse?()
        let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: until))
        let stageEnd = day.addingTimeInterval(6 * 3600)
        let stageStart = stageEnd.addingTimeInterval(-7 * 3600)
        let points: [GoogleHealthKind: [GoogleHealthPoint]] = sleep ? [
            .sleep: [.sleep(SleepNight(start: stageStart, end: stageEnd, segments: [], reportedAsleep: 7 * 3600),
                             main: true, nap: false, updated: nil,
                             source: GoogleMetricOrigin(family: .fitbit, device: "Fitbit"))]
        ] : [:]
        var days = GoogleHealthMerge.days(points: points, from: from, until: until, calendar: calendar)
        days[days.count - 1].steps = steps
        let hours = activityHour.map { [HourlyMetrics(start: $0, end: $0.addingTimeInterval(3600), activeEnergy: 42)] }
        return .init(days: days, hours: hours ?? [], pulses: [], failed: failed)
    }

    func loadPulse(from: Date, until: Date, calendar: Calendar) async throws -> [HourlyMetrics] { [] }
}
