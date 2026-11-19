import Foundation

enum GoogleHealthMerge {
    private struct DailyValue {
        let value: Double
        let origin: GoogleMetricOrigin
    }

    private struct Amount {
        let value: Double
        let start: Date
        let end: Date
    }

    private struct Night {
        let value: SleepNight
        let main: Bool
        let updated: Date?
        let origin: GoogleMetricOrigin
    }

    private struct NightRecording: Hashable {
        let start: Date
        let origin: GoogleMetricOrigin
    }

    static func days(points: [GoogleHealthKind: [GoogleHealthPoint]], from: Date, until: Date,
                     calendar: Calendar, activity: [HourlyMetrics] = []) -> [DayMetrics] {
        let nights = nightsByDay(points[.sleep] ?? [], from: from, until: until, calendar: calendar)
        let workouts = workoutsByDay(points[.exercise] ?? [], from: from, until: until, calendar: calendar)
        let byDay = Dictionary(grouping: activity) { calendar.startOfDay(for: $0.start) }
        let vitalKinds: [GoogleHealthKind] = [.hrv, .restingHR, .respiration, .oxygen, .vo2, .temperature]
        let vitals = vitalKinds.map { dailyValues(points[$0] ?? [], kind: $0, calendar: calendar) }
        var result: [DayMetrics] = []
        var date = from
        while date < until {
            var day = DayMetrics(date: date, civilDay: CivilDay(date, in: calendar))
            if let night = nights[date] {
                day.sleep = night.value
                day.setOrigins([night.origin], for: .sleep)
            }
            if let sessions = workouts[date] {
                day.workouts = sessions.map(\.0)
                day.setOrigins(sessions.map(\.1), for: .workouts)
            }
            for (kind, values) in zip(vitalKinds, vitals) {
                guard let value = values[date], let series = kind.series else { continue }
                switch kind {
                case .hrv: day.hrv = value.value
                case .restingHR: day.restingHR = value.value
                case .respiration: day.respiratoryRate = value.value
                case .oxygen: day.spo2 = value.value
                case .vo2: day.vo2max = value.value
                case .temperature: day.skinTemperature = value.value
                default: break
                }
                day.setOrigins([value.origin], for: series)
            }
            if let hours = byDay[date] {
                let stepValues = hours.compactMap(\.steps)
                let energyValues = hours.compactMap(\.activeEnergy)
                if !stepValues.isEmpty {
                    day.steps = stepValues.reduce(0, +).rounded()
                    day.setOrigins(hours.compactMap(\.stepOrigin), for: .steps)
                }
                if !energyValues.isEmpty {
                    day.activeEnergy = energyValues.reduce(0, +)
                    day.setOrigins(hours.compactMap(\.energyOrigin), for: .activeEnergy)
                }
            }
            result.append(day.sanitized())
            guard let next = calendar.startOfDay(offsetBy: 1, from: date), next > date else { break }
            date = next
        }
        return result
    }

    static func hours(steps: [GoogleHealthPoint], energy: [GoogleHealthPoint], pulse: [GoogleHealthPoint] = [],
                      from: Date, until: Date, calendar: Calendar,
                      cachedStepOrigins: [Date: GoogleMetricOrigin] = [:]) -> [HourlyMetrics] {
        let stepBuckets = amountBuckets(steps, from: from, until: until, calendar: calendar)
        let energyBuckets = amountBuckets(energy, from: from, until: until, calendar: calendar)
        var pulseBuckets: [Date: [GoogleMetricOrigin: [Date: Double]]] = [:]
        for case .pulse(let value, let time, let source) in pulse where time >= from && time < until {
            guard let hour = calendar.dateInterval(of: .hour, for: time)?.start else { continue }
            pulseBuckets[hour, default: [:]][source, default: [:]][time] = value
        }
        let starts = Set(stepBuckets.keys).union(energyBuckets.keys).union(pulseBuckets.keys)
        return starts.sorted().compactMap { start in
            guard let interval = calendar.dateInterval(of: .hour, for: start) else { return nil }
            var hour = HourlyMetrics(start: start, end: interval.end)
            if let bySource = stepBuckets[start], let origin = preferred(bySource, family: .appleWatch) {
                hour.steps = nonOverlappingTotal(bySource[origin] ?? [])
                hour.stepOrigin = origin
                if let amounts = energyBuckets[start]?[origin] {
                    hour.activeEnergy = nonOverlappingTotal(amounts)
                    hour.energyOrigin = origin
                }
            } else if let bySource = energyBuckets[start],
                      let origin = cachedStepOrigins[start] ?? preferred(bySource, family: .appleWatch),
                      let amounts = bySource[origin] {
                hour.activeEnergy = nonOverlappingTotal(amounts)
                hour.energyOrigin = origin
            }
            if let bySource = pulseBuckets[start], let origin = preferred(bySource, family: .appleWatch),
               let samples = bySource[origin]?.values, !samples.isEmpty {
                hour.heartRate = samples.reduce(0, +) / Double(samples.count)
                hour.heartRateOrigin = origin
            }
            return hour
        }
    }

    private static func amountBuckets(_ points: [GoogleHealthPoint], from: Date, until: Date,
                                      calendar: Calendar) -> [Date: [GoogleMetricOrigin: [Amount]]] {
        var buckets: [Date: [GoogleMetricOrigin: [Amount]]] = [:]
        for case .amount(let value, let start, let end, let source) in points {
            let duration = end.timeIntervalSince(start)
            var cursor = max(start, from)
            let limit = min(end, until)
            while cursor < limit, let hour = calendar.dateInterval(of: .hour, for: cursor) {
                let next = min(hour.end, limit)
                guard next > cursor else { break }
                let part = value * next.timeIntervalSince(cursor) / duration
                buckets[hour.start, default: [:]][source, default: []].append(.init(value: part, start: cursor, end: next))
                cursor = next
            }
        }
        return buckets
    }

    /// Addiert pro ausgewähltem Modell nur den bislang unbedeckten Teil eines Intervalls.
    private static func nonOverlappingTotal(_ amounts: [Amount]) -> Double {
        var coveredUntil = Date.distantPast
        var total = 0.0
        for amount in amounts.sorted(by: {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.value > $1.value
        }) {
            let uncovered = amount.end.timeIntervalSince(max(amount.start, coveredUntil))
            guard uncovered > 0 else { continue }
            total += amount.value * uncovered / amount.end.timeIntervalSince(amount.start)
            coveredUntil = amount.end
        }
        return total
    }

    private static func preferred<T>(_ candidates: [GoogleMetricOrigin: T],
                                     family: GoogleMetricOrigin.Family) -> GoogleMetricOrigin? {
        candidates.keys.min { comesFirst($0, $1, family: family) }
    }

    private static func comesFirst(_ lhs: GoogleMetricOrigin, _ rhs: GoogleMetricOrigin,
                                   family: GoogleMetricOrigin.Family) -> Bool {
        if lhs.family != rhs.family { return lhs.family == family }
        if (lhs.device == nil) != (rhs.device == nil) { return lhs.device != nil }
        return (lhs.device ?? "") < (rhs.device ?? "")
    }

    private static func dailyValues(_ points: [GoogleHealthPoint], kind: GoogleHealthKind,
                                    calendar: Calendar) -> [Date: DailyValue] {
        var values: [Date: DailyValue] = [:]
        let range: ClosedRange<Double>
        switch kind {
        case .hrv: range = 1...400
        case .restingHR: range = 25...150
        case .respiration: range = 4...45
        case .oxygen: range = 50...100
        case .vo2: range = 8...100
        case .temperature: range = 20...45
        default: return values
        }
        for case .daily(let number, let year, let month, let day, let origin) in points where range.contains(number) {
            let parts = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: parts),
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day else { continue }
            let key = calendar.startOfDay(for: date)
            if let existing = values[key], !comesFirst(origin, existing.origin, family: .fitbit) { continue }
            values[key] = .init(value: number, origin: origin)
        }
        return values
    }

    private static func nightsByDay(_ points: [GoogleHealthPoint], from: Date, until: Date,
                                    calendar: Calendar) -> [Date: Night] {
        var recordings: [Date: [NightRecording: Night]] = [:]
        for case .sleep(let night, let main, let nap, let updated, let origin) in points {
            guard !nap, night.end >= from, night.end < until else { continue }
            let date = calendar.startOfDay(for: night.end)
            let key = NightRecording(start: night.start, origin: origin)
            let candidate = Night(value: night, main: main, updated: updated, origin: origin)
            if let old = recordings[date]?[key] {
                let oldRevision = old.updated ?? .distantPast
                let revision = updated ?? .distantPast
                if revision != oldRevision {
                    guard revision > oldRevision else { continue }
                } else if !preferredNight(candidate, over: old) { continue }
            }
            recordings[date, default: [:]][key] = candidate
        }
        return recordings.compactMapValues { daily in
            // Gerätepriorität gilt nur für Aufzeichnungen in der Größenordnung der längsten Nacht.
            let longest = daily.values.map { $0.value.asleep }.max() ?? 0
            return daily.values.filter { $0.value.asleep >= longest * 0.75 }
                .min { preferredNight($0, over: $1) }
        }
    }

    private static func preferredNight(_ lhs: Night, over rhs: Night) -> Bool {
        if lhs.main != rhs.main { return lhs.main }
        if lhs.origin.family != rhs.origin.family { return lhs.origin.family == .fitbit }
        if lhs.value.asleep != rhs.value.asleep { return lhs.value.asleep > rhs.value.asleep }
        if lhs.updated != rhs.updated { return (lhs.updated ?? .distantPast) > (rhs.updated ?? .distantPast) }
        if lhs.value.start != rhs.value.start { return lhs.value.start < rhs.value.start }
        if lhs.value.end != rhs.value.end { return lhs.value.end > rhs.value.end }
        return comesFirst(lhs.origin, rhs.origin, family: .fitbit)
    }

    private static func workoutsByDay(_ points: [GoogleHealthPoint], from: Date, until: Date,
                                      calendar: Calendar) -> [Date: [(WorkoutSummary, GoogleMetricOrigin)]] {
        let candidates = points.compactMap { point -> (WorkoutSummary, GoogleMetricOrigin)? in
            guard case .workout(let workout, let source) = point, workout.start >= from,
                  workout.start < until else { return nil }
            return (workout, source)
        }.sorted {
            if $0.1.family != $1.1.family { return $0.1.family == .appleWatch }
            return $0.0.start < $1.0.start
        }
        var selected: [(WorkoutSummary, GoogleMetricOrigin)] = []
        for candidate in candidates {
            let workout = candidate.0
            if !selected.contains(where: { workout.isDuplicate(of: $0.0) }) {
                selected.append(candidate)
            }
        }
        return Dictionary(grouping: selected.sorted { $0.0.start < $1.0.start }) {
            calendar.startOfDay(for: $0.0.start)
        }
    }
}
