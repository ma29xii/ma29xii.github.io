import XCTest
@testable import Forma

final class HabitExperimentTests: XCTestCase {
    private let calendar = Calendar.forma
    private var start: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000)) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    func testComparisonNeedsFourDaysPerGroup() {
        var answers: [Date: Bool] = [:]
        var values: [Date: Double] = [:]
        for offset in 0..<7 {
            answers[day(offset)] = offset < 3   // 3 mit, 4 ohne
            values[day(offset)] = 50
        }
        let result = ExperimentComparison.compare(answers: answers, values: values, calendar: calendar)
        XCTAssertEqual(result.withCount, 3)
        XCTAssertEqual(result.withoutCount, 4)
        XCTAssertNil(result.withMean)
        XCTAssertEqual(result.withoutMean, 50)
        XCTAssertFalse(result.isConclusive)
        XCTAssertNil(result.difference)
    }

    func testComparisonAveragesOnlyDaysWithAnswerAndMeasurement() throws {
        var answers: [Date: Bool] = [:]
        var values: [Date: Double] = [:]
        for offset in 0..<14 {
            answers[day(offset)] = offset.isMultiple(of: 2)
            values[day(offset)] = offset.isMultiple(of: 2) ? 60 : 70
        }
        values[day(0)] = nil            // mit, aber ohne Messung
        values[day(1)] = .nan           // ungültig
        values[day(20)] = 10            // außerhalb des Experiments, ohne Antwort
        let result = ExperimentComparison.compare(answers: answers, values: values, calendar: calendar)
        XCTAssertEqual(result.withCount, 6)
        XCTAssertEqual(result.withoutCount, 6)
        XCTAssertEqual(try XCTUnwrap(result.difference), -10, accuracy: 0.0001)
    }

    func testExperimentDaysAndCompletion() {
        var experiment = HabitExperiment(habit: .alcohol, start: day(0).addingTimeInterval(9 * 3600), calendar: calendar)
        XCTAssertEqual(experiment.start, day(0))
        XCTAssertEqual(experiment.dayIndex(of: day(13), calendar: calendar), 13)
        XCTAssertNil(experiment.dayIndex(of: day(14), calendar: calendar))
        XCTAssertNil(experiment.dayIndex(of: day(-1), calendar: calendar))
        XCTAssertEqual(experiment.elapsedDays(now: day(5), calendar: calendar), 6)
        XCTAssertEqual(experiment.elapsedDays(now: day(40), calendar: calendar), 14)
        XCTAssertFalse(experiment.isComplete(now: day(13), calendar: calendar))
        XCTAssertTrue(experiment.isComplete(now: day(14), calendar: calendar))
        experiment.answers[2] = true
        XCTAssertEqual(experiment.answersByDate(calendar: calendar), [day(2): true])
    }

    func testStoreRoundTripsAndFinishes() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "HabitExperimentTests"))
        defaults.removePersistentDomain(forName: "HabitExperimentTests")
        var store = ExperimentStore()
        var experiment = HabitExperiment(habit: .magnesium, start: day(0), calendar: calendar)
        experiment.answers = [0: true, 1: false]
        store.current = experiment
        store.save(isSample: false, defaults: defaults)
        XCTAssertEqual(ExperimentStore.load(isSample: false, defaults: defaults), store)
        XCTAssertNil(ExperimentStore.load(isSample: true, defaults: defaults).current)

        store.finishCurrent(now: day(14))
        XCTAssertNil(store.current)
        XCTAssertEqual(store.past.first?.answers, [0: true, 1: false])
        XCTAssertEqual(store.past.first?.ended, day(14))
    }

    func testValuesReadHRVAndSleepFromDays() {
        var first = DayMetrics(date: day(0))
        first.hrv = 48
        let second = DayMetrics(date: day(1))
        let values = ExperimentComparison.values(for: .hrv, dates: [day(0), day(1), day(5)], days: [first, second],
                                                 calendar: calendar)
        XCTAssertEqual(values, [day(0): 48])
        XCTAssertTrue(ExperimentComparison.values(for: .sleep, dates: [day(0)], days: [first], calendar: calendar).isEmpty)
    }
}
