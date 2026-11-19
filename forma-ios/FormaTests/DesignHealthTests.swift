import XCTest
@testable import Forma

final class DesignHealthTests: XCTestCase {
    // MARK: Alterungstempo

    func testAgingPaceScalePositions() {
        XCTAssertEqual(AgingPace.fraction(-1), 0, accuracy: 0.0001)
        XCTAssertEqual(AgingPace.fraction(1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(AgingPace.fraction(3), 1, accuracy: 0.0001)
        // Werte außerhalb der Skala sitzen am Rand statt daneben.
        XCTAssertEqual(AgingPace.fraction(7.5), 1, accuracy: 0.0001)
        XCTAssertEqual(AgingPace.fraction(-4), 0, accuracy: 0.0001)
    }

    func testAgingPaceBandsAndText() {
        XCTAssertEqual(AgingPace.band(0.3), .slow)
        XCTAssertEqual(AgingPace.band(1.0), .clock)
        XCTAssertEqual(AgingPace.band(1.2), .clock)
        XCTAssertEqual(AgingPace.band(1.5), .fast)
        XCTAssertEqual(AgingPace.text(1), "1,0×")
        XCTAssertEqual(AgingPace.text(-0.44), "−0,4×")
        XCTAssertEqual(AgingPace.text(-0.04), "0,0×")
    }

    // MARK: Faktoren

    func testFactorGapPointsFromReferenceToValue() throws {
        let domain = FactorScale.domain(value: 50, display: 35...105)
        XCTAssertEqual(domain, 35...105)
        let gap = try XCTUnwrap(FactorScale.gap(value: 50, reference: 65...65, in: domain))
        XCTAssertEqual(gap.lowerBound, 15.0 / 70, accuracy: 0.0001)
        XCTAssertEqual(gap.upperBound, 30.0 / 70, accuracy: 0.0001)
        // Schlaf im Vergleichsbereich: keine Strecke.
        XCTAssertNil(FactorScale.gap(value: 7.5, reference: 7...8, in: 4...11))
    }

    func testFactorDomainGrowsForValuesOutsideTheDisplay() {
        let domain = FactorScale.domain(value: 18_000, display: 0...15_000)
        XCTAssertEqual(domain.upperBound, 18_000)
        XCTAssertEqual(FactorScale.fraction(18_000, in: domain), 1, accuracy: 0.0001)
        XCTAssertEqual(FactorScale.fraction(.nan, in: domain), 0.5, accuracy: 0.0001)
    }

    // MARK: Biomarker

    func testBiomarkerStatusIsNeutralAgainstYourRange() {
        let today = Date.now.startOfDay
        let usual = 56.0...64.0
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: nil, range: usual, today: today), .none)
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: (date: today.adding(days: -3), value: 60), range: usual, today: today),
                       .stale(today.adding(days: -3)))
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: (date: today, value: 60), range: nil, today: today), .noBaseline)
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: (date: today, value: 64), range: usual, today: today), .within)
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: (date: today, value: 70), range: usual, today: today), .above)
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: (date: today, value: 50), range: usual, today: today), .below)
        XCTAssertEqual(BiomarkerStatus.above.title, "Über deinem Bereich")
        // K-03-24: keine Ampelfarben – über und unter dem Bereich sehen gleich aus.
        XCTAssertEqual(BiomarkerStatus.above.color, BiomarkerStatus.below.color)
        XCTAssertNotEqual(BiomarkerStatus.above.color, Theme.warning)
    }

    func testBiomarkerRangeUsesThirtyPriorDaysAndNeedsSeven() throws {
        let today = Date.now.startOfDay
        let days = (1...40).reversed().map { DayMetrics(date: today.adding(days: -$0), restingHR: $0.isMultiple(of: 2) ? 58 : 62) }
            + [DayMetrics(date: today, restingHR: 75)]
        let evaluation = BiomarkerComparison.evaluate(.restingHR, days: days, today: today)
        let usual = try XCTUnwrap(evaluation.range)
        XCTAssertEqual((usual.lowerBound + usual.upperBound) / 2, 60, accuracy: 0.5)
        XCTAssertEqual(evaluation.status, .above)
        let thin = [DayMetrics(date: today.adding(days: -2), restingHR: 60), DayMetrics(date: today, restingHR: 60)]
        XCTAssertNil(BiomarkerComparison.evaluate(.restingHR, days: thin, today: today).range)
    }

    func testPaceOutsideTheScaleIsNotShownPrecisely() {
        XCTAssertEqual(AgingPace.text(3.65), "über 3,0×")
        XCTAssertEqual(AgingPace.text(-2), "unter −1,0×")
    }

    func testMonitorSummaryCountsValuesInRange() {
        func reading(_ id: String, _ value: Double?) -> MonitorReading {
            MonitorReading(id: id, title: id, icon: "heart", shortTitle: id, value: value,
                           baseline: ScoreEngine.Baseline(mean: 60, sd: 5), decimals: 0, unit: "bpm")
        }
        let all = MonitorSummary(readings: [reading("a", 60), reading("b", 62), reading("c", 58)])
        XCTAssertEqual(all.text, "3 von 3 im üblichen Bereich")
        XCTAssertEqual(all.icon, "checkmark.circle")
        let some = MonitorSummary(readings: [reading("a", 60), reading("b", 80), reading("c", 61), reading("d", nil)])
        XCTAssertEqual(some.text, "2 von 3 im üblichen Bereich")
        // K-03-30: Unter drei vergleichbaren Werten keine Bewertung, sondern der ehrliche Stand.
        let thin = MonitorSummary(readings: [reading("a", 60), reading("b", nil), reading("c", nil), reading("d", nil)])
        XCTAssertEqual(thin.text, "Erst 1 von 4 vergleichbar")
        XCTAssertEqual(MonitorSummary(readings: [reading("a", nil)]).text, "Keine Messung")
        XCTAssertEqual(reading("b", 80).isAbove, true)
        XCTAssertEqual(reading("b", 40).statusIcon, "arrow.down.circle")
        XCTAssertNil(reading("a", 60).isAbove)
    }

    func testSpO2RangeNeverExceeds100() throws {
        let reading = MonitorReading(id: MetricKind.spo2.rawValue, title: "SpO₂", icon: "drop", shortTitle: "SpO₂",
                                     value: 99, baseline: ScoreEngine.Baseline(mean: 98, sd: 3), decimals: 0, unit: "%")
        XCTAssertEqual(try XCTUnwrap(reading.range).upperBound, 100)
        XCTAssertEqual(reading.inRange, true)
    }

    // MARK: Health Age Trend

    func testTrendIsWeeklyAndEndsWithTodaysHealthAge() throws {
        let now = Date.now
        let today = now.startOfDay
        let days = (1...90).reversed().map { offset in
            DayMetrics(date: today.adding(days: -offset), restingHR: 58 + Double(offset % 5), steps: 9_000)
        }
        let person = PersonInfo(birthDate: today.adding(days: -35 * 365), sex: .unknown, origin: .manual)
        let points = HealthAgeTrend.points(days: days, person: person, sessions: [], now: now)

        // Stichtage 0, 7, …, 70 Tage zurück; ab 77 Tagen fehlen die 21 nötigen Tage.
        XCTAssertEqual(points.count, 11)
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
        let last = try XCTUnwrap(points.last)
        XCTAssertEqual(last.date, now)
        guard case .ready(let result) = HealthAgeTrend.outcome(days: days, person: person, sessions: [], now: now) else {
            return XCTFail("Health Age sollte verfügbar sein")
        }
        XCTAssertEqual(last.bodyAge, result.bodyAge, accuracy: 0.000_001)
        XCTAssertEqual(last.age, result.age, accuracy: 0.000_001)
    }

    func testTrendNeedsEnoughDays() {
        let today = Date.now.startOfDay
        let days = (1...10).map { DayMetrics(date: today.adding(days: -$0), restingHR: 60, steps: 9_000) }.reversed()
        let person = PersonInfo(birthDate: today.adding(days: -35 * 365), sex: .unknown, origin: .manual)
        XCTAssertTrue(HealthAgeTrend.points(days: Array(days), person: person, sessions: []).isEmpty)
    }

    // MARK: Kugel

    func testOrbMoodFollowsDifference() {
        XCTAssertEqual(OrbMood(difference: -2), .younger)
        XCTAssertEqual(OrbMood(difference: 1.5), .older)
        XCTAssertEqual(OrbMood(difference: 0.01), .even)
        XCTAssertEqual(OrbMood(difference: nil), .none)
    }
}
