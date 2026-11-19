import Foundation

/// Der lokale Stand der drei Today-Werte. `nil` steht für eine fehlende Messgrundlage.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    let recovery: Int?
    let strain: Int?
    let sleep: Int?
    let updatedAt: Date
    let validUntil: Date

    init?(recovery: Int?, strain: Int?, sleep: Int?, updatedAt: Date, day: Date, calendar: Calendar) {
        guard let interval = calendar.dateInterval(of: .day, for: day),
              interval.start <= updatedAt, updatedAt < interval.end else { return nil }

        self.recovery = Self.validScore(recovery)
        self.strain = Self.validScore(strain)
        self.sleep = Self.validScore(sleep)
        self.updatedAt = updatedAt
        validUntil = interval.end
        guard isValid else { return nil }
    }

    func expiry(in calendar: Calendar) -> Date {
        min(validUntil, calendar.dateInterval(of: .day, for: updatedAt)?.end ?? validUntil)
    }

    func isCurrent(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        updatedAt <= date && date < expiry(in: calendar)
    }

    fileprivate var isValid: Bool {
        let scores = [recovery, strain, sleep].compactMap { $0 }
        return !scores.isEmpty && scores.allSatisfy { (0...100).contains($0) }
            && updatedAt.timeIntervalSinceReferenceDate.isFinite
            && validUntil.timeIntervalSinceReferenceDate.isFinite && validUntil > updatedAt
    }

    private static func validScore(_ value: Int?) -> Int? {
        value.flatMap { (0...100).contains($0) ? $0 : nil }
    }
}

struct WidgetSnapshotStore: Sendable {
    static let groupID = "group.com.ma29xii.forma"
    static let widgetKind = "com.ma29xii.forma.today"

    let fileURL: URL?

    static var shared: Self {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        let file = root?.appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent("forma-widget-v1.json")
        return Self(fileURL: file)
    }

    func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.isValid else { return nil }
        return snapshot
    }

    /// Ein atomarer Wechsel verhindert halbe Stände beim gleichzeitigen Lesen im Widget.
    func replace(with snapshot: WidgetSnapshot?) throws -> Bool {
        guard let fileURL else { return false }
        if let snapshot {
            guard read() != snapshot else { return false }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                return false
            }
        }
        return true
    }
}
