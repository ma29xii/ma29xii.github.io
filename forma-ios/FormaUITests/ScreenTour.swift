import XCTest

/// Fährt alle Hauptbildschirme ab und hängt Screenshots an (für die Design-Prüfung in der CI).
final class ScreenTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapButton(beginningWith prefix: String, timeout: TimeInterval = 4) -> Bool {
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        guard button.waitForExistence(timeout: timeout) else { return false }
        button.tap()
        return true
    }

    /// Tippt den Knopf „… abschließen“ im Dock (nicht die Satzzeilen).
    private func tapCompleteSet() -> Bool {
        let button = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "abschließen")).firstMatch
        guard button.waitForExistence(timeout: 4) else { return false }
        button.tap()
        return true
    }

    private func back() {
        let b = app.navigationBars.buttons.firstMatch
        if b.waitForExistence(timeout: 2) { b.tap() }
        sleep(1)
    }

    /// Die Tab-Leiste minimiert sich beim Scrollen (iOS 26). Erst ausklappen, dann wechseln.
    private func tab(_ name: String) {
        let target = app.tabBars.buttons[name]
        if !(target.exists && target.isHittable) {
            let minimized = app.tabBars.buttons.firstMatch
            if minimized.exists && minimized.isHittable { minimized.tap() } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.955)).tap()
            }
            sleep(1)
        }
        if target.waitForExistence(timeout: 3) && target.isHittable { target.tap() }
        else { _ = tapButton(beginningWith: name) }
        sleep(1)
    }

    private func reveal(_ element: XCUIElement, swipes: Int = 10) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func captureDetail(_ id: String, title: String, screenshot: String) {
        let button = app.buttons[id]
        guard reveal(button) else {
            XCTFail("Der Einstieg für \(title) fehlt")
            return
        }
        button.tap()
        guard app.navigationBars[title].waitForExistence(timeout: 3) else {
            XCTFail("Die Detailseite \(title) fehlt")
            return
        }
        shot(screenshot)
        back()
    }

    private func finishEditing() {
        let done = app.buttons["tiles.done"]
        if done.exists && done.isHittable {
            done.tap()
            return
        }
        let edit = app.buttons["tiles.edit"]
        guard reveal(edit), edit.label == "Fertig" else {
            XCTFail("Der Bearbeitungsmodus lässt sich nicht beenden")
            return
        }
        edit.tap()
    }

    func testTour() {
        sleep(2)
        let steps = app.buttons["today.steps"]
        XCTAssertTrue(steps.waitForExistence(timeout: 5))
        let edit = app.buttons["tiles.edit"]
        shot("01 Today")

        let nextDay = app.buttons["dashboard.right"]
        let dayLabel = app.staticTexts["dashboard.date"]
        XCTAssertTrue(dayLabel.exists)
        let today = dayLabel.label
        XCTAssertFalse(nextDay.isEnabled)
        app.buttons["dashboard.left"].tap()
        XCTAssertTrue(nextDay.isEnabled)
        XCTAssertNotEqual(dayLabel.label, today)
        shot("02 Today Vortag")
        nextDay.tap()
        XCTAssertEqual(dayLabel.label, today)

        captureDetail("today.steps", title: "Schritte", screenshot: "08b Schritte")
        captureDetail("health.monitor", title: "Health Monitor", screenshot: "08c Health Monitor")
        if reveal(app.staticTexts["today.stress.title"]) {
            shot("08d Stress Monitor")
        } else {
            XCTFail("Stress Monitor fehlt")
        }
        if reveal(app.staticTexts["today.activities.title"]) {
            shot("03 Mein Tag")
        } else {
            XCTFail("Die Aktivitäten fehlen")
        }

        for (kind, name) in [("recovery", "04 Recovery"), ("sleep", "06 Sleep"), ("strain", "08 Strain")] {
            if kind == "sleep" {
                app.buttons["today.tab.overview"].tap()
                let ring = app.buttons["ring.sleep"]
                XCTAssertTrue(ring.waitForExistence(timeout: 3) && ring.isHittable)
                ring.tap()
            } else {
                app.buttons["today.tab.\(kind)"].tap()
            }
            XCTAssertTrue(app.descendants(matching: .any)["ring.detail.\(kind)"].firstMatch.waitForExistence(timeout: 3))
            shot(name)
        }

        let ranges = app.segmentedControls["trend.range"]
        if reveal(ranges), ranges.buttons.count == 3 {
            let previousWindow = app.buttons["trend.window.left"]
            let nextWindow = app.buttons["trend.window.right"]
            let window = app.staticTexts["trend.window.date"]
            if reveal(previousWindow, swipes: 3) {
                let latestWindow = window.label
                previousWindow.tap()
                XCTAssertTrue(nextWindow.isEnabled)
                XCTAssertNotEqual(window.label, latestWindow)
                nextWindow.tap()
                XCTAssertEqual(window.label, latestWindow)
            } else {
                XCTFail("Der Zeitraum lässt sich nicht wechseln")
            }
            ranges.buttons.element(boundBy: 1).tap()
            ranges.buttons.element(boundBy: 2).tap()
            shot("08e Strain Trend")
        } else {
            XCTFail("Die Trend-Zeiträume fehlen")
        }

        tab("Training")
        shot("09 Training")
        app.swipeUp()
        shot("09b Training unten")
        app.swipeDown(); app.swipeDown()
        let startButton = app.buttons["training.start"]
        if startButton.waitForExistence(timeout: 4) {
            startButton.tap()
            sleep(1)
            shot("10 Live-Training")
            if tapCompleteSet() {
                shot("11 Pause")
                let skip = app.buttons["rest.skip"]
                if skip.waitForExistence(timeout: 3) { skip.tap() }
                sleep(1)
                shot("12 Nächster Satz")
                _ = tapCompleteSet()
                if skip.waitForExistence(timeout: 3) { skip.tap() }
            }
            let end = app.buttons["Beenden"]
            if end.waitForExistence(timeout: 3) {
                end.tap()
                if tapButton(beginningWith: "Speichern") {
                    sleep(2)
                    shot("13 Zusammenfassung")
                    _ = tapButton(beginningWith: "Fertig")
                }
            }
        }

        tab("Health")
        XCTAssertTrue(app.navigationBars["Health"].exists)
        XCTAssertTrue(app.buttons["health.age"].isHittable)
        shot("14 Health")
        captureDetail("health.age", title: "Datengrundlage", screenshot: "14b Health Age Datengrundlage")
        if reveal(app.staticTexts["health.age.pace.title"]) {
            shot("14d Alterungstempo")
        } else {
            XCTFail("Das Alterungstempo fehlt")
        }
        if reveal(app.staticTexts["health.age.trend.title"]) {
            shot("14e Health Age Trend")
        } else {
            XCTFail("Der Health Age Trend fehlt")
        }
        captureDetail("health.monitor", title: "Health Monitor", screenshot: "14f Health Monitor")
        captureDetail("health.metric.hrv", title: "HRV", screenshot: "15 HRV")
        if reveal(edit) {
            edit.tap()
            XCTAssertFalse(app.sheets.firstMatch.exists)
            shot("14c Health bearbeiten")
            finishEditing()
        } else {
            XCTFail("Der Bearbeitungsmodus von Health fehlt")
        }

        tab("Coach")
        shot("16 Coach")
        if tapButton(beginningWith: "Wann soll ich") { sleep(1); shot("17 Coach Antwort") }

        tab("Today")
        let profile = app.buttons["Profil und Einstellungen"].firstMatch
        if profile.waitForExistence(timeout: 3) {
            profile.tap()
            XCTAssertTrue(app.navigationBars["Profil"].waitForExistence(timeout: 3))
            shot("19 Profil")
            captureDetail("Body", title: "Body", screenshot: "20 Body")
        } else {
            XCTFail("Das Profil fehlt")
        }
    }
}
