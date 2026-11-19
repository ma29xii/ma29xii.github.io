import Foundation
import SwiftData

@Model
final class Exercise {
    var name: String
    var muscle: String
    var equipment: String
    var isCustom: Bool

    init(name: String, muscle: String, equipment: String, isCustom: Bool = false) {
        self.name = name
        self.muscle = muscle
        self.equipment = equipment
        self.isCustom = isCustom
    }
}

@Model
final class Routine {
    var name: String
    var createdAt: Date
    var lastUsed: Date?
    /// Ordner zum Gruppieren, z. B. „Kraft“ oder „Reha“. nil = ohne Ordner. (Neues optionales Feld: leichte Migration.)
    var folder: String?
    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine) var items: [RoutineItem]

    init(name: String, items: [RoutineItem] = []) {
        self.name = name
        self.createdAt = .now
        self.items = items
    }

    var sortedItems: [RoutineItem] { items.sorted { $0.order < $1.order } }
    var totalSets: Int { items.reduce(0) { $0 + $1.sets } }
    /// Kopie mit allen Übungen und gleichem Ordner, Name „… Kopie“ (bzw. „… Kopie 2“).
    @discardableResult
    func duplicate(in context: ModelContext, existingNames: [String]) -> Routine {
        let copy = Routine(name: Routine.copyName(name, existing: existingNames))
        copy.folder = folder
        context.insert(copy)
        for item in sortedItems {
            let c = RoutineItem(order: item.order, exerciseName: item.exerciseName, muscle: item.muscle, sets: item.sets,
                                reps: item.reps, weight: item.weight, restSeconds: item.restSeconds)
            context.insert(c)
            c.superset = item.superset
            c.routine = copy
        }
        return copy
    }

    static func copyName(_ name: String, existing: [String]) -> String {
        let base = "\(name) Kopie"
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Routinen nach Ordner: zuerst ohne Ordner, dann Ordner alphabetisch. Reihenfolge innerhalb bleibt.
    static func grouped(_ routines: [Routine]) -> [(folder: String?, routines: [Routine])] {
        let loose = routines.filter { $0.folder == nil }
        let names = Set(routines.compactMap(\.folder)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var result: [(folder: String?, routines: [Routine])] = loose.isEmpty ? [] : [(folder: nil, routines: loose)]
        for name in names { result.append((folder: name, routines: routines.filter { $0.folder == name })) }
        return result
    }

    /// Ordnernamen bereinigt: leer oder nur Leerzeichen = kein Ordner.
    static func cleanFolder(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(40))
    }

    var muscleSummary: String {
        var seen: [String] = []
        for m in sortedItems.map(\.muscle) where !seen.contains(m) { seen.append(m) }
        return seen.prefix(3).joined(separator: ", ")
    }
}

@Model
final class RoutineItem {
    var order: Int
    var exerciseName: String
    var muscle: String
    var sets: Int
    var reps: Int
    var weight: Double
    var restSeconds: Int
    /// Supersatz-Gruppe: benachbarte Übungen mit gleicher Nummer wechseln sich ab. nil = einzeln. (Neues optionales Feld.)
    var superset: Int?
    var routine: Routine?

    init(order: Int, exerciseName: String, muscle: String, sets: Int = 3, reps: Int = 8, weight: Double = 20, restSeconds: Int = 90) {
        self.order = order
        self.exerciseName = exerciseName
        self.muscle = muscle
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.restSeconds = restSeconds
    }
}

@Model
final class WorkoutSession {
    var title: String
    var start: Date
    var end: Date
    /// Kennung des Entwurfs, aus dem die Einheit gespeichert wurde – verhindert doppeltes Speichern (Codex R-02-05).
    var draftID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \SetRecord.session) var sets: [SetRecord]

    init(title: String, start: Date, end: Date, sets: [SetRecord] = []) {
        self.title = title
        self.start = start
        self.end = end
        self.sets = sets
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var workSets: [SetRecord] { sets.filter { !$0.isWarmup } }
    var volume: Double { workSets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var exerciseNames: [String] {
        var seen: [String] = []
        for s in sets.sorted(by: { $0.order < $1.order }) where !seen.contains(s.exerciseName) { seen.append(s.exerciseName) }
        return seen
    }
    func bestOneRepMax(for exercise: String) -> Double {
        workSets.filter { $0.exerciseName == exercise }.map { OneRepMax.epley(weight: $0.weight, reps: $0.reps) }.max() ?? 0
    }
}

@Model
final class SetRecord {
    var order: Int
    var exerciseName: String
    var weight: Double
    var reps: Int
    var rir: Int        // −1 = nicht erfasst
    var isWarmup: Bool
    var session: WorkoutSession?

    init(order: Int, exerciseName: String, weight: Double, reps: Int, rir: Int, isWarmup: Bool) {
        self.order = order
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.rir = rir
        self.isWarmup = isWarmup
    }
}

@Model
final class JournalAnswer {
    var day: Date
    var question: String
    var answer: Bool

    init(day: Date, question: String, answer: Bool) {
        self.day = day
        self.question = question
        self.answer = answer
    }
}

/// Übungsbibliothek und Startroutinen.
enum TrainingSeed {
    /// Name, Gruppe, Gerät – kommt aus `ExerciseCatalog` (dort stehen auch Muskeln und Ausführung).
    static var library: [(String, String, String)] { ExerciseCatalog.all.map { ($0.name, $0.group, $0.equipment) } }

    static let routines: [(String, [(String, String, Int, Int, Double, Int)])] = [
        ("Push", [("Bankdrücken", "Brust", 4, 8, 72.5, 150), ("Schrägbankdrücken Kurzhantel", "Brust", 3, 10, 26, 120),
                  ("Schulterdrücken", "Schultern", 3, 8, 45, 120), ("Seitheben", "Schultern", 3, 14, 10, 75),
                  ("Dips", "Brust", 3, 10, 0, 90), ("Trizepsdrücken am Kabel", "Arme", 3, 12, 25, 75)]),
        ("Pull", [("Klimmzüge", "Rücken", 4, 7, 0, 150), ("Langhantelrudern", "Rücken", 3, 8, 65, 120),
                  ("Latzug", "Rücken", 3, 10, 60, 90), ("Face Pulls", "Schultern", 3, 15, 20, 60),
                  ("Bizepscurls", "Arme", 3, 10, 14, 75), ("Hammercurls", "Arme", 2, 12, 14, 60)]),
        ("Beine", [("Kniebeuge", "Beine", 4, 6, 90, 180), ("Rumänisches Kreuzheben", "Beine", 3, 8, 80, 150),
                   ("Beinpresse", "Beine", 3, 12, 160, 120), ("Beinbeuger", "Beine", 3, 12, 45, 75), ("Wadenheben", "Beine", 4, 12, 60, 60)])
    ]

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = Set(((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map(\.name))
        // Neue Katalogübungen kommen auch in bestehende Bibliotheken; Routinen nur beim ersten Start.
        for (name, muscle, equipment) in library where !existing.contains(name) {
            context.insert(Exercise(name: name, muscle: muscle, equipment: equipment))
        }
        guard existing.isEmpty else {
            try? context.save()
            return
        }
        for (name, items) in routines {
            let routine = Routine(name: name)
            context.insert(routine)
            for (i, item) in items.enumerated() {
                let ri = RoutineItem(order: i, exerciseName: item.0, muscle: item.1, sets: item.2, reps: item.3, weight: item.4, restSeconds: item.5)
                context.insert(ri)
                ri.routine = routine
            }
        }
        try? context.save()
    }
}
