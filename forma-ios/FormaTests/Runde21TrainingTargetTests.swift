import XCTest
@testable import Forma

final class Runde21TrainingTargetTests: XCTestCase {
    func testMissingRecoveryHidesTarget() {
        XCTAssertNil(TrainingStrainTarget(strain: 40, recovery: nil))
    }

    func testRecoveryThresholdsSetRangeAndLightRoutine() throws {
        for (recovery, range, lightRoutine) in [
            (33, 10...25, true),
            (34, 25...40, false),
            (66, 25...40, false),
            (67, 35...55, false)
        ] {
            let target = try XCTUnwrap(TrainingStrainTarget(strain: nil, recovery: recovery))
            XCTAssertEqual(target.range, range, "Recovery \(recovery)")
            XCTAssertEqual(target.offersLightRoutine, lightRoutine, "Recovery \(recovery)")
        }
    }

    func testStrainStatusAndColorAtTargetBoundaries() throws {
        let cases: [(Int?, String, TrainingStrainTarget.Tone)] = [
            (nil, "Noch keine Belastung", .neutral),
            (0, "Unter dem Ziel", .neutral),
            (34, "Unter dem Ziel", .neutral),
            (35, "Im Ziel", .green),
            (55, "Im Ziel", .green),
            (56, "Über dem Ziel", .orange)
        ]
        for (strain, status, tone) in cases {
            let target = try XCTUnwrap(TrainingStrainTarget(strain: strain, recovery: 80))
            XCTAssertEqual(target.status, status)
            XCTAssertEqual(target.tone, tone)
        }
    }
}
