import Foundation
import XCTest
@testable import Forma

final class Runde19WeekWidgetTests: XCTestCase {
    func testSnapshotUsesSevenCalendarDaysInOrderAndKeepsGaps() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        func date(_ day: Int, hour: Int = 0) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour)))
        }

        // Zehn Dashboard-Tage in gemischter Reihenfolge, davon einer in der Zukunft.
        let history = try [29, 22, 31, 26, 25, 24, 27, 23, 21, 30].map { day in
            DayMetrics(date: try date(day), activeEnergy: day == 29 ? 1_100 : 0)
        }
        let now = try date(30, hour: 12)
        let snapshot = WidgetBridge.weekSnapshot(for: history, updatedAt: now, calendar: calendar)

        XCTAssertEqual(snapshot.days.map(\.date), try (24...30).map { try date($0) })
        XCTAssertEqual(snapshot.days.map(\.strain), [0, 0, 0, 0, nil, 63, 0])
        XCTAssertEqual(snapshot.days.map(\.recovery), Array(repeating: nil, count: 7))
        XCTAssertEqual(snapshot.days.map(\.sleep), Array(repeating: nil, count: 7))
        XCTAssertEqual(snapshot.updatedAt, now)

        let tomorrow = snapshot.days(endingAt: try date(31), calendar: calendar)
        XCTAssertEqual(tomorrow.map(\.date), try (25...31).map { try date($0) })
        XCTAssertEqual(tomorrow.map(\.strain), [0, 0, 0, nil, 63, 0, nil])
    }

    func testRecoveryTrafficLightUsesInclusiveThresholds() {
        XCTAssertEqual(WeekWidgetSnapshot.recoveryColor(for: 0), .red)
        XCTAssertEqual(WeekWidgetSnapshot.recoveryColor(for: 33), .red)
        XCTAssertEqual(WeekWidgetSnapshot.recoveryColor(for: 34), .yellow)
        XCTAssertEqual(WeekWidgetSnapshot.recoveryColor(for: 66), .yellow)
        XCTAssertEqual(WeekWidgetSnapshot.recoveryColor(for: 67), .green)
        XCTAssertEqual(WeekWidgetSnapshot.recoveryColor(for: 100), .green)
        XCTAssertNil(WeekWidgetSnapshot.recoveryColor(for: nil))
        XCTAssertNil(WeekWidgetSnapshot.recoveryColor(for: -1))
        XCTAssertNil(WeekWidgetSnapshot.recoveryColor(for: 101))
    }

    func testCodableRoundTripPreservesScoresAndGaps() throws {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let snapshot = WeekWidgetSnapshot(measurements: [
            .init(date: date, recovery: 67, strain: 100, sleep: 101)
        ], updatedAt: date, calendar: calendar)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WeekWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.days.last?.recovery, 67)
        XCTAssertEqual(decoded.days.last?.strain, 100)
        XCTAssertNil(decoded.days.last?.sleep)
    }

    func testDecodedScoresOutsideRangeBecomeMissing() throws {
        let data = Data(#"{"date":0,"recovery":-1,"strain":101,"sleep":0}"#.utf8)
        let day = try JSONDecoder().decode(WeekWidgetSnapshot.Day.self, from: data)

        XCTAssertNil(day.recovery)
        XCTAssertNil(day.strain)
        XCTAssertEqual(day.sleep, 0)
    }

    func testStorePublishesAndClearsSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let store = WeekWidgetSnapshotStore(fileURL: directory.appendingPathComponent("week.json"))
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let snapshot = WeekWidgetSnapshot(measurements: [.init(date: date, sleep: 87)],
                                          updatedAt: date, calendar: .current)

        XCTAssertTrue(try store.replace(with: snapshot))
        XCTAssertEqual(store.read(), snapshot)
        XCTAssertFalse(try store.replace(with: snapshot))
        XCTAssertTrue(try store.replace(with: nil))
        XCTAssertNil(store.read())
        XCTAssertFalse(try store.replace(with: nil))
    }
}
