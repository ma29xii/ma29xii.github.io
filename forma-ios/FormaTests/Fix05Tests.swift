import Foundation
import UIKit
import UserNotifications
import XCTest
@testable import Forma

final class Fix05Tests: XCTestCase {
    @MainActor
    func testGoogleDiscardedRowsKeepStepsOnDiskUntilAnEmptyResponse() async throws {
        let fixture = try Fix05Fixture()
        defer { fixture.cleanup() }
        let google = fixture.google
        let hub = fixture.makeHub()
        let steps = """
        "steps":{"count":8000,"interval":{"startTime":"2026-06-11T08:00:00Z","endTime":"2026-06-11T08:15:00Z"}}
        """
        google.pages = ["""
        {"dataPoints":[{"dataSource":{"platform":"FITBIT"},\(steps)}]}
        """]
        let first = await hub.refresh()
        XCTAssertEqual(first, .updated)
        XCTAssertEqual(hub.today.steps, 8000)

        for row in ["{\(steps)}", "{\"dataSource\":{\"platform\":12},\(steps)}",
                    "{\"dataSource\":{\"platform\":\"HEALTH_KIT\",\"device\":{\"formFactor\":\"PHONE\"}},\(steps)}"] {
            google.pages = ["{\"nextPageToken\":\"next\"}", "{\"dataPoints\":[\(row)]}"]
            let result = await hub.refresh()
            XCTAssertEqual(result, .partial([.steps]))
            let reopened = fixture.makeHub()
            XCTAssertEqual(reopened.today.steps, 8000)
            XCTAssertEqual(reopened.hours.first?.steps, 8000)
        }

        google.pages = ["{\"dataPoints\":[]}"]
        let empty = await hub.refresh()
        XCTAssertEqual(empty, .updated)
        let reopened = fixture.makeHub()
        XCTAssertNil(reopened.today.steps)
        XCTAssertTrue(reopened.hours.isEmpty)
    }

    @MainActor
    func testUnreadableGoogleRowMakesMixedPagesIncomplete() async {
        do {
            _ = try await GoogleHealthService.readPoints(.sleep) { token in
                if token == nil {
                    return Data("""
                    {"dataPoints":[{"dataSource":{"platform":"FITBIT"},"sleep":{
                     "interval":{"startTime":"2026-06-10T22:00:00Z","endTime":"2026-06-11T06:00:00Z"},
                     "summary":{"minutesAsleep":480}}}],"nextPageToken":"next"}
                    """.utf8)
                }
                return Data("""
                {"dataPoints":[{"dataSource":{"platform":"FITBIT"},"sleep":{
                 "interval":{"startTime":"2026-06-09T22:00:00Z","endTime":"2026-06-10T06:00:00Z"},
                 "metadata":{"mainSleep":"invalid"},"summary":{"minutesAsleep":480}}}]}
                """.utf8)
            }
            XCTFail("Die gültige Seite macht den Teilabruf nicht vollständig.")
        } catch {
            XCTAssertEqual(error as? GoogleHealthError, .invalidResponse)
        }
    }

    func testWidgetValueEntryExpiresAfterFifteenMinutesOrAtMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let morning = try XCTUnwrap(GoogleHealthTime.parse("2026-06-11T09:00:00Z"))
        let nearMidnight = try XCTUnwrap(GoogleHealthTime.parse("2026-06-11T23:58:00Z"))
        let snapshot = try XCTUnwrap(WidgetSnapshot(recovery: 81, strain: nil, sleep: nil,
                                                     updatedAt: morning, day: morning, calendar: calendar))
        XCTAssertEqual(snapshot.timelineExpiry(forEntryAt: morning, calendar: calendar), morning + 900)
        XCTAssertEqual(snapshot.timelineExpiry(forEntryAt: nearMidnight, calendar: calendar), nearMidnight + 120)
    }

    @MainActor
    func testRevokingChatPhotosCancelsAnInFlightPhotoTransport() async throws {
        let defaults = UserDefaults.standard
        let settings = [CoachProviders.consentKey, CoachProviders.photoConsentKey, FoodSettings.photoConsentKey]
        let previous = settings.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(settings, previous) { defaults.set(value, forKey: key) } }
        defaults.set(true, forKey: CoachProviders.consentKey)
        defaults.set(true, forKey: CoachProviders.photoConsentKey)
        CoachProviders.monitorConsent()
        let photo = try makeJPEG()
        let started = XCTestExpectation(description: "Chatfoto im Transport")
        let cancelled = XCTestExpectation(description: "Chatfoto-Transport abgebrochen")
        let send = heldTransport(started: started, cancelled: cancelled)
        let task = Task {
            try await CoachProviders.replyInCurrentConversation(
                context: "", history: [.init(role: .user, text: "Was ist auf dem Foto?")], images: [photo],
                anthropicKey: "fixture", openAIKey: nil,
                maySend: { CoachProviders.allowsCoachReply(withPhotos: true) }, send: send
            )
        }
        defer { task.cancel() }
        let didStart = await Self.didFulfill(started)
        XCTAssertTrue(didStart)
        // Derselbe Pfad wie beim Schalter im Profil.
        defaults.set(false, forKey: CoachProviders.photoConsentKey)
        let didCancel = await Self.didFulfill(cancelled)
        XCTAssertTrue(didCancel)
        if didCancel {
            if case .failure(let error) = await task.result { XCTAssertTrue(error is CancellationError) }
            else { XCTFail("Der widerrufene Auftrag darf keine Antwort liefern.") }
        }
    }

    @MainActor
    func testRevokingFoodPhotosCancelsAnInFlightPhotoTransport() async throws {
        let fixture = try Fix05Fixture()
        defer { fixture.cleanup() }
        fixture.defaults.set(true, forKey: FoodSettings.photoConsentKey)
        let photo = try makeJPEG()
        let started = XCTestExpectation(description: "Essensfoto im Transport")
        let cancelled = XCTestExpectation(description: "Essensfoto-Transport abgebrochen")
        let send = heldTransport(started: started, cancelled: cancelled)
        let task = Task {
            try await FoodVision.estimate(photo: photo, anthropicKey: "fixture", openAIKey: nil,
                                          maySend: { true }, send: send)
        }
        defer { task.cancel() }
        let didStart = await Self.didFulfill(started)
        XCTAssertTrue(didStart)
        CoachProviders.revokeFoodPhotoConsent(defaults: fixture.defaults)
        let didCancel = await Self.didFulfill(cancelled)
        XCTAssertTrue(didCancel)
        if didCancel {
            if case .failure(let error) = await task.result { XCTAssertTrue(error is CancellationError) }
            else { XCTFail("Der widerrufene Auftrag darf keine Antwort liefern.") }
        }
    }

    @MainActor
    func testBedtimeRemovesOldRequestOnlyAfterAConfirmedLossOfBasis() async throws {
        let fixture = try Fix05Fixture()
        defer { fixture.cleanup() }
        var scheduled: Set<String> = ["forma.bedtime"]
        var authorization = UNAuthorizationStatus.authorized
        let hub = fixture.makeHub(notify: { hub, _, generation in
            await CoachNotifier.reconcileBedtime(hub, generation: generation, now: fixture.now,
                                                 confirmedBySync: true, defaults: fixture.defaults,
                                                 authorization: { authorization },
                                                 remove: { scheduled.subtract($0) })
        })
        fixture.google.failed = [.sleep, .activeEnergy, .workouts]
        let partial = await hub.refresh()
        XCTAssertEqual(partial, .partial([.sleep, .activeEnergy, .workouts]))
        XCTAssertEqual(scheduled, ["forma.bedtime"])

        fixture.google.failed = []
        authorization = .notDetermined
        _ = await hub.refresh()
        XCTAssertEqual(scheduled, ["forma.bedtime"])
        authorization = .authorized
        let confirmed = await hub.refresh()
        XCTAssertEqual(confirmed, .updated)
        XCTAssertTrue(scheduled.isEmpty)
    }

    @MainActor
    func testCancelledBedtimeReconciliationKeepsOldRequest() async throws {
        let fixture = try Fix05Fixture()
        defer { fixture.cleanup() }
        let hub = fixture.makeHub()
        _ = await hub.refresh()
        var scheduled: Set<String> = ["forma.bedtime"]
        let task = Task { @MainActor in
            await CoachNotifier.reconcileBedtime(hub, generation: hub.generation, now: fixture.now,
                                                 confirmedBySync: true, defaults: fixture.defaults,
                                                 authorization: {
                withUnsafeCurrentTask { $0?.cancel() }
                return .authorized
            },
                                                 remove: { scheduled.subtract($0) })
        }
        _ = await task.value
        XCTAssertEqual(scheduled, ["forma.bedtime"])
    }

    func testMarkedNightWinsBeforeRelativeDurationInBothOrders() throws {
        let end = try XCTUnwrap(GoogleHealthTime.parse("2026-06-11T06:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let day = calendar.startOfDay(for: end)
        let watch = GoogleMetricOrigin(family: .appleWatch, device: "Watch")
        let fitbit = GoogleMetricOrigin(family: .fitbit, device: "Fitbit")
        for (markedDuration, expected, origin) in [(20_700.0, 20_700.0, watch), (10_800, 10_800, watch),
                                                   (10_799, 28_800, fitbit)] {
            let marked = SleepNight(start: end - markedDuration, end: end, segments: [], reportedAsleep: markedDuration)
            let unmarked = SleepNight(start: end - 28_800, end: end, segments: [], reportedAsleep: 28_800)
            let points: [GoogleHealthPoint] = [
                .sleep(marked, main: true, nap: false, updated: nil, source: watch),
                .sleep(unmarked, main: false, nap: false, updated: nil, source: fitbit)
            ]
            for order in [points, Array(points.reversed())] {
                let result = try XCTUnwrap(GoogleHealthMerge.days(points: [.sleep: order], from: day,
                                                                   until: day + 86_400, calendar: calendar).first)
                XCTAssertEqual(result.sleep?.asleep, expected)
                XCTAssertEqual(result.origins?[.sleep], [origin])
            }
        }
    }

    private static func didFulfill(_ expectation: XCTestExpectation) async -> Bool {
        await XCTWaiter().fulfillment(of: [expectation], timeout: 3) == .completed
    }

    @MainActor
    private func makeJPEG() throws -> Data {
        let size = CGSize(width: 16, height: 16)
        let photo = UIGraphicsImageRenderer(size: size).image { renderer in
            UIColor.white.setFill()
            renderer.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(photo.jpegData(compressionQuality: 1))
    }

    private func heldTransport(started: XCTestExpectation, cancelled: XCTestExpectation) -> CoachProviders.Transport {
        { _ in
            try await withTaskCancellationHandler {
                started.fulfill()
                try await Task.sleep(for: .seconds(3600))
                return Data()
            } onCancel: {
                cancelled.fulfill()
            }
        }
    }
}

@MainActor
private final class Fix05Fixture {
    let google = Fix05Google()
    let defaults: UserDefaults
    let now: Date
    private let suite = "Forma.Fix05.\(UUID())"
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        now = try XCTUnwrap(GoogleHealthTime.parse("2026-06-11T09:00:00Z"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    func makeHub(notify: (@MainActor (DataHub, CivilDay?, Int) async -> String?)? = nil) -> DataHub {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return DataHub(googleService: google, defaults: defaults, cacheURL: directory.appendingPathComponent("sync.json"),
                       now: { self.now }, calendar: { calendar }, notify: notify)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class Fix05Google: GoogleHealthImporting {
    let isConfigured = true
    let accountID: String? = "fix05-account"
    var pages = ["{}"]
    var failed: Set<MetricSeries> = []

    func restore() throws {}
    func connect() async throws {}
    func disconnect() throws -> Task<GoogleRevocation, Never>? { nil }

    func load(from: Date, until: Date, calendar: Calendar, includePulse: Bool) async throws -> GoogleHealthService.Import {
        guard includePulse else { throw GoogleHealthError.invalidResponse }
        let steps = try? await GoogleHealthService.readPoints(.steps) { token in
            Data(self.pages[token == nil ? 0 : 1].utf8)
        }
        var imported: [GoogleHealthKind: [GoogleHealthPoint]] = [:]
        for kind in GoogleHealthKind.dailyImport where kind.series.map({ !failed.contains($0) }) == true {
            imported[kind] = kind == .steps ? steps : []
        }
        imported[.pulse] = []
        return GoogleHealthService.makeImport(imported, from: from, until: until, measuredUntil: until,
                                             calendar: calendar, kinds: GoogleHealthKind.dailyImport + [.pulse])
    }

    func loadPulse(from: Date, until: Date, calendar: Calendar) async throws -> [HourlyMetrics] { [] }
}
