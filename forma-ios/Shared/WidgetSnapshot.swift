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

    func timelineExpiry(forEntryAt date: Date, calendar: Calendar) -> Date {
        min(expiry(in: calendar), date.addingTimeInterval(15 * 60))
    }

    /// Wann das Widget die Datei spätestens neu liest: alle 30 Minuten, nie nach Tagesende.
    /// Der Stand bleibt dazwischen sichtbar (früher folgte nach 15 Minuten ein leerer Eintrag).
    func nextReload(after date: Date, calendar: Calendar) -> Date {
        min(expiry(in: calendar), date.addingTimeInterval(30 * 60))
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
    private let accessURL: URL?

    init(fileURL: URL?, accessURL: URL? = nil) {
        self.fileURL = fileURL
        self.accessURL = accessURL ?? fileURL?.appendingPathExtension("access")
    }

    static var shared: Self {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        let file = root?.appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent("forma-widget-v1.json")
        return Self(fileURL: file, accessURL: root?.appendingPathComponent("forma-widget-v1.access"))
    }

    func read() -> WidgetSnapshot? {
        guard let fileURL, let accessURL, let permit = try? Data(contentsOf: accessURL), !permit.isEmpty,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.isValid, (try? Data(contentsOf: accessURL)) == permit else { return nil }
        return snapshot
    }

    func current(at date: Date) -> WidgetSnapshot? {
        guard let snapshot = read(), snapshot.isCurrent(at: date) else { return nil }
        return snapshot
    }

    /// Ein atomarer Wechsel verhindert halbe Stände beim gleichzeitigen Lesen im Widget.
    func replace(with snapshot: WidgetSnapshot?,
                 removeSnapshot: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) throws -> Bool {
        guard let fileURL, let accessURL else { throw CocoaError(.fileNoSuchFile) }
        if let snapshot {
            guard read() != snapshot else { return false }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try Data(UUID().uuidString.utf8).write(to: accessURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        }

        // Zuerst die Lesefreigabe abziehen. Sie liegt unabhängig von der Cache-Datei im App-Group-Ordner.
        var revoked = false
        var revocationError: (any Error)?
        do {
            revoked = try removeIfPresent(accessURL) { try FileManager.default.removeItem(at: $0) }
        } catch {
            do {
                try Data().write(to: accessURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                revoked = true
            } catch {
                revocationError = error
            }
        }
        let removed = try removeIfPresent(fileURL, remove: removeSnapshot)
        if !removed, let revocationError { throw revocationError }
        return removed || revoked
    }

    private func removeIfPresent(_ url: URL, remove: (URL) throws -> Void) throws -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            try remove(url)
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return false
        }
    }
}
