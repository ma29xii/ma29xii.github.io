import SwiftUI
import UIKit
import XCTest
@testable import Forma

final class F5WidgetsTests: XCTestCase {
    private func berlin() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }

    private func date(_ day: Int, hour: Int, minute: Int = 0, in calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)))
    }

    // MARK: Gültigkeit und Neuladen

    func testSnapshotStaysVisibleAllDayAndReloadsEveryHalfHour() throws {
        let calendar = berlin()
        let morning = try date(19, hour: 7, minute: 30, in: calendar)
        let snapshot = try XCTUnwrap(WidgetSnapshot(recovery: 81, strain: 12, sleep: 77,
                                                    updatedAt: morning, day: morning, calendar: calendar))
        // Mittags und abends noch gültig – kein Leerlauf nach 15 Minuten.
        XCTAssertTrue(snapshot.isCurrent(at: try date(19, hour: 12, in: calendar), calendar: calendar))
        XCTAssertTrue(snapshot.isCurrent(at: try date(19, hour: 23, minute: 59, in: calendar), calendar: calendar))
        XCTAssertEqual(snapshot.nextReload(after: morning, calendar: calendar), morning + 1800)
    }

    func testReloadNeverLiesBeyondDayEnd() throws {
        let calendar = berlin()
        let late = try date(19, hour: 23, minute: 50, in: calendar)
        let midnight = try date(20, hour: 0, in: calendar)
        let snapshot = try XCTUnwrap(WidgetSnapshot(recovery: 40, strain: nil, sleep: nil,
                                                    updatedAt: late, day: late, calendar: calendar))
        XCTAssertEqual(snapshot.nextReload(after: late, calendar: calendar), midnight)
        XCTAssertFalse(snapshot.isCurrent(at: midnight, calendar: calendar))
    }

    func testReloadIsShortenedOnShortDSTDay() throws {
        let calendar = berlin()
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 29)))
        let snapshot = try XCTUnwrap(WidgetSnapshot(recovery: 71, strain: nil, sleep: nil,
                                                    updatedAt: start, day: start, calendar: calendar))
        let nearEnd = snapshot.validUntil.addingTimeInterval(-60)
        XCTAssertEqual(snapshot.nextReload(after: nearEnd, calendar: calendar), snapshot.validUntil)
    }

    func testSnapshotFromYesterdayIsNotCurrent() throws {
        let calendar = berlin()
        let yesterday = try date(18, hour: 20, in: calendar)
        let snapshot = try XCTUnwrap(WidgetSnapshot(recovery: 60, strain: 30, sleep: 70,
                                                    updatedAt: yesterday, day: yesterday, calendar: calendar))
        XCTAssertFalse(snapshot.isCurrent(at: try date(19, hour: 8, in: calendar), calendar: calendar))
    }

    // MARK: Designs

    func testThemeCountAndStableRawValues() {
        XCTAssertGreaterThanOrEqual(AppTheme.allCases.count, 17)
        for raw in Self.added {
            XCTAssertEqual(AppTheme.resolve(raw).rawValue, raw)
        }
    }

    func testAllThemesKeepTextAndAccentReadable() throws {
        for theme in AppTheme.allCases {
            let raised = Self.luminance(UIColor(theme.cardRaised))
            XCTAssertGreaterThanOrEqual(Self.contrast(1, raised), 7, "Weißer Text auf \(theme.title)")
            // Ältere Designs (Blau, Bordeaux …) bleiben unverändert; die neuen müssen den Akzent AA-lesbar halten.
            if Self.added.contains(theme.rawValue) {
                XCTAssertGreaterThanOrEqual(Self.contrast(Self.luminance(UIColor(theme.accent)), raised), 4.5,
                                            "Akzent auf \(theme.title)")
            }
            XCTAssertLessThan(Self.luminance(UIColor(theme.top)), 0.04, "Hintergrund \(theme.title) bleibt dunkel")
        }
    }

    private static let added = ["midnight", "sand", "graphite", "ocean", "rose", "olive", "sunset", "aurora"]

    private static func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
