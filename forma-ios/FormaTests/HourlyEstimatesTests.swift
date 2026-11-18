import XCTest
@testable import Forma

final class HourlyEstimatesTests: XCTestCase {
    func testStepsAloneDoNotProduceStressOrEnergy() throws {
        let start = Date.now.startOfDay
        let hours = [HourlyMetrics(start: start, end: start.adding(minutes: 60), steps: 63)]
        let result = HourlyEstimate.timeline(hours: hours, today: DayMetrics(date: start), history: [])
        let estimate = try XCTUnwrap(result.first)

        XCTAssertNil(estimate.strain)
        XCTAssertNil(estimate.stress)
        XCTAssertNil(estimate.energy)
    }

    func testWorkoutDoesNotCountBeforeItIsFinished() {
        let start = Date.now.startOfDay
        let hours = (0..<2).map { offset in
            HourlyMetrics(start: start.adding(minutes: Double(offset) * 60),
                          end: start.adding(minutes: Double(offset + 1) * 60))
        }
        let workout = WorkoutSummary(name: "Lauf", start: start.adding(minutes: 50), duration: 20 * 60)
        let today = DayMetrics(date: start, workouts: [workout])

        let result = HourlyEstimate.timeline(hours: hours, today: today, history: [])

        XCTAssertEqual(result.map(\.strain), [nil, ScoreEngine.strain(today)])
    }

    func testNoEnergyBeforeSleepEnds() {
        let start = Date.now.startOfDay
        let hours = (0..<2).map { offset in
            HourlyMetrics(start: start.adding(minutes: Double(offset) * 60),
                          end: start.adding(minutes: Double(offset + 1) * 60),
                          activeEnergy: 10, hrv: 55)
        }
        let end = start.adding(minutes: 90)
        let segment = SleepNight.Segment(stage: .core, start: end.adding(minutes: -420), end: end)
        let today = DayMetrics(date: start, sleep: SleepNight(start: segment.start, end: end, segments: [segment]))
        let history = (1...4).map { DayMetrics(date: start.adding(days: -$0), hrv: 50) }

        let result = HourlyEstimate.timeline(hours: hours, today: today, history: history)

        XCTAssertEqual(result.count, 2)
        XCTAssertNil(result.first?.energy)
        XCTAssertNotNil(result.last?.energy)
    }
}
