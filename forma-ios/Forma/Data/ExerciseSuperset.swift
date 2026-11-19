import Foundation

/// Supersätze: benachbarte Übungen mit derselben Gruppennummer werden abwechselnd trainiert,
/// die Pause kommt erst nach der letzten Übung der Runde. Reine Logik auf Gruppennummern (nil = einzeln).
enum Superset {
    enum Position: Equatable, Sendable { case first, middle, last }

    /// Die zusammenhängende Gruppe um Position `i` (bei einzelnen Übungen nur `i`).
    static func members(_ groups: [Int?], at i: Int) -> ClosedRange<Int> {
        guard groups.indices.contains(i), let g = groups[i] else { return i...i }
        var lo = i, hi = i
        while lo > 0, groups[lo - 1] == g { lo -= 1 }
        while hi < groups.count - 1, groups[hi + 1] == g { hi += 1 }
        return lo...hi
    }

    static func position(_ groups: [Int?], at i: Int) -> Position? {
        let run = members(groups, at: i)
        guard run.count > 1 else { return nil }
        return i == run.lowerBound ? .first : (i == run.upperBound ? .last : .middle)
    }

    static func isLinkedWithNext(_ groups: [Int?], at i: Int) -> Bool {
        groups.indices.contains(i + 1) && groups[i] != nil && groups[i] == groups[i + 1]
    }

    /// Einzelne Reste lösen, jede zusammenhängende Gruppe bekommt eine eigene Nummer (1, 2, …).
    static func normalized(_ groups: [Int?]) -> [Int?] {
        var result = [Int?](repeating: nil, count: groups.count)
        var next = 1
        var i = 0
        while i < groups.count {
            let run = members(groups, at: i)
            if run.count > 1 {
                for j in run { result[j] = next }
                next += 1
            }
            i = run.upperBound + 1
        }
        return result
    }

    /// Koppelt Position `i` mit der nächsten Übung (hängt sie an eine bestehende Gruppe an).
    static func linking(_ groups: [Int?], at i: Int) -> [Int?] {
        guard groups.indices.contains(i), groups.indices.contains(i + 1) else { return normalized(groups) }
        var g = groups
        let id = g[i] ?? g[i + 1] ?? ((g.compactMap { $0 }.max() ?? 0) + 1)
        let merged = [g[i], g[i + 1]].compactMap { $0 }
        for j in g.indices { if let v = g[j], merged.contains(v) { g[j] = id } }
        g[i] = id
        g[i + 1] = id
        return normalized(g)
    }

    /// Löst Position `i` aus ihrer Gruppe; der Rest bleibt gekoppelt, wenn er zusammenhängt.
    static func unlinking(_ groups: [Int?], at i: Int) -> [Int?] {
        guard groups.indices.contains(i) else { return normalized(groups) }
        var g = groups
        g[i] = nil
        return normalized(g)
    }

    /// Wohin es nach einem erledigten Satz in Übung `i` geht: zur nächsten offenen Übung der Runde ohne Pause,
    /// sonst zurück zur ersten offenen Übung der Gruppe mit Pause. nil = kein Supersatz oder Gruppe fertig.
    static func next(after i: Int, groups: [Int?], open: [Bool]) -> (index: Int, rests: Bool)? {
        let run = members(groups, at: i)
        guard run.count > 1, open.count == groups.count else { return nil }
        if let j = run.first(where: { $0 > i && open[$0] }) { return (j, false) }
        if let j = run.first(where: { open[$0] }) { return (j, true) }
        return nil
    }
}
