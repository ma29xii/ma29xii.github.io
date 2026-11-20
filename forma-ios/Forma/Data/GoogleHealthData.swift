import CoreFoundation
import CryptoKit
import Foundation

struct GoogleMetricOrigin: Hashable, Codable, Sendable {
    enum Family: String, Codable, Sendable {
        case fitbit, appleWatch, googleWearable
    }

    var family: Family
    /// Google v4 veröffentlicht hier das Modell, keine Seriennummer.
    var device: String?

    var title: String {
        switch family {
        case .fitbit: "Fitbit"
        case .appleWatch: "Apple Watch"
        case .googleWearable: "Google Health"
        }
    }
}

enum GoogleHealthTime {
    static func parse(_ value: String) -> Date? {
        let count = value.utf8.count
        guard (20...35).contains(count) else { return nil }
        let bytes = Array(value.utf8)
        guard bytes[4] == 45, bytes[7] == 45, bytes[10] == 84, bytes[13] == 58, bytes[16] == 58,
              bytes.last == 90 || (count >= 25 && [43, 45].contains(bytes[count - 6]) && bytes[count - 3] == 58)
        else { return nil }
        func two(_ index: Int, in range: ClosedRange<Int>) -> Bool {
            let a = Int(bytes[index]) - 48
            let b = Int(bytes[index + 1]) - 48
            return (0...9).contains(a) && (0...9).contains(b) && range.contains(a * 10 + b)
        }
        guard two(5, in: 1...12), two(8, in: 1...31), two(11, in: 0...23),
              two(14, in: 0...59), two(17, in: 0...59) else { return nil }
        return (try? Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle(timeZoneSeparator: .colon).parse(value))
    }

    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func physical(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

enum GoogleHealthKind: String, CaseIterable, Sendable {
    case sleep, steps, exercise
    case hrv = "daily-heart-rate-variability"
    case restingHR = "daily-resting-heart-rate"
    case respiration = "daily-respiratory-rate"
    case oxygen = "daily-oxygen-saturation"
    case vo2 = "daily-vo2-max"
    case energy = "active-energy-burned"
    case pulse = "heart-rate"
    case temperature = "daily-sleep-temperature-derivations"

    static let dailyImport: [Self] = [.sleep, .steps, .exercise, .hrv, .restingHR, .respiration, .oxygen, .vo2, .energy, .temperature]

    var series: MetricSeries? {
        switch self {
        case .sleep: .sleep
        case .steps: .steps
        case .exercise: .workouts
        case .hrv: .hrv
        case .restingHR: .restingHR
        case .respiration: .respiratoryRate
        case .oxygen: .spo2
        case .vo2: .vo2max
        case .energy: .activeEnergy
        case .pulse: nil
        case .temperature: .skinTemperature
        }
    }

    var jsonKey: String {
        let parts = rawValue.split(separator: "-")
        return String(parts[0]) + parts.dropFirst().map { $0.prefix(1).uppercased() + String($0.dropFirst()) }.joined()
    }

    func filter(from: Date, until: Date, calendar: Calendar) -> String {
        let prefix = rawValue.replacingOccurrences(of: "-", with: "_")
        let field: String
        let lower: String
        let upper: String
        switch self {
        case .sleep, .steps, .energy, .pulse:
            switch self {
            case .sleep: field = "interval.end_time"
            case .pulse: field = "sample_time.physical_time"
            default: field = "interval.start_time"
            }
            lower = GoogleHealthTime.physical(from)
            upper = GoogleHealthTime.physical(until)
        case .exercise:
            field = "interval.civil_start_time"
            // Ein Reisetag kann am Aufnahmeort ein anderes Datum als auf diesem iPhone haben.
            lower = GoogleHealthTime.day(from.addingTimeInterval(-86_400), calendar: calendar)
            upper = GoogleHealthTime.day(until.addingTimeInterval(86_400), calendar: calendar)
        default:
            field = "date"
            lower = GoogleHealthTime.day(from, calendar: calendar)
            upper = GoogleHealthTime.day(until, calendar: calendar)
        }
        let key = "\(prefix).\(field)"
        return "\(key) >= \"\(lower)\" AND \(key) < \"\(upper)\""
    }
}

enum GoogleHealthPoint: Sendable {
    case daily(Double, _ year: Int, _ month: Int, _ day: Int, source: GoogleMetricOrigin)
    case amount(Double, start: Date, end: Date, source: GoogleMetricOrigin)
    case pulse(Double, time: Date, source: GoogleMetricOrigin)
    case sleep(SleepNight, main: Bool, nap: Bool, updated: Date?, source: GoogleMetricOrigin)
    case workout(WorkoutSummary, source: GoogleMetricOrigin)
}

struct GoogleHealthPage: Sendable {
    var points: [GoogleHealthPoint]
    var nextPageToken: String?
    let hasRows: Bool

    static func decode(_ data: Data, kind: GoogleHealthKind, reconciledWearables: Bool = false) throws -> Self {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleHealthError.invalidResponse
        }
        let entries: [[String: Any]]
        if let raw = json["dataPoints"] {
            guard let rows = raw as? [[String: Any]] else { throw GoogleHealthError.invalidResponse }
            entries = rows
        } else {
            guard json.keys.allSatisfy({ $0 == "nextPageToken" }) else { throw GoogleHealthError.invalidResponse }
            entries = []
        }
        if let token = json["nextPageToken"], !(token is String) { throw GoogleHealthError.invalidResponse }
        return Self(points: try entries.compactMap { try point($0, kind: kind, reconciledWearables: reconciledWearables) },
                    nextPageToken: json["nextPageToken"] as? String, hasRows: !entries.isEmpty)
    }

    private static func point(_ entry: [String: Any], kind: GoogleHealthKind,
                              reconciledWearables: Bool) throws -> GoogleHealthPoint? {
        guard let payload = entry[kind.jsonKey] as? [String: Any] else { throw GoogleHealthError.invalidResponse }
        let source: GoogleMetricOrigin
        if reconciledWearables {
            source = GoogleMetricOrigin(family: .googleWearable, device: nil)
        } else {
            guard let rawSource = try origin(entry["dataSource"]) else { return nil }
            source = rawSource
        }
        switch kind {
        case .steps, .energy:
            let key = kind == .steps ? "count" : "kcal"
            guard let (start, end) = interval(payload["interval"]), end.timeIntervalSince(start) <= 3600,
                  let value = number(payload[key]), (0...1_000_000).contains(value) else {
                throw GoogleHealthError.invalidResponse
            }
            return .amount(value, start: start, end: end, source: source)
        case .sleep:
            guard let (start, end) = interval(payload["interval"]), end.timeIntervalSince(start) <= 86_400 else {
                throw GoogleHealthError.invalidResponse
            }
            let metadata = payload["metadata"] as? [String: Any]
            guard payload["metadata"] == nil || metadata != nil else { throw GoogleHealthError.invalidResponse }
            let main = try sleepFlag(metadata?["mainSleep"] ?? metadata?["main"])
            let nap = try sleepFlag(metadata?["nap"])
            let updated = date(payload["updateTime"])
            guard payload["updateTime"] == nil || updated != nil else { throw GoogleHealthError.invalidResponse }
            let stages = payload["stages"] as? [[String: Any]]
            guard payload["stages"] == nil || stages != nil else { throw GoogleHealthError.invalidResponse }
            var segments: [SleepNight.Segment] = []
            for stage in stages ?? [] {
                guard let (stageStart, stageEnd) = interval(stage) else { throw GoogleHealthError.invalidResponse }
                let lower = max(start, stageStart)
                let upper = min(end, stageEnd)
                guard upper > lower else { continue }
                let type: SleepNight.Stage
                switch stage["type"] as? String {
                case "AWAKE": type = .awake
                case "DEEP": type = .deep
                case "LIGHT": type = .core
                case "REM": type = .rem
                case "ASLEEP": type = .unspecified
                default: continue
                }
                segments.append(.init(stage: type, start: lower, end: upper))
            }
            let summary = payload["summary"] as? [String: Any]
            let asleepSeconds = (number(summary?["minutesAsleep"]) ?? 0) * 60
            let reported = asleepSeconds > 0 && asleepSeconds <= end.timeIntervalSince(start) ? asleepSeconds : nil
            let night = SleepNight(start: start, end: end, segments: segments, reportedAsleep: reported)
            guard night.asleep > 0 else { return nil }
            return .sleep(night, main: main, nap: nap, updated: updated, source: source)
        case .exercise:
            guard let (start, end) = interval(payload["interval"]), end.timeIntervalSince(start) <= 86_400 else {
                throw GoogleHealthError.invalidResponse
            }
            let type = payload["exerciseType"] as? String ?? ""
            let strength = ["BODY_WEIGHT", "FREE_WEIGHTS", "FUNCTIONAL_STRENGTH_TRAINING", "POWERLIFTING",
                            "STRENGTH_TRAINING", "WEIGHTLIFTING", "WEIGHT_MACHINES", "WEIGHTS", "RESISTANCE_BANDS"].contains(type)
            let rawName = payload["displayName"] as? String ?? ""
            let name = String(rawName.prefix(100))
            let summary = payload["metricsSummary"] as? [String: Any]
            let id = workoutID(entry["name"] as? String ?? "\(type)/\(start)/\(end)/\(source.title)")
            return .workout(.init(id: id, name: name.isEmpty ? "Training" : name, start: start,
                                  duration: end.timeIntervalSince(start), energy: number(summary?["caloriesKcal"]),
                                  isStrength: strength, activityType: type.isEmpty ? nil : type), source: source)
        case .pulse:
            let sample = payload["sampleTime"] as? [String: Any]
            guard let time = date(sample?["physicalTime"]), let value = number(payload["beatsPerMinute"]),
                  (1...300).contains(value) else { throw GoogleHealthError.invalidResponse }
            return .pulse(value, time: time, source: source)
        default:
            return try daily(payload, kind: kind, source: source)
        }
    }

    private static func daily(_ payload: [String: Any], kind: GoogleHealthKind,
                              source: GoogleMetricOrigin) throws -> GoogleHealthPoint? {
        let key: String
        switch kind {
        case .hrv:
            // Die v4-Reihe ist RMSSD. Fremdimporte ohne nachweisbare Methode kommen nicht in diese Reihe.
            guard source.family == .fitbit else { return nil }
            key = "averageHeartRateVariabilityMilliseconds"
            if payload[key] == nil { return nil } // laut Schema optional
        case .restingHR: key = "beatsPerMinute"
        case .respiration, .oxygen, .temperature:
            guard source.family == .fitbit else { return nil }
            switch kind {
            case .respiration: key = "breathsPerMinute"
            case .oxygen: key = "averagePercentage"
            default: key = "nightlyTemperatureCelsius"
            }
        case .vo2: key = "vo2Max"
        default: return nil
        }
        guard let value = number(payload[key]), let civil = payload["date"] as? [String: Any],
              let year = civil["year"] as? Int, (1900...2200).contains(year),
              let month = civil["month"] as? Int, (1...12).contains(month),
              let day = civil["day"] as? Int,
              DateComponents(year: year, month: month, day: day).isValidDate(in: Calendar(identifier: .gregorian)) else {
            throw GoogleHealthError.invalidResponse
        }
        return .daily(value, year, month, day, source: source)
    }

    private static func origin(_ value: Any?) throws -> GoogleMetricOrigin? {
        guard let value else { return nil }
        guard let raw = value as? [String: Any],
              raw["platform"] == nil || raw["platform"] is String,
              raw["recordingMethod"] == nil || raw["recordingMethod"] is String else {
            throw GoogleHealthError.invalidResponse
        }
        guard let platform = raw["platform"] as? String, !platform.isEmpty,
              platform != "PLATFORM_UNSPECIFIED" else { return nil }
        if raw["recordingMethod"] as? String == "MANUAL" { return nil }
        let device = raw["device"] as? [String: Any]
        guard raw["device"] == nil || device != nil,
              ["displayName", "manufacturer", "formFactor"].allSatisfy({ device?[$0] == nil || device?[$0] is String }) else {
            throw GoogleHealthError.invalidResponse
        }
        let name = (device?["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let manufacturer = (device?["manufacturer"] as? String)?.lowercased()
        let model = name.flatMap { $0.isEmpty ? nil : String($0.prefix(120)) }
        let form = device?["formFactor"] as? String
        switch platform {
        case "FITBIT":
            guard form != "PHONE", manufacturer != "apple",
                  model?.localizedCaseInsensitiveContains("pixel watch") != true else { return nil }
            return .init(family: .fitbit, device: model)
        case "HEALTH_KIT":
            guard model?.localizedCaseInsensitiveContains("apple watch") == true
                    || (manufacturer == "apple" && form == "WATCH") else { return nil }
            return .init(family: .appleWatch, device: model)
        default:
            return nil
        }
    }

    private static func sleepFlag(_ value: Any?) throws -> Bool {
        guard let value else { return false }
        guard let boolean = value as? NSNumber, CFGetTypeID(boolean) == CFBooleanGetTypeID() else {
            throw GoogleHealthError.invalidResponse
        }
        return boolean.boolValue
    }

    private static func number(_ value: Any?) -> Double? {
        if let string = value as? String, let parsed = Double(string), parsed.isFinite { return parsed }
        guard let numeric = value as? NSNumber, CFGetTypeID(numeric) != CFBooleanGetTypeID(),
              numeric.doubleValue.isFinite else { return nil }
        return numeric.doubleValue
    }

    private static func workoutID(_ input: String) -> UUID {
        let hash = Array(SHA256.hash(data: Data(input.utf8)))
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]))
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap(GoogleHealthTime.parse)
    }

    private static func interval(_ value: Any?) -> (Date, Date)? {
        guard let raw = value as? [String: Any], let start = date(raw["startTime"]),
              let end = date(raw["endTime"]), end > start else { return nil }
        return (start, end)
    }
}
