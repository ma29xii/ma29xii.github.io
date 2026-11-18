import Foundation

/// Scheibenrechner: welche Scheiben pro Seite auf die Langhantel gehören.
enum PlateMath {
    static let standardPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    /// Gibt nil zurück, wenn das Gewicht unter der Stange liegt oder nicht aufgeht.
    static func perSide(total: Double, bar: Double = 20, plates: [Double] = standardPlates) -> [Double]? {
        guard total.isFinite, total >= bar else { return nil }
        var remaining = ((total - bar) / 2 * 100).rounded() / 100
        var result: [Double] = []
        for plate in plates.sorted(by: >) {
            while remaining + 0.0001 >= plate {
                result.append(plate)
                remaining -= plate
                if result.count > 40 { return nil }
            }
        }
        return remaining < 0.01 ? result : nil
    }
}
