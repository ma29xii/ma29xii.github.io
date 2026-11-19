import SwiftData
import XCTest
@testable import Forma

final class Runde11WaterSyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testMissingSkipsGlassesThatAreAlreadyStored() {
        let a = WaterWidgetEvent(id: UUID(), date: t0)
        let b = WaterWidgetEvent(id: UUID(), date: t0.addingTimeInterval(60))
        let existing = [(date: t0, milliliters: WaterWidgetStore.glassMilliliters)]
        XCTAssertEqual(WaterWidgetSync.missing([a, b], existing: existing).map(\.id), [b.id])
    }

    func testMissingKeepsGlassWhenSameTimeButOtherAmount() {
        let a = WaterWidgetEvent(id: UUID(), date: t0)
        XCTAssertEqual(WaterWidgetSync.missing([a], existing: [(date: t0, milliliters: 500)]).count, 1)
        XCTAssertTrue(WaterWidgetSync.missing([], existing: []).isEmpty)
    }

    @MainActor
    func testSyncImportsPublishesAndAcknowledges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("water-sync-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WaterWidgetStore(directory: root)
        let calendar = Calendar.forma
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: t0)!
        try store.recordGlass(at: now.addingTimeInterval(-60))
        try store.recordGlass(at: now.addingTimeInterval(-30))

        let container = try ModelContainer(for: FoodWaterEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "water-sync-test-" + UUID().uuidString)!

        WaterWidgetSync.sync(in: context, enabled: true, store: store, now: now, calendar: calendar, defaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodWaterEntry>()), 2)
        XCTAssertTrue(try store.pendingEntries().isEmpty, "Übernommene Gläser sind bestätigt")
        XCTAssertEqual(try store.progress(at: now, calendar: calendar).milliliters, 500, accuracy: 0.001)

        // Zweiter Lauf ohne neue Gläser ändert nichts.
        WaterWidgetSync.sync(in: context, enabled: true, store: store, now: now, calendar: calendar, defaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodWaterEntry>()), 2)
    }

    @MainActor
    func testSyncDoesNothingWhenDisabled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("water-sync-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WaterWidgetStore(directory: root)
        try store.recordGlass(at: t0)
        let container = try ModelContainer(for: FoodWaterEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        WaterWidgetSync.sync(in: container.mainContext, enabled: false, store: store, now: t0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<FoodWaterEntry>()), 0)
        XCTAssertEqual(try store.pendingEntries().count, 1)
    }
}
