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
        return (0..<max(0, count)).reversed().map { index in
            let date = today.adding(days: -index)
            // Der Abstand zu heute hält dieselben Tage auch in kürzeren Vorschauen stabil.
            let t = 29 - Double(index)
            let wave = sin(t * 0.9) * 0.5 + sin(t * 0.37 + 1.3) * 0.5
            var noise = DailyNoise(daysAgo: index)
            let sleepVariation = wave * 0.65 + noise.next() * 0.35
            let stepsVariation = noise.next()
            let lighterWeek = (36...43).contains(index)
            let lateNight = index % 7 == 4 || index % 7 == 5

            var day = DayMetrics(date: date)
            day.hrv = (56 + wave * 6 + (index == 0 ? 3 : 0)).rounded()
            day.restingHR = (54 - wave * 2.7 - (index == 0 ? 1 : 0)).rounded()
            day.respiratoryRate = ((14.3 + sin(t * 0.5) * 0.3) * 10).rounded() / 10
            day.spo2 = (96.5 + sin(t * 0.7) * 0.8).rounded()
            day.skinTemperature = ((33.6 + sin(t * 0.6) * 0.22 - wave * 0.15) * 10).rounded() / 10
            // Wöchentliche VO₂max-Schätzungen schwanken leicht um einen stabilen Trainingsstand.
            if index % 7 == 0 {
                day.vo2max = ((45.5 + sin(Double(index) * 0.14) * 0.4) * 10).rounded() / 10
            }
            let bedtime = -50 + wave * 15 + (lateNight && !lighterWeek ? 85 : 0)
            let sleepScale = if index == 0 { 1.0 }
                else if lighterWeek { 1.22 + wave * 0.01 }
                else { 1 + sleepVariation * 0.12 - (lateNight ? 0.13 : 0) }
            day.sleep = night(for: date, bedtimeMinutes: bedtime, scale: sleepScale)

            let training: (name: String, minutes: Double, kcal: Double)? = switch index % 7 {
            case 2: ("Beine", 59, 310)
            case 3: ("Lauf", 36, 340)
            case 4: ("Pull", 51, 250)
            case 6: ("Push", 54, 270)
            default: nil
            }
            if let training, !lighterWeek {
                let start = date.adding(minutes: 18 * 60)
                day.workouts = [WorkoutSummary(id: workoutID(on: date), name: training.name, start: start,
                                               duration: (training.minutes + wave * 6) * 60,
                                               energy: training.kcal, isStrength: training.name != "Lauf")]
            }
            let workoutEnergy = day.workouts.first?.energy ?? 0
            let walkingSteps = lighterWeek ? 9100 + wave * 650 : 8150 + wave * 1800 + stepsVariation * 650
            day.steps = (walkingSteps + (day.workouts.isEmpty ? 0 : 500)).rounded()
            day.activeEnergy = ((lighterWeek ? 270 : 320) + wave * 110 + workoutEnergy).rounded()
            if index == 0 {
                day.steps = 6240
                day.activeEnergy = 410
                day.workouts = [
                    WorkoutSummary(id: workoutID(on: date), name: "Push", start: date.adding(minutes: 7 * 60),
                                   duration: 49 * 60, energy: 230, isStrength: true),
                    WorkoutSummary(id: workoutID(on: date, slot: 1), name: "Spaziergang",
                                   start: date.adding(minutes: 12 * 60 + 10), duration: 34 * 60, energy: 110)
                ]
            }
            return day
        }
    }

    private struct DailyNoise {
        private var state: UInt64

        init(daysAgo: Int) {
            state = 0x466f726d61 &+ (UInt64(daysAgo) &* 0x9e3779b97f4a7c15)
        }

        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return Double(state >> 32) / Double(UInt32.max) * 2 - 1
        }
    }

    private static func workoutID(on date: Date, slot: UInt8 = 0) -> UUID {
        let day = CivilDay(date, in: .forma)
        return UUID(uuid: (0x46, 0x6f, 0x72, 0x6d, 0x61, 0, 0x40, 0, 0x80, 0, 0,
                           UInt8(truncatingIfNeeded: day.year >> 8), UInt8(truncatingIfNeeded: day.year),
                           UInt8(day.month), UInt8(day.day), slot))
    }

    /// Nur der flüchtige Beispiel-Speicher erhält aufgezeichnete Einheiten.
    @MainActor
    static func seedWorkouts(_ days: [DayMetrics], in context: ModelContext) {
        guard context.container.configurations.allSatisfy(\.isStoredInMemoryOnly),
              let count = try? context.fetchCount(FetchDescriptor<WorkoutSession>()), count == 0 else { return }
        let workouts = days.suffix(60).flatMap(\.workouts).filter(\.isStrength)
        for (index, workout) in workouts.enumerated() {
            guard let template = TrainingSeed.routines.first(where: { $0.0 == workout.name }) else { continue }
            let earlierBlocks = Double(max(0, 3 - index / 5))
            var sets: [SetRecord] = []
            for item in template.1 {
                let (exercise, _, count, reps, weight, _) = item
                let increment = weight >= 30 ? 2.5 : 1.0
                let load = weight > 0 ? max(0.5, weight - earlierBlocks * increment) : 0
                for set in 0..<count {
                    sets.append(SetRecord(order: sets.count, exerciseName: exercise, weight: load,
                                          reps: max(1, reps - (set == count - 1 ? 1 : 0)), rir: set == 0 ? 3 : 2, isWarmup: false))
                }
            }
            context.insert(WorkoutSession(title: workout.name, start: workout.start,
                                          end: workout.start.addingTimeInterval(workout.duration), sets: sets))
        }
        try? context.save()
    }

    /// Nacht mit typischen Phasen vom Vorabend bis zum Morgen.
    private static func night(for date: Date, bedtimeMinutes: Double, scale: Double) -> SleepNight {
        let start = date.adding(minutes: bedtimeMinutes)
        let pattern: [(SleepNight.Stage, Double)] = [
            (.core, 14), (.deep, 50), (.core, 36), (.rem, 18), (.awake, 6), (.core, 46), (.deep, 30),
            (.core, 44), (.rem, 26), (.awake, 5), (.core, 60), (.deep, 20), (.rem, 28), (.core, 42), (.rem, 26), (.awake, 7)
        ]
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
