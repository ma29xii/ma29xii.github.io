import ActivityKit
import Foundation

struct LiveTrainingAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let exerciseName: String?
        let setNumber: Int?
        let isWarmup: Bool
        let pauseEndsAt: Date?

        init(exerciseName: String?, setNumber: Int?, isWarmup: Bool, pauseEndsAt: Date?) {
            let trimmed = exerciseName?.trimmingCharacters(in: .whitespacesAndNewlines)
            // ActivityKit zählt Bytes. Skalare zu begrenzen hält auch zusammengesetzte Emojis klein.
            self.exerciseName = trimmed.flatMap {
                $0.isEmpty ? nil : String(String.UnicodeScalarView($0.unicodeScalars.prefix(80)))
            }
            self.setNumber = setNumber.flatMap { $0 > 0 ? $0 : nil }
            self.isWarmup = isWarmup
            self.pauseEndsAt = pauseEndsAt.flatMap { $0.timeIntervalSinceReferenceDate.isFinite ? $0 : nil }
        }

        func pauseInterval(at date: Date) -> ClosedRange<Date>? {
            guard let pauseEndsAt, date < pauseEndsAt else { return nil }
            return date...pauseEndsAt
        }
    }

    let workoutID: UUID
}
