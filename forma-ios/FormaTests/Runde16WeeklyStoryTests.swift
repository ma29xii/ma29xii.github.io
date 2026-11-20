import XCTest
@testable import Forma

final class Runde16WeeklyStoryTests: XCTestCase {
    private func row(_ metric: WeeklyInsight.Metric, _ current: Double?, _ previous: Double?) -> WeeklyInsight.Row {
        WeeklyInsight.Row(metric: metric, current: current.flatMap { InsightAverage([$0]) },
                          previous: previous.flatMap { InsightAverage([$0]) })
    }

    func testChangeInPercent() {
        XCTAssertEqual(row(.sleep, 27_000, 25_000).change ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(row(.sleep, 27_000, 25_000).changeText, "+8 %")
        XCTAssertEqual(row(.hrv, 45, 50).changeText, "−10 %")
        XCTAssertEqual(row(.steps, 8_010, 8_000).changeText, "±0 %")
        // Grenzfall: +0,6 % wird wie im Text auf +1 % gerundet und zählt als Verbesserung.
        XCTAssertEqual(row(.steps, 8_050, 8_000).changeText, "+1 %")
        XCTAssertEqual(WeeklyRecapLink.highlight([row(.steps, 8_050, 8_000)]), "Schritte +1 %")
        XCTAssertNil(row(.recovery, 60, nil).change)
        XCTAssertNil(row(.recovery, 60, 0).change)
        XCTAssertEqual(row(.recovery, 60, nil).changeText, "–")
    }

    func testHighlightPicksBiggestImprovementButNeverStrain() {
        let rows = [row(.strain, 20, 10), row(.sleep, 26_400, 24_000), row(.hrv, 66, 50), row(.steps, 7_000, 9_000)]
        XCTAssertEqual(WeeklyRecapLink.highlight(rows), "HRV +32 %")
        XCTAssertEqual(WeeklyRecapLink.highlight([row(.strain, 20, 10), row(.steps, 7_000, 9_000)]), "Deine Woche")
    }

    func testRegularPeriodStaysOutsideUITest() {
        // Mittwochmittag: außerhalb Sonntagabend–Montagmittag gibt es keinen Rückblick (ohne -uitest).
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 18; parts.hour = 12
        let wednesday = Calendar.forma.date(from: parts)!
        XCTAssertNil(WeeklyInsight.period(at: wednesday))
        XCTAssertNil(WeeklyInsight.displayPeriod(at: wednesday))
    }
}
