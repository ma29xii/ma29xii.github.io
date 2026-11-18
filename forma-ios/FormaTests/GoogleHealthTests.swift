import Foundation
import XCTest
@testable import Forma

final class GoogleHealthTests: XCTestCase {
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
