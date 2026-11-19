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

    func testBiomarkerStatusWords() {
        let today = Date.now.startOfDay
        let base = ScoreEngine.Baseline(mean: 60, sd: 4)
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: nil, baseline: base, today: today), .none)
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: (date: today.adding(days: -3), value: 60), baseline: base, today: today),
                       .stale(today.adding(days: -3)))
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: (date: today, value: 60), baseline: nil, today: today), .noBaseline)
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: (date: today, value: 62), baseline: base, today: today), .normal)
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: (date: today, value: 70), baseline: base, today: today), .higher)
        XCTAssertEqual(BiomarkerStatus.evaluate(latest: (date: today, value: 50), baseline: base, today: today), .lower)
    }

    func testBiomarkerColorFollowsGoodDirection() {
        XCTAssertEqual(BiomarkerStatus.higher.color(for: .restingHR), Theme.warning)
        XCTAssertEqual(BiomarkerStatus.higher.color(for: .hrv), Theme.younger)
        XCTAssertEqual(BiomarkerStatus.lower.color(for: .restingHR), Theme.younger)
        XCTAssertEqual(BiomarkerStatus.noBaseline.color(for: .hrv), Theme.textSecondary)
    }

    // MARK: Health Monitor

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
