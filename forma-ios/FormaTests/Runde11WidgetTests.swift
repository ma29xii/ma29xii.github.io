import Foundation
import XCTest
@testable import Forma

final class Runde11WidgetTests: XCTestCase {
    func testTwoTapsArePersistedAsSeparateGlasses() throws {
        let store = try makeStore()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        try store.recordGlass(at: date)
        try store.recordGlass(at: date)

        let pending = try store.pendingEntries()
        XCTAssertEqual(Set(pending.map(\.id)).count, 2)
        XCTAssertEqual(pending.map(\.date), [date, date])
        XCTAssertEqual(try store.progress(at: date).milliliters, 500)
    }

    func testParallelTapsDoNotOverwriteEachOther() throws {
        let store = try makeStore()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            try? store.recordGlass(at: date)
        }

        XCTAssertEqual(try store.pendingEntries().count, 16)
        XCTAssertEqual(try store.progress(at: date).milliliters, 4_000)
    }

    func testPublishedTotalDoesNotCountImportedGlassesTwice() throws {
        let store = try makeStore()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        try store.recordGlass(at: date)
        let imported = try store.pendingEntries()
        try store.recordGlass(at: date)

        try store.publish(milliliters: 1_250, goalMilliliters: 2_000, including: imported, at: date)
        XCTAssertEqual(try store.progress(at: date).milliliters, 1_500)
        XCTAssertEqual(try store.progress(at: date).fraction, 0.75)
        try store.acknowledge(imported)
        try store.acknowledge(imported)
        XCTAssertEqual(try store.pendingEntries().count, 1)
        XCTAssertEqual(try store.progress(at: date).milliliters, 1_500)
    }

    func testMidnightOnShortDayResetsDisplayButKeepsUnimportedGlasses() throws {
        let store = try makeStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 29)))
        let midnight = start.addingTimeInterval(23 * 3_600)
        let before = midnight.addingTimeInterval(-1)

        try store.publish(milliliters: 800, goalMilliliters: 3_000, including: [], at: before, calendar: calendar)
        try store.recordGlass(at: before)
        try store.recordGlass(at: midnight)

        XCTAssertEqual(try store.progress(at: before, calendar: calendar).milliliters, 1_050)
        let nextDay = try store.progress(at: midnight, calendar: calendar)
        XCTAssertEqual(nextDay.milliliters, 250)
        XCTAssertEqual(nextDay.goalMilliliters, 3_000)
        XCTAssertEqual(try store.pendingEntries().count, 2)
    }

    func testInvalidGoalUsesDefaultAndRingCapsAtOne() throws {
        let store = try makeStore()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        try store.publish(milliliters: 3_000, goalMilliliters: .nan, including: [], at: date)

        let progress = try store.progress(at: date)
        XCTAssertEqual(progress.goalMilliliters, 2_500)
        XCTAssertEqual(progress.milliliters, 3_000)
        XCTAssertEqual(progress.fraction, 1)
    }

    func testMissingAppGroupDoesNotReportASuccessfulWrite() {
        let store = WaterWidgetStore(directory: nil)
        XCTAssertThrowsError(try store.recordGlass())
    }

    private func makeStore() throws -> WaterWidgetStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return WaterWidgetStore(directory: directory.appendingPathComponent("water", isDirectory: true))
    }
}
