import XCTest
@testable import Forma

final class R23WhatIfTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)

    func testScenarioMatchesBodyAgeForTheSameAverages() throws {
        let days = makeDays()
        let baseline = try evaluate(days)
        let scenario: [BodyAge.AdjustableFactor: Double] = [.sleep: 60, .steps: 2_000, .strength: 20, .restingHR: -5]
        let expected = try evaluate(makeDays(sleepHours: 7.25, steps: 8_000, restingHR: 65), strength: 30)

        XCTAssertEqual(BodyAge.projectedAge(baseline, changes: [:]), baseline.bodyAge)
        XCTAssertEqual(BodyAge.projectedAge(baseline, changes: scenario), expected.bodyAge, accuracy: 0.000_001)
    }

    func testScenarioKeepsMissingFactorsAndClampsTrainingAtZero() throws {
        let days = makeDays().map { day in
            var day = day
            day.steps = nil
            return day
        }
        let baseline = try evaluate(days)
        XCTAssertEqual(BodyAge.projectedAge(baseline, changes: [.steps: 5_000]), baseline.bodyAge, accuracy: 0.000_001)
        let expected = try evaluate(days, strength: 0)
        XCTAssertEqual(BodyAge.projectedAge(baseline, changes: [.strength: -120]), expected.bodyAge, accuracy: 0.000_001)
    }

    private func makeDays(sleepHours: Double = 6.25, steps: Double = 6_000, restingHR: Double = 70) -> [DayMetrics] {
        (0..<30).reversed().map { offset in
            let date = now.startOfDay.adding(days: -offset)
            let sleep = sleepHours * 3_600
            return DayMetrics(date: date, restingHR: restingHR, steps: steps,
                              sleep: SleepNight(start: date - sleep, end: date, segments: [], reportedAsleep: sleep))
        }
    }

    private func evaluate(_ days: [DayMetrics], strength: Double = 10) throws -> BodyAge.Result {
        let person = PersonInfo(birthDate: now - 35 * 365 * 86_400, sex: .male, origin: .manual)
        let outcome = BodyAge.evaluate(days: days, person: person, strength: .init(perWeek: strength, recentPerWeek: 0), now: now)
        let result: BodyAge.Result? = if case .ready(let result) = outcome { result } else { nil }
        return try XCTUnwrap(result)
    }
}
