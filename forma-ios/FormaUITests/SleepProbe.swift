import XCTest

/// Vorübergehende Messung: Welcher Abschnitt macht die Sleep-Seite im Simulator so langsam?
/// Ergebnis steht als Text-Anhang „Sleep-Probe …“ und im Log („SLEEP-PROBE“).
final class SleepProbe: XCTestCase {
    private func measure(hiding: String) {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + (hiding.isEmpty ? [] : ["-probeHide", hiding])
        app.launch()
        let ring = app.buttons["ring.sleep"]
        guard ring.waitForExistence(timeout: 60) else { return record(hiding, "ring.sleep fehlt") }
        let t0 = Date()
        ring.tap()
        let detail = app.descendants(matching: .any)["ring.detail.sleep"].firstMatch
        let opened = detail.waitForExistence(timeout: 180)
        let t1 = Date()
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 120) { backButton.tap() }
        let back = ring.waitForExistence(timeout: 180)
        let t2 = Date()
        record(hiding, String(format: "öffnen %.1f s (%@), zurück %.1f s (%@)",
                              t1.timeIntervalSince(t0), opened ? "ok" : "fehlt",
                              t2.timeIntervalSince(t1), back ? "ok" : "fehlt"))
        app.terminate()
    }

    private func record(_ hiding: String, _ text: String) {
        let line = "SLEEP-PROBE [\(hiding.isEmpty ? "alles" : "ohne " + hiding)] \(text)"
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "Sleep-Probe \(hiding.isEmpty ? "alles" : hiding)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testProbe1Base() { measure(hiding: "") }
    func testProbe2WithoutPlan() { measure(hiding: "plan") }
    func testProbe3WithoutTrend() { measure(hiding: "trend") }
    func testProbe4WithoutMetrics() { measure(hiding: "metrics") }
    func testProbe5WithoutAll() { measure(hiding: "plan,metrics,consistency,phases,trend,summary") }
}
