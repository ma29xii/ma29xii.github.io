import Foundation
import XCTest
@testable import Forma

final class GoogleHealthTests: XCTestCase {
    @MainActor
    func testGoogleWearablesRecoverStepsWhenRawRowsHaveNoSource() async throws {
        let start = "2026-11-20T09:00:00Z"
        let end = "2026-11-20T09:01:00Z"
        let point = """
        {"steps":{"count":"130","interval":{"startTime":"\(start)","endTime":"\(end)"}}}
        """
        var reconciledRequests: [Bool] = []
        let points = try await GoogleHealthService.readWithWearableFallback(.steps) { reconciled, _ in
            reconciledRequests.append(reconciled)
            return Data("{\"dataPoints\":[\(point)]}".utf8)
        }

        XCTAssertEqual(reconciledRequests, [false, true])
        guard case .amount(let count, _, _, let source) = try XCTUnwrap(points.first) else {
            return XCTFail("Schritte fehlen")
        }
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(count, 130)
        XCTAssertEqual(source.family, .googleWearable)
    }

    @MainActor
    func testRawWearableStepsAreUsedWithoutAddingReconciledSteps() async throws {
        var reconciledRequests: [Bool] = []
        let points = try await GoogleHealthService.readWithWearableFallback(.steps) { reconciled, _ in
            reconciledRequests.append(reconciled)
            return Data("""
            {"dataPoints":[
              {"steps":{"count":"5","interval":{"startTime":"2026-11-20T09:01:00Z","endTime":"2026-11-20T09:02:00Z"}}},
              {"dataSource":{"platform":"FITBIT"},
               "steps":{"count":"130","interval":{"startTime":"2026-11-20T09:00:00Z","endTime":"2026-11-20T09:01:00Z"}}}
            ]}
            """.utf8)
        }

        XCTAssertEqual(reconciledRequests, [false])
        guard case .amount(let count, _, _, let source) = try XCTUnwrap(points.first) else {
            return XCTFail("Fitbit-Schritte fehlen")
        }
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(count, 130)
        XCTAssertEqual(source.family, .fitbit)
    }

    @MainActor
    func testReconciledSleepAcceptsGoogleMainFlag() async throws {
        let points = try await GoogleHealthService.readWithWearableFallback(.sleep) { reconciled, _ in
            guard reconciled else { return Data("{}".utf8) }
            return Data("""
            {"dataPoints":[{"sleep":{
              "interval":{"startTime":"2026-11-19T22:00:00Z","endTime":"2026-11-20T06:00:00Z"},
              "metadata":{"main":true},"summary":{"minutesAsleep":"407"}
            }}]}
            """.utf8)
        }

        guard case .sleep(let night, let main, _, _, let source) = try XCTUnwrap(points.first) else {
            return XCTFail("Hauptschlaf fehlt")
        }
        XCTAssertTrue(main)
        XCTAssertEqual(night.asleep, 407 * 60)
        XCTAssertEqual(source.family, .googleWearable)
    }

    func testParsesSleepStagesAndChoosesFitbitMainNight() throws {
        let page = try GoogleHealthPage.decode(Data("""
        {"dataPoints":[
          {"dataSource":{"platform":"FITBIT","device":{"displayName":"Charge 6"}},
           "sleep":{"metadata":{"mainSleep":true},"interval":{"startTime":"2026-11-17T22:00:00Z","endTime":"2026-11-18T06:00:00Z"},
                    "stages":[{"type":"DEEP","startTime":"2026-11-17T22:00:00Z","endTime":"2026-11-18T00:00:00Z"},
                              {"type":"LIGHT","startTime":"2026-11-18T00:00:00Z","endTime":"2026-11-18T06:00:00Z"}]}},
          {"dataSource":{"platform":"HEALTH_KIT","device":{"manufacturer":"Apple","displayName":"Apple Watch"}},
           "sleep":{"interval":{"startTime":"2026-11-17T21:00:00Z","endTime":"2026-11-18T06:00:00Z"},
                    "summary":{"minutesAsleep":"500"}}}
        ],"nextPageToken":"next"}
        """.utf8), kind: .sleep)
        let start = try XCTUnwrap(GoogleHealthTime.parse("2026-11-18T00:00:00Z"))
        let day = try XCTUnwrap(GoogleHealthMerge.days(
            points: [.sleep: page.points], from: start, until: start.addingTimeInterval(86_400), calendar: utc
        ).first)
        XCTAssertEqual(page.nextPageToken, "next")
        XCTAssertEqual(day.sleep?.asleep, 8 * 3600)
        XCTAssertEqual(day.sleep?.total(.deep), 2 * 3600)
        XCTAssertEqual(day.origins?[.sleep]?.first?.family, .fitbit)
    }

    func testHourlyWatchPriorityDeduplicationAndMatchingEnergy() throws {
        let first = try XCTUnwrap(GoogleHealthTime.parse("2026-11-18T10:00:00Z"))
        let second = first.addingTimeInterval(3600)
        let fitbit = GoogleMetricOrigin(family: .fitbit, device: "Charge 6")
        let watch = GoogleMetricOrigin(family: .appleWatch, device: "Apple Watch")
        let apple = GoogleHealthPoint.amount(80, start: first, end: first.addingTimeInterval(60), source: watch)
        let hours = GoogleHealthMerge.hours(steps: [
            .amount(100, start: first, end: first.addingTimeInterval(60), source: fitbit), apple, apple,
            .amount(50, start: second, end: second.addingTimeInterval(60), source: fitbit)
        ], energy: [
            .amount(12, start: first, end: first.addingTimeInterval(60), source: fitbit),
            .amount(4, start: second, end: second.addingTimeInterval(60), source: fitbit)
        ], from: first, until: second.addingTimeInterval(3600), calendar: utc)
        XCTAssertEqual(hours.map(\.steps), [80, 50])
        XCTAssertEqual(hours.map(\.stepOrigin), [watch, fitbit])
        XCTAssertEqual(hours.map(\.activeEnergy), [nil, 4])
    }

    func testDailyRMSSDStaysWithinIdentifiedDeviceBaseline() throws {
        let page = try GoogleHealthPage.decode(Data("""
        {"dataPoints":[
          {"dataSource":{"platform":"FITBIT","device":{"displayName":"Charge 6"}},
           "dailyHeartRateVariability":{"date":{"year":2026,"month":11,"day":18},"averageHeartRateVariabilityMilliseconds":42}},
          {"dataSource":{"platform":"HEALTH_KIT","device":{"displayName":"Apple Watch"}},
           "dailyHeartRateVariability":{"date":{"year":2026,"month":11,"day":18},"averageHeartRateVariabilityMilliseconds":75}}
        ]}
        """.utf8), kind: .hrv)
        let date = try XCTUnwrap(GoogleHealthTime.parse("2026-11-18T00:00:00Z"))
        let day = try XCTUnwrap(GoogleHealthMerge.days(
            points: [.hrv: page.points], from: date, until: date.addingTimeInterval(86_400), calendar: utc
        ).first)
        XCTAssertEqual(day.hrv, 42)
        var other = day
        other.origins = [.hrv: [.init(family: .fitbit, device: "Inspire 3")]]
        XCTAssertNil(ScoreEngine.baseline(for: \.hrv, today: day, history: Array(repeating: other, count: 5)))
        XCTAssertNotNil(ScoreEngine.baseline(for: \.hrv, today: day, history: Array(repeating: day, count: 5)))
        var unknown = day
        unknown.origins = [.hrv: [.init(family: .fitbit, device: nil)]]
        XCTAssertNil(ScoreEngine.baseline(for: \.hrv, today: unknown, history: Array(repeating: unknown, count: 5)))
    }

    func testParsesStringStepsAndIgnoresIPhone() throws {
        let page = try GoogleHealthPage.decode(Data("""
        {"dataPoints":[
          {"dataSource":{"platform":"FITBIT","device":{"displayName":"Charge 6"}},
           "steps":{"count":"100","interval":{"startTime":"2026-11-18T10:00:00Z","endTime":"2026-11-18T10:01:00Z"}}},
          {"dataSource":{"platform":"HEALTH_KIT","device":{"manufacturer":"Apple","formFactor":"PHONE"}},
           "steps":{"count":"950","interval":{"startTime":"2026-11-18T10:00:00Z","endTime":"2026-11-18T10:01:00Z"}}}
        ]}
        """.utf8), kind: .steps)
        let start = try XCTUnwrap(GoogleHealthTime.parse("2026-11-18T00:00:00Z"))
        let end = start.addingTimeInterval(86_400)
        let hours = GoogleHealthMerge.hours(steps: page.points, energy: [], from: start, until: end, calendar: utc)
        let day = GoogleHealthMerge.days(points: [:], from: start, until: end, calendar: utc, activity: hours).first
        XCTAssertEqual(page.points.count, 1)
        XCTAssertEqual(day?.steps, 100)
        XCTAssertEqual(day?.origins?[.steps]?.first?.family, .fitbit)
    }

    func testBothHoursDuringAutumnTimeChangeRemainSeparate() throws {
        var berlin = utc
        berlin.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let first = try XCTUnwrap(GoogleHealthTime.parse("2026-10-25T02:10:00+02:00"))
        let second = try XCTUnwrap(GoogleHealthTime.parse("2026-10-25T02:10:00+01:00"))
        let fitbit = GoogleMetricOrigin(family: .fitbit, device: "Charge 6")
        let hours = GoogleHealthMerge.hours(steps: [
            .amount(25, start: first, end: first.addingTimeInterval(60), source: fitbit),
            .amount(50, start: second, end: second.addingTimeInterval(60), source: fitbit)
        ], energy: [], from: berlin.startOfDay(for: first), until: second.addingTimeInterval(3600), calendar: berlin)
        XCTAssertEqual(hours.map(\.steps), [25, 50])
        XCTAssertEqual(hours.last?.start.timeIntervalSince(hours.first?.start ?? .distantPast), 3600)
    }

    func testNightVitalsUseDocumentedUnitsAndFitbitOrigin() throws {
        let oxygen = try GoogleHealthPage.decode(Data("""
        {"dataPoints":[{"dataSource":{"platform":"FITBIT","device":{"displayName":"Charge 6"}},
          "dailyOxygenSaturation":{"date":{"year":2026,"month":11,"day":18},"averagePercentage":97.5}}]}
        """.utf8), kind: .oxygen)
        let respiration = try GoogleHealthPage.decode(Data("""
        {"dataPoints":[{"dataSource":{"platform":"FITBIT","device":{"displayName":"Charge 6"}},
          "dailyRespiratoryRate":{"date":{"year":2026,"month":11,"day":18},"breathsPerMinute":15.2}}]}
        """.utf8), kind: .respiration)
        let date = try XCTUnwrap(GoogleHealthTime.parse("2026-11-18T00:00:00Z"))
        let day = GoogleHealthMerge.days(points: [.oxygen: oxygen.points, .respiration: respiration.points],
                                         from: date, until: date.addingTimeInterval(86_400), calendar: utc).first
        XCTAssertEqual(day?.spo2, 97.5)
        XCTAssertEqual(day?.respiratoryRate, 15.2)
        XCTAssertEqual(day?.origins?[.spo2]?.first?.family, .fitbit)
    }

    func testOAuthCallbackChecksSchemeStateAndDuplicateCode() throws {
        let scheme = "com.googleusercontent.apps.example"
        let valid = try XCTUnwrap(URL(string: "\(scheme):/oauth2callback?code=fixture&state=expected"))
        XCTAssertEqual(try GoogleHealthService.authorizationCode(valid, scheme: scheme, state: "expected"), "fixture")
        XCTAssertThrowsError(try GoogleHealthService.authorizationCode(valid, scheme: scheme, state: "other"))
        let duplicate = try XCTUnwrap(URL(string: "\(valid.absoluteString)&code=second"))
        XCTAssertThrowsError(try GoogleHealthService.authorizationCode(duplicate, scheme: scheme, state: "expected"))
    }

    func testSourceMigrationKeepsOnlyExplicitSampleChoice() {
        for old in ["health", "fitbit", "automatic", "unknown"] {
            XCTAssertEqual(DataHub.source(from: old), .google)
        }
        XCTAssertEqual(DataHub.source(from: nil), .google)
        XCTAssertEqual(DataHub.source(from: "sample"), .sample)
    }

    func testRefreshPreservesRefreshTokenIfResponseOmitsIt() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let old = GoogleOAuthTokens(accessToken: "fixture-old", refreshToken: "fixture-refresh", expiresAt: now)
        let data = Data(#"{"access_token":"fixture-new","expires_in":3600,"token_type":"Bearer"}"#.utf8)
        let updated = try GoogleOAuthTokens.decode(data, status: 200, previous: old, now: now)
        XCTAssertEqual(updated.refreshToken, old.refreshToken)
        XCTAssertEqual(updated.expiresAt, now.addingTimeInterval(3540))
        XCTAssertThrowsError(try GoogleOAuthTokens.decode(data, status: 200, previous: nil, now: now))
    }

    func testRefreshOnlyInvalidGrantRequiresReconnection() {
        let now = Date()
        let old = GoogleOAuthTokens(accessToken: "fixture-old", refreshToken: "fixture-refresh", expiresAt: now)
        let denied = Data(#"{"error":"invalid_grant"}"#.utf8)
        XCTAssertThrowsError(try GoogleOAuthTokens.decode(denied, status: 400, previous: old, now: now)) {
            XCTAssertEqual($0 as? GoogleHealthError, .reauthorize)
        }
        XCTAssertThrowsError(try GoogleOAuthTokens.decode(Data(), status: 503, previous: old, now: now)) {
            XCTAssertEqual($0 as? GoogleHealthError, .http(503))
        }
        XCTAssertThrowsError(try GoogleOAuthTokens.decode(Data("broken".utf8), status: 200, previous: old, now: now))
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
