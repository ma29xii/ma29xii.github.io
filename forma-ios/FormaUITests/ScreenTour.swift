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

    func testTour() {
        sleep(2)
        shot("01 Heute")
        app.swipeUp()
        shot("02 Heute gescrollt")
        app.swipeUp()
        app.swipeUp()
        shot("03 Heute unten")
        app.swipeUp()
        if tapButton(beginningWith: "Heute anpassen") {
            sleep(1)
            shot("03b Heute anpassen")
            _ = tapButton(beginningWith: "Fertig")
        }
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        sleep(1)

        if tapButton(beginningWith: "Erholung ") { shot("04 Erholung"); app.swipeUp(); shot("05 Erholung unten"); back() }
        if tapButton(beginningWith: "Schlaf ") { shot("06 Schlaf"); app.swipeUp(); shot("07 Schlaf unten"); back() }
        if tapButton(beginningWith: "Belastung ") { shot("08 Belastung"); back() }

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

        tab("Gesundheit")
        shot("14 Gesundheit")
        app.swipeUp()
        if tapButton(beginningWith: "Körperalter") {
            shot("14b Körperalter")
            app.swipeUp()
            shot("14c Körperalter Faktoren")
            app.swipeUp(); app.swipeUp()
            shot("14d Körperalter Methode")
            back()
        }
        shot("14e Gesundheit unten")
        app.swipeDown(); app.swipeDown()
        if tapButton(beginningWith: "HRV") { shot("15 HRV"); back() }

        tab("Coach")
        shot("16 Coach")
        if tapButton(beginningWith: "Wann soll ich") { sleep(1); shot("17 Coach Antwort") }

        tab("Heute")
        if tapButton(beginningWith: "Journal") { sleep(1); shot("18 Journal"); _ = tapButton(beginningWith: "Fertig") }
        let profile = app.buttons["Profil und Einstellungen"].firstMatch
        if profile.waitForExistence(timeout: 3) { profile.tap(); sleep(1); shot("19 Profil") }
    }
}
