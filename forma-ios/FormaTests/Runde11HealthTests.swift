import XCTest
@testable import Forma

final class Runde11HealthTests: XCTestCase {
    func testWeekLabelSpansSevenDays() {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 19
        components.hour = 12
        let date = Calendar.forma.date(from: components) ?? .now
        XCTAssertEqual(BodyAgeText.week(ending: date), "13. Nov. – 19. Nov.")
    }

    func testDifferenceTextForWeeklyPoints() {
        XCTAssertEqual(BodyAgeText.difference(-2.96, decimals: 1, approximate: false), "3,0 Jahre jünger")
        XCTAssertEqual(BodyAgeText.difference(1.2, decimals: 0, approximate: true), "etwa 1 Jahr älter")
        XCTAssertEqual(BodyAgeText.difference(0.02, decimals: 1, approximate: false), "Etwa so alt wie du bist")
    }

    @MainActor
    func testParticlesAreDenserAtTheRim() {
        let particles = AgeOrb.particles
        XCTAssertEqual(particles.count, 1100)
        XCTAssertTrue(particles.allSatisfy { (0.38...1).contains($0.radius) })
        let outer = particles.filter { $0.radius > 0.8 }.count
        XCTAssertGreaterThan(outer, particles.count / 2)
        // Feste Verteilung: gleiches Bild bei jedem Start.
        XCTAssertEqual(AgeOrb.particles.first?.angle, particles.first?.angle)
    }
}
