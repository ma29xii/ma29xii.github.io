import Foundation
import SwiftData

/// Realistische Beispieldaten (Standard: 180 Tage, für Körperalter). Werden in der App immer als „Beispieldaten“ gekennzeichnet.
enum SampleData {
    static let weightKg = 76.4

    static func person(at date: Date = .now) -> PersonInfo {
        let birthday = Calendar.forma.date(byAdding: .year, value: -32, to: date)?.adding(days: -42)
        return PersonInfo(birthDate: birthday, sex: .male, origin: .assumed)
    }

    static func days(count: Int = 180, endingAt end: Date = .now) -> [DayMetrics] {
        let today = end.startOfDay
        return (0..<count).map { offset in
            let index = count - 1 - offset
            let date = today.adding(days: -index)
            // Die letzten 30 Tage bleiben wie in früheren Versionen (gleiche Phase der Wellen).
            let t = Double(offset - (count - 30))
            let wave = sin(t * 0.9) * 0.5 + sin(t * 0.37 + 1.3) * 0.5
            var day = DayMetrics(date: date)
            day.hrv = (56 + wave * 6 + (index == 0 ? 3 : 0)).rounded()
            day.restingHR = (53 - wave * 2 - (index == 0 ? 1 : 0) + (index >= 30 ? 4 : 0)).rounded()
            day.respiratoryRate = ((14.3 + sin(t * 0.5) * 0.3) * 10).rounded() / 10
            day.spo2 = (96.5 + sin(t * 0.7) * 0.8).rounded()
            if index % 7 == 0 { day.vo2max = ((44.0 + Double(offset) / Double(max(1, count - 1)) * 3.0) * 10).rounded() / 10 }
            day.steps = index == 0 ? 6240 : (8200 + wave * 2600 - (index >= 30 ? 1200 : 0)).rounded()
            day.activeEnergy = index == 0 ? 410 : (520 + wave * 160).rounded()
            day.sleep = night(for: date, variation: wave, isToday: index == 0)
            if index % 2 == 1 {
                let names = ["Push", "Pull", "Beine", "Lauf"]
                day.workouts = [WorkoutSummary(name: names[(offset / 2) % 4], start: date.adding(minutes: 18 * 60),
                                               duration: (52 + wave * 8) * 60, energy: 380,
                                               isStrength: names[(offset / 2) % 4] != "Lauf")]
            }
            if index == 0 {
                day.workouts = [
                    WorkoutSummary(name: "Push", start: date.adding(minutes: 7 * 60), duration: 49 * 60, energy: 230, isStrength: true),
                    WorkoutSummary(name: "Spaziergang", start: date.adding(minutes: 12 * 60 + 10), duration: 34 * 60, energy: 110)
                ]
            }
            return day
        }
    }

    /// Nur der flüchtige Beispiel-Speicher erhält aufgezeichnete Einheiten.
    @MainActor
    static func seedWorkouts(_ days: [DayMetrics], in context: ModelContext) {
        guard context.container.configurations.allSatisfy(\.isStoredInMemoryOnly),
              let count = try? context.fetchCount(FetchDescriptor<WorkoutSession>()), count == 0 else { return }
        let workouts = days.suffix(60).flatMap(\.workouts).filter(\.isStrength)
        for (index, workout) in workouts.enumerated() {
            guard let template = TrainingSeed.routines.first(where: { $0.0 == workout.name }) else { continue }
            var sets: [SetRecord] = []
            for item in template.1 {
                let (exercise, _, count, reps, weight, _) = item
                for set in 0..<count {
                    let progression: Double = index < workouts.count / 2 ? 2.5 : 0
                    let load = weight > 0 ? max(0.5, weight - progression) : 0
                    sets.append(SetRecord(order: sets.count, exerciseName: exercise, weight: load,
                                          reps: max(1, reps - (set == count - 1 ? 1 : 0)), rir: set == 0 ? 3 : 2, isWarmup: false))
                }
            }
            context.insert(WorkoutSession(title: workout.name, start: workout.start,
                                          end: workout.start.addingTimeInterval(workout.duration), sets: sets))
        }
        try? context.save()
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
