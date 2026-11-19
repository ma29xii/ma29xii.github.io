import Foundation
import SwiftData
import XCTest
@testable import Forma

final class Runde12DataTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @MainActor
    func testWaterSyncKeepsTwoWidgetGlassesAndManualGlassAtSameTime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WaterWidgetStore(directory: root)
        try store.recordGlass(at: now)
        try store.recordGlass(at: now)
        let events = try store.pendingEntries()

        let container = try ModelContainer(for: FoodWaterEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(FoodWaterEntry(date: now, milliliters: 250))
        try context.save()

        WaterWidgetSync.sync(in: context, enabled: true, store: store, now: now, calendar: .forma)

        let entries = try context.fetch(FetchDescriptor<FoodWaterEntry>())
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.filter { $0.widgetEventID == nil }.count, 1)
        XCTAssertEqual(Set(entries.compactMap(\.widgetEventID)), Set(events.map(\.id)))
        XCTAssertTrue(try store.pendingEntries().isEmpty)
        XCTAssertEqual(try store.progress(at: now, calendar: .forma).milliliters, 750)
    }

    @MainActor
    func testWaterSyncRetriesAfterPublishFailureAndStoreReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let widgetDirectory = root.appendingPathComponent("widget", isDirectory: true)
        let store = WaterWidgetStore(directory: widgetDirectory)
        let progressFile = widgetDirectory.appendingPathComponent("progress.json")
        // Ein Verzeichnis am Dateipfad lässt das Veröffentlichen nach dem SwiftData-Save fehlschlagen.
        try FileManager.default.createDirectory(at: progressFile, withIntermediateDirectories: true)
        try store.recordGlass(at: now)
        let firstEvent = try XCTUnwrap(store.pendingEntries().first)
        let configuration = ModelConfiguration(url: root.appendingPathComponent("water.store"), cloudKitDatabase: .none)

        do {
            let container = try ModelContainer(for: FoodWaterEntry.self, configurations: configuration)
            let context = container.mainContext
            WaterWidgetSync.sync(in: context, enabled: true, store: store, now: now, calendar: .forma)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodWaterEntry>()), 1)
            XCTAssertEqual(try store.pendingEntries(), [firstEvent])
        }

        try FileManager.default.removeItem(at: progressFile)
        try store.recordGlass(at: now)
        let expectedIDs = Set(try store.pendingEntries().map(\.id))
        let container = try ModelContainer(for: FoodWaterEntry.self, configurations: configuration)
        let context = container.mainContext
        let savedEntry = try XCTUnwrap(context.fetch(FetchDescriptor<FoodWaterEntry>()).first)
        XCTAssertEqual(savedEntry.widgetEventID, firstEvent.id)

        WaterWidgetSync.sync(in: context, enabled: true, store: store, now: now, calendar: .forma)

        let entries = try context.fetch(FetchDescriptor<FoodWaterEntry>())
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.compactMap(\.widgetEventID)), expectedIDs)
        XCTAssertTrue(try store.pendingEntries().isEmpty)
        XCTAssertEqual(try store.progress(at: now, calendar: .forma).milliliters, 500)
    }
}

// Runde 11 verwendet weiterhin ihre damaligen Zeitstempel-Fixtures für den gemeinsamen Filter.
extension WaterWidgetSync {
    nonisolated static func missing(_ pending: [WaterWidgetEvent],
                                    existing: [(date: Date, milliliters: Double)]) -> [WaterWidgetEvent] {
        let dates = Set(existing.filter { $0.milliliters == WaterWidgetStore.glassMilliliters }.map(\.date))
        return missing(pending, existing: dates, identifiedBy: \.date)
    }
}
