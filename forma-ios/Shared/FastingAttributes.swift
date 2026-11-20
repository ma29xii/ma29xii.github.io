import ActivityKit
import Foundation

struct FastingAttributes: ActivityAttributes, Equatable, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let end: Date?
    }

    struct Progress {
        let elapsed: TimeInterval
        let target: TimeInterval

        var remaining: TimeInterval { max(0, target - elapsed) }
        var fraction: Double { target > 0 ? min(1, elapsed / target) : 0 }
        var reached: Bool { target > 0 && remaining == 0 }
    }

    let start: Date
    let targetHours: Double

    var timerInterval: ClosedRange<Date> {
        start...start.addingTimeInterval(targetHours * 3_600)
    }

    func progress(at date: Date, state: ContentState) -> Progress {
        let stop = min(state.end ?? date, date)
        return Progress(elapsed: max(0, stop.timeIntervalSince(start)),
                        target: timerInterval.upperBound.timeIntervalSince(start))
    }
}
