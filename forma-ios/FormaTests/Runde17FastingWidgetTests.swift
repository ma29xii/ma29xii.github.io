import Foundation
import SwiftData
import XCTest
@testable import Forma

final class Runde17FastingWidgetTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testWidgetKeepsStartAndStopUntilTheAppImportsThem() throws {
        let store = try makeStore()
        let end = start.addingTimeInterval(3_600)
        let session = FastingAttributes(start: start, targetHours: 16)

        XCTAssertEqual(try store.state().presentation(at: start), .idle(planHours: 16))
        try store.toggle(at: start)
        XCTAssertEqual(try store.state().active, session)
        try store.toggle(at: end)

        let state = try store.state()
        XCTAssertNil(state.active)
        XCTAssertEqual(state.pending, [.start(session), .end(start: start, at: end)])
    }

    func testPresentationSwitchesAtTheGoal() {
        let session = FastingAttributes(start: start, targetHours: 18)
        let goal = session.timerInterval.upperBound
        let state = FastingWidgetStore.State(planHours: 16, active: session)

        XCTAssertEqual(state.presentation(at: goal.addingTimeInterval(-1)), .countdown(session))
        XCTAssertEqual(state.presentation(at: goal), .elapsed(session))
        XCTAssertEqual(state.presentation(at: goal.addingTimeInterval(3_600)), .elapsed(session))
    }

    func testAnOutdatedStartButtonDoesNotStopTheCurrentFast() throws {
        let store = try makeStore()
        try store.toggle(at: start, expectedActive: false)
        try store.toggle(at: start.addingTimeInterval(1), expectedActive: false)

        let session = FastingAttributes(start: start, targetHours: 16)
        let state = try store.state()
        XCTAssertEqual(state.active, session)
        XCTAssertEqual(state.pending, [.start(session)])
    }

    func testAnOutdatedStopButtonDoesNotEndTheNextFast() throws {
        let store = try makeStore()
        let secondStart = start.addingTimeInterval(600)
        try store.toggle(at: start)
        try store.toggle(at: start.addingTimeInterval(300))
        try store.toggle(at: secondStart)
        let before = try store.state()

        XCTAssertNil(try store.toggle(at: secondStart.addingTimeInterval(60), expectedActive: true,
                                      expectedStart: start))
        XCTAssertEqual(try store.state(), before)
    }

    func testMatchingStopReturnsThePersistedEndAndDoesNotRestartOnRetry() throws {
        let store = try makeStore()
        try store.toggle(at: start)
        let end = start.addingTimeInterval(300)

        XCTAssertEqual(try store.toggle(at: end, expectedActive: true, expectedStart: start),
                       .end(start: start, at: end))
        let stopped = try store.state()
        XCTAssertNil(stopped.active)
        XCTAssertEqual(stopped.pending.last, .end(start: start, at: end))
        XCTAssertNil(try store.toggle(at: end, expectedActive: true, expectedStart: start))
        XCTAssertEqual(try store.state(), stopped)
    }

    func testLegacyStopButtonWithoutAStartCannotEndTheCurrentFast() throws {
        let store = try makeStore()
        try store.toggle(at: start)
        let before = try store.state()

        try store.toggle(at: start.addingTimeInterval(300), expectedActive: true)

        XCTAssertEqual(try store.state(), before)
    }

    func testAFailedTransferLeavesEventsPending() throws {
        struct TransferFailure: Error {}
        let store = try makeStore()
        try store.toggle(at: start)
        let pending = try store.state()

        XCTAssertThrowsError(try store.update { state in
            state.pending.removeAll()
            throw TransferFailure()
        })

        XCTAssertEqual(try store.state(), pending)
    }

    @MainActor
    func testImportAndRetryKeepOneCompletedFastAndTheNextActiveFast() throws {
        let store = try makeStore()
        let container = try ModelContainer(for: FoodFast.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let end = start.addingTimeInterval(3_600)
        let next = end.addingTimeInterval(300)
        try store.toggle(at: start)
        try store.toggle(at: end)
        try store.toggle(at: next)
        let pending = try store.state()

        try FastingWidgetSync.sync(in: context, planHours: 18, store: store)
        XCTAssertTrue(try store.state().pending.isEmpty)
        // Ein Absturz zwischen SwiftData-Save und Veröffentlichung lässt die Ereignisse erneut anliegen.
        try store.update { $0 = pending }
        try FastingWidgetSync.sync(in: context, planHours: 18, store: store)

        let fasts = try context.fetch(FetchDescriptor<FoodFast>(sortBy: [SortDescriptor(\.start)]))
        XCTAssertEqual(fasts.map(\.start), [start, next])
        XCTAssertEqual(fasts.map(\.end), [end, nil])
        let published = try store.state()
        XCTAssertEqual(published.active, FastingAttributes(start: next, targetHours: 16))
        XCTAssertEqual(published.planHours, 18)
        XCTAssertTrue(published.pending.isEmpty)
    }

    @MainActor
    func testWidgetCanEndAFastStartedInTheApp() throws {
        let store = try makeStore()
        let container = try ModelContainer(for: FoodFast.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let session = FastingAttributes(start: start, targetHours: 20)
        try FastingWidgetSync.sync(in: context, planHours: 20, action: .start(session), store: store)
        XCTAssertEqual(try store.state().active, session)

        let end = start.addingTimeInterval(300)
        try store.toggle(at: end)
        try FastingWidgetSync.sync(in: context, planHours: 20, store: store)

        let fasts = try context.fetch(FetchDescriptor<FoodFast>())
        XCTAssertEqual(fasts.count, 1)
        XCTAssertEqual(fasts.first?.end, end)
        XCTAssertEqual(try store.state().presentation(at: end), .idle(planHours: 20))
    }

    private func makeStore() throws -> FastingWidgetStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return FastingWidgetStore(directory: directory)
    }
}
