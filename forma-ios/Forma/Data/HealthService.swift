import Foundation
import HealthKit

/// Liest Daten aus Apple Health (nur lesen).
actor HealthService {
    private let store = HKHealthStore()

    nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.vo2Max),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.heartRate),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex)
        ]
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: Hintergrund-Synchronisierung

    /// Typen, deren Beobachter läuft (pro Typ, damit fehlgeschlagene erneut registriert werden können).
    private var observing: Set<String> = []

    /// Lässt Apple Health Forma wecken, sobald neue Daten da sind – auch wenn die App geschlossen ist.
    /// Schlaf, HRV, Ruhepuls und Trainings sofort, Schritte und Energie höchstens stündlich.
    /// Muss bei jedem App-Start erneut gestartet werden (auch beim Start im Hintergrund).
    /// Gibt die Typen zurück, deren Hintergrundzustellung nicht eingerichtet werden konnte (Codex R-02-06).
    func startObserving(onChange: @escaping @Sendable () async -> Void) async -> [String] {
        guard isAvailable else { return ["Apple Health"] }
        let types: [(HKSampleType, HKUpdateFrequency, String)] = [
            (HKCategoryType(.sleepAnalysis), .immediate, "Schlaf"),
            (HKQuantityType(.heartRateVariabilitySDNN), .immediate, "HRV"),
            (HKQuantityType(.restingHeartRate), .immediate, "Ruhepuls"),
            (HKObjectType.workoutType(), .immediate, "Trainings"),
            (HKQuantityType(.stepCount), .hourly, "Schritte"),
            (HKQuantityType(.activeEnergyBurned), .hourly, "Aktive Energie")
        ]
        var failed: [String] = []
        for (type, frequency, title) in types where !observing.contains(type.identifier) {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                nonisolated(unsafe) let done = completion
                guard error == nil else { done(); return }
                Task {
                    await onChange()
                    done() // HealthKit erwartet die Rückmeldung, sonst drosselt es die Zustellung.
                }
            }
            store.execute(query)
            do {
                try await store.enableBackgroundDelivery(for: type, frequency: frequency)
                observing.insert(type.identifier)
            } catch {
                store.stop(query)
                failed.append(title)
            }
        }
        return failed
    }

    /// Geburtsdatum und Geschlecht aus Apple Health (falls freigegeben und eingetragen).
    func person() -> (birthDate: Date?, sex: BiologicalSex) {
        let components = try? store.dateOfBirthComponents()
        let birthDate = components.flatMap { Calendar(identifier: .gregorian).date(from: $0) }
        let sex: BiologicalSex
        switch (try? store.biologicalSex())?.biologicalSex {
        case .male?: sex = .male
        case .female?: sex = .female
        default: sex = .unknown
        }
        return (birthDate, sex)
    }

    /// Ergebnis eines Imports: Tage plus die Messreihen, deren Abfrage fehlgeschlagen ist
    /// (z. B. weil das iPhone gesperrt war). Leer heißt: erfolgreich gelesen, nur keine Werte (Codex R-02-01).
    struct ImportResult: Sendable {
        var days: [DayMetrics]
        var failed: Set<MetricSeries>
    }

    /// Lädt die letzten `count` Tage (inklusive heute).
    func loadDays(count: Int = 30) async -> ImportResult {
        let today = Date.now.startOfDay
        let start = today.adding(days: -(count - 1))
        var days: [Date: DayMetrics] = [:]
        for i in 0..<count {
            let d = start.adding(days: i)
            days[d] = DayMetrics(date: d)
        }

        let hrv = await dailyValues(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), option: .discreteAverage, from: start)
        let rhr = await dailyValues(.restingHeartRate, unit: .count().unitDivided(by: .minute()), option: .discreteAverage, from: start)
        let resp = await dailyValues(.respiratoryRate, unit: .count().unitDivided(by: .minute()), option: .discreteAverage, from: start)
        let spo2 = await dailyValues(.oxygenSaturation, unit: .percent(), option: .discreteAverage, from: start)
        let vo2 = await dailyValues(.vo2Max, unit: HKUnit(from: "ml/kg*min"), option: .discreteAverage, from: start)
        let steps = await dailyValues(.stepCount, unit: .count(), option: .cumulativeSum, from: start)
        let energy = await dailyValues(.activeEnergyBurned, unit: .kilocalorie(), option: .cumulativeSum, from: start)
        let nights = await sleepNights(from: start.adding(days: -1))
        let workouts = await workouts(from: start)

        var failed: Set<MetricSeries> = []
        if hrv == nil { failed.insert(.hrv) }
        if rhr == nil { failed.insert(.restingHR) }
        if resp == nil { failed.insert(.respiratoryRate) }
        if spo2 == nil { failed.insert(.spo2) }
        if vo2 == nil { failed.insert(.vo2max) }
        if steps == nil { failed.insert(.steps) }
        if energy == nil { failed.insert(.activeEnergy) }
        if nights == nil { failed.insert(.sleep) }
        if workouts == nil { failed.insert(.workouts) }

        for key in days.keys {
            days[key]?.hrv = hrv?[key]
            days[key]?.restingHR = rhr?[key]
            days[key]?.respiratoryRate = resp?[key]
            days[key]?.spo2 = spo2?[key].map { $0 * 100 }
            days[key]?.vo2max = vo2?[key]
            days[key]?.steps = steps?[key]
            days[key]?.activeEnergy = energy?[key]
            days[key]?.sleep = nights?[key]
            days[key]?.workouts = workouts?[key] ?? []
        }
        // VO₂max nicht fortschreiben: nur echte Messtage zählen (Codex R-01-09). Anzeigen nehmen den letzten Wert.
        return ImportResult(days: days.keys.sorted().compactMap { days[$0] }, failed: failed)
    }

    /// nil = Abfrage fehlgeschlagen (nicht: keine Werte).
    private func dailyValues(_ id: HKQuantityTypeIdentifier, unit: HKUnit, option: HKStatisticsOptions, from start: Date) async -> [Date: Double]? {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: option,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await descriptor.result(for: store)
            var result: [Date: Double] = [:]
            for stats in collection.statistics() {
                let quantity = option == .cumulativeSum ? stats.sumQuantity() : stats.averageQuantity()
                if let quantity { result[stats.startDate.startOfDay] = quantity.doubleValue(for: unit) }
            }
            return result
        } catch {
            return nil
        }
    }

    /// Schlaf je Aufwachtag (Codex R-01-06):
    /// 1. Phasen pro Quelle (Uhr, Ring, App) getrennt halten – keine Doppelzählung überlappender Tracker.
    /// 2. Pro Quelle zusammenhängende Blöcke bilden (Lücke über 90 min trennt) – Nickerchen werden kein Teil der Nacht.
    /// 3. Pro Aufwachtag den längsten Block wählen; bei Gleichstand die Quelle mit Tief-/REM-Phasen.
    private func sleepNights(from start: Date) async -> [Date: SleepNight]? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return nil }
        var bySource: [String: [SleepNight.Segment]] = [:]
        for sample in samples {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            let stage: SleepNight.Stage
            switch value {
            case .awake: stage = .awake
            case .asleepREM: stage = .rem
            case .asleepDeep: stage = .deep
            case .asleepCore, .asleepUnspecified: stage = .core
            default: continue // „Im Bett“ wird nicht als Phase gezählt
            }
            guard sample.endDate > sample.startDate else { continue }
            let source = sample.sourceRevision.source.bundleIdentifier
            bySource[source, default: []].append(.init(stage: stage, start: sample.startDate, end: sample.endDate))
        }
        return SleepNight.mainNights(bySource: bySource)
    }

    private func workouts(from start: Date) async -> [Date: [WorkoutSummary]]? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return nil }
        var result: [Date: [WorkoutSummary]] = [:]
        for w in workouts {
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let strength = [.traditionalStrengthTraining, .functionalStrengthTraining].contains(w.workoutActivityType)
            let summary = WorkoutSummary(name: Self.name(for: w.workoutActivityType), start: w.startDate, duration: w.duration, energy: kcal, isStrength: strength)
            result[w.startDate.startOfDay, default: []].append(summary)
        }
        return result
    }

    private static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Krafttraining"
        case .running: "Lauf"
        case .cycling: "Radfahren"
        case .walking: "Gehen"
        case .swimming: "Schwimmen"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Yoga"
        case .rowing: "Rudern"
        case .hiking: "Wandern"
        default: "Training"
        }
    }
}
