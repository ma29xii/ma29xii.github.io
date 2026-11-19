import SwiftData
import XCTest
@testable import Forma

final class SampleDataTests: XCTestCase {
    private let now = Calendar.forma.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 18))!

    func testHealthAgeIsYoungerAndPaceFitsScale() throws {
        for end in [now, now.adding(days: -120), now.adding(days: 120)] {
            let days = SampleData.days(endingAt: end)
            let person = SampleData.person(at: end)
            guard case .ready(let result) = HealthAgeTrend.outcome(days: days, person: person, sessions: [], now: end) else {
                return XCTFail("Health Age muss in der Vorschau verfügbar sein")
            }
            let pace = try XCTUnwrap(result.pace)
            XCTAssertTrue((0.7...0.9).contains(pace), "Alterungstempo: \(pace)")
            XCTAssertTrue((2...6).contains(-result.difference), "Altersvorsprung: \(-result.difference)")
            XCTAssertEqual(result.factors.count, 5)
            XCTAssertNotNil(result.trend)
        }
        let trend = HealthAgeTrend.points(days: SampleData.days(endingAt: now), person: SampleData.person(at: now),
                                          sessions: [], now: now)
        XCTAssertGreaterThanOrEqual(trend.count, 20)
    }

    func testPreviewIsDeterministicIncludingWorkoutIdentities() {
        let full = SampleData.days(endingAt: now)
        XCTAssertEqual(full, SampleData.days(endingAt: now))
        XCTAssertEqual(Array(full.suffix(30)), SampleData.days(count: 30, endingAt: now))
    }

    func testTodayHasBiomarkersSleepPhasesAndHourlyEstimates() throws {
        let days = SampleData.days(endingAt: now)
        let today = try XCTUnwrap(days.last)
        let history = Array(days.dropLast())
        let snapshot = DashboardDay(day: today, history: history)
        XCTAssertNotNil(snapshot.recovery)
        XCTAssertNotNil(snapshot.sleepScore)
        XCTAssertNotNil(snapshot.strain)
        let night = try XCTUnwrap(today.sleep)
        XCTAssertEqual(Set(night.recordedStages), [.core, .deep, .rem, .awake])
        for kind in MetricKind.allCases {
            let biomarker = BiomarkerComparison.evaluate(kind, days: days, today: now)
            XCTAssertNotNil(biomarker.latest, kind.rawValue)
        }
        let vitals = NightVitals(day: today, history: history)
        XCTAssertTrue(vitals.readings.allSatisfy { $0.value != nil && $0.baseline != nil })

        let timeline = HourlyEstimate.timeline(hours: HourlyMetrics.samples(for: today), today: today, history: snapshot.history)
        XCTAssertGreaterThanOrEqual(timeline.compactMap(\.stress).count, 8)
        XCTAssertGreaterThanOrEqual(timeline.compactMap(\.energy).count, 8)
        XCTAssertGreaterThan(Set(timeline.compactMap(\.stress)).count, 1)
        XCTAssertGreaterThan(Set(timeline.compactMap(\.energy)).count, 1)
    }

    func testHistoryPopulatesTrendsWeeklyRecapAndAchievements() throws {
        let days = SampleData.days(endingAt: now)
        let history = InsightHistory(days)
        let end = now.startOfDay.adding(days: -1)
        let snapshots = days.suffix(30).map { DashboardDay(day: $0, history: history.prior(to: $0.date)) }
        for values in [snapshots.compactMap(\.recovery), snapshots.compactMap(\.sleepScore), snapshots.compactMap(\.strain)] {
            XCTAssertEqual(values.count, 30)
            XCTAssertGreaterThanOrEqual((values.max() ?? 0) - (values.min() ?? 0), 15)
        }
        let path = StrainInsight.path(endingAt: end, history: history)
        XCTAssertEqual(path.compactMap(\.value).count, 28)
        XCTAssertGreaterThan(Set(path.compactMap { $0.value?.short.mean }).count, 1)
        XCTAssertTrue(StressInsight.trend(endingAt: end, history: history).allSatisfy { $0.value != nil })
        let consistency = SleepConsistency(endingAt: end, history: history)
        XCTAssertEqual(consistency.measured, 14)
        XCTAssertTrue((1...99).contains(try XCTUnwrap(consistency.percent)))

        let period = try XCTUnwrap(WeeklyInsight.period(at: now))
        let rows = WeeklyInsight.rows(period: period, history: history)
        XCTAssertEqual(rows.count, WeeklyInsight.Metric.allCases.count)
        XCTAssertTrue(rows.allSatisfy { $0.current?.count == period.dayCount && $0.previous?.count == period.dayCount })
        let earned = AchievementEngine.health(days: days, ageTrend: nil, now: now)
        XCTAssertNotNil(earned[.steps])
        XCTAssertNotNil(earned[.sleep])
        XCTAssertNotNil(earned[.tracked])
    }

    @MainActor
    func testTrainingShowsAtLeastFourWeeksAndAnEarnedRecord() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, SetRecord.self, configurations: configuration)
        let context = container.mainContext
        SampleData.seedWorkouts(SampleData.days(endingAt: now), in: context)
        let workouts = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.start)]))
        let first = try XCTUnwrap(workouts.first)
        let latest = try XCTUnwrap(workouts.last)
        XCTAssertGreaterThanOrEqual(latest.start, first.start.adding(days: 28))
        XCTAssertEqual(Set(workouts.map(\.title)), ["Push", "Pull", "Beine"])
        let exercise = "Bankdrücken"
        let bench = workouts.map { $0.bestOneRepMax(for: exercise) }.filter { $0 > 0 }
        XCTAssertGreaterThanOrEqual(Set(bench).count, 3)
        XCTAssertGreaterThan(try XCTUnwrap(bench.last), try XCTUnwrap(bench.first))

        let history = workouts.map { workout in
            AchievementWorkout(start: workout.start, end: workout.end,
                               bests: Dictionary(uniqueKeysWithValues: workout.exerciseNames.map {
                                   ($0, workout.bestOneRepMax(for: $0))
                               }))
        }
        XCTAssertNotNil(AchievementEngine.firstRecord(in: history, now: now))
    }
}
