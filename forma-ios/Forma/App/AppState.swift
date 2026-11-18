import Foundation
import SwiftData
import SwiftUI
import UserNotifications

enum AppTab: Hashable {
    case today, training, health, coach
}

/// Globale Bedienzustände (Tab, Coach-Kontext, laufendes Training).
@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .today
    var coachPrompt: String?
    var liveWorkout: LiveWorkout? {
        didSet {
            if let liveWorkout {
                liveWorkout.persist()
                if oldValue == nil { RestNotifier.requestPermission() }
            } else {
                LiveWorkout.clearSaved()
                RestNotifier.cancel()
            }
        }
    }
    var finishedSession: WorkoutSession?
    var showProfile = false
    var showJournal = false

    var weightUnit: WeightUnit {
        didSet { UserDefaults.standard.set(weightUnit.rawValue, forKey: "forma.weightUnit") }
    }

    init() {
        weightUnit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "forma.weightUnit") ?? "") ?? .kg
    }

    func openCoach(with prompt: String) {
        coachPrompt = prompt
        selectedTab = .coach
    }
}

/// Vom Coach vorgeschlagene, von Maxi bestätigte Anpassung für heute.
/// Die gespeicherte Routine bleibt unverändert.
enum TrainingAdjustment: String, Sendable, Codable {
    case minusOneSet, plusWeight

    var title: String {
        switch self {
        case .minusOneSet: "Ein Satz weniger pro Übung"
        case .plusWeight: "+2,5 kg bei der ersten Übung"
        }
    }

    private static func key(_ date: Date = .now) -> String { "forma.adjust." + FitbitService.dayString(date) }

    static var today: TrainingAdjustment? {
        get { TrainingAdjustment(rawValue: UserDefaults.standard.string(forKey: key()) ?? "") }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: key()) }
    }

    static var dismissedToday: Bool {
        get { UserDefaults.standard.bool(forKey: key() + ".dismissed") }
        set { UserDefaults.standard.set(newValue, forKey: key() + ".dismissed") }
    }
}

// MARK: - Live-Training

struct LiveSet: Identifiable, Equatable, Codable {
    var id = UUID()
    var weight: Double
    var reps: Int
    var rir: Int?
    var isWarmup: Bool
    var done = false
}

struct LiveExercise: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var muscle: String
    var restSeconds: Int
    var sets: [LiveSet]
    var lastTime: String?
    /// Vorschlag aus dem letzten Training (progressive Steigerung), nur Hinweis.
    var progression: String? = nil
}

/// Steigerungsregel: Wurden letztes Mal alle Arbeitssätze mit dem Ziel an Wiederholungen
/// und im Mittel mindestens 2 Wiederholungen Reserve geschafft, schlägt Forma +2,5 kg vor.
/// Bei Reserve 0 und verfehlten Wiederholungen bleibt das Gewicht. Sonst gleiches Gewicht wie zuletzt.
enum Progression {
    struct Plan: Equatable { var weight: Double; var note: String?; var increased = false }

    static func plan(targetReps: Int, routineWeight: Double, lastWorkSets: [(weight: Double, reps: Int, rir: Int)]) -> Plan {
        guard let top = lastWorkSets.map({ $0.weight }).max(), top > 0 else { return Plan(weight: routineWeight, note: nil) }
        let atTop = lastWorkSets.filter { $0.weight == top }
        let allReps = atTop.allSatisfy { $0.reps >= targetReps }
        let rirs = atTop.map({ $0.rir }).filter { $0 >= 0 }
        let meanRIR = rirs.isEmpty ? nil : Double(rirs.reduce(0, +)) / Double(rirs.count)
        if allReps, let meanRIR, meanRIR >= 2 {
            return Plan(weight: top + 2.5, note: "+2,5 kg: Letztes Mal alle \(targetReps) Wdh. mit Reserve geschafft", increased: true)
        }
        if !allReps, let meanRIR, meanRIR < 1 {
            return Plan(weight: top, note: "Gewicht halten: Letztes Mal am Limit")
        }
        return Plan(weight: top, note: nil)
    }
}

/// Lokale Erinnerung, wenn die Pause vorbei ist (auch bei gesperrtem iPhone).
enum RestNotifier {
    static let id = "forma.rest"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(at date: Date, next: String?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let interval = date.timeIntervalSinceNow
        guard interval > 2 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Pause vorbei"
        content.body = next.map { "Weiter mit \($0)." } ?? "Weiter geht's."
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        center.add(request, withCompletionHandler: nil)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

@MainActor
@Observable
final class LiveWorkout: Identifiable {
    let id = UUID()
    var title: String
    let start: Date
    var exercises: [LiveExercise]
    var exerciseIndex = 0
    var setIndex = 0
    var restEndsAt: Date?
    var restTotal: Int = 90
    var currentRIR: Int = 2 { didSet { persist() } }
    var adjustment: TrainingAdjustment?

    init(title: String, exercises: [LiveExercise], adjustment: TrainingAdjustment? = nil, start: Date = .now) {
        self.title = title
        self.exercises = exercises
        self.adjustment = adjustment
        self.start = start
        selectFirstOpen()
    }

    // MARK: Sichern und Wiederherstellen (iOS kann die App im Hintergrund beenden)

    private struct Snapshot: Codable {
        var title: String
        var start: Date
        var exercises: [LiveExercise]
        var exerciseIndex: Int
        var setIndex: Int
        var restEndsAt: Date?
        var restTotal: Int
        var currentRIR: Int
        var adjustment: TrainingAdjustment?
    }

    private static let storageKey = "forma.liveWorkout"

    func persist() {
        let snap = Snapshot(title: title, start: start, exercises: exercises, exerciseIndex: exerciseIndex, setIndex: setIndex,
                            restEndsAt: restEndsAt, restTotal: restTotal, currentRIR: currentRIR, adjustment: adjustment)
        if let data = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
    }

    static func clearSaved() { UserDefaults.standard.removeObject(forKey: storageKey) }

    /// Gespeichertes Training der letzten 8 Stunden zurückholen. Kaputte Daten werden verworfen.
    static func restore(now: Date = .now) -> LiveWorkout? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
              now.timeIntervalSince(snap.start) < 8 * 3600, snap.start <= now.addingTimeInterval(60),
              !snap.exercises.isEmpty else {
            clearSaved()
            return nil
        }
        let w = LiveWorkout(title: snap.title, exercises: snap.exercises, adjustment: snap.adjustment, start: snap.start)
        if w.exercises.indices.contains(snap.exerciseIndex), w.exercises[snap.exerciseIndex].sets.indices.contains(snap.setIndex) {
            w.exerciseIndex = snap.exerciseIndex
            w.setIndex = snap.setIndex
        }
        w.restTotal = max(1, snap.restTotal)
        w.restEndsAt = snap.restEndsAt.flatMap { $0 > now ? $0 : nil }
        w.currentRIR = min(4, max(0, snap.currentRIR))
        return w
    }

    static func from(_ routine: Routine, history: [WorkoutSession], adjustment: TrainingAdjustment?) -> LiveWorkout {
        let items = routine.sortedItems
        let exercises = items.enumerated().map { index, item -> LiveExercise in
            var setCount = item.sets
            let lastSession = history.first { $0.sets.contains { $0.exerciseName == item.exerciseName } }
            let lastWork = (lastSession?.workSets ?? []).filter { $0.exerciseName == item.exerciseName }
                .map { (weight: $0.weight, reps: $0.reps, rir: $0.rir) }
            let plan = Progression.plan(targetReps: item.reps, routineWeight: item.weight, lastWorkSets: lastWork)
            var weight = plan.weight
            if adjustment == .minusOneSet { setCount = max(1, setCount - 1) }
            if adjustment == .plusWeight && index == 0 && !plan.increased { weight += 2.5 }
            var sets = (0..<setCount).map { _ in LiveSet(weight: weight, reps: item.reps, isWarmup: false) }
            if index == 0 && weight >= 40 {
                sets.insert(LiveSet(weight: (weight * 0.55 / 2.5).rounded() * 2.5, reps: 10, isWarmup: true), at: 0)
            }
            let last = history.first { $0.sets.contains { $0.exerciseName == item.exerciseName } }
            let lastText = last.map { session -> String in
                let work = session.workSets.filter { $0.exerciseName == item.exerciseName }
                let top = work.max { $0.weight < $1.weight }
                return "Letztes Mal \(work.count) × \(top?.reps ?? 0) · \(Format.number(top?.weight ?? 0, decimals: (top?.weight ?? 0).truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) kg"
            }
            return LiveExercise(name: item.exerciseName, muscle: item.muscle, restSeconds: max(15, item.restSeconds), sets: sets,
                                lastTime: lastText, progression: plan.note)
        }
        return LiveWorkout(title: routine.name, exercises: exercises, adjustment: adjustment)
    }

    static func empty() -> LiveWorkout { LiveWorkout(title: "Freies Training", exercises: []) }

    var isResting: Bool { (restEndsAt ?? .distantPast) > .now }
    var allDone: Bool { !exercises.isEmpty && exercises.allSatisfy { $0.sets.allSatisfy(\.done) } }
    var currentExercise: LiveExercise? { exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil }
    var currentSet: LiveSet? {
        guard let ex = currentExercise, ex.sets.indices.contains(setIndex) else { return nil }
        return ex.sets[setIndex]
    }

    func workSetNumber(exercise: Int, set: Int) -> Int {
        exercises[exercise].sets.prefix(set + 1).filter { !$0.isWarmup }.count
    }

    func changeWeight(by delta: Double) {
        guard currentSet != nil else { return }
        let w = exercises[exerciseIndex].sets[setIndex].weight
        exercises[exerciseIndex].sets[setIndex].weight = min(1000, max(0, ((w + delta) * 4).rounded() / 4))
        persist()
    }

    func changeReps(by delta: Int) {
        guard currentSet != nil else { return }
        exercises[exerciseIndex].sets[setIndex].reps = min(100, max(1, exercises[exerciseIndex].sets[setIndex].reps + delta))
        persist()
    }

    func select(exercise: Int, set: Int) {
        guard exercises.indices.contains(exercise), exercises[exercise].sets.indices.contains(set) else { return }
        exerciseIndex = exercise
        setIndex = set
        restEndsAt = nil
        RestNotifier.cancel()
        persist()
    }

    func completeCurrentSet() {
        guard currentSet != nil else { return }
        exercises[exerciseIndex].sets[setIndex].done = true
        exercises[exerciseIndex].sets[setIndex].rir = exercises[exerciseIndex].sets[setIndex].isWarmup ? nil : currentRIR
        // Gleiche Werte in den nächsten offenen Satz übernehmen, falls noch Standard
        let done = exercises[exerciseIndex].sets[setIndex]
        if let next = exercises[exerciseIndex].sets.firstIndex(where: { !$0.done }), !done.isWarmup {
            exercises[exerciseIndex].sets[next].weight = done.weight
        }
        restTotal = exercises[exerciseIndex].restSeconds
        restEndsAt = .now.addingTimeInterval(TimeInterval(restTotal))
        selectFirstOpen(keepRest: true)
        if allDone {
            restEndsAt = nil
            RestNotifier.cancel()
        } else if let end = restEndsAt {
            RestNotifier.schedule(at: end, next: currentExercise?.name)
        }
        persist()
    }

    func extendRest(by seconds: Int) {
        let base = max(Date.now, restEndsAt ?? .now)
        restEndsAt = base.addingTimeInterval(TimeInterval(seconds))
        restTotal += seconds
        if let end = restEndsAt { RestNotifier.schedule(at: end, next: currentExercise?.name) }
        persist()
    }

    func skipRest() {
        restEndsAt = nil
        RestNotifier.cancel()
        persist()
    }

    func addSet(to exercise: Int) {
        guard exercises.indices.contains(exercise) else { return }
        let last = exercises[exercise].sets.last
        exercises[exercise].sets.append(LiveSet(weight: last?.weight ?? 20, reps: last?.reps ?? 8, isWarmup: false))
        if allDone == false && currentSet == nil { selectFirstOpen() }
        persist()
    }

    func addExercise(name: String, muscle: String) {
        exercises.append(LiveExercise(name: name, muscle: muscle, restSeconds: 90,
                                      sets: (0..<3).map { _ in LiveSet(weight: 20, reps: 10, isWarmup: false) }))
        if currentSet == nil || currentSet?.done == true { selectFirstOpen() }
        persist()
    }

    private func selectFirstOpen(keepRest: Bool = false) {
        if let ex = exercises.indices.first(where: { i in exercises[i].sets.contains { !$0.done } }),
           let s = exercises[ex].sets.firstIndex(where: { !$0.done }) {
            exerciseIndex = ex
            setIndex = s
        }
        if !keepRest { restEndsAt = nil }
    }

    /// Speichert das Training. Gibt die Sitzung zurück.
    func save(into context: ModelContext) -> WorkoutSession? {
        var records: [SetRecord] = []
        var order = 0
        for ex in exercises {
            for s in ex.sets where s.done {
                records.append(SetRecord(order: order, exerciseName: ex.name, weight: s.weight, reps: s.reps, rir: s.rir ?? -1, isWarmup: s.isWarmup))
                order += 1
            }
        }
        guard !records.isEmpty else { return nil }
        let session = WorkoutSession(title: title, start: start, end: .now)
        context.insert(session)
        for r in records {
            context.insert(r)
            r.session = session
        }
        try? context.save()
        return session
    }
}

