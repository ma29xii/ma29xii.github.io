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

    override func record(_ issue: XCTIssue) {
        // Bei einem Fehler Bildschirm und Element-Baum festhalten – erleichtert die Fehlersuche.
        if let app, app.state == .runningForeground {
            shot("FEHLER-\(name)")
            print("UI-HIERARCHIE-BEGINN")
            print(app.debugDescription.split(separator: "\n").prefix(140).joined(separator: "\n"))
            print("UI-HIERARCHIE-ENDE")
        }
        super.record(issue)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Findet ein Element unabhängig von seinem Typ (Text, Button, …) über die Beschriftung.
    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func waitFor(_ label: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element(label).waitForExistence(timeout: timeout), "„\(label)“ nicht gefunden", file: file, line: line)
    }

    private func openTab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab \(name) fehlt")
        button.tap()
    }

    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 5) {
            back.tap()
        }
    }

    func testWalkthrough() {
        app.launch()

        // Übersicht mit Kachel-Karten
        waitFor("Lesen", timeout: 30)
        waitFor("Wasser trinken")
        shot("01-Gewohnheiten")

        // Abhaken direkt auf der Karte
        let complete = app.buttons["complete-Laufen"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()
        shot("02-Abgehakt")

        // Detailansicht
        element("Lesen").tap()
        waitFor("Verlauf")
        shot("03-Detail")
        app.swipeUp()
        shot("04-Detail-Kalender")
        app.swipeUp()
        shot("05-Detail-Diagramme")
        goBack()

        // Neue Gewohnheit anlegen
        let add = app.buttons["add-habit"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Gitarre üben")
        shot("06-Editor")

        // Symbolauswahl
        let symbolRow = element("Symbol")
        if symbolRow.waitForExistence(timeout: 5) {
            symbolRow.tap()
            if element("Eigenes Emoji").waitForExistence(timeout: 10) {
                shot("06b-Symbole")
                goBack()
            }
        }

        app.buttons["save-habit"].tap()
        waitFor("Gitarre üben")

        // Heute
        openTab("Heute")
        waitFor("Offen")
        shot("07-Heute")

        // Statistik
        openTab("Statistik")
        waitFor("Letzte 30 Tage")
        shot("08-Statistik")
        app.swipeUp()
        shot("09-Statistik-unten")

        // Einstellungen
        openTab("Einstellungen")
        waitFor("Erscheinungsbild")
        shot("10-Einstellungen")
    }

    func testDarkModeOverview() {
        app.launchArguments += ["-appearance", "2"]
        app.launch()
        waitFor("Lesen", timeout: 30)
        shot("11-Dunkel-Gewohnheiten")
        openTab("Heute")
        waitFor("Offen")
        shot("12-Dunkel-Heute")
    }

    func testEmptyState() {
        app.launchArguments = ["-inMemoryStore", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        waitFor("Noch keine Gewohnheiten", timeout: 30)
        shot("13-Leer")
    }
}
