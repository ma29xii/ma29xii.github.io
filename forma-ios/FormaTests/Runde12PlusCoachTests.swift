import XCTest
@testable import Forma

final class Runde12PlusCoachTests: XCTestCase {
    func testAmountTextShowsZeroOnlyWithoutEntries() {
        XCTAssertEqual(FoodAmountText.text([]), "0")
        XCTAssertFalse(FoodAmountText.isPartial([]))
    }

    func testAmountTextShowsDashWhenNoValueIsKnown() {
        XCTAssertEqual(FoodAmountText.text([nil, nil]), "–")
        XCTAssertEqual(FoodAmountText.text([nil, .nan]), "–")
    }

    func testAmountTextMarksPartialSumsAsAtLeast() {
        XCTAssertEqual(FoodAmountText.text([12, nil, 8]), "≥ 20")
        XCTAssertTrue(FoodAmountText.isPartial([12, nil]))
    }

    func testAmountTextIsExactWhenEveryValueIsKnown() {
        XCTAssertEqual(FoodAmountText.text([12, 8.4]), "20")
        XCTAssertFalse(FoodAmountText.isPartial([12, 8]))
    }
}
