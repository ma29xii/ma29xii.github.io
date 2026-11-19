import Foundation

/// Ein Glas aus dem Widget, bis die App es in SwiftData übernommen hat.
struct WaterWidgetEvent: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let date: Date
}

struct WaterWidgetProgress: Sendable {
    let milliliters: Double
    let goalMilliliters: Double

    var fraction: Double { min(milliliters / goalMilliliters, 1) }
}

struct WaterWidgetStore: Sendable {
    static let widgetKind = "com.ma29xii.forma.water"
    static let glassMilliliters = 250.0
    static let defaultGoalMilliliters = 2_500.0
    static let goalRange = 500.0...6_000.0

    private let directory: URL?

    init(directory: URL?) {
        self.directory = directory
    }

    static var shared: Self {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.groupID)
        return Self(directory: root?.appendingPathComponent("forma-water-v1", isDirectory: true))
    }

    func recordGlass(at date: Date = .now) throws {
        let directory = try storageDirectory()
        let event = WaterWidgetEvent(id: UUID(), date: date)
        try write(event, to: eventURL(event.id, in: directory))
    }

    /// Alle noch nicht bestätigten Gläser, auch von vergangenen Tagen.
    func pendingEntries() throws -> [WaterWidgetEvent] {
        let directory = try storageDirectory()
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                options: .skipsHiddenFiles)
        } catch let error as CocoaError where Self.isMissing(error) {
            return []
        }
        return try files.compactMap { file in
            guard file.pathExtension == "glass",
                  let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let data = try read(file),
                  let event = try? JSONDecoder().decode(WaterWidgetEvent.self, from: data),
                  event.id == id else { return nil }
            return event
        }
    }

    /// Die App veröffentlicht den bereits gespeicherten Tagesstand, bevor sie importierte Gläser bestätigt.
    func publish(milliliters: Double, goalMilliliters: Double, including imported: [WaterWidgetEvent],
                 at date: Date = .now, calendar: Calendar = .autoupdatingCurrent) throws {
        let directory = try storageDirectory()
        let snapshot = Snapshot(
            day: try day(containing: date, calendar: calendar),
            milliliters: milliliters.isFinite ? max(0, milliliters) : 0,
            goalMilliliters: Self.goalRange.contains(goalMilliliters) ? goalMilliliters : Self.defaultGoalMilliliters,
            importedIDs: Set(imported.map(\.id))
        )
        try write(snapshot, to: snapshotURL(in: directory))
    }

    /// Erst nach erfolgreichem SwiftData-Save und Publish aufrufen. Neue Gläser bleiben unangetastet.
    func acknowledge(_ events: [WaterWidgetEvent]) throws {
        let directory = try storageDirectory()
        for event in events {
            do {
                try FileManager.default.removeItem(at: eventURL(event.id, in: directory))
            } catch let error as CocoaError where Self.isMissing(error) {
                continue
            }
        }
    }

    func progress(at date: Date, calendar: Calendar = .autoupdatingCurrent) throws -> WaterWidgetProgress {
        let day = try day(containing: date, calendar: calendar)
        let file = snapshotURL(in: try storageDirectory())
        // Beim Import wechselt zuerst der Snapshot. Wiederhole den Lesezugriff, falls er
        // zwischen dem Lesen der Gläser und ihrem Abgleich ausgetauscht wurde.
        for _ in 0..<3 {
            let before = try read(file)
            let pending = try pendingEntries()
            guard before == (try read(file)) else { continue }

            let snapshot = try before.map { try JSONDecoder().decode(Snapshot.self, from: $0) }
            let today = snapshot.flatMap { $0.day == day ? $0 : nil }
            let glasses = pending.lazy.filter { event in
                day.start <= event.date && event.date <= date && today?.importedIDs.contains(event.id) != true
            }.count
            return WaterWidgetProgress(milliliters: (today?.milliliters ?? 0) + Double(glasses) * Self.glassMilliliters,
                                       goalMilliliters: snapshot?.goalMilliliters ?? Self.defaultGoalMilliliters)
        }
        throw CocoaError(.fileReadUnknown)
    }

    private struct Snapshot: Codable {
        let day: DateInterval
        let milliliters: Double
        let goalMilliliters: Double
        let importedIDs: Set<UUID>
    }

    private func storageDirectory() throws -> URL {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        return directory
    }

    private func day(containing date: Date, calendar: Calendar) throws -> DateInterval {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let day = calendar.dateInterval(of: .day, for: date) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return day
    }

    private func eventURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("glass")
    }

    private func snapshotURL(in directory: URL) -> URL {
        directory.appendingPathComponent("progress.json")
    }

    private func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where Self.isMissing(error) {
            return nil
        }
    }

    private static func isMissing(_ error: CocoaError) -> Bool {
        error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
    }
}
