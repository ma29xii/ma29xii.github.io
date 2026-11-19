import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Forma

final class Fix04Tests: XCTestCase {
    func testShortUnmarkedFitbitSleepDoesNotDisplaceMainNight() throws {
        let end = try XCTUnwrap(GoogleHealthTime.parse("2026-06-11T06:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let day = calendar.startOfDay(for: end)
        let watch = GoogleMetricOrigin(family: .appleWatch, device: "Watch")
        let fitbit = GoogleMetricOrigin(family: .fitbit, device: "Fitbit")
        let full = SleepNight(start: end - 28_800, end: end, segments: [], reportedAsleep: 28_800)
        let short = SleepNight(start: end - 3_600, end: end, segments: [], reportedAsleep: 3_600)
        for markedMain in [false, true] {
            let points: [GoogleHealthPoint] = [
                .sleep(full, main: markedMain, nap: false, updated: nil, source: watch),
                .sleep(short, main: false, nap: false, updated: nil, source: fitbit)
            ]
            for input in [points, Array(points.reversed())] {
                let result = try XCTUnwrap(GoogleHealthMerge.days(points: [.sleep: input], from: day,
                                                                   until: day + 86_400, calendar: calendar).first)
                XCTAssertEqual(result.sleep?.asleep, 28_800)
                XCTAssertEqual(result.origins?[.sleep], [watch])
            }
        }
    }

    @MainActor
    func testConfirmedEmptyGoogleSeriesClearLastValueAndPulseOnRestart() async throws {
        let fixture = try Fix04Hub()
        defer { fixture.cleanup() }
        let hub = fixture.makeHub()
        fixture.google.steps = 1234
        _ = await hub.refresh()
        XCTAssertEqual(hub.today.steps, 1234)
        XCTAssertEqual(hub.hours.first?.heartRate, 65)

        fixture.google.steps = nil
        _ = await hub.refresh()
        XCTAssertNil(hub.today.steps)
        XCTAssertTrue(hub.hours.isEmpty)
        let reopened = fixture.makeHub()
        XCTAssertNil(reopened.today.steps)
        XCTAssertTrue(reopened.hours.isEmpty)
        XCTAssertNil(try XCTUnwrap(reopened.seriesFreshness[.steps]).latestMeasurementDay)
    }

    @MainActor
    func testPartialEmptyGoogleImportKeepsOnlyFailedSeries() async throws {
        let fixture = try Fix04Hub()
        defer { fixture.cleanup() }
        let hub = fixture.makeHub()
        fixture.google.steps = 1234
        fixture.google.hrv = 52
        _ = await hub.refresh()
        fixture.google.steps = nil
        fixture.google.hrv = nil
        fixture.google.failed = [.hrv]
        let result = await hub.refresh()
        XCTAssertEqual(result, .partial([.hrv]))
        XCTAssertEqual(hub.today.hrv, 52)
        XCTAssertNil(hub.today.steps)
    }

    @MainActor
    func testConfirmedEmptyEnergyClearsWhileFailedStepsRemain() async throws {
        let fixture = try Fix04Hub()
        defer { fixture.cleanup() }
        let hub = fixture.makeHub()
        fixture.google.steps = 1234
        fixture.google.energy = 52
        _ = await hub.refresh()
        XCTAssertEqual(hub.today.activeEnergy, 52)
        fixture.google.steps = nil
        fixture.google.energy = nil
        fixture.google.failed = [.steps]
        fixture.google.unpairedEnergy = []
        let result = await hub.refresh()
        XCTAssertEqual(result, .partial([.steps]))
        XCTAssertEqual(hub.today.steps, 1234)
        XCTAssertNil(hub.today.activeEnergy)
        XCTAssertEqual(hub.hours.first?.steps, 1234)
        XCTAssertNil(hub.hours.first?.activeEnergy)
    }

    func testWidgetReadIsRevokedEvenWhenSnapshotCannotBeDeleted() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        let file = root.appendingPathComponent("snapshot.json")
        let access = root.appendingPathComponent("access")
        let store = WidgetSnapshotStore(fileURL: file, accessURL: access)
        let now = Date.now
        let snapshot = try XCTUnwrap(WidgetSnapshot(recovery: 81, strain: nil, sleep: nil,
                                                     updatedAt: now, day: now, calendar: .forma))
        XCTAssertTrue(try store.replace(with: snapshot))
        XCTAssertEqual(store.read(), snapshot)
        XCTAssertThrowsError(try store.replace(with: nil, removeSnapshot: { _ in
            throw CocoaError(.fileWriteNoPermission)
        }))
        XCTAssertTrue(files.fileExists(atPath: file.path))
        XCTAssertNil(WidgetSnapshotStore(fileURL: file, accessURL: access).current(at: now))
        XCTAssertTrue(try store.replace(with: nil))
        XCTAssertFalse(files.fileExists(atPath: file.path))
        XCTAssertTrue(try store.replace(with: snapshot))
        XCTAssertEqual(store.read(), snapshot)
    }

    @MainActor
    func testBedtimeKeepsOldRequestOnFailureAndRemovesItAfterAcceptance() async throws {
        let fixture = try Fix04Hub()
        defer { fixture.cleanup() }
        var scheduled = Set(["forma.bedtime"])
        let failed = await CoachNotifier.replaceBedtimeReminder(id: "failed", defaults: fixture.defaults,
                                                               isCurrent: { true }, enqueue: {
            throw CocoaError(.fileWriteUnknown)
        }, remove: { scheduled.subtract($0) })
        XCTAssertNotNil(failed)
        XCTAssertEqual(scheduled, ["forma.bedtime"])

        let success = await CoachNotifier.replaceBedtimeReminder(id: "accepted", defaults: fixture.defaults,
                                                                isCurrent: { true }, enqueue: {
            XCTAssertEqual(scheduled, ["forma.bedtime"])
            scheduled.insert("accepted")
        }, remove: { scheduled.subtract($0) })
        XCTAssertNil(success)
        XCTAssertEqual(scheduled, ["accepted"])
    }

    @MainActor
    func testSupersededBedtimeReplacementRemovesOnlyItsOwnRequest() async throws {
        let fixture = try Fix04Hub()
        defer { fixture.cleanup() }
        var scheduled = Set(["forma.bedtime"])
        var current = true
        _ = await CoachNotifier.replaceBedtimeReminder(id: "cancelled", defaults: fixture.defaults,
                                                       isCurrent: { current }, enqueue: {
            scheduled.insert("cancelled")
            current = false
        }, remove: { scheduled.subtract($0) })
        XCTAssertEqual(scheduled, ["forma.bedtime"])
    }

    @MainActor
    func testFoodConsentCanBeRevokedAloneAndChatRevocationClearsBothPhotos() throws {
        let fixture = try Fix04Hub()
        defer { fixture.cleanup() }
        let defaults = fixture.defaults
        defaults.set(true, forKey: CoachProviders.consentKey)
        defaults.set(true, forKey: CoachProviders.photoConsentKey)
        defaults.set(true, forKey: FoodSettings.photoConsentKey)
        XCTAssertTrue(CoachProviders.allowsFoodPhoto(defaults: defaults))

        CoachProviders.revokeFoodPhotoConsent(defaults: defaults)
        XCTAssertFalse(CoachProviders.allowsFoodPhoto(defaults: defaults))
        XCTAssertTrue(CoachProviders.allowsCoachReply(withPhotos: true, defaults: defaults))

        defaults.set(true, forKey: FoodSettings.photoConsentKey)
        CoachProviders.revokeChatConsent(defaults: defaults)
        defaults.set(true, forKey: CoachProviders.consentKey)
        XCTAssertFalse(CoachProviders.allowsFoodPhoto(defaults: defaults))
        XCTAssertFalse(CoachProviders.allowsCoachReply(withPhotos: true, defaults: defaults))
    }

    @MainActor
    func testRegrantingFoodConsentDoesNotSendAnOldPhotoToFallback() async throws {
        let fixture = try Fix04Hub()
        defer { fixture.cleanup() }
        fixture.defaults.set(true, forKey: CoachProviders.consentKey)
        fixture.defaults.set(true, forKey: FoodSettings.photoConsentKey)
        let size = CGSize(width: 16, height: 16)
        let photo = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        do {
            _ = try await FoodVision.estimate(photo: XCTUnwrap(photo.jpegData(compressionQuality: 1)),
                                              anthropicKey: "fixture-a", openAIKey: "fixture-b", maySend: { true }) { request in
                guard request.url?.host == "api.anthropic.com" else {
                    XCTFail("Ein widerrufenes Foto darf nicht an den zweiten Anbieter gehen.")
                    throw URLError(.unknown)
                }
                await MainActor.run {
                    CoachProviders.revokeFoodPhotoConsent(defaults: fixture.defaults)
                    fixture.defaults.set(true, forKey: FoodSettings.photoConsentKey)
                }
                throw URLError(.timedOut)
            }
            XCTFail("Der alte Auftrag muss nach dem Widerruf beendet sein.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    @MainActor
    func testOpenSampleUsesNewCalendarDayAfterMidnight() throws {
        let fixture = try Fix04Hub()
        defer { fixture.cleanup() }
        fixture.defaults.set(DataSourceKind.sample.rawValue, forKey: "forma.source")
        fixture.now = try XCTUnwrap(GoogleHealthTime.parse("2026-06-11T23:59:00Z"))
        let hub = fixture.makeHub()
        let previous = hub.today.date
        fixture.now = fixture.now.addingTimeInterval(120)
        let day = hub.today
        XCTAssertEqual(day.date, previous + 86_400)
        XCTAssertEqual(hub.longDays.last?.date, day.date)
        XCTAssertTrue(day.workouts.allSatisfy { fixture.calendar.isDate($0.start, inSameDayAs: day.date) })
        let dashboard = DashboardDay(day: day, history: hub.dashboardHistory(recent: hub.days))
        XCTAssertNotNil(dashboard.strain)
        XCTAssertNotNil(dashboard.recovery)
        XCTAssertNotNil(dashboard.sleepScore)
    }

    @MainActor
    func testSampleTrainingRolloverRefreshesSeedsAndRetainsLocalDemoWorkout() throws {
        let fixture = try Fix04Hub()
        defer { fixture.cleanup() }
        fixture.defaults.set(DataSourceKind.sample.rawValue, forKey: "forma.source")
        let hub = fixture.makeHub()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, SetRecord.self, configurations: configuration)
        let context = container.mainContext
        SampleData.seedWorkouts(hub.longDays, in: context)
        context.insert(WorkoutSession(title: "Eigenes Vorschautraining", start: fixture.now, end: fixture.now + 3600))
        fixture.now = fixture.now.addingTimeInterval(86_400)

        SampleData.seedWorkouts(hub.longDays, in: context)
        SampleData.seedWorkouts(hub.longDays, in: context)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.filter { $0.title == "Eigenes Vorschautraining" }.count, 1)
        let todays = sessions.filter { fixture.calendar.isDate($0.start, inSameDayAs: fixture.now) }
        XCTAssertEqual(todays.map(\.title), ["Push"])
    }

    @MainActor
    func testDeletingHealthCopyRemovesOnlyCurrentAccountsBadges() throws {
        let fixture = try Fix04Hub()
        defer { fixture.cleanup() }
        let hub = fixture.makeHub()
        let tracker = hub.achievementTracker
        let current = AchievementHealthScope(accountID: try XCTUnwrap(fixture.google.accountID))
        let other = AchievementHealthScope(accountID: "another-account")
        _ = tracker.update(scope: other, health: [.tracked: fixture.now], record: nil, now: fixture.now)
        _ = tracker.update(scope: current, health: [.sleep: fixture.now], record: fixture.now, now: fixture.now)
        XCTAssertEqual(tracker.unlocked(scope: current), [.firstRecord, .sleep])

        hub.deleteLocalHealthCopy()
        XCTAssertEqual(tracker.unlocked(scope: current), [.firstRecord])
        let reopened = fixture.makeHub().achievementTracker
        _ = reopened.update(scope: current, health: [:], record: nil, now: fixture.now)
        XCTAssertEqual(reopened.unlocked(scope: current), [.firstRecord])
        _ = reopened.update(scope: other, health: [:], record: nil, now: fixture.now)
        XCTAssertEqual(reopened.unlocked(scope: other), [.firstRecord, .tracked])
    }

    @MainActor
    func testThreeLongValuesRenderThroughTheirFinalDigitInBothFormats() throws {
        let metrics = [ShareCardContent.Metric(label: "Dauer", value: "12345 h 59 min"),
                       .init(label: "Arbeitssätze", value: "12.345.679"),
                       .init(label: "Volumen", value: "123.456.789,9 kg")]
        for (format, height) in [(ShareCardFormat.story, 1_920), (.square, 1_080)] {
            func image(_ metrics: [ShareCardContent.Metric]) throws -> CGImage {
                let display = ShareCardContent.Display(kind: .training, isSample: true,
                                                       date: "Donnerstag, 19. November", metrics: metrics)
                let card = try XCTUnwrap(RenderedShareCard.make(display: display, format: format))
                return try XCTUnwrap(UIImage(data: card.transfer.data)?.cgImage)
            }
            let baseline = try image(metrics)
            let pixels = try XCTUnwrap(baseline.dataProvider?.data) as Data
            XCTAssertEqual(baseline.width, 1_080)
            XCTAssertEqual(baseline.height, height)
            XCTAssertEqual(pixels, try XCTUnwrap(image(metrics).dataProvider?.data) as Data)
            for index in metrics.indices {
                var changed = metrics
                let metric = metrics[index]
                let lastDigit = try XCTUnwrap(metric.value.lastIndex(of: "9"))
                var different = metric.value
                different.replaceSubrange(lastDigit...lastDigit, with: "8")
                changed[index] = .init(label: metric.label, value: different)
                XCTAssertNotEqual(pixels, try XCTUnwrap(image(changed).dataProvider?.data) as Data, metric.label)
            }
        }
    }
}

@MainActor
private final class Fix04Hub {
    let google = Fix04Google()
    let suite = "Forma.Fix04.\(UUID())"
    let defaults: UserDefaults
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var now: Date
    var calendar = Calendar(identifier: .gregorian)

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        now = try XCTUnwrap(GoogleHealthTime.parse("2026-06-11T09:00:00Z"))
        calendar.timeZone = .gmt
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    func makeHub() -> DataHub {
        DataHub(googleService: google, defaults: defaults, cacheURL: directory.appendingPathComponent("sync.json"),
                now: { self.now }, calendar: { self.calendar })
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class Fix04Google: GoogleHealthImporting {
    let isConfigured = true
    var accountID: String? = "fixture-account"
    var steps: Double?
    var hrv: Double?
    var energy: Double?
    var unpairedEnergy: [GoogleHealthPoint]?
    var failed: Set<MetricSeries> = []

    func restore() throws {}
    func connect() async throws {}
    func disconnect() throws -> Task<GoogleRevocation, Never>? { nil }

    func load(from: Date, until: Date, calendar: Calendar, includePulse: Bool) async throws -> GoogleHealthService.Import {
        guard includePulse else { throw GoogleHealthError.invalidResponse }
        let today = try XCTUnwrap(calendar.startOfDay(offsetBy: -1, from: until))
        let hour = today + 8 * 3600
        var days = GoogleHealthMerge.days(points: [:], from: from, until: until, calendar: calendar)
        days[days.count - 1].steps = steps
        days[days.count - 1].hrv = hrv
        days[days.count - 1].activeEnergy = energy
        let pulses = steps == nil ? [] : [HourlyMetrics(start: hour, end: hour + 3600, heartRate: 65)]
        let origin = GoogleMetricOrigin(family: .appleWatch, device: "Watch")
        let activity = HourlyMetrics(start: hour, end: hour + 3600, steps: steps, activeEnergy: energy,
                                     stepOrigin: origin, energyOrigin: origin)
        let hours = failed.contains(.steps) ? nil : (steps != nil || energy != nil ? [activity] : [])
        return .init(days: days, hours: hours, pulses: pulses, failed: failed, unpairedEnergy: unpairedEnergy)
    }

    func loadPulse(from: Date, until: Date, calendar: Calendar) async throws -> [HourlyMetrics] { [] }
}
