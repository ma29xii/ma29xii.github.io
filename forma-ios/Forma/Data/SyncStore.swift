import Foundation

/// Lokaler Zwischenspeicher der Messwerte.
///
/// Zweck: Forma soll nie Daten „verlieren“, nur weil ein Abruf scheitert.
/// - Die App startet sofort mit dem letzten Stand (auch offline).
/// - Ein leerer oder unvollständiger Abruf (z. B. bei gesperrtem iPhone, wenn Apple Health
///   keine Daten herausgibt) überschreibt keine vorhandenen Werte.
/// - Spät nachsynchronisierte Werte (Uhr war nicht verbunden) werden ergänzt.
enum SyncStore {
    struct Snapshot: Codable, Sendable {
        var days: [DayMetrics]
        var updated: Date
        var source: String
    }

    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("forma-sync.json")
    }

    static func load() -> Snapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        // Nach dem ersten Entsperren lesbar: Hintergrund-Abrufe können auch bei gesperrtem Bildschirm schreiben.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Hat ein Tag überhaupt Messwerte?
    static func hasData(_ d: DayMetrics) -> Bool {
        d.hrv != nil || d.restingHR != nil || d.sleep != nil || (d.steps ?? 0) > 0 || d.activeEnergy != nil
            || d.respiratoryRate != nil || d.spo2 != nil || d.vo2max != nil || !d.workouts.isEmpty
    }

    enum MergeResult: Equatable {
        case merged([DayMetrics])
        /// Neuer Abruf ist verdächtig leer, alter Stand hatte Daten: nicht überschreiben.
        case rejectedEmpty
    }

    /// Führt einen neuen Abruf mit dem gespeicherten Stand zusammen.
    /// - Heute und gestern: der neue Abruf gilt (Werte können sich noch ändern).
    /// - Ältere Tage: fehlt ein Wert im neuen Abruf, bleibt der gespeicherte stehen.
    static func merge(old: [DayMetrics], new: [DayMetrics], today: Date = Date.now.startOfDay, keepDays: Int = 180) -> MergeResult {
        let oldHasData = old.contains(where: hasData)
        let newHasData = new.contains(where: hasData)
        if oldHasData && !newHasData { return .rejectedEmpty }

        var byDate: [Date: DayMetrics] = [:]
        for d in old { byDate[d.date] = d }
        let cutoff = today.adding(days: -1)
        for n in new {
            guard let o = byDate[n.date], n.date < cutoff else { byDate[n.date] = n; continue }
            var m = n
            m.hrv = n.hrv ?? o.hrv
            m.restingHR = n.restingHR ?? o.restingHR
            m.respiratoryRate = n.respiratoryRate ?? o.respiratoryRate
            m.spo2 = n.spo2 ?? o.spo2
            m.vo2max = n.vo2max ?? o.vo2max
            m.steps = n.steps ?? o.steps
            m.activeEnergy = n.activeEnergy ?? o.activeEnergy
            m.sleep = n.sleep ?? o.sleep
            if n.workouts.isEmpty { m.workouts = o.workouts }
            byDate[n.date] = m
        }
        let first = today.adding(days: -(keepDays - 1))
        // Lückenlos von first bis heute, damit Indizes und Fenster stimmen.
        var result: [DayMetrics] = []
        var d = first
        while d <= today {
            result.append(byDate[d] ?? DayMetrics(date: d))
            d = d.adding(days: 1)
        }
        return .merged(result)
    }
}
