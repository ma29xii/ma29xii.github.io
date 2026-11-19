import Foundation
import UIKit
import XCTest
@testable import Forma

final class AchievementsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }

    func testStepSeriesUsesCalendarDaysAcrossDaylightSavingTime() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22)))
        let days = try (0..<7).map { offset in
            DayMetrics(date: try XCTUnwrap(calendar.startOfDay(offsetBy: offset, from: start)), steps: 8_000)
        }
        let last = try XCTUnwrap(days.last?.date)
        let now = last.addingTimeInterval(12 * 3_600)
        XCTAssertEqual(AchievementEngine.health(days: Array(days.reversed()), ageTrend: nil,
                                                now: now, calendar: calendar)[.steps], last)

        let withGap = days.enumerated().compactMap { $0.offset == 2 ? nil : $0.element }
        XCTAssertNil(AchievementEngine.health(days: withGap, ageTrend: nil, now: now, calendar: calendar)[.steps])
    }

    func testImportedDaysExcludeMissingInvalidDuplicateAndFutureDays() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let days = try (0..<29).map { offset in
            DayMetrics(date: try XCTUnwrap(calendar.startOfDay(offsetBy: offset, from: start)), restingHR: 58)
        }
        let last = try XCTUnwrap(days.last)
        let next = try XCTUnwrap(calendar.startOfDay(offsetBy: 1, from: last.date))
        let tomorrow = try XCTUnwrap(calendar.startOfDay(offsetBy: 1, from: next))
        let now = next.addingTimeInterval(12 * 3_600)
        let extra = [last, DayMetrics(date: next, steps: .infinity), DayMetrics(date: tomorrow, restingHR: 55)]
        XCTAssertNil(AchievementEngine.health(days: days + extra, ageTrend: nil, now: now,
                                              calendar: calendar)[.tracked])
        XCTAssertEqual(AchievementEngine.health(days: days + [DayMetrics(date: next, steps: 0)],
                                                ageTrend: nil, now: now, calendar: calendar)[.tracked], next)
    }

    func testSleepSeriesUsesTheNeedForEachNightAndRequiresSevenCompletedNights() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let days = try (0..<12).map { offset in
            let date = try XCTUnwrap(calendar.startOfDay(offsetBy: offset, from: start))
            let wake = date.addingTimeInterval(7 * 3_600)
            let night = SleepNight(start: wake.addingTimeInterval(-9 * 3_600), end: wake,
                                   segments: [], reportedAsleep: 9 * 3_600)
            return DayMetrics(date: date, activeEnergy: 100, sleep: night)
        }
        let last = try XCTUnwrap(days.last)
        let noon = last.date.addingTimeInterval(12 * 3_600)
        XCTAssertEqual(AchievementEngine.health(days: days, ageTrend: nil, now: noon,
                                                calendar: calendar)[.sleep], last.date)
        XCTAssertNil(AchievementEngine.health(days: days, ageTrend: nil, now: last.date,
                                              calendar: calendar)[.sleep])

        var missingActivity = days
        missingActivity[8].activeEnergy = nil
        XCTAssertNil(AchievementEngine.health(days: missingActivity, ageTrend: nil, now: noon,
                                              calendar: calendar)[.sleep])
    }

    func testTrainingNeedsAnActualImprovementOverAnEarlierSession() {
        let start = Date(timeIntervalSince1970: 10_000)
        let first = AchievementWorkout(start: start, end: start + 600, bests: ["Bankdrücken": 60])
        let level = AchievementWorkout(start: start + 1_200, end: start + 1_800,
                                       bests: ["Bankdrücken": 60, "Kniebeuge": 100])
        let better = AchievementWorkout(start: start + 2_400, end: start + 3_000,
                                        bests: ["Bankdrücken": 61])
        let now = start + 4_000
        XCTAssertNil(AchievementEngine.firstRecord(in: [level, first], now: now))
        XCTAssertNil(AchievementEngine.firstRecord(in: [better, first], now: better.start))
        XCTAssertEqual(AchievementEngine.firstRecord(in: [better, level, first], now: now), better.end)
    }

    func testHealthAgeNeedsAComparableWindowAndHalfAYearDecrease() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let previous = BodyAge.Estimate(date: now - 60 * 86_400, bodyAge: 40, age: 39)
        let lower = BodyAge.Estimate(date: now - 30 * 86_400, bodyAge: 39.5, age: 39.1)
        let almost = BodyAge.Estimate(date: lower.date, bodyAge: 39.6, age: 39.1)
        XCTAssertNil(AchievementEngine.health(days: [], ageTrend: nil, now: now)[.healthAge])
        XCTAssertNil(AchievementEngine.health(days: [], ageTrend: (previous, almost), now: now)[.healthAge])
        XCTAssertNil(AchievementEngine.health(days: [], ageTrend: (lower, previous), now: now)[.healthAge])
        XCTAssertEqual(AchievementEngine.health(days: [], ageTrend: (previous, lower), now: now)[.healthAge], now)
    }

    @MainActor
    func testLedgerKeepsHistoricalUnlocksQuietAndAnnouncesNewUnlocksOncePerScope() throws {
        let suite = "FormaTests.Achievements.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let tracker = AchievementTracker(defaults: defaults)
        let account = AchievementHealthScope(accountID: "account-a")
        let other = AchievementHealthScope(accountID: "account-b")
        let old = try XCTUnwrap(calendar.startOfDay(offsetBy: -3, from: now))
        XCTAssertEqual(tracker.update(scope: account, health: [.sleep: old], record: nil,
                                      now: now, calendar: calendar), [])
        XCTAssertEqual(tracker.update(scope: account, health: [.tracked: old, .steps: now], record: now,
                                      now: now, calendar: calendar), [.steps, .firstRecord])
        let reloaded = AchievementTracker(defaults: defaults)
        XCTAssertEqual(reloaded.update(scope: account, health: [.steps: now], record: now,
                                       now: now, calendar: calendar), [])
        XCTAssertEqual(reloaded.unlocked(scope: account), [.sleep, .steps, .firstRecord, .tracked])
        XCTAssertEqual(reloaded.unlocked(scope: other), [.firstRecord])
        XCTAssertEqual(reloaded.unlocked(scope: nil), [.firstRecord])
    }

    @MainActor
    func testSampleUnlocksStayOutOfTheRealLedger() throws {
        let suite = "FormaTests.Achievements.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = AchievementTracker(defaults: defaults)
        tracker.updateSample(health: [.steps: .now], record: .now)
        XCTAssertEqual(tracker.sample, [.steps, .firstRecord])
        XCTAssertNil(tracker.recentUnlock)
        XCTAssertTrue(AchievementTracker(defaults: defaults).unlocked(scope: nil).isEmpty)
        XCTAssertTrue(defaults.persistentDomain(forName: suite)?.isEmpty ?? true)
    }

    @MainActor
    func testShareWithoutMeasurementsStripsDataBeforeRendering() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let day = DayMetrics(date: date, activeEnergy: 500)
        let today = ShareCardContent.today(DashboardDay(day: day, history: []), isSample: true)
        let session = WorkoutSession(title: "Privater Trainingsname", start: date, end: date + 1_800)
        let training = ShareCardContent.training(session, unit: .kg, isSample: false)
        let result = BodyAge.Result(age: 40, bodyAge: 37.5, recent: nil, previous: nil, factors: [], missing: [],
                                    daysWithData: 180, windowDays: 180, confidence: .high)
        let age = ShareCardContent.healthAge(result, isSample: false)

        XCTAssertEqual(today.display(includeMeasurements: true).metrics.map(\.label), ["Strain"])
        XCTAssertEqual(training.display(includeMeasurements: true).metrics.first?.value, "30 min")
        XCTAssertEqual(age.display(includeMeasurements: true).metrics.first?.value, "37,5 Jahre")
        for content in [today, training, age] {
            XCTAssertTrue(content.hasMeasurements)
            XCTAssertTrue(content.display(includeMeasurements: false).metrics.isEmpty)
            XCTAssertNil(content.display(includeMeasurements: false).date)
        }
        XCTAssertTrue(today.display(includeMeasurements: false).isSample)
    }

    @MainActor
    func testShareExportsPNGAtBothPixelSizes() throws {
        let content = ShareCardContent.today(DashboardDay(day: DayMetrics(date: .now), history: []), isSample: false)
        let display = content.display(includeMeasurements: false)
        for (format, height) in [(ShareCardFormat.story, 1_920), (.square, 1_080)] {
            let card = try XCTUnwrap(RenderedShareCard.make(display: display, format: format))
            XCTAssertEqual(Array(card.transfer.data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
            let pngImage = try XCTUnwrap(UIImage(data: card.transfer.data)?.cgImage)
            XCTAssertEqual(pngImage.width, 1_080)
            XCTAssertEqual(pngImage.height, height)
        }
    }
}
