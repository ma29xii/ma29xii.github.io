import SwiftUI
import XCTest
@testable import Forma

/// F7-09: neue Designs, eigene Akzent- und Ringfarben, Farben für die Widgets.
final class F7ThemeTests: XCTestCase {
    private let newThemes: [AppTheme] = [.neonLime, .electric, .blaze, .synthwave, .toxic, .coral, .gold, .magenta, .ice]

    private func suite() throws -> (UserDefaults, () -> Void) {
        let name = "forma.test.f7theme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    // MARK: Farbwahl

    func testDefaultColorsMatchStandardTheme() throws {
        let (defaults, cleanup) = try suite()
        defer { cleanup() }
        let store = ThemeStore(defaults: defaults)
        XCTAssertTrue(store.overrides.isEmpty)
        XCTAssertEqual(ThemeOverrides.hex(of: store.strain), 0x0093E7)
        XCTAssertEqual(ThemeOverrides.hex(of: store.sleep), 0x8E8CFF)
        XCTAssertEqual(ThemeOverrides.hex(of: store.accent), 0x34D26B)
        XCTAssertEqual(store.palette, .standard)
    }

    func testSavedChoiceSurvivesNewStoreAndBeatsTheme() throws {
        let (defaults, cleanup) = try suite()
        defer { cleanup() }
        let store = ThemeStore(defaults: defaults)
        store.select(.gold)
        XCTAssertEqual(ThemeOverrides.hex(of: store.accent), AppTheme.gold.accentHex)
        store.setColors { $0.accent = 0xFF3DAA; $0.strain = 0x00E5FF }

        let reloaded = ThemeStore(defaults: defaults)
        XCTAssertEqual(reloaded.current, .gold)
        XCTAssertEqual(ThemeOverrides.hex(of: reloaded.accent), 0xFF3DAA)
        XCTAssertEqual(ThemeOverrides.hex(of: reloaded.strain), 0x00E5FF)
        XCTAssertEqual(ThemeOverrides.hex(of: reloaded.sleep), 0x8E8CFF, "nicht gewählt = Standard")
    }

    func testResetRestoresDefaultsAndRemovesKeys() throws {
        let (defaults, cleanup) = try suite()
        defer { cleanup() }
        let store = ThemeStore(defaults: defaults)
        store.setColors { $0.accent = 0xFF3DAA; $0.strain = 0x00E5FF; $0.sleep = 0xFFC93C }
        store.resetColors()
        XCTAssertTrue(store.overrides.isEmpty)
        XCTAssertEqual(ThemeOverrides.hex(of: store.strain), 0x0093E7)
        XCTAssertNil(defaults.object(forKey: ThemeOverrides.accentKey))
        XCTAssertNil(defaults.object(forKey: ThemeOverrides.strainKey))
        XCTAssertNil(defaults.object(forKey: ThemeOverrides.sleepKey))
        XCTAssertTrue(ThemeStore(defaults: defaults).overrides.isEmpty)
    }

    func testGarbageInDefaultsIsIgnored() throws {
        let (defaults, cleanup) = try suite()
        defer { cleanup() }
        defaults.set(-5, forKey: ThemeOverrides.accentKey)
        defaults.set(0x1_000_000, forKey: ThemeOverrides.strainKey)
        defaults.set("rot", forKey: ThemeOverrides.sleepKey)
        XCTAssertTrue(ThemeStore(defaults: defaults).overrides.isEmpty)
    }

    func testWidgetPaletteFollowsThemeAndChoice() throws {
        let (defaults, cleanup) = try suite()
        defer { cleanup() }
        let (group, cleanupGroup) = try suite()
        defer { cleanupGroup() }
        XCTAssertEqual(WidgetPalette.load(from: group), .standard)

        let store = ThemeStore(defaults: defaults, widgetDefaults: group)
        store.select(.neonLime)
        XCTAssertEqual(WidgetPalette.load(from: group).accent, AppTheme.neonLime.accentHex)
        store.setColors { $0.sleep = 0xFFC93C }
        XCTAssertEqual(WidgetPalette.load(from: group).sleep, 0xFFC93C)
        XCTAssertEqual(WidgetPalette.load(from: group).accent, AppTheme.neonLime.accentHex)
        store.resetColors()
        XCTAssertEqual(WidgetPalette.load(from: group).sleep, 0x8E8CFF)
    }

    // MARK: Kontrast

    func testNewThemesAreRegisteredWithTitlesAndUniqueRawValues() {
        XCTAssertGreaterThanOrEqual(newThemes.count, 6)
        for theme in newThemes {
            XCTAssertTrue(AppTheme.allCases.contains(theme))
            XCTAssertFalse(theme.title.isEmpty)
            XCTAssertEqual(AppTheme.resolve(theme.rawValue), theme)
        }
        XCTAssertEqual(Set(AppTheme.allCases.map(\.rawValue)).count, AppTheme.allCases.count)
    }

    func testNewThemesKeepTextAndAccentReadable() {
        let primary: UInt32 = 0xF5F5F7, secondary: UInt32 = 0x9C9DA1
        for theme in newThemes {
            for surface in [theme.card, theme.cardRaised, theme.bottom] {
                let hex = ThemeOverrides.hex(of: surface)
                XCTAssertGreaterThanOrEqual(ThemeOverrides.contrast(primary, hex), 7, "\(theme) Text")
                XCTAssertGreaterThanOrEqual(ThemeOverrides.contrast(secondary, hex), 4.5, "\(theme) Nebentext")
                XCTAssertGreaterThanOrEqual(ThemeOverrides.contrast(theme.accentHex, hex), 4.5, "\(theme) Akzent")
            }
        }
    }

    func testPaletteSwatchesAreReadableOnStandardCard() {
        let card = ThemeOverrides.hex(of: AppTheme.standard.card)
        for swatch in ThemeOverrides.palette {
            XCTAssertGreaterThanOrEqual(ThemeOverrides.contrast(swatch, card), 4.5, String(format: "%06X", swatch))
        }
    }

    func testContrastHelperKnownValues() {
        XCTAssertEqual(ThemeOverrides.contrast(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(ThemeOverrides.contrast(0x777777, 0x777777), 1, accuracy: 0.001)
    }

    // MARK: Tagesstand für Widgets

    func testDaySnapshotDecodesOlderFileAndDropsInvalidValues() throws {
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let old = #"{"updatedAt": 800000100, "day": 800000000, "steps": 4200}"#
        let decoded = try JSONDecoder().decode(DayWidgetSnapshot.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.steps, 4200)
        XCTAssertNil(decoded.healthAge)
        XCTAssertNil(decoded.signalTitles)

        let bad = DayWidgetSnapshot(updatedAt: day, day: day, healthAge: .nan, steps: -3, stepGoal: 0, sleepScore: 400)
        XCTAssertFalse(bad.hasValues)
        XCTAssertEqual(bad.stepFraction, 0)

        let good = DayWidgetSnapshot(updatedAt: day, day: day, healthAge: 31.4, chronologicalAge: 34,
                                     steps: 15_000, stepGoal: 10_000)
        XCTAssertEqual(good.stepFraction, 1)
        XCTAssertEqual(try XCTUnwrap(good.healthAgeDifference), -2.6, accuracy: 0.001)
        XCTAssertEqual(try JSONDecoder().decode(DayWidgetSnapshot.self, from: JSONEncoder().encode(good)), good)
    }

    func testDaySnapshotIsOnlyCurrentOnItsOwnDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 7)))
        let snapshot = DayWidgetSnapshot(updatedAt: morning, day: calendar.startOfDay(for: morning), steps: 100)
        XCTAssertTrue(snapshot.isCurrent(at: morning.addingTimeInterval(14 * 3_600), calendar: calendar))
        XCTAssertFalse(snapshot.isCurrent(at: morning.addingTimeInterval(20 * 3_600), calendar: calendar))
    }
}
