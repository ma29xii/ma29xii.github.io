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
    }

    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("forma-sync.json")
    }

    static func load() -> Snapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Speichert den Stand. Gibt false zurück, wenn das Schreiben scheitert (wird angezeigt, Codex R-02-01).
    @discardableResult
    static func save(_ snapshot: Snapshot) -> Bool {
        guard var url, let data = try? JSONEncoder().encode(snapshot) else { return false }
        do {
            // Nach dem ersten Entsperren lesbar: Hintergrund-Abrufe können auch bei gesperrtem Bildschirm schreiben.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // Gesundheitskopie nicht in iCloud-/iTunes-Backups (rekonstruierbar aus Google Health).
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    /// Löscht die lokale Kopie der Gesundheitsdaten.
    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Bringt einen gespeicherten Stand auf ein lückenloses Raster, das mit *heute* endet (Codex R-02-24):
    /// Nach Mitternacht oder Zeitzonenwechsel steht der alte Stand unter seinem echten Datum, heute bleibt leer.
    static func normalized(_ days: [DayMetrics], today: Date = Date.now.startOfDay, keepDays: Int = 180) -> [DayMetrics] {
        var byDate: [Date: DayMetrics] = [:]
        for var d in days {
            let key = d.date.startOfDay
            guard key <= today else { continue }   // Tage aus der „Zukunft“ (Uhr verstellt) verwerfen
            d.date = key
            byDate[key] = d
        }
        var result: [DayMetrics] = []
        var date = today.adding(days: -(keepDays - 1))
        while date <= today {
            result.append(byDate[date] ?? DayMetrics(date: date))
            date = date.adding(days: 1)
        }
        return result
    }

    /// Hat ein Tag überhaupt Messwerte?
    static func hasData(_ d: DayMetrics) -> Bool {
        d.hrv != nil || d.restingHR != nil || d.sleep != nil || d.steps != nil || d.activeEnergy != nil
            || d.respiratoryRate != nil || d.spo2 != nil || d.vo2max != nil || d.skinTemperature != nil || !d.workouts.isEmpty
    }

    enum MergeResult: Equatable {
        case merged([DayMetrics])
        /// Nichts wurde gelesen (alle Reihen fehlgeschlagen) oder ein verdächtig leerer Abruf: nicht überschreiben.
        case rejectedEmpty
    }

    /// Führt einen neuen Abruf mit dem gespeicherten Stand zusammen – pro Messreihe (Codex R-02-01):
    /// - Reihe erfolgreich gelesen → der neue Wert gilt, auch `nil`.
    /// - Reihe fehlgeschlagen → der gespeicherte Wert bleibt.
    /// - Alle Reihen fehlgeschlagen, oder alles leer obwohl vorher Daten da waren → nichts überschreiben.
    static func merge(old: [DayMetrics], new: [DayMetrics], failed: Set<MetricSeries> = [],
                      today: Date = Date.now.startOfDay, keepDays: Int = 180) -> MergeResult {
        if failed.count == MetricSeries.allCases.count { return .rejectedEmpty }
        let oldHasData = old.contains(where: hasData)
        let newHasData = new.contains(where: hasData)
        let oldInWindowHasData = oldHasData && !Set(old.filter(hasData).map(\.date))
            .isDisjoint(with: new.map(\.date))
        if oldInWindowHasData && !newHasData && failed.isEmpty { return .rejectedEmpty }

        var oldByDate: [Date: DayMetrics] = [:]
        for d in old { oldByDate[d.date] = d }
        var newByDate: [Date: DayMetrics] = [:]
        for d in new { newByDate[d.date] = d }

        let first = today.adding(days: -(keepDays - 1))
        var result: [DayMetrics] = []
        var date = first
        while date <= today {
            let o = oldByDate[date]
            if var m = newByDate[date] {
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
                result.append(o ?? DayMetrics(date: date))
            }
            date = date.adding(days: 1)
        }
        return .merged(result)
    }
}
