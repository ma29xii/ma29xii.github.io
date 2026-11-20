import Foundation
import SwiftUI
import XCTest
@testable import Forma

/// Runde 11 (design-rest): wählbare Designs.
final class Runde11DesignRestTests: XCTestCase {
    func testUnknownOrMissingThemeFallsBackToStandard() {
        XCTAssertEqual(AppTheme.resolve(nil), .standard)
        XCTAssertEqual(AppTheme.resolve(""), .standard)
        XCTAssertEqual(AppTheme.resolve("pink"), .standard)
        XCTAssertEqual(AppTheme.resolve("bordeaux"), .bordeaux)
    }

    func testThemesHaveUniqueNamesAndIdentifiers() {
        XCTAssertEqual(Set(AppTheme.allCases.map(\.title)).count, AppTheme.allCases.count)
        XCTAssertEqual(Set(AppTheme.allCases.map(\.id)).count, AppTheme.allCases.count)
        XCTAssertTrue(AppTheme.allCases.count >= 6, "Standard, Schwarz, Blau, Bordeaux, Verlauf und mindestens eine Mischung")
    }

    func testStandardGlowComesFromDataOthersBringTheirOwn() {
        let green = Theme.recoveryHigh
        XCTAssertTrue(AppTheme.standard.glowLayers(tint: nil).isEmpty)
        XCTAssertEqual(AppTheme.standard.glowLayers(tint: green).count, 1)
        // Schwarz bleibt schwarz, auch mit Datenfarbe.
        XCTAssertTrue(AppTheme.black.glowLayers(tint: green).isEmpty)
        // Blau und Bordeaux nehmen ihre Farbe, nicht die der Daten.
        XCTAssertEqual(AppTheme.blue.glowLayers(tint: green).count, 1)
        XCTAssertEqual(AppTheme.bordeaux.glowLayers(tint: Theme.recoveryLow).count, 1)
        // Der Verlauf aus Blau und Bordeaux hat zwei Scheine.
        XCTAssertEqual(AppTheme.blend.glowLayers(tint: nil).count, 2)
        XCTAssertTrue(AppTheme.blend.glowLayers(tint: nil).allSatisfy { $0.opacity > 0 })
    }

    func testBlackIsPureBlackFromTopToBottom() {
        let black = Color(hex: 0x000000)
        XCTAssertEqual(AppTheme.black.top, black)
        XCTAssertEqual(AppTheme.black.mid, black)
        XCTAssertEqual(AppTheme.black.bottom, black)
    }

    func testNewGradientsRetainRequestedColors() {
        XCTAssertEqual(AppTheme.lagoon.glows.first, Color(hex: 0x4D8EB6))
        XCTAssertEqual(AppTheme.aubergine.glows.last, Color(hex: 0x5C2624))
        XCTAssertEqual(AppTheme.resolve("lagoon"), .lagoon)
        XCTAssertEqual(AppTheme.resolve("aubergine"), .aubergine)
    }

    func testStoreKeepsSelectionAndIgnoresGarbage() throws {
        let suite = "forma.test.theme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(ThemeStore(defaults: defaults).current, .standard)
        let store = ThemeStore(defaults: defaults)
        store.select(.blue, defaults: defaults)
        XCTAssertEqual(store.current, .blue)
        XCTAssertEqual(defaults.string(forKey: ThemeStore.key), "blue")
        XCTAssertEqual(ThemeStore(defaults: defaults).current, .blue)

        defaults.set("kaputt", forKey: ThemeStore.key)
        XCTAssertEqual(ThemeStore(defaults: defaults).current, .standard)
    }
}
