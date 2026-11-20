import XCTest
@testable import Forma

final class F6IllnessSignalTests: XCTestCase {
    private let calendar = Calendar.forma
    private var today: Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 11, day: 20))!)
    }

    private func night(ending day: Date) -> SleepNight {
        SleepNight(start: day.addingTimeInterval(-1 * 3600), end: day.addingTimeInterval(7 * 3600),
                   segments: [], reportedAsleep: 7 * 3600)
    }

    /// Stabile Nächte vor `day`: HRV 55, Ruhepuls 55, Atmung 15, Haut 34 → Spannen 2,2 / 2,2 / 0,6 / 0,2.
    private func prior(count: Int = 20) -> [DayMetrics] {
        (1...count).reversed().map { offset in
            let date = today.adding(days: -offset)
            return DayMetrics(date: date, hrv: 55, restingHR: 55, respiratoryRate: 15,
                              sleep: night(ending: date), skinTemperature: 34)
        }
    }

    private func current(hrv: Double? = 55, rhr: Double? = 55, resp: Double? = 15, skin: Double? = 34) -> DayMetrics {
        DayMetrics(date: today, hrv: hrv, restingHR: rhr, respiratoryRate: resp,
                   sleep: night(ending: today), skinTemperature: skin)
    }

    func testQuietNightIsInconspicuous() throws {
        let signal = try XCTUnwrap(IllnessSignal.evaluate(day: current(), history: prior()))
        XCTAssertEqual(signal.level, .normal)
        XCTAssertTrue(signal.flagged.isEmpty)
        XCTAssertEqual(signal.readings.count, 4)
    }

    func testSingleSignalStaysInconspicuous() throws {
        let signal = try XCTUnwrap(IllnessSignal.evaluate(day: current(skin: 34.9), history: prior()))
        XCTAssertEqual(signal.flagged.map(\.kind), [.skinTemperature])
        XCTAssertEqual(signal.level, .normal)
    }

    func testTwoSignalsAreWatched() throws {
        let signal = try XCTUnwrap(IllnessSignal.evaluate(day: current(hrv: 50.6, rhr: 59.4), history: prior()))
        XCTAssertEqual(Set(signal.flagged.map(\.kind)), [.hrv, .restingHR])
        XCTAssertEqual(signal.level, .watch)
    }

    func testThreeSignalsMeanBodyIsFighting() throws {
        let signal = try XCTUnwrap(IllnessSignal.evaluate(day: current(hrv: 50.6, rhr: 59.4, skin: 34.35),
                                                          history: prior()))
        XCTAssertEqual(signal.flagged.count, 3)
        XCTAssertEqual(signal.level, .fighting)
    }

    func testStrongSkinTemperaturePlusOneOtherIsFighting() throws {
        let signal = try XCTUnwrap(IllnessSignal.evaluate(day: current(rhr: 59.4, skin: 34.6), history: prior()))
        XCTAssertEqual(signal.flagged.count, 2)
        XCTAssertEqual(signal.level, .fighting)
    }

    func testMildSkinTemperaturePlusOneOtherOnlyWatch() throws {
        let signal = try XCTUnwrap(IllnessSignal.evaluate(day: current(rhr: 59.4, skin: 34.35), history: prior()))
        XCTAssertEqual(signal.level, .watch)
    }

    func testHigherHRVIsNotAWarning() throws {
        let signal = try XCTUnwrap(IllnessSignal.evaluate(day: current(hrv: 70), history: prior()))
        XCTAssertTrue(signal.flagged.isEmpty)
        let reading = try XCTUnwrap(signal.readings.first { $0.kind == .hrv })
        XCTAssertLessThan(reading.deviation, 0)
        XCTAssertTrue(reading.isAboveNormal)
    }

    func testLowHRVPointsDown() throws {
        let signal = try XCTUnwrap(IllnessSignal.evaluate(day: current(hrv: 50.6), history: prior()))
        let reading = try XCTUnwrap(signal.flagged.first)
        XCTAssertEqual(reading.kind, .hrv)
        XCTAssertFalse(reading.isAboveNormal)
    }

    func testTooFewComparisonNightsGiveNothing() {
        XCTAssertNil(IllnessSignal.evaluate(day: current(), history: prior(count: 5)))
    }

    func testTooFewMeasuredValuesGiveNothing() {
        XCTAssertNil(IllnessSignal.evaluate(day: current(hrv: nil, rhr: nil), history: prior()))
        XCTAssertNotNil(IllnessSignal.evaluate(day: current(resp: nil), history: prior()))
    }

    func testNoNightGivesNothing() {
        var day = current()
        day.sleep = nil
        XCTAssertNil(IllnessSignal.evaluate(day: day, history: prior()))
    }

    func testTrailCoversFourteenDaysAndKeepsGaps() throws {
        var history = prior(count: 40)
        history.append(current(hrv: 50.6, rhr: 59.4))
        history.removeAll { $0.date == today.adding(days: -3) }
        let trail = IllnessSignal.trail(endingAt: today, history: history)
        XCTAssertEqual(trail.count, 14)
        XCTAssertEqual(trail.last?.date, today)
        XCTAssertEqual(trail.last?.signal?.level, .watch)
        let gap = try XCTUnwrap(trail.first { $0.date == today.adding(days: -3) })
        XCTAssertNil(gap.signal)
        XCTAssertEqual(trail.first { $0.date == today.adding(days: -2) }?.signal?.level, .normal)
    }

    func testLevelTitles() {
        XCTAssertEqual(IllnessSignal.Level.normal.title, "Unauffällig")
        XCTAssertEqual(IllnessSignal.Level.watch.title, "Beobachten")
        XCTAssertEqual(IllnessSignal.Level.fighting.title, "Dein Körper kämpft")
    }
}
