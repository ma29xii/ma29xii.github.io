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

    private func back() {
        let b = app.navigationBars.buttons.firstMatch
        if b.waitForExistence(timeout: 2) { b.tap() }
        sleep(1)
    }

    private func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        if b.waitForExistence(timeout: 3) { b.tap() } else { _ = tapButton(beginningWith: name) }
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
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        sleep(1)

        if tapButton(beginningWith: "Erholung") { shot("04 Erholung"); app.swipeUp(); shot("05 Erholung unten"); back() }
        if tapButton(beginningWith: "Schlaf") { shot("06 Schlaf"); app.swipeUp(); shot("07 Schlaf unten"); back() }
        if tapButton(beginningWith: "Belastung") { shot("08 Belastung"); back() }

        tab("Training")
        shot("09 Training")
        if tapButton(beginningWith: "Training starten") {
            sleep(1)
            shot("10 Live-Training")
            if tapButton(beginningWith: "Aufwärmsatz abschließen") || tapButton(beginningWith: "Satz") {
                shot("11 Pause")
                _ = tapButton(beginningWith: "Weiter")
                sleep(1)
                shot("12 Nächster Satz")
                _ = tapButton(beginningWith: "Satz")
                _ = tapButton(beginningWith: "Weiter")
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
