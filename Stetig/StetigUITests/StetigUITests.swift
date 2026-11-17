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

    /// Scrollt nach oben, bis die (beim Scrollen verkleinerte) Tab-Leiste wieder aufklappt.
    private func openTab(_ name: String) {
        let button = app.tabBars.buttons[name]
        var attempts = 0
        while !(button.exists && button.isHittable), attempts < 4 {
            app.swipeDown()
            attempts += 1
        }
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab \(name) fehlt")
        button.tap()
    }

    /// Schließt die einmalige Tastatur-Einführung des Simulators, falls sie erscheint.
    private func dismissKeyboardTutorial() {
        let button = app.buttons["Continue"]
        if button.waitForExistence(timeout: 2) {
            button.tap()
        }
    }

    private var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: Date())
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
        // Der Monatskalender muss beim 1. beginnen (früher fehlten Tage durch doppelte IDs).
        waitFor("1. \(currentMonthName)")
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
        dismissKeyboardTutorial()
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
        // Die Liste scrollt automatisch zur neuen Karte.
        waitFor("Gitarre üben")
        shot("06c-Neu-angelegt")

        // Suche (Suchfeld erscheint oben in der Liste)
        app.swipeDown()
        app.swipeDown()
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Gitarre")
            waitFor("Gitarre üben")
            XCTAssertFalse(element("Wasser trinken").exists, "Suche filtert nicht")
            shot("06d-Suche")
            // iOS 26 schließt die Suche über ein „X“; Beschriftung je nach Version.
            let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Abbrechen", "Schließen", "Cancel", "Close"])).firstMatch
            if close.waitForExistence(timeout: 3) {
                close.tap()
            }
            if app.keyboards.firstMatch.exists {
                app.keyboards.buttons.matching(NSPredicate(format: "label IN %@", ["Suchen", "search", "Search"])).firstMatch.tap()
            }
        }

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
        element("Lesen").tap()
        waitFor("Verlauf")
        shot("11b-Dunkel-Detail")
        goBack()
        openTab("Heute")
        waitFor("Offen")
        shot("12-Dunkel-Heute")
        openTab("Statistik")
        waitFor("Letzte 30 Tage")
        shot("12b-Dunkel-Statistik")
        openTab("Einstellungen")
        waitFor("Akzentfarbe")
        shot("12c-Dunkel-Einstellungen")
    }

    func testEmptyState() {
        app.launchArguments = ["-inMemoryStore", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        waitFor("Noch keine Gewohnheiten", timeout: 30)
        shot("13-Leer")
    }
}
