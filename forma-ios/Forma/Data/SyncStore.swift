import Foundation

/// Lokaler Zwischenspeicher der Messwerte.
///
/// Zweck: Forma soll nie Daten „verlieren“, nur weil ein Abruf scheitert.
/// - Die App startet sofort mit dem letzten Stand (auch offline).
/// - Ein fehlgeschlagener Abruf überschreibt keine vorhandenen Werte.
/// - Spät nachsynchronisierte Werte (Uhr war nicht verbunden) werden ergänzt.
enum SyncStore {
    struct Snapshot: Codable, Sendable {
        var days: [DayMetrics]
        var updated: Date?
        var source: String
        var accountID: String? = nil
        var hours: [HourlyMetrics]? = nil
        var historyThrough: Date? = nil
        var historyGaps: [Date]? = nil
        var historyThroughDay: CivilDay? = nil
        var historyGapDays: [CivilDay]? = nil
        var dayTimeZone: String? = nil
        var series: [MetricSeries: DataHub.SeriesFreshness]? = nil
        var recentFailed: Set<MetricSeries>? = nil
        var recentPulseFailed: Bool? = nil
    }

    static var fileURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("forma-sync.json")
    }

    static func load(from url: URL? = fileURL) -> Snapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Speichert den Stand. Gibt false zurück, wenn das Schreiben scheitert (wird angezeigt, Codex R-02-01).
    @discardableResult
    static func save(_ snapshot: Snapshot, to url: URL? = fileURL) -> Bool {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return false }
        let files = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = files.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else { return false }
        var temporary = replacementURL(for: url)
        defer { try? removeFile(at: temporary) }
        do {
            // Nach dem ersten Entsperren lesbar: Hintergrund-Abrufe können auch bei gesperrtem Bildschirm schreiben.
            try data.write(to: temporary, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // Erst nach erfolgreichem Backup-Ausschluss den alten Stand atomar ersetzen.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try temporary.setResourceValues(values)
            if exists {
                _ = try files.replaceItemAt(url, withItemAt: temporary, options: .usingNewMetadataOnly)
            } else {
                try files.moveItem(at: temporary, to: url)
            }
            return true
        } catch {
            return false
        }
    }

    /// Eine bereits fehlende Datei zählt als gelöscht. Andere Fehler bleiben sichtbar.
    static func clear(at url: URL? = fileURL) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        var failure: (any Error)?
        for file in [url, replacementURL(for: url)] {
            do { try removeFile(at: file) }
            catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }

    private static func replacementURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".replacement-\(url.lastPathComponent)")
    }

    private static func removeFile(at url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    /// Bringt einen gespeicherten Stand auf ein lückenloses Raster, das mit *heute* endet (Codex R-02-24):
    /// Nach Mitternacht oder Zeitzonenwechsel steht der alte Stand unter seinem echten Datum, heute bleibt leer.
    static func normalized(_ days: [DayMetrics], today: Date = Date.now.startOfDay, keepDays: Int = 180,
                           calendar: Calendar = .forma, legacyCalendar: Calendar? = nil) -> [DayMetrics] {
        var byDay: [CivilDay: DayMetrics] = [:]
        for day in days {
            guard let projected = day.onCivilDay(in: calendar, legacyCalendar: legacyCalendar),
                  let key = projected.civilDay else { continue }
            byDay[key] = projected
        }
        return dayGrid(ending: today, count: keepDays, calendar: calendar).map { date in
            let key = CivilDay(date, in: calendar)
            return byDay[key] ?? DayMetrics(date: date, civilDay: key)
        }
    }

    private static func dayGrid(ending today: Date, count: Int, calendar: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        return (0..<count).reversed().compactMap { offset in
            calendar.startOfDay(offsetBy: -offset, from: today)
        }
    }

    /// Hat ein Tag überhaupt Messwerte?
    static func hasData(_ d: DayMetrics) -> Bool {
        d.hrv != nil || d.restingHR != nil || d.sleep != nil || d.steps != nil || d.activeEnergy != nil
            || d.respiratoryRate != nil || d.spo2 != nil || d.vo2max != nil || d.skinTemperature != nil || !d.workouts.isEmpty
    }

    enum MergeResult: Equatable {
        case merged([DayMetrics])
        /// Keine Reihe gelesen oder ein Leerstand ohne Bestätigung des Importers.
        case rejectedEmpty
    }

    /// Führt einen neuen Abruf mit dem gespeicherten Stand zusammen – pro Messreihe (Codex R-02-01):
    /// - Reihe erfolgreich gelesen → der neue Wert gilt, auch `nil`.
    /// - Reihe fehlgeschlagen → der gespeicherte Wert bleibt.
    /// - Alle Reihen fehlgeschlagen oder unbestätigt leer → nichts überschreiben.
    static func merge(old: [DayMetrics], new: [DayMetrics], failed: Set<MetricSeries> = [],
                      confirmedEmpty: Bool = false,
                      today: Date = Date.now.startOfDay, keepDays: Int = 180, calendar: Calendar = .forma) -> MergeResult {
        if failed.count == MetricSeries.allCases.count { return .rejectedEmpty }
        let oldDays = old.compactMap { $0.onCivilDay(in: calendar) }
        let newDays = new.compactMap { $0.onCivilDay(in: calendar) }
        if !confirmedEmpty && failed.isEmpty && !new.contains(where: hasData) {
            let oldInWindowHasData = !Set(oldDays.filter(hasData).compactMap(\.civilDay))
                .isDisjoint(with: newDays.compactMap(\.civilDay))
            if oldInWindowHasData { return .rejectedEmpty }
        }

        func byCivilDay(_ days: [DayMetrics]) -> [CivilDay: DayMetrics] {
            Dictionary(days.compactMap { day in day.civilDay.map { ($0, day) } },
                       uniquingKeysWith: { _, latest in latest })
        }
        let oldByDate = byCivilDay(oldDays)
        let newByDate = byCivilDay(newDays)

        var result: [DayMetrics] = []
        for date in dayGrid(ending: today, count: keepDays, calendar: calendar) {
            let key = CivilDay(date, in: calendar)
            let o = oldByDate[key]
            if var m = newByDate[key] {
                if let o {
                    if failed.contains(.hrv) { m.hrv = o.hrv }
                    if failed.contains(.restingHR) { m.restingHR = o.restingHR }
                    if failed.contains(.respiratoryRate) { m.respiratoryRate = o.respiratoryRate }
                    if failed.contains(.spo2) { m.spo2 = o.spo2 }
                    if failed.contains(.vo2max) { m.vo2max = o.vo2max }
                    if failed.contains(.steps) { m.steps = o.steps }
                    if failed.contains(.activeEnergy) { m.activeEnergy = o.activeEnergy }
                    if failed.contains(.sleep) { m.sleep = o.sleep }
                    if failed.contains(.workouts) { m.workouts = o.workouts }
                    if failed.contains(.skinTemperature) { m.skinTemperature = o.skinTemperature }
                    for series in failed { m.setOrigins(o.origins?[series] ?? [], for: series) }
                }
                result.append(m)
            } else {
                // Tag lag nicht im Abruf (älter als das Abruffenster): gespeicherten Stand behalten.
                result.append(o ?? DayMetrics(date: date, civilDay: key))
            }
        }
        return .merged(result)
    }
}
