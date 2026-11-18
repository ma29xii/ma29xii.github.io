import Foundation

/// Realistische Beispieldaten (Standard: 180 Tage, für Körperalter). Werden in der App immer als „Beispieldaten“ gekennzeichnet.
enum SampleData {
    static func days(count: Int = 180, endingAt end: Date = .now) -> [DayMetrics] {
        let today = end.startOfDay
        return (0..<count).map { offset in
            let index = count - 1 - offset
            let date = today.adding(days: -index)
            let t = Double(offset)
            let wave = sin(t * 0.9) * 0.5 + sin(t * 0.37 + 1.3) * 0.5
            var day = DayMetrics(date: date)
            day.hrv = (56 + wave * 6 + (index == 0 ? 3 : 0)).rounded()
            day.restingHR = (53 - wave * 2 - (index == 0 ? 1 : 0)).rounded()
            day.respiratoryRate = ((14.3 + sin(t * 0.5) * 0.3) * 10).rounded() / 10
            day.spo2 = (96.5 + sin(t * 0.7) * 0.8).rounded()
            day.vo2max = ((44.0 + t / Double(max(1, count - 1)) * 3.0) * 10).rounded() / 10
            day.steps = index == 0 ? 6240 : (8200 + wave * 2600).rounded()
            day.activeEnergy = index == 0 ? 410 : (520 + wave * 160).rounded()
            day.sleep = night(for: date, variation: wave, isToday: index == 0)
            if offset % 2 == 0 && index != 0 {
                let names = ["Push", "Pull", "Beine", "Lauf"]
                day.workouts = [WorkoutSummary(name: names[(offset / 2) % 4], start: date.adding(minutes: 18 * 60),
                                               duration: (52 + wave * 8) * 60, energy: 380,
                                               isStrength: names[(offset / 2) % 4] != "Lauf")]
            }
            if index == 0 {
                day.workouts = [WorkoutSummary(name: "Spaziergang", start: date.adding(minutes: 12 * 60 + 10), duration: 34 * 60, energy: 110)]
            }
            return day
        }
    }

    /// Nacht vor `date`: 23:10 bis 06:40 mit typischen Phasen.
    static func night(for date: Date, variation: Double, isToday: Bool) -> SleepNight {
        let start = date.adding(minutes: -50 + variation * 15)
        let pattern: [(SleepNight.Stage, Double)] = [
            (.core, 14), (.deep, 50), (.core, 36), (.rem, 18), (.awake, 6), (.core, 46), (.deep, 30),
            (.core, 44), (.rem, 26), (.awake, 5), (.core, 60), (.deep, 20), (.rem, 28), (.core, 42), (.rem, 26), (.awake, 7)
        ]
        let scale = isToday ? 1.0 : 1 + variation * 0.06
        var cursor = start
        var segments: [SleepNight.Segment] = []
        for (stage, minutes) in pattern {
            let end = cursor.adding(minutes: minutes * scale)
            segments.append(.init(stage: stage, start: cursor, end: end))
            cursor = end
        }
        return SleepNight(start: start, end: cursor, segments: segments)
    }
}
