import Foundation

enum StepGoal {
    /// Persönliches Ziel auf Basis der letzten 28 abgeschlossenen Kalendertage.
    static func target(on date: Date, history: [DayMetrics], recovery: Int? = nil,
                       sleepScore: Int? = nil, sleepDebt: TimeInterval? = nil,
                       strainTarget: ClosedRange<Int>? = nil, calendar: Calendar = .forma) -> Int? {
        let today = calendar.startOfDay(for: date)
        guard let firstDay = calendar.startOfDay(offsetBy: -28, from: today) else { return nil }

        var stepsByDay: [Date: Double] = [:]
        for day in history where day.date >= firstDay && day.date < today {
            guard let steps = day.steps, (0...150_000).contains(steps) else { continue }
            stepsByDay[calendar.startOfDay(for: day.date)] = steps
        }
        guard stepsByDay.count >= 7 else { return nil }
        let average = stepsByDay.values.sorted().reduce(0, +) / Double(stepsByDay.count)

        let hasSleepDebt = sleepDebt.map { $0.isFinite && $0 >= 3_600 } ?? false
        var percent = 100.0
        if let recovery, recovery < 34 {
            percent -= 10
        } else if let recovery, recovery >= 67, let sleepScore, sleepScore >= 85, !hasSleepDebt {
            percent += 10
        }
        if hasSleepDebt { percent -= 10 }
        if let strainTarget, strainTarget.upperBound >= 50 { percent -= 5 }

        let adjusted = average * percent / 100
        let rounded = (adjusted / 50).rounded() * 50
        return Int(rounded).clamped(4_000, 16_000)
    }
}
