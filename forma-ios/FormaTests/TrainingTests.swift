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
}
