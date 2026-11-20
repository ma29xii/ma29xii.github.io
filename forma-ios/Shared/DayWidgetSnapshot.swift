import Foundation

/// Tageswerte für die kleinen Widgets (Health Age, Schlaf, Schritte, Energie, Körpersignale).
/// Alle Felder sind optional: Ältere Dateien ohne ein neues Feld bleiben lesbar, fehlende Werte zeigt das Widget als „–“.
struct DayWidgetSnapshot: Codable, Equatable, Sendable {
    var updatedAt: Date
    /// Beginn des Kalendertags, für den die Werte gelten.
    var day: Date
    var healthAge: Double?
    var chronologicalAge: Double?
    var steps: Int?
    var stepGoal: Int?
    var sleepMinutes: Int?
    var sleepNeedMinutes: Int?
    var sleepScore: Int?
    /// Geplante Bettzeit der nächsten Nacht.
    var bedtime: Date?
    var activeEnergy: Int?
    var strain: Int?
    /// 0 unauffällig, 1 beobachten, 2 Körper kämpft; `nil` ohne genug Nachtdaten.
    var signalLevel: Int?
    var signalTitles: [String]?

    init(updatedAt: Date, day: Date, healthAge: Double? = nil, chronologicalAge: Double? = nil,
         steps: Int? = nil, stepGoal: Int? = nil, sleepMinutes: Int? = nil, sleepNeedMinutes: Int? = nil,
         sleepScore: Int? = nil, bedtime: Date? = nil, activeEnergy: Int? = nil, strain: Int? = nil,
         signalLevel: Int? = nil, signalTitles: [String]? = nil) {
        self.updatedAt = updatedAt
        self.day = day
        self.healthAge = Self.finite(healthAge, in: 0...150)
        self.chronologicalAge = Self.finite(chronologicalAge, in: 0...150)
        self.steps = Self.whole(steps, in: 0...200_000)
        self.stepGoal = Self.whole(stepGoal, in: 1...200_000)
        self.sleepMinutes = Self.whole(sleepMinutes, in: 0...1_440)
        self.sleepNeedMinutes = Self.whole(sleepNeedMinutes, in: 1...1_440)
        self.sleepScore = Self.whole(sleepScore, in: 0...100)
        self.bedtime = bedtime
        self.activeEnergy = Self.whole(activeEnergy, in: 0...20_000)
        self.strain = Self.whole(strain, in: 0...100)
        self.signalLevel = Self.whole(signalLevel, in: 0...2)
        self.signalTitles = signalTitles.map { Array($0.prefix(4)) }
    }

    var hasValues: Bool {
        healthAge != nil || steps != nil || sleepMinutes != nil || bedtime != nil
            || activeEnergy != nil || signalLevel != nil
    }

    /// Nur Werte vom selben Kalendertag zeigen; sonst wären Schritte von gestern heute falsch.
    func isCurrent(at date: Date, calendar: Calendar) -> Bool {
        calendar.isDate(day, inSameDayAs: date)
    }

    /// Bruchteil 0…1, bei fehlendem Ziel 0.
    var stepFraction: Double {
        guard let steps, let stepGoal else { return 0 }
        return min(1, Double(steps) / Double(stepGoal))
    }

    var sleepFraction: Double {
        guard let sleepMinutes, let need = sleepNeedMinutes else { return 0 }
        return min(1, Double(sleepMinutes) / Double(need))
    }

    /// Jahre, positiv = älter als der Kalender.
    var healthAgeDifference: Double? {
        guard let healthAge, let chronologicalAge else { return nil }
        return healthAge - chronologicalAge
    }

    private static func finite(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        value.flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
    }

    private static func whole(_ value: Int?, in range: ClosedRange<Int>) -> Int? {
        value.flatMap { range.contains($0) ? $0 : nil }
    }
}

struct DayWidgetSnapshotStore: Sendable {
    static let kinds = [
        "com.ma29xii.forma.healthage", "com.ma29xii.forma.sleep", "com.ma29xii.forma.steps",
        "com.ma29xii.forma.energy", "com.ma29xii.forma.signals"
    ]

    let fileURL: URL?

    static var shared: Self {
        let directory = WidgetSnapshotStore.shared.fileURL?.deletingLastPathComponent()
        return Self(fileURL: directory?.appendingPathComponent("forma-day-widget-v1.json"))
    }

    func read() -> DayWidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DayWidgetSnapshot.self, from: data)
    }

    /// `true`, wenn sich der Inhalt geändert hat.
    func replace(with snapshot: DayWidgetSnapshot?) throws -> Bool {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        if let snapshot {
            guard read() != snapshot else { return false }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: options)
        } else {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                return false
            } catch {
                try Data().write(to: fileURL, options: options)
            }
        }
        return true
    }
}
