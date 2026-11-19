import Foundation
import XCTest
@testable import Forma

final class WidgetTests: XCTestCase {
    func testEmptyDayDoesNotPublishCalculatedFallbacks() throws {
        let calendar = calendar(in: "Europe/Berlin")
        let now = try date(2026, 11, 19, hour: 9, in: calendar)
        let day = DayMetrics(date: calendar.startOfDay(for: now))
        let dashboard = DashboardDay(day: day, history: [])

        XCTAssertNil(WidgetBridge.snapshot(for: dashboard, checkedAt: now, calendar: calendar))
    }

    func testMeasuredZeroStrainIsDifferentFromMissingScores() throws {
        let calendar = calendar(in: "Europe/Berlin")
        let now = try date(2026, 11, 19, hour: 9, in: calendar)
        var day = DayMetrics(date: calendar.startOfDay(for: now))
        day.activeEnergy = 0
        let dashboard = DashboardDay(day: day, history: [])

        let snapshot = try XCTUnwrap(WidgetBridge.snapshot(for: dashboard, checkedAt: now, calendar: calendar))
        XCTAssertEqual(snapshot.strain, 0)
        XCTAssertNil(snapshot.recovery)
        XCTAssertNil(snapshot.sleep)
        XCTAssertEqual(snapshot.updatedAt, now)
    }

    func testSnapshotExpiresAtMidnightOnShortDSTDay() throws {
        let calendar = calendar(in: "Europe/Berlin")
        let start = try date(2026, 3, 29, in: calendar)
        let midnight = try date(2026, 3, 30, in: calendar)
        let snapshot = try XCTUnwrap(WidgetSnapshot(recovery: 71, strain: nil, sleep: nil,
                                                   updatedAt: start, day: start, calendar: calendar))

        XCTAssertEqual(snapshot.validUntil.timeIntervalSince(start), 23 * 3600)
        XCTAssertTrue(snapshot.isCurrent(at: midnight.addingTimeInterval(-1), calendar: calendar))
        XCTAssertFalse(snapshot.isCurrent(at: midnight, calendar: calendar))
        XCTAssertFalse(snapshot.isCurrent(at: start.addingTimeInterval(-1), calendar: calendar))
        XCTAssertNil(WidgetSnapshot(recovery: 71, strain: nil, sleep: nil,
                                    updatedAt: start, day: midnight, calendar: calendar))
    }

    func testStoreReplacesClearsAndIgnoresInvalidData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appendingPathComponent("snapshot.json")
        let store = WidgetSnapshotStore(fileURL: file)
        let calendar = calendar(in: "Europe/Berlin")
        let now = try date(2026, 11, 19, hour: 9, in: calendar)
        let snapshot = try XCTUnwrap(WidgetSnapshot(recovery: 71, strain: 0, sleep: nil,
                                                   updatedAt: now, day: now, calendar: calendar))
        XCTAssertNil(store.read())
        XCTAssertTrue(try store.replace(with: snapshot))
        XCTAssertEqual(store.read(), snapshot)
        XCTAssertFalse(try store.replace(with: snapshot))

        try Data("{ungültig".utf8).write(to: file)
        XCTAssertNil(store.read())
        XCTAssertTrue(try store.replace(with: nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(try store.replace(with: nil))
    }

    func testOutOfRangeScoresNeverBecomeFallbackNumbers() throws {
        let calendar = calendar(in: "Europe/Berlin")
        let now = try date(2026, 11, 19, hour: 9, in: calendar)
        let snapshot = try XCTUnwrap(WidgetSnapshot(recovery: 101, strain: -1, sleep: 100,
                                                   updatedAt: now, day: now, calendar: calendar))
        XCTAssertNil(snapshot.recovery)
        XCTAssertNil(snapshot.strain)
        XCTAssertEqual(snapshot.sleep, 100)
    }

    func testWidgetDoesNotShowPreviousDayAfterTravellingEast() throws {
        let berlin = calendar(in: "Europe/Berlin")
        let tokyo = calendar(in: "Asia/Tokyo")
        let updated = try date(2026, 11, 19, hour: 9, in: berlin)
        let firstNextDayInTokyo = try date(2026, 11, 20, in: tokyo)
        let snapshot = try XCTUnwrap(WidgetSnapshot(recovery: 78, strain: nil, sleep: nil,
                                                   updatedAt: updated, day: updated, calendar: berlin))

        XCTAssertTrue(snapshot.isCurrent(at: firstNextDayInTokyo, calendar: berlin))
        XCTAssertEqual(snapshot.expiry(in: tokyo), firstNextDayInTokyo)
        XCTAssertFalse(snapshot.isCurrent(at: firstNextDayInTokyo, calendar: tokyo))
    }

    @MainActor
    func testForegroundRouteIsRetainedUntilItIsConsumed() {
        let router = HealthIntentRouter()
        router.request(.startTraining)
        XCTAssertEqual(router.pending, .startTraining)
        XCTAssertEqual(router.consume(), .startTraining)
        XCTAssertNil(router.consume())

        router.request(.scanFood)
        XCTAssertEqual(router.consume(), .scanFood)
    }

    func testPauseIntervalStopsAtEndAndRejectsInvalidDates() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let end = now.addingTimeInterval(90)
        let state = LiveTrainingAttributes.ContentState(exerciseName: "  Bankdrücken  ", setNumber: 2,
                                                         isWarmup: false, pauseEndsAt: end)

        XCTAssertEqual(state.exerciseName, "Bankdrücken")
        XCTAssertEqual(state.setNumber, 2)
        XCTAssertEqual(state.pauseInterval(at: now), now...end)
        XCTAssertNil(state.pauseInterval(at: end))
        let invalid = LiveTrainingAttributes.ContentState(exerciseName: "\n", setNumber: 0,
                                                           isWarmup: false, pauseEndsAt: Date(timeIntervalSince1970: .infinity))
        XCTAssertNil(invalid.exerciseName)
        XCTAssertNil(invalid.setNumber)
        XCTAssertNil(invalid.pauseEndsAt)
    }

    func testActivityPayloadKeepsLongExerciseNamesWithinBudget() throws {
        let state = LiveTrainingAttributes.ContentState(exerciseName: String(repeating: "🏋️‍♂️", count: 2000),
                                                         setNumber: nil, isWarmup: true, pauseEndsAt: nil)
        let data = try JSONEncoder().encode(state)

        XCTAssertLessThan(data.count, 4096)
        XCTAssertTrue(state.isWarmup)
        XCTAssertNotNil(state.exerciseName)
    }

    private func calendar(in zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, in calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }
}
