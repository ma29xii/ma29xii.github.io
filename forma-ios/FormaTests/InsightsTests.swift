import XCTest
@testable import Forma

final class InsightsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ day: Int, hour: Int = 0, minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func night(_ day: Int, startHour: Int = 23, startMinute: Int = 45, wakeHour: Int = 7) -> SleepNight {
        let startDay = startHour >= 12 ? day - 1 : day
        return SleepNight(start: date(startDay, hour: startHour, minute: startMinute), end: date(day, hour: wakeHour),
                          segments: [], reportedAsleep: 6 * 3600)
    }

    func testNightMarksTwoOutliersFromSevenPriorNights() {
        let days = (8...14).map { DayMetrics(date: date($0), hrv: 55, spo2: 98,
                                             sleep: night($0), skinTemperature: 34) }
        var current = DayMetrics(date: date(15), hrv: 55, spo2: 92, sleep: night(15), skinTemperature: 35)
        let check = NightVitals(day: current, history: days, calendar: calendar)
        XCTAssertTrue(check.isMarked)
        XCTAssertEqual(check.outliers, [.spo2, .skinTemperature])
        XCTAssertFalse(NightVitals(day: current, history: Array(days.dropFirst()) + [current], calendar: calendar).isMarked)
        current.sleep = nil
        XCTAssertFalse(NightVitals(day: current, history: days, calendar: calendar).isMarked)
        current.sleep = night(15)
        current.skinTemperature = .nan
        XCTAssertEqual(NightVitals(day: current, history: days, calendar: calendar).outliers, [.spo2])
        XCTAssertFalse(NightVitals(day: current, history: days, calendar: calendar).isMarked)
    }

    func testNightDoesNotBorrowTemperatureBaselineAcrossDevices() {
        let old = GoogleMetricOrigin(family: .fitbit, device: "A")
        let new = GoogleMetricOrigin(family: .fitbit, device: "B")
        let past = (8...14).map { DayMetrics(date: date($0), sleep: night($0), skinTemperature: 34,
                                             origins: [.skinTemperature: [old]]) }
        let day = DayMetrics(date: date(15), sleep: night(15), skinTemperature: 36,
                             origins: [.skinTemperature: [new]])
        XCTAssertNil(NightVitals(day: day, history: past, calendar: calendar).readings.last?.baseline)
    }

    func testStrainComparesMeasuredDaysAndPreservesGapAndZero() throws {
        let anchor = date(28)
        let days = (1...28).filter { $0 != 26 }.map { day in
            DayMetrics(date: date(day), activeEnergy: day > 21 ? 1100 : 0)
        }
        let history = InsightHistory(days, calendar: calendar)
        let path = StrainInsight.path(endingAt: anchor, history: history)
        let latest = try XCTUnwrap(path.last?.value)
        XCTAssertEqual(latest.short.count, 6)
        XCTAssertEqual(latest.long.count, 27)
        XCTAssertEqual(latest.short.mean, 63)
        XCTAssertEqual(latest.long.mean, 63.0 * 6 / 27, accuracy: 0.001)
        XCTAssertEqual(latest.state, .tooMuch)
        XCTAssertNil(path.first { $0.date == date(26) }?.value)
        XCTAssertNil(StrainInsight.path(endingAt: anchor, history: InsightHistory(Array(days.suffix(7)), calendar: calendar)).last?.value)
        XCTAssertEqual(StrainInsight.state(short: 44, long: 40), .hold)
        XCTAssertEqual(StrainInsight.state(short: 50, long: 40), .build)
        XCTAssertEqual(StrainInsight.state(short: 0, long: 0), .hold)
    }

    func testSleepConsistencyWrapsMidnightAndUsesBothTimes() {
        let days = [DayMetrics(date: date(12), sleep: night(12)),
                    DayMetrics(date: date(13), sleep: night(13, startHour: 0, startMinute: 15, wakeHour: 8)),
                    DayMetrics(date: date(14), sleep: night(14, startHour: 0, startMinute: 20)),
                    DayMetrics(date: date(15), sleep: night(15, wakeHour: 10))]
        let result = SleepConsistency(endingAt: date(15), history: InsightHistory(days, calendar: calendar))
        XCTAssertEqual(result.nights.count, 14)
        XCTAssertEqual(result.nights.first?.date, date(2))
        XCTAssertNil(result.nights.first?.value)
        XCTAssertEqual(result.measured, 4)
        XCTAssertEqual(result.percent, 75)
        XCTAssertNil(SleepConsistency(endingAt: date(15), history: InsightHistory(Array(days.prefix(3)), calendar: calendar)).percent)
    }

    func testWeeklyVisibilityAndMatchedDaysAcrossSundayMidnight() throws {
        let sunday = date(22, hour: 18)
        let monday = date(23)
        XCTAssertNil(WeeklyInsight.period(at: date(22, hour: 17, minute: 59), calendar: calendar))
        XCTAssertNil(WeeklyInsight.period(at: date(23, hour: 12), calendar: calendar))
        XCTAssertNotNil(WeeklyInsight.period(at: date(23, hour: 11, minute: 59), calendar: calendar))
        let preview = try XCTUnwrap(WeeklyInsight.period(at: sunday, calendar: calendar))
        let final = try XCTUnwrap(WeeklyInsight.period(at: monday, calendar: calendar))
        XCTAssertEqual(preview.currentStart, date(16))
        XCTAssertEqual(preview.previousStart, date(9))
        XCTAssertEqual(preview.dayCount, 6)
        XCTAssertEqual(final.dayCount, 7)
        let days = [DayMetrics(date: date(9), steps: 0), DayMetrics(date: date(15), steps: 600),
                    DayMetrics(date: date(16), steps: 200), DayMetrics(date: date(22), steps: 800),
                    DayMetrics(date: date(23), steps: 9000)]
        let history = InsightHistory(days, calendar: calendar)
        let draft = try XCTUnwrap(WeeklyInsight.rows(period: preview, history: history).first { $0.metric == .steps })
        let complete = try XCTUnwrap(WeeklyInsight.rows(period: final, history: history).first { $0.metric == .steps })
        XCTAssertEqual(draft.current?.mean, 200)
        XCTAssertEqual(draft.previous?.mean, 0)
        XCTAssertEqual(complete.current?.mean, 500)
        XCTAssertEqual(complete.previous?.mean, 300)
        XCTAssertEqual(complete.current?.count, 2)
        XCTAssertNil(WeeklyInsight.rows(period: final, history: history).first { $0.metric == .hrv }?.current)
    }

    func testSundayWindowUsesCivilTimeDuringClockChange() throws {
        let preview = try XCTUnwrap(WeeklyInsight.period(at: date(25, hour: 18, month: 10), calendar: calendar))
        XCTAssertEqual(preview.currentStart, date(19, month: 10))
        XCTAssertEqual(preview.dayCount, 6)
        XCTAssertNil(WeeklyInsight.period(at: date(26, hour: 12, month: 10), calendar: calendar))
    }

    func testWeeklyHRVLeavesIncompatiblePreviousSourceEmpty() throws {
        let period = try XCTUnwrap(WeeklyInsight.period(at: date(23), calendar: calendar))
        let old = GoogleMetricOrigin(family: .fitbit, device: "A")
        let new = GoogleMetricOrigin(family: .fitbit, device: "B")
        let days = [DayMetrics(date: date(15), hrv: 60, origins: [.hrv: [old]]),
                    DayMetrics(date: date(22), hrv: 54, origins: [.hrv: [new]])]
        let history = InsightHistory(days, calendar: calendar)
        let hrv = try XCTUnwrap(WeeklyInsight.rows(period: period, history: history).first { $0.metric == .hrv })
        XCTAssertEqual(hrv.current?.mean, 54)
        XCTAssertNil(hrv.previous)
    }

    func testStressNeedsComparableHeartMeasurementsWithoutActivityAndKeepsGaps() throws {
        let days = (1...18).filter { $0 != 16 }.map { day in
            DayMetrics(date: date(day), hrv: 60, restingHR: 55, activeEnergy: day.isMultiple(of: 2) ? 6000 : 0)
        }
        let history = InsightHistory(days, calendar: calendar)
        let trend = StressInsight.trend(endingAt: date(18), history: history)
        let last = try XCTUnwrap(trend.last?.value)
        XCTAssertEqual(last.mean, 1.2, accuracy: 0.0001)
        XCTAssertEqual(last.count, 6)
        XCTAssertNil(trend.first { $0.date == date(16) }?.value)
        let onlyActivity = days.map { DayMetrics(date: $0.date, activeEnergy: 800) }
        XCTAssertTrue(StressInsight.trend(endingAt: date(18), history: InsightHistory(onlyActivity, calendar: calendar))
            .allSatisfy { $0.value == nil })
        var changed = days
        changed[changed.count - 1].hrv = 48
        changed[changed.count - 1].restingHR = 60
        let changedTrend = StressInsight.trend(endingAt: date(18), history: InsightHistory(changed, calendar: calendar))
        XCTAssertEqual(try XCTUnwrap(changedTrend.last?.value?.mean), 8.2 / 6, accuracy: 0.0001)
    }
}
