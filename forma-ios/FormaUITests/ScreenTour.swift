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

    /// Element per Kennung, egal welcher Typ (Text in Buttons wird oft zusammengefasst).
    private func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func reveal(_ element: XCUIElement, swipes: Int = 10) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func captureDetail(_ id: String, title: String, screenshot: String) {
        let button = el(id)
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

    /// Anpassen öffnen, Karten ↔ Balken des Health Monitors umschalten, Anpassen beenden.
    private func toggleVitalsLayout() -> Bool {
        let edit = el("tiles.edit")
        guard reveal(edit) else { return false }
        edit.tap()
        let toggle = el("tiles.layout")
        for _ in 0..<12 where !(toggle.exists && toggle.isHittable) { app.swipeDown() }
        let found = toggle.exists && toggle.isHittable
        if found { toggle.tap() }
        finishEditing()
        return found
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

    /// Schließt ein Blatt: erst ein sichtbarer Knopf, sonst nach unten wischen.
    private func dismissSheet() {
        for label in ["Fertig", "Schließen", "Abbrechen"] {
            let b = app.buttons[label].firstMatch
            if b.exists && b.isHittable { b.tap(); sleep(1); return }
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        sleep(1)
    }

    private var plusButton: XCUIElement {
        // Der native Such-Tab kann im Accessibility-Baum nur seine Beschriftung liefern.
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@ OR label == %@",
                                    "tab.plus", "Plus", "Plus-Menü schließen")
        return app.buttons.matching(predicate).firstMatch
    }

    /// Öffnet das Plus-Menü und tippt die Kachel mit genau diesem Titel (sonst die erste, die so beginnt).
    @discardableResult
    private func openPlus(_ title: String) -> Bool {
        if !el("plus.track").exists {
            let plus = plusButton
            guard plus.waitForExistence(timeout: 4) else { return false }
            plus.tap()
            sleep(1)
        }
        let exact = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if exact.waitForExistence(timeout: 3) { exact.tap(); sleep(1); return true }
        return tapButton(beginningWith: title)
    }

    /// Prüft den Wechsel vom offenen Plus-Menü nach Food und erstellt Bildschirmfotos.
    func testTourPlus() {
        sleep(2)
        let plus = plusButton
        guard plus.waitForExistence(timeout: 6) else { XCTFail("Plus fehlt"); return }
        plus.tap()
        let track = el("plus.track")
        XCTAssertTrue(track.waitForExistence(timeout: 4))
        shot("30 Plus-Menü")
        // Zweiter Tipp auf den Plus-Knopf (jetzt X) schließt das Menü wieder.
        guard plus.waitForExistence(timeout: 4) else { XCTFail("X zum Schließen fehlt"); return }
        plus.tap()
        XCTAssertTrue(track.waitForNonExistence(timeout: 3), "Plus-Menü schließt sich beim zweiten Tipp nicht.")
        plus.tap()
        XCTAssertTrue(track.waitForExistence(timeout: 4))
        tab("Food")
        XCTAssertTrue(app.navigationBars["Food"].waitForExistence(timeout: 4))
        XCTAssertFalse(track.exists, "Beim Wechsel zu Food schließt sich das Plus-Menü.")
        shot("31 Food")
        app.swipeUp(); shot("31b Food unten"); app.swipeDown(); app.swipeDown()
        for (title, name) in [("Nährwerte tracken", "33 Nährwerte tracken"), ("Essen planen", "32 Essen planen"),
                              ("Wasser", "34 Wasser"), ("Fasten", "35 Fasten"), ("Gewicht", "36 Gewicht"),
                              ("Stimmung", "36b Stimmung"), ("Koffein", "36c Koffein"), ("Schlafplan", "36d Schlafplan")] {
            guard openPlus(title) else { dismissSheet(); continue }
            shot(name)
            if title == "Essen planen" {
                let shopping = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Einkauf")).firstMatch
                if shopping.waitForExistence(timeout: 2) { shopping.tap(); sleep(1); shot("32b Einkaufsliste") }
            }
            dismissSheet(); dismissSheet()
        }
        tab("Today")
        let profile = app.buttons["Profil und Einstellungen"].firstMatch
        if profile.waitForExistence(timeout: 3) {
            profile.tap()
            if tapButton(beginningWith: "Erfolge") { sleep(1); shot("37 Erfolge"); back() }
            if tapButton(beginningWith: "Design") { sleep(1); shot("38 Designs") }
        }
    }

    func testTour() {
        XCTAssertTrue(app.buttons["ring.recovery"].waitForExistence(timeout: 6))
        shot("01 Today")

        // Vitalwerte als Balken (F6-02): Umstellen nur im Anpassen-Modus, danach zurück zu Karten.
        if toggleVitalsLayout() {
            let bars = el("health.monitor.metric.respiratoryRate")
            if reveal(bars) { shot("01b Vitalwerte Balken") }
            _ = toggleVitalsLayout()
            for _ in 0..<8 { app.swipeDown() }
        } else {
            XCTFail("Der Umschalter Karten/Balken fehlt im Anpassen-Modus")
        }

        // Today v2: Kopf mit Recovery-Bogen und Strain/Sleep-Kapseln, keine Reiter, kein Datumsschalter.
        for (kind, name) in [("sleep", "06 Sleep"), ("recovery", "04 Recovery"), ("strain", "08 Strain")] {
            let ring = app.buttons["ring.\(kind)"]
            guard ring.waitForExistence(timeout: 3) else { XCTFail("Anzeige \(kind) fehlt"); continue }
            ring.tap()
            if app.descendants(matching: .any)["ring.detail.\(kind)"].firstMatch.waitForExistence(timeout: 4) {
                shot(name)
                if kind == "strain" { break }   // Strain-Detail bleibt offen für den Trend-Teil
                back()
            } else {
                XCTFail("Die Detailseite \(kind) fehlt")
            }
        }

        let ranges = app.segmentedControls.firstMatch
        if reveal(ranges), ranges.buttons.count == 3 {
            XCTAssertFalse(el("trend.window.date").exists)
            ranges.buttons.element(boundBy: 1).tap()
            ranges.buttons.element(boundBy: 2).tap()
            shot("08e Strain Trend")
            let measurements = app.buttons["trend.measurements"]
            if reveal(measurements, swipes: 3) {
                measurements.tap()
                XCTAssertEqual(measurements.value as? String, "Ausgeklappt")
                measurements.tap()
            } else {
                XCTFail("Einzelwerte im Trend fehlen")
            }
        } else {
            XCTFail("Die Trend-Zeiträume fehlen")
        }

        back()
        app.swipeDown(); app.swipeDown()
        XCTAssertFalse(el("today.compact").exists)
        captureDetail("health.monitor.metric.respiratoryRate", title: "Atemfrequenz", screenshot: "08c Health Monitor")
        let stress = el("today.stress.open")
        if reveal(stress) {
            stress.tap()
            if app.navigationBars["Stress Monitor"].waitForExistence(timeout: 3) {
                shot("08d Stress Monitor")
                // Atemübung: nur der Startbildschirm (die laufende Animation hält XCUITest auf).
                let breathe = el("breathing.open")
                if breathe.waitForExistence(timeout: 2) {
                    breathe.tap()
                    if el("breathing.start").waitForExistence(timeout: 3) { shot("08h Atmen") }
                    else { XCTFail("Atemübung öffnet nicht") }
                    let close = el("breathing.close")
                    if close.exists { close.tap() }
                } else { XCTFail("Atmen fehlt im Stress Monitor") }
                back()
            } else { XCTFail("Die Detailseite Stress Monitor fehlt") }
        } else { XCTFail("Der Einstieg für Stress Monitor fehlt") }
        captureDetail("today.energy", title: "Energie", screenshot: "08f Energie")
        if reveal(el("today.food")) { shot("08g Heutiges Essen") } else { XCTFail("Essensanzeige fehlt") }
        // Wochenrückblick als Story (im Rundgang unabhängig vom Wochentag sichtbar).
        let weekly = el("today.weekly.open")
        if reveal(weekly) {
            weekly.tap()
            if el("weekly.story").waitForExistence(timeout: 4) {
                shot("03b Wochenrückblick")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55)).tap()
                shot("03c Wochenrückblick Wert")
                let close = el("weekly.close")
                if close.waitForExistence(timeout: 2) { close.tap() }
                XCTAssertTrue(close.waitForNonExistence(timeout: 3), "Wochenrückblick schließt nicht")
            } else { XCTFail("Wochenrückblick öffnet nicht") }
        } else { XCTFail("Wochenrückblick fehlt") }
        XCTAssertFalse(el("today.activities.title").exists)
        captureDetail("today.steps", title: "Schritte", screenshot: "08b Schritte")
        captureDetail("sleepplan.card", title: "Schlafplan", screenshot: "08i Today Schlafplan")
        if reveal(el("today.hydration")) { shot("08j Today Wasser") } else { XCTFail("Wasserkachel fehlt") }

        XCTAssertTrue(openPlus("Fitness"), "Fitness im Plus-Menü fehlt")
        shot("09 Training")
        if reveal(el("fitness.muscles")) { shot("09b Training unten") }
        let startButton = app.buttons["training.start"]
        for _ in 0..<8 {
            if startButton.exists && startButton.isHittable { break }
            app.swipeDown()
        }
        if reveal(startButton) {
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
        dismissSheet()

        tab("Health")
        XCTAssertTrue(app.navigationBars["Health"].exists)
        XCTAssertTrue(app.buttons["health.age"].isHittable)
        shot("14 Health")
        // Runde 3: Tempo, Trend und Quellen liegen auf der Health-Age-Seite.
        app.buttons["health.age"].tap()
        if app.navigationBars["Health Age"].waitForExistence(timeout: 4) {
            shot("14b Health Age")
            if reveal(el("health.age.pace")) { shot("14d Alterungstempo") } else { XCTFail("Das Alterungstempo fehlt") }
            if reveal(el("health.age.trend")) { shot("14e Health Age Trend") } else { XCTFail("Der Health Age Trend fehlt") }
            back()
        } else {
            XCTFail("Die Health-Age-Seite fehlt")
        }
        app.swipeDown(); app.swipeDown()
        captureDetail("health.monitor.metric.respiratoryRate", title: "Atemfrequenz", screenshot: "14f Health Monitor")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        captureDetail("health.metric.hrv", title: "HRV", screenshot: "15 HRV")
        let edit = app.buttons["tiles.edit"]
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
        XCTAssertFalse(el("coach.mascot").exists)
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
