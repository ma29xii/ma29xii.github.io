import XCTest

/// Klickt einmal quer durch die App (mit Beispieldaten in einer flüchtigen
/// Datenbank) und hängt von jedem Bildschirm einen Screenshot an.
final class StetigUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemo", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openTab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab \(name) fehlt")
        button.tap()
    }

    func testWalkthrough() {
        app.launch()

        // Übersicht mit Kachel-Karten
        XCTAssertTrue(app.staticTexts["Lesen"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Wasser trinken"].exists)
        shot("01-Gewohnheiten")

        // Abhaken direkt auf der Karte
        let complete = app.buttons["complete-Laufen"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        shot("02-Abgehakt")

        // Detailansicht
        app.staticTexts["Lesen"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Verlauf"].waitForExistence(timeout: 10))
        shot("03-Detail")
        app.swipeUp()
        shot("04-Detail-Kalender")
        app.swipeUp()
        shot("05-Detail-Diagramme")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Neue Gewohnheit anlegen
        let add = app.buttons["add-habit"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Gitarre üben")
        shot("06-Editor")
        app.buttons["save-habit"].tap()
        XCTAssertTrue(app.staticTexts["Gitarre üben"].waitForExistence(timeout: 10))

        // Heute
        openTab("Heute")
        XCTAssertTrue(app.staticTexts["Offen"].waitForExistence(timeout: 10))
        shot("07-Heute")

        // Statistik
        openTab("Statistik")
        XCTAssertTrue(app.staticTexts["Letzte 30 Tage"].waitForExistence(timeout: 10))
        shot("08-Statistik")
        app.swipeUp()
        shot("09-Statistik-unten")

        // Einstellungen
        openTab("Einstellungen")
        XCTAssertTrue(app.staticTexts["Darstellung"].waitForExistence(timeout: 10) || app.staticTexts["DARSTELLUNG"].exists)
        shot("10-Einstellungen")
    }

    func testDarkModeOverview() {
        app.launchArguments += ["-appearance", "2"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Lesen"].waitForExistence(timeout: 30))
        shot("11-Dunkel-Gewohnheiten")
        openTab("Heute")
        XCTAssertTrue(app.staticTexts["Offen"].waitForExistence(timeout: 10))
        shot("12-Dunkel-Heute")
    }

    func testEmptyState() {
        app.launchArguments = ["-inMemoryStore", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Noch keine Gewohnheiten"].waitForExistence(timeout: 30))
        shot("13-Leer")
    }
}
