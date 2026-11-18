import Foundation

/// Ziel beim Antippen einer Anzeige oder Zeile: die Detailseite, mit Zoom nur aus dem Kopf.
struct RingRoute: Hashable {
    let kind: RingKind
    var zoom = false
}

/// Die Zahl, das Detail und der Verlauf benutzen dieselbe Verfügbarkeitsprüfung.
extension DashboardDay {
    func value(for kind: RingKind) -> Int? {
        switch kind {
        case .sleep: sleepScore
        case .recovery: recovery
        case .strain: strain
        }
    }
}

/// Genau ein Satz zum gewählten Tag: die auffälligste Messung zuerst, nie eine Rechen-Erklärung.
enum TodayInsight {
    static func sentence(for snapshot: DashboardDay) -> String {
        let day = snapshot.day
        if let pulse = day.restingHR, let base = snapshot.baseline({ $0.restingHR }), abs(pulse - base.mean) >= 2 {
            let delta = Format.number(abs(pulse - base.mean))
            return pulse < base.mean
                ? "Dein Ruhepuls liegt \(delta) Schläge unter deinem 30-Tage-Schnitt."
                : "Dein Ruhepuls liegt \(delta) Schläge über deinem 30-Tage-Schnitt."
        }
        if let hrv = day.hrv, let base = snapshot.baseline({ $0.hrv }), base.mean > 0 {
            let change = (hrv - base.mean) / base.mean
            if abs(change) >= 0.10 {
                let percent = Format.number(abs(change) * 100)
                return "Deine HRV liegt \(percent) % \(change > 0 ? "über" : "unter") deinem 30-Tage-Schnitt."
            }
        }
        if let night = day.sleep, night.asleep > 0 {
            if let need = snapshot.sleepNeed, need - night.asleep >= 30 * 60 {
                return "Du hast \(Format.duration(need - night.asleep)) weniger geschlafen, als du brauchst."
            }
            return "Du hast \(Format.duration(night.asleep)) geschlafen."
        }
        if let steps = day.steps { return "Bisher \(Format.number(steps)) Schritte." }
        if let strain = snapshot.strain { return "Deine Belastung liegt bei \(strain) von 100." }
        return "Für diesen Tag fehlen noch Messungen."
    }
}
