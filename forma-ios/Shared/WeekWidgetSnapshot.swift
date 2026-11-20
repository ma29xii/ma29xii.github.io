import Foundation

struct WeekWidgetSnapshot: Codable, Equatable, Sendable {
    struct Day: Codable, Equatable, Identifiable, Sendable {
        let date: Date
        let calendarDay: DateComponents?
        let recovery: Int?
        let strain: Int?
        let sleep: Int?

        var id: Date { date }
        var hasMeasurements: Bool { recovery != nil || strain != nil || sleep != nil }

        init(date: Date, recovery: Int? = nil, strain: Int? = nil, sleep: Int? = nil,
             calendarDay: DateComponents? = nil) {
            self.date = date
            self.calendarDay = calendarDay
            self.recovery = WeekWidgetSnapshot.validScore(recovery)
            self.strain = WeekWidgetSnapshot.validScore(strain)
            self.sleep = WeekWidgetSnapshot.validScore(sleep)
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(date: try values.decode(Date.self, forKey: .date),
                      recovery: try values.decodeIfPresent(Int.self, forKey: .recovery),
                      strain: try values.decodeIfPresent(Int.self, forKey: .strain),
                      sleep: try values.decodeIfPresent(Int.self, forKey: .sleep),
                      calendarDay: try values.decodeIfPresent(DateComponents.self, forKey: .calendarDay))
        }
    }

    enum RecoveryColor: Equatable, Sendable {
        case red, yellow, green
    }

    let days: [Day]
    let updatedAt: Date

    init(measurements: [Day], updatedAt: Date, calendar: Calendar) {
        self.updatedAt = updatedAt
        days = Self.week(from: measurements, endingAt: updatedAt, calendar: calendar)
    }

    func days(endingAt date: Date, calendar: Calendar) -> [Day] {
        Self.week(from: days, endingAt: date, calendar: calendar)
    }

    static func dates(endingAt date: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: date)
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .map { calendar.startOfDay(for: $0) }
    }

    static func recoveryColor(for score: Int?) -> RecoveryColor? {
        guard let score = validScore(score) else { return nil }
        if score >= 67 { return .green }
        if score >= 34 { return .yellow }
        return .red
    }

    private static func week(from measurements: [Day], endingAt date: Date, calendar: Calendar) -> [Day] {
        let byDay = Dictionary(measurements.map { day in
            (day.calendarDay ?? calendar.dateComponents([.year, .month, .day], from: day.date), day)
        }, uniquingKeysWith: { _, newer in newer })
        return dates(endingAt: date, calendar: calendar).map { date in
            let calendarDay = calendar.dateComponents([.year, .month, .day], from: date)
            let measurement = byDay[calendarDay]
            return Day(date: date, recovery: measurement?.recovery, strain: measurement?.strain,
                       sleep: measurement?.sleep, calendarDay: calendarDay)
        }
    }

    private static func validScore(_ value: Int?) -> Int? {
        value.flatMap { (0...100).contains($0) ? $0 : nil }
    }
}

struct WeekWidgetSnapshotStore: Sendable {
    static let widgetKind = "com.ma29xii.forma.week"

    let fileURL: URL?

    static var shared: Self {
        let directory = WidgetSnapshotStore.shared.fileURL?.deletingLastPathComponent()
        return Self(fileURL: directory?.appendingPathComponent("forma-week-widget-v1.json"))
    }

    func read() -> WeekWidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WeekWidgetSnapshot.self, from: data)
    }

    func replace(with snapshot: WeekWidgetSnapshot?) throws -> Bool {
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
                // Ohne löschbare Datei bleibt nach dem Wechsel nur ein leerer Stand lesbar.
                try Data().write(to: fileURL, options: options)
            }
        }
        return true
    }
}
