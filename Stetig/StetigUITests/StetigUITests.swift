import XCTest

final class StetigUITests: XCTestCase {
    func testLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemo"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    }
}
