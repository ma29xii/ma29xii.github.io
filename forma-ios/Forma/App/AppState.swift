import Foundation
import SwiftData
import SwiftUI
import UserNotifications

enum AppTab: Hashable {
    case today, training, health, coach, add
}

/// Globale Bedienzustände (Tab, Coach-Kontext, laufendes Training).
@MainActor
@Observable
final class AppState {
    let isDemo: Bool
    var selectedTab: AppTab = .today
    var coachPrompt: String?
    /// Thema der ersten Coach-Antwort (z. B. „schlaf“), damit sie zum Einstieg passt.
    var coachTopic: String = "erholung"
    var liveWorkout: LiveWorkout? {
        didSet {
            // Die Live Activity spiegelt nur ein echtes Training, nie Vorschau oder UI-Test.
            let mirrorsActivity = !isDemo && !FormaApp.isUITest
            if let liveWorkout {
                liveWorkout.isDemo = isDemo
                liveWorkout.persist()
                // Keine Mitteilungs-Abfrage beim Start: Sie unterbrach den ersten Satz (Codex R-02-26).
                if mirrorsActivity {
                    if let old = oldValue, old.draftID != liveWorkout.draftID { LiveTrainingActivity.end(workoutID: old.draftID) }
                    LiveTrainingActivity.start(workout: liveWorkout)
                }
            } else {
                if !isDemo {
                    LiveWorkout.clearSaved()
                    RestNotifier.cancel()
                }
                if mirrorsActivity, let old = oldValue { LiveTrainingActivity.end(workoutID: old.draftID) }
            }
        }
    }
    /// Start abgeschlossen (Onboarding entschieden, Entwurf wiederhergestellt): erst dann werden Kurzbefehle ausgeführt.
    var launchReady = false
    var finishedSession: WorkoutSession?
    var showProfile = false
    /// Plus-Menü (Mahlzeit scannen, Essen suchen, Ernährung heute, Training starten).
    var showPlus = false
    var profilePhoto = ProfilePhotoStore.load()

    var weightUnit: WeightUnit {
        didSet { UserDefaults.standard.set(weightUnit.rawValue, forKey: "forma.weightUnit") }
    }

    init(isDemo: Bool = false) {
        self.isDemo = isDemo
        weightUnit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "forma.weightUnit") ?? "") ?? .kg
    }

    var workoutAdjustment: TrainingAdjustment? { isDemo ? nil : TrainingAdjustment.today }

    func openCoach(with prompt: String, topic: String = "erholung") {
        coachTopic = topic
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

    private static func key(_ date: Date = .now) -> String { "forma.adjust." + GoogleHealthTime.day(date, calendar: .forma) }

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
    /// Gewicht aus dem Plan. Nur unveränderte Folgesätze übernehmen das Gewicht des letzten Satzes (Codex R-01-26).
    var plannedWeight: Double? = nil
}

struct LiveExercise: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var muscle: String
    var restSeconds: Int
    var sets: [LiveSet]
    /// Vorschlag aus dem letzten Training (progressive Steigerung), ohne Einheit. Wird erst nach „Übernehmen“ wirksam (Codex R-02-12).
    var progression: String? = nil
    var suggestedWeight: Double? = nil
    /// Übernommenes Gewicht in kg; die Anzeige rechnet in die gewählte Einheit um (Gegenprüfung 02 #13).
    var appliedWeight: Double? = nil
}

/// Steigerungsregel: Wurden letztes Mal alle Arbeitssätze mit dem Ziel an Wiederholungen
/// und im Mittel mindestens 2 Wiederholungen Reserve geschafft, schlägt Forma +2,5 kg vor.
/// Bei Reserve 0 und verfehlten Wiederholungen bleibt das Gewicht. Sonst gleiches Gewicht wie zuletzt.
enum Progression {
    struct Plan: Equatable { var weight: Double; var note: String?; var increased = false }
    /// Steigerung in kg. Texte nennen keine Einheit, die Anzeige rechnet um.
    static let step = 2.5

    /// - Parameter plannedSets: Wie viele Arbeitssätze die Routine vorsieht. Eine Steigerung gibt es nur,
    ///   wenn letztes Mal mindestens so viele Sätze am Topgewicht geschafft **und** alle mit Reserve erfasst wurden (Codex A-17/A-18).
    static func plan(targetReps: Int, routineWeight: Double, lastWorkSets: [(weight: Double, reps: Int, rir: Int)], plannedSets: Int = 0) -> Plan {
        guard let top = lastWorkSets.map({ $0.weight }).max(), top > 0 else { return Plan(weight: routineWeight, note: nil) }
        let atTop = lastWorkSets.filter { $0.weight == top }
        let allReps = atTop.allSatisfy { $0.reps >= targetReps }
        let rirs = atTop.map({ $0.rir }).filter { $0 >= 0 }
        let allRecorded = rirs.count == atTop.count
        let complete = atTop.count >= plannedSets
        let meanRIR = rirs.isEmpty ? nil : Double(rirs.reduce(0, +)) / Double(rirs.count)
        if allReps, complete, allRecorded, let meanRIR, meanRIR >= 2 {
            return Plan(weight: top + step, note: "Letztes Mal alle \(targetReps) Wdh. mit Reserve geschafft", increased: true)
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
        guard !ProcessInfo.processInfo.arguments.contains("-uitest") else { return }
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
    var isDemo = false
    let id = UUID()
    var title: String
    let start: Date
    var exercises: [LiveExercise]
    var exerciseIndex = 0
    var setIndex = 0
    var restEndsAt: Date?
    var restTotal: Int = 90
    /// Reserve des aktuellen Satzes. Standard: nicht erfasst (Codex R-02-12/A-18).
    var currentRIR: Int? = nil { didSet { persist() } }
    /// Feste Kennung des Entwurfs, auch über Neustarts hinweg (Codex R-02-05).
    let draftID: UUID
    var adjustment: TrainingAdjustment?

    init(title: String, exercises: [LiveExercise], adjustment: TrainingAdjustment? = nil, start: Date = .now, draftID: UUID = UUID()) {
        self.title = title
        self.exercises = exercises
        self.adjustment = adjustment
        self.start = start
        self.draftID = draftID
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
        var currentRIR: Int?
        var adjustment: TrainingAdjustment?
        var draftID: UUID?
        var version: Int?
    }

    private static let storageKey = "forma.liveWorkout"

    func persist() {
        guard !isDemo else { return }
        let snap = Snapshot(title: title, start: start, exercises: exercises, exerciseIndex: exerciseIndex, setIndex: setIndex,
                            restEndsAt: restEndsAt, restTotal: restTotal, currentRIR: currentRIR, adjustment: adjustment,
                            draftID: draftID, version: 2)
        if let data = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
    }

    static func clearSaved() { UserDefaults.standard.removeObject(forKey: storageKey) }

    /// Gespeichertes Training der letzten 8 Stunden zurückholen. Kaputte Daten werden verworfen,
    /// unplausible Werte normalisiert (Codex A-20). Wurde der Entwurf schon gespeichert, wird er nicht erneut angeboten (A-07).
    static func restore(now: Date = .now, alreadySaved: (UUID) -> Bool = { _ in false }) -> LiveWorkout? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
              now.timeIntervalSince(snap.start) < 8 * 3600, snap.start <= now.addingTimeInterval(60) else {
            clearSaved()
            return nil
        }
        let draftID = snap.draftID ?? UUID()
        if alreadySaved(draftID) { clearSaved(); return nil }
        // Grenzen wie bei der Eingabe (Start aus Routine und Hinzufügen sind gleich gedeckelt), damit nie ein
        // gültiger Entwurf gekürzt wird (Gegenprüfung 02 #12): höchstens maxExercises Übungen à 50 Sätze, Gewicht 0–1000, Wdh 1–100.
        let exercises = snap.exercises.prefix(maxExercises).map { ex -> LiveExercise in
            var ex = ex
            ex.sets = ex.sets.prefix(50).map { s in
                var s = s
                s.weight = s.weight.isFinite ? min(1000, max(0, s.weight)) : 0
                s.reps = min(100, max(1, s.reps))
                s.rir = s.rir.map { min(4, max(0, $0)) }
                return s
            }
            ex.restSeconds = min(900, max(15, ex.restSeconds))
            return ex
        }.filter { !$0.sets.isEmpty }
        guard !exercises.isEmpty else { clearSaved(); return nil }
        let w = LiveWorkout(title: snap.title, exercises: exercises, adjustment: snap.adjustment, start: snap.start, draftID: draftID)
        if w.exercises.indices.contains(snap.exerciseIndex), w.exercises[snap.exerciseIndex].sets.indices.contains(snap.setIndex) {
            w.exerciseIndex = snap.exerciseIndex
            w.setIndex = snap.setIndex
        }
        w.restTotal = min(900, max(1, snap.restTotal))
        w.restEndsAt = snap.restEndsAt.flatMap { $0 > now && $0 < now.addingTimeInterval(900) ? $0 : nil }
        w.currentRIR = snap.currentRIR.map { min(4, max(0, $0)) }
        return w
    }

    /// Obergrenze für Übungen pro Training – gilt beim Start, beim Hinzufügen und beim Wiederherstellen gleich.
    static let maxExercises = 60

    static func from(_ routine: Routine, history: [WorkoutSession], adjustment: TrainingAdjustment?) -> LiveWorkout {
        let items = Array(routine.sortedItems.prefix(maxExercises))
        let exercises = items.enumerated().map { index, item -> LiveExercise in
            var setCount = item.sets
            let lastSession = history.first { $0.sets.contains { $0.exerciseName == item.exerciseName } }
            let lastWork = (lastSession?.workSets ?? []).filter { $0.exerciseName == item.exerciseName }
                .map { (weight: $0.weight, reps: $0.reps, rir: $0.rir) }
            let plan = Progression.plan(targetReps: item.reps, routineWeight: item.weight, lastWorkSets: lastWork, plannedSets: item.sets)
            // Gewicht vom letzten Mal halten; eine Steigerung ist nur ein Vorschlag (Codex R-02-12).
            var weight = plan.increased ? plan.weight - 2.5 : plan.weight
            if adjustment == .minusOneSet { setCount = max(1, setCount - 1) }
            if adjustment == .plusWeight && index == 0 { weight += 2.5 }
            // Vorwerte und „Letztes Mal“ berechnet die Ansicht numerisch aus dem Verlauf, in der gewählten Einheit.
            var sets = (0..<setCount).map { _ in
                LiveSet(weight: weight, reps: item.reps, isWarmup: false, plannedWeight: weight)
            }
            if index == 0 && weight >= 40 {
                sets.insert(LiveSet(weight: (weight * 0.55 / 2.5).rounded() * 2.5, reps: 10, isWarmup: true), at: 0)
            }
            return LiveExercise(name: item.exerciseName, muscle: item.muscle, restSeconds: max(15, item.restSeconds), sets: sets,
                                progression: plan.note,
                                suggestedWeight: plan.increased && !(adjustment == .plusWeight && index == 0) ? plan.weight : nil)
        }
        return LiveWorkout(title: routine.name, exercises: exercises, adjustment: adjustment)
    }

    static func empty() -> LiveWorkout { LiveWorkout(title: "Freies Training", exercises: []) }

    var isResting: Bool { (restEndsAt ?? .distantPast) > .now }
    /// Fertig nur, wenn es mindestens einen Satz gibt und alle erledigt sind (Codex A-19).
    var allDone: Bool {
        exercises.contains { !$0.sets.isEmpty } && exercises.allSatisfy { $0.sets.allSatisfy(\.done) }
    }
    var currentExercise: LiveExercise? { exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil }
    var currentSet: LiveSet? {
        guard let ex = currentExercise, ex.sets.indices.contains(setIndex) else { return nil }
        return ex.sets[setIndex]
    }

    /// „Bankdrücken · Satz 2“ bzw. „Bankdrücken · Aufwärmen“ für den aktuellen Satz.
    var currentLabel: String? {
        guard let ex = currentExercise, let set = currentSet else { return nil }
        return set.isWarmup ? "\(ex.name) · Aufwärmen" : "\(ex.name) · Satz \(workSetNumber(exercise: exerciseIndex, set: setIndex))"
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

    /// Satz auswählen. Eine laufende Pause bleibt bestehen – beenden nur über „Pause beenden“ (Codex R-02-04).
    func select(exercise: Int, set: Int) {
        guard exercises.indices.contains(exercise), exercises[exercise].sets.indices.contains(set),
              !exercises[exercise].sets[set].done else { return }
        exerciseIndex = exercise
        setIndex = set
        persist()
        LiveTrainingActivity.update(workout: self)
    }

    /// Vorschlag übernehmen: alle offenen Arbeitssätze der Übung auf das vorgeschlagene Gewicht.
    func applyProgression(exercise: Int) {
        guard exercises.indices.contains(exercise), let w = exercises[exercise].suggestedWeight else { return }
        for i in exercises[exercise].sets.indices where !exercises[exercise].sets[i].done && !exercises[exercise].sets[i].isWarmup {
            exercises[exercise].sets[i].weight = w
            exercises[exercise].sets[i].plannedWeight = w
        }
        exercises[exercise].suggestedWeight = nil
        exercises[exercise].appliedWeight = w
        exercises[exercise].progression = "Übernommen"
        persist()
    }

    /// Schließt genau den Satz mit dieser ID ab – ein zweiter Tipp auf denselben Knopf tut nichts (Codex R-02-04/A-06).
    @discardableResult
    func completeCurrentSet(id: UUID) -> Bool {
        guard let set = currentSet, set.id == id, !set.done else { return false }
        completeCurrentSet()
        return true
    }

    func completeCurrentSet() {
        guard let current = currentSet, !current.done else { return }
        exercises[exerciseIndex].sets[setIndex].done = true
        exercises[exerciseIndex].sets[setIndex].rir = exercises[exerciseIndex].sets[setIndex].isWarmup ? nil : currentRIR
        currentRIR = nil
        // Gleiche Werte in den nächsten offenen Satz übernehmen, falls noch Standard
        let done = exercises[exerciseIndex].sets[setIndex]
        if let next = exercises[exerciseIndex].sets.firstIndex(where: { !$0.done }), !done.isWarmup {
            let candidate = exercises[exerciseIndex].sets[next]
            if !candidate.isWarmup, candidate.plannedWeight == nil || candidate.weight == candidate.plannedWeight {
                exercises[exerciseIndex].sets[next].weight = done.weight
                exercises[exerciseIndex].sets[next].plannedWeight = done.weight
            }
        }
        restTotal = exercises[exerciseIndex].restSeconds
        restEndsAt = .now.addingTimeInterval(TimeInterval(restTotal))
        selectFirstOpen(keepRest: true)
        if allDone {
            restEndsAt = nil
            if !isDemo { RestNotifier.cancel() }
        } else if !isDemo, let end = restEndsAt {
            RestNotifier.schedule(at: end, next: currentExercise?.name)
        }
        persist()
        LiveTrainingActivity.update(workout: self)
    }

    func extendRest(by seconds: Int) {
        let base = max(Date.now, restEndsAt ?? .now)
        restEndsAt = base.addingTimeInterval(TimeInterval(seconds))
        restTotal += seconds
        if !isDemo, let end = restEndsAt { RestNotifier.schedule(at: end, next: currentExercise?.name) }
        persist()
        LiveTrainingActivity.update(workout: self)
    }

    func skipRest() {
        restEndsAt = nil
        if !isDemo { RestNotifier.cancel() }
        persist()
        LiveTrainingActivity.update(workout: self)
    }

    func addSet(to exercise: Int) {
        guard exercises.indices.contains(exercise) else { return }
        guard exercises[exercise].sets.count < 50 else { return }
        let last = exercises[exercise].sets.last
        exercises[exercise].sets.append(LiveSet(weight: last?.weight ?? 20, reps: last?.reps ?? 8, isWarmup: false))
        // Ist der ausgewählte Satz schon erledigt, den neuen auswählen (Codex A-19).
        if currentSet == nil || currentSet?.done == true { selectFirstOpen(keepRest: true) }
        persist()
        LiveTrainingActivity.update(workout: self)
    }

    func addExercise(name: String, muscle: String) {
        guard exercises.count < Self.maxExercises else { return }
        exercises.append(LiveExercise(name: name, muscle: muscle, restSeconds: 90,
                                      sets: (0..<3).map { _ in LiveSet(weight: 20, reps: 10, isWarmup: false) }))
        if currentSet == nil || currentSet?.done == true { selectFirstOpen() }
        persist()
        LiveTrainingActivity.update(workout: self)
    }

    private func selectFirstOpen(keepRest: Bool = false) {
        if let ex = exercises.indices.first(where: { i in exercises[i].sets.contains { !$0.done } }),
           let s = exercises[ex].sets.firstIndex(where: { !$0.done }) {
            exerciseIndex = ex
            setIndex = s
        }
        if !keepRest { restEndsAt = nil }
    }

    /// Speichert das Training. Gibt die Sitzung zurück (nil, wenn kein Satz erledigt wurde).
    /// Wirft bei Schreibfehlern und nimmt dann alles zurück, damit kein halbes Training bleibt.
    func save(into context: ModelContext) throws -> WorkoutSession? {
        // Schon gespeichert (z. B. Neustart zwischen Speichern und Aufräumen)? Dann dieselbe Einheit zurückgeben.
        let id = draftID
        if let existing = try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.draftID == id })).first {
            return existing
        }
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
        session.draftID = draftID
        context.insert(session)
        for r in records {
            context.insert(r)
            r.session = session
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return session
    }
}

