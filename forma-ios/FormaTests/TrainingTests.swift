import Foundation
import XCTest
@testable import Forma

/// Übungskatalog, Muskelzuordnung, Muskelkarte und Wochenzählung.
@MainActor
final class TrainingTests: XCTestCase {
    private let now = Calendar.forma.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 18))!

    // MARK: Katalog

    func testCatalogIsComplete() {
        let names = ExerciseCatalog.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "Übungsnamen doppelt")
        for info in ExerciseCatalog.all {
            XCTAssertFalse(info.primary.isEmpty, "\(info.name): keine Hauptmuskeln")
            XCTAssertTrue((3...5).contains(info.steps.count), "\(info.name): 3–5 Schritte erwartet")
            XCTAssertFalse(info.mistakes.isEmpty, "\(info.name): keine Fehler")
            XCTAssertFalse(info.breathing.isEmpty)
            XCTAssertFalse(info.tempo.isEmpty)
            XCTAssertTrue(Set(info.primary).isDisjoint(with: info.secondary), "\(info.name): Muskel primär und sekundär")
            XCTAssertTrue(["Brust", "Rücken", "Schultern", "Beine", "Arme", "Rumpf"].contains(info.group), info.name)
        }
    }

    func testEveryMuscleHasExercises() {
        for muscle in Muscle.allCases {
            XCTAssertFalse(ExerciseCatalog.exercises(for: muscle).primary.isEmpty, "\(muscle.name) ohne Übung")
        }
    }

    func testExistingLibraryNamesStay() {
        // Gespeicherte Trainings verweisen per Name auf Übungen – alte Namen dürfen nicht verschwinden.
        let old = ["Bankdrücken", "Schrägbankdrücken Kurzhantel", "Dips", "Fliegende am Kabel", "Liegestütz", "Schulterdrücken",
                   "Seitheben", "Face Pulls", "Arnold Press", "Klimmzüge", "Langhantelrudern", "Latzug", "Rudern am Kabel",
                   "Kurzhantelrudern einarmig", "Kreuzheben", "Kniebeuge", "Rumänisches Kreuzheben", "Beinpresse", "Ausfallschritte",
                   "Beinstrecker", "Beinbeuger", "Wadenheben", "Hip Thrust", "Bulgarian Split Squat", "Bizepscurls", "Hammercurls",
                   "Langhantelcurls", "Trizepsdrücken am Kabel", "Überkopf-Trizepsstrecken", "French Press", "Plank",
                   "Hängendes Beinheben", "Cable Crunch", "Ab Wheel"]
        let names = Set(TrainingSeed.library.map(\.0))
        for name in old { XCTAssertTrue(names.contains(name), name) }
        for routine in TrainingSeed.routines {
            for item in routine.1 { XCTAssertNotNil(ExerciseCatalog.info(for: item.0), item.0) }
        }
    }

    func testExerciseToMuscleMapping() {
        let bench = ExerciseCatalog.muscles(for: "Bankdrücken", group: "Brust")
        XCTAssertEqual(bench.primary, [.chest])
        XCTAssertEqual(Set(bench.secondary), [.frontDelts, .triceps])

        let squat = ExerciseCatalog.muscles(for: "Kniebeuge", group: "Beine")
        XCTAssertTrue(squat.primary.contains(.quads) && squat.primary.contains(.glutes))

        XCTAssertEqual(ExerciseCatalog.muscles(for: "Klimmzüge", group: nil).primary, [.lats])
        XCTAssertEqual(ExerciseCatalog.muscles(for: "Seitheben", group: nil).primary, [.sideDelts])

        // Eigene Übung ohne Katalogeintrag: Hauptmuskeln der Gruppe.
        XCTAssertEqual(ExerciseCatalog.muscles(for: "Meine Presse", group: "Brust").primary, [.chest])
        XCTAssertTrue(ExerciseCatalog.muscles(for: "Unbekannt", group: nil).primary.isEmpty)

        let intensity = ExerciseCatalog.intensity(primary: [.chest], secondary: [.triceps])
        XCTAssertEqual(intensity[.chest], 1)
        XCTAssertEqual(intensity[.triceps], ExerciseCatalog.secondaryLevel)
        XCTAssertNil(intensity[.quads])
    }

    func testMotionCoverage() {
        let withMotion = ExerciseCatalog.all.filter { $0.motion != nil }
        XCTAssertGreaterThanOrEqual(withMotion.count, 15)
        XCTAssertEqual(Set(withMotion.compactMap(\.motion)), Set(ExerciseMotion.allCases), "Jede Animation wird genutzt")
        for motion in ExerciseMotion.allCases {
            let scene = MotionScene.scene(for: motion)
            XCTAssertEqual(scene.start.joints.count, 8, motion.rawValue)
            XCTAssertEqual(scene.end.joints.count, 8, motion.rawValue)
            XCTAssertEqual(scene.start.mixed(with: scene.end, 1).joints, scene.end.joints, motion.rawValue)
        }
    }

    // MARK: Muskelkarte

    func testMapShapesMatchSides() {
        for muscle in Muscle.allCases {
            XCTAssertTrue(muscle.onFront || muscle.onBack, muscle.name)
            XCTAssertEqual(MuscleArt.polygons(muscle, .front) != nil, muscle.onFront, "\(muscle.name) vorne")
            XCTAssertEqual(MuscleArt.polygons(muscle, .back) != nil, muscle.onBack, "\(muscle.name) hinten")
        }
    }

    func testMapHitTestFindsChest() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 440)
        let chest = BodyShape(polygons: MuscleArt.polygons(.chest, .front)!).path(in: rect)
        XCTAssertTrue(chest.contains(CGPoint(x: 120, y: 108)))
        XCTAssertTrue(chest.contains(CGPoint(x: 80, y: 108)), "gespiegelte Hälfte")
        XCTAssertFalse(chest.contains(CGPoint(x: 120, y: 300)))
    }

    func testPreferredSide() {
        XCTAssertEqual(MuscleMapView.preferredSide(for: [.chest: 1, .triceps: 0.4]), .front)
        XCTAssertEqual(MuscleMapView.preferredSide(for: [.lats: 1, .biceps: 0.4]), .back)
        XCTAssertEqual(MuscleMapView.preferredSide(for: [:]), .front)
    }

    // MARK: Wochenzählung

    func testWeeklyVolumeCountsPrimaryAndSecondary() {
        let yesterday = now.addingTimeInterval(-86_400)
        let sets: [(exercise: String, date: Date)] = Array(repeating: ("Bankdrücken", yesterday), count: 3)
        let volume = MuscleVolume.lastSevenDays(sets, now: now)
        XCTAssertEqual(volume[.chest], 3)
        XCTAssertEqual(volume[.triceps], 1.5)
        XCTAssertEqual(volume[.frontDelts], 1.5)
        XCTAssertNil(volume[.quads])
    }

    func testWeeklyVolumeWindow() {
        let cal = Calendar.forma
        let sixDaysAgoMorning = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!.addingTimeInterval(60)
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now)!
        let tomorrow = now.addingTimeInterval(86_400)
        let sets: [(exercise: String, date: Date)] = [("Kniebeuge", sixDaysAgoMorning), ("Kniebeuge", sevenDaysAgo), ("Kniebeuge", tomorrow)]
        XCTAssertEqual(MuscleVolume.lastSevenDays(sets, now: now, calendar: cal)[.quads], 1)
    }

    func testWeeklyVolumeCustomExercise() {
        let sets: [(exercise: String, date: Date)] = [("Meine Presse", now), ("Meine Presse", now)]
        XCTAssertEqual(MuscleVolume.lastSevenDays(sets, groups: ["Meine Presse": "Brust"], now: now)[.chest], 2)
        XCTAssertTrue(MuscleVolume.lastSevenDays(sets, now: now).isEmpty, "ohne Gruppe keine Zuordnung")
    }

    func testLevelAndText() {
        XCTAssertEqual(MuscleVolume.level(0), 0)
        XCTAssertGreaterThan(MuscleVolume.level(0.5), 0)
        XCTAssertEqual(MuscleVolume.level(10), 1)
        XCTAssertEqual(MuscleVolume.level(25), 1)
        XCTAssertLessThan(MuscleVolume.level(3), MuscleVolume.level(6))
        XCTAssertEqual(MuscleVolume.text(4.5), "4,5")
        XCTAssertEqual(MuscleVolume.text(12), "12")
    }

    // MARK: Runde 5 – Bestwerte

    func testPersonalRecord() {
        XCTAssertFalse(PersonalRecord.isNew(weight: 100, reps: 5, previousBest: 0), "erstes Mal ist kein Rekord")
        XCTAssertTrue(PersonalRecord.isNew(weight: 100, reps: 5, previousBest: 110))     // 116,7 > 110
        XCTAssertFalse(PersonalRecord.isNew(weight: 100, reps: 1, previousBest: 100), "gleich ist kein Rekord")
        XCTAssertFalse(PersonalRecord.isNew(weight: 0, reps: 10, previousBest: 50))
    }

    func testExerciseRecordsAndSeries() throws {
        let d1 = now.addingTimeInterval(-7 * 86_400), d2 = now
        let lifts: [(date: Date, sets: [LiftSet])] = [
            (date: d2, sets: [(weight: 80, reps: 8), (weight: 85, reps: 5)]),
            (date: d1, sets: [(weight: 75, reps: 12), (weight: 75, reps: 10)]),
            (date: now.addingTimeInterval(-3 * 86_400), sets: [])
        ]
        let r = try XCTUnwrap(ExerciseRecords.from(lifts))
        XCTAssertEqual(r.heaviest, 85)
        XCTAssertEqual(r.heaviestReps, 5)
        XCTAssertEqual(r.mostReps, 12)
        XCTAssertEqual(r.bestSessionVolume, 75 * 12 + 75 * 10)
        XCTAssertEqual(r.bestOneRepMax, 75 * (1 + 12.0 / 30), accuracy: 0.001)   // 105 schlägt 80 × 8 (≈ 101,3)
        XCTAssertEqual(r.bestOneRepMaxDate, d1)

        let series = ExerciseProgressPoint.series(lifts)
        XCTAssertEqual(series.map(\.date), [d1, d2], "sortiert, leere Trainings fehlen")
        XCTAssertEqual(series[1].volume, 80 * 8 + 85 * 5)
        XCTAssertNil(ExerciseRecords.from([(date: now, sets: [])]))
    }

    // MARK: Runde 5 – Muskel-Erholung

    func testRecoveryDecaysOver72Hours() {
        let fresh: [(exercise: String, date: Date)] = Array(repeating: ("Bankdrücken", now), count: 3)
        let load = MuscleRecovery.load(fresh, now: now)
        XCTAssertEqual(load[.chest], 3)
        XCTAssertEqual(load[.triceps], 1.5)
        XCTAssertEqual(MuscleRecovery.state(load[.chest] ?? 0), .recovering)

        let heavy: [(exercise: String, date: Date)] = Array(repeating: ("Bankdrücken", now), count: 6)
        XCTAssertEqual(MuscleRecovery.state(MuscleRecovery.load(heavy, now: now)[.chest] ?? 0), .loaded)

        let half: [(exercise: String, date: Date)] = [("Kniebeuge", now.addingTimeInterval(-36 * 3600))]
        XCTAssertEqual(MuscleRecovery.load(half, now: now)[.quads] ?? 0, 0.5, accuracy: 0.001)

        let old: [(exercise: String, date: Date)] = [("Kniebeuge", now.addingTimeInterval(-73 * 3600)), ("Kniebeuge", now.addingTimeInterval(3600))]
        XCTAssertTrue(MuscleRecovery.load(old, now: now).isEmpty, "älter als 72 h und Zukunft zählen nicht")
        XCTAssertEqual(MuscleRecovery.state(0), .fresh)
        XCTAssertEqual(MuscleRecovery.level(0.5), 0)
        XCTAssertEqual(MuscleRecovery.level(20), 1)
    }

    // MARK: Runde 5 – Kalender und Serie

    func testCalendarGridStartsOnMonday() {
        // 1. November 2026 ist ein Sonntag → 6 Lücken bei Wochenstart Montag, 30 Tage.
        let grid = TrainingCalendar.grid(for: now)
        XCTAssertEqual(grid.prefix(6).filter { $0 == nil }.count, 6)
        XCTAssertNotNil(grid[6])
        XCTAssertEqual(grid.compactMap { $0 }.count, 30)
        XCTAssertEqual(Calendar.forma.component(.day, from: grid[6]!), 1)
    }

    func testWeekStreak() {
        let day: TimeInterval = 86_400
        let thisWeek = now                                  // Do 19.11.
        let lastWeek = now.addingTimeInterval(-7 * day)     // Do 12.11.
        let twoAgo = now.addingTimeInterval(-14 * day)      // Do 5.11.
        let fourAgo = now.addingTimeInterval(-28 * day)
        XCTAssertEqual(TrainingCalendar.weekStreak([thisWeek, lastWeek, twoAgo, fourAgo], now: now), 3)
        XCTAssertEqual(TrainingCalendar.weekStreak([lastWeek, twoAgo], now: now), 2, "laufende Woche bricht die Serie nicht")
        XCTAssertEqual(TrainingCalendar.weekStreak([twoAgo], now: now), 0)
        XCTAssertEqual(TrainingCalendar.weekStreak([], now: now), 0)
        XCTAssertEqual(TrainingCalendar.days([now, now.addingTimeInterval(60)]).count, 1)
    }

    // MARK: Runde 5 – Routinen

    func testRoutineCopyNamesAndFolders() {
        XCTAssertEqual(Routine.copyName("Push", existing: ["Push"]), "Push Kopie")
        XCTAssertEqual(Routine.copyName("Push", existing: ["Push", "Push Kopie"]), "Push Kopie 2")
        XCTAssertEqual(Routine.copyName("Push", existing: ["Push Kopie", "Push Kopie 2"]), "Push Kopie 3")
        XCTAssertNil(Routine.cleanFolder("   "))
        XCTAssertEqual(Routine.cleanFolder("  Kraft "), "Kraft")

        let a = Routine(name: "A"), b = Routine(name: "B"), c = Routine(name: "C")
        b.folder = "Reha"; c.folder = "Kraft"
        let groups = Routine.grouped([a, b, c])
        XCTAssertEqual(groups.map(\.folder), [nil, "Kraft", "Reha"])
        XCTAssertEqual(groups[0].routines.map(\.name), ["A"])
    }

    // MARK: Supersätze

    func testSupersetGroups() {
        XCTAssertEqual(Superset.linking([nil, nil, nil], at: 0), [1, 1, nil])
        XCTAssertEqual(Superset.linking([1, 1, nil], at: 1), [1, 1, 1])
        XCTAssertEqual(Superset.linking([1, 1, 2, 2], at: 1), [1, 1, 1, 1], "zwei Gruppen verschmelzen")
        XCTAssertEqual(Superset.unlinking([1, 1, 1], at: 2), [1, 1, nil])
        XCTAssertEqual(Superset.unlinking([1, 1], at: 0), [nil, nil], "allein bleibt keine Gruppe")
        XCTAssertEqual(Superset.normalized([5, 5, nil, 5]), [1, 1, nil, nil], "getrennte Reste lösen sich")
        XCTAssertEqual(Superset.normalized([2, 2, 1, 1]), [1, 1, 2, 2])
        XCTAssertEqual(Superset.position([1, 1, nil], at: 0), .first)
        XCTAssertEqual(Superset.position([1, 1, 1], at: 1), .middle)
        XCTAssertEqual(Superset.position([1, 1, nil], at: 1), .last)
        XCTAssertNil(Superset.position([1, 1, nil], at: 2))
        XCTAssertTrue(Superset.isLinkedWithNext([1, 1, nil], at: 0))
        XCTAssertFalse(Superset.isLinkedWithNext([1, 1, nil], at: 1))
    }

    func testSupersetNextStep() {
        let groups: [Int?] = [1, 1, nil]
        XCTAssertEqual(Superset.next(after: 0, groups: groups, open: [true, true, true])?.index, 1)
        XCTAssertEqual(Superset.next(after: 0, groups: groups, open: [true, true, true])?.rests, false)
        XCTAssertEqual(Superset.next(after: 1, groups: groups, open: [true, true, true])?.index, 0)
        XCTAssertEqual(Superset.next(after: 1, groups: groups, open: [true, true, true])?.rests, true)
        // Mehr Sätze in der zweiten Übung: nach der Pause dort weiter.
        XCTAssertEqual(Superset.next(after: 1, groups: groups, open: [false, true, true])?.index, 1)
        XCTAssertNil(Superset.next(after: 1, groups: groups, open: [false, false, true]), "Gruppe fertig")
        XCTAssertNil(Superset.next(after: 2, groups: groups, open: [true, true, true]), "einzelne Übung")
    }

    func testLiveSupersetAlternatesAndRestsAfterRound() {
        func sets(_ n: Int) -> [LiveSet] { (0..<n).map { _ in LiveSet(weight: 40, reps: 10, isWarmup: false) } }
        let workout = LiveWorkout(title: "Test", exercises: [
            LiveExercise(name: "Bankdrücken", muscle: "Brust", restSeconds: 60, sets: sets(2), superset: 1),
            LiveExercise(name: "Rudern", muscle: "Rücken", restSeconds: 90, sets: sets(2), superset: 1),
            LiveExercise(name: "Seitheben", muscle: "Schultern", restSeconds: 60, sets: sets(1))
        ])
        workout.isDemo = true
        workout.completeCurrentSet()
        XCTAssertEqual([workout.exerciseIndex, workout.setIndex], [1, 0])
        XCTAssertFalse(workout.isResting, "keine Pause innerhalb der Runde")
        workout.completeCurrentSet()
        XCTAssertEqual([workout.exerciseIndex, workout.setIndex], [0, 1])
        XCTAssertTrue(workout.isResting)
        XCTAssertEqual(workout.restTotal, 90, "Pause der letzten Übung der Runde")
        workout.completeCurrentSet()
        XCTAssertEqual([workout.exerciseIndex, workout.setIndex], [1, 1])
        XCTAssertFalse(workout.isResting)
        workout.completeCurrentSet()
        XCTAssertEqual([workout.exerciseIndex, workout.setIndex], [2, 0])
        XCTAssertTrue(workout.isResting)
    }

    func testRestExtensionShowsWhatIsPossible() {
        XCTAssertEqual(LiveWorkout.possibleExtension(15, remaining: 0), 15)
        XCTAssertEqual(LiveWorkout.possibleExtension(15, remaining: 600), 15)
        XCTAssertEqual(LiveWorkout.possibleExtension(15, remaining: 898), 2)
        XCTAssertEqual(LiveWorkout.possibleExtension(15, remaining: 900), 0)
    }
}
