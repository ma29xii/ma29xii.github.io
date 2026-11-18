import XCTest
@testable import Forma

/// Angriffs- und Logiktests: kaputte Eingaben dürfen nie abstürzen oder Unsinn liefern.
final class ParsingAndMathTests: XCTestCase {

    // MARK: Fitbit-Zeit (kommt aus dem Netz, also nicht vertrauenswürdig)

    func testFitbitTimeValid() {
        let date = FitbitTime.parse("2026-11-17T23:10:30.000")
        XCTAssertNotNil(date)
        let c = Calendar.forma.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date!)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2026, 11, 17, 23, 10, 30])
    }

    func testFitbitTimeMalformedNeverCrashes() {
        let evil = ["", "T", "2026-11-17T", "2026-11-17T.", "2026-11-17T..", "T23:10", "2026-13-01T10:00", "2026-11-17T25:00",
                    "2026-11-17T10:61", "abc", "2026-11-17T10", "2026-11-17T10:00:00:00", "😈T😈", String(repeating: "9", count: 10_000)]
        for input in evil {
            XCTAssertNil(FitbitTime.parse(input), "Sollte nil sein: \(input.prefix(40))")
        }
    }

    func testRetryAfterHeader() {
        XCTAssertEqual(FitbitService.retryAfter("60"), 60)
        XCTAssertEqual(FitbitService.retryAfter(" 120 "), 120)
        XCTAssertEqual(FitbitService.retryAfter("999999"), 3 * 3600)
        XCTAssertNil(FitbitService.retryAfter("abc"))
        XCTAssertNil(FitbitService.retryAfter("-5"))
        XCTAssertNil(FitbitService.retryAfter("nan"))
        XCTAssertNil(FitbitService.retryAfter(nil))
    }

    func testPKCEChallengeIsBase64URL() {
        // RFC 7636, Anhang B
        XCTAssertEqual(FitbitService.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let random = FitbitService.randomString(length: 64)
        XCTAssertEqual(random.count, 64)
        XCTAssertNotEqual(random, FitbitService.randomString(length: 64))
    }

    // MARK: Scheibenrechner

    func testPlateMath() {
        XCTAssertEqual(PlateMath.perSide(total: 100), [25, 15])
        XCTAssertEqual(PlateMath.perSide(total: 20), [])
        XCTAssertEqual(PlateMath.perSide(total: 72.5), [25, 1.25])
        XCTAssertNil(PlateMath.perSide(total: 15))
        XCTAssertNil(PlateMath.perSide(total: 21))       // 0,5 kg pro Seite gibt es nicht
        XCTAssertNil(PlateMath.perSide(total: .nan))
        XCTAssertNil(PlateMath.perSide(total: .infinity))
        XCTAssertNil(PlateMath.perSide(total: 100_000))  // Schutz vor endlosen Listen
    }

    // MARK: Steigerung

    func testProgressionIncreasesWithReserve() {
        let plan = Progression.plan(targetReps: 8, routineWeight: 60, lastWorkSets: [(70, 8, 2), (70, 8, 3), (70, 9, 2)])
        XCTAssertEqual(plan.weight, 72.5)
        XCTAssertTrue(plan.increased)
    }

    func testProgressionHoldsAtLimit() {
        let plan = Progression.plan(targetReps: 8, routineWeight: 60, lastWorkSets: [(70, 8, 0), (70, 6, 0)])
        XCTAssertEqual(plan.weight, 70)
        XCTAssertFalse(plan.increased)
        XCTAssertNotNil(plan.note)
    }

    func testProgressionWithoutHistoryUsesRoutine() {
        let plan = Progression.plan(targetReps: 8, routineWeight: 60, lastWorkSets: [])
        XCTAssertEqual(plan.weight, 60)
        XCTAssertNil(plan.note)
    }

    func testProgressionIgnoresUnknownRIR() {
        let plan = Progression.plan(targetReps: 8, routineWeight: 60, lastWorkSets: [(70, 8, -1), (70, 8, -1)])
        XCTAssertEqual(plan.weight, 70)
        XCTAssertFalse(plan.increased)
    }

    func testOneRepMax() {
        XCTAssertEqual(OneRepMax.epley(weight: 100, reps: 1), 100)
        XCTAssertEqual(OneRepMax.epley(weight: 100, reps: 10), 100 * (1 + 10.0 / 30), accuracy: 0.001)
        XCTAssertEqual(OneRepMax.epley(weight: 0, reps: 5), 0)
        XCTAssertEqual(OneRepMax.epley(weight: 100, reps: 0), 0)
    }

    // MARK: Daten bereinigen

    func testSanitizedDropsImpossibleValues() {
        var d = DayMetrics(date: Date.now.startOfDay)
        d.hrv = .nan
        d.restingHR = 400
        d.steps = -5
        d.spo2 = 97
        d.vo2max = .infinity
        d.workouts = [WorkoutSummary(name: "x", start: .now, duration: -10, energy: 100),
                      WorkoutSummary(name: "y", start: .now, duration: 600, energy: .nan)]
        let s = d.sanitized()
        XCTAssertNil(s.hrv)
        XCTAssertNil(s.restingHR)
        XCTAssertNil(s.steps)
        XCTAssertEqual(s.spo2, 97)
        XCTAssertNil(s.vo2max)
        XCTAssertEqual(s.workouts.count, 1)
        XCTAssertNil(s.workouts.first?.energy)
    }

    func testSanitizedDropsBrokenSleep() {
        var d = DayMetrics(date: Date.now.startOfDay)
        let now = Date.now
        d.sleep = SleepNight(start: now, end: now.addingTimeInterval(-3600), segments: [])
        XCTAssertNil(d.sanitized().sleep)
    }
}

final class ScoreTests: XCTestCase {
    func testScoresStayInRangeWithEmptyHistory() {
        let s = ScoreEngine.scores(today: DayMetrics(date: Date.now.startOfDay), history: [])
        XCTAssertTrue((0...100).contains(s.recovery))
        XCTAssertTrue((0...100).contains(s.sleep))
        XCTAssertTrue((0...100).contains(s.strain))
        XCTAssertTrue((0...3).contains(s.stress))
    }

    func testScoresStayInRangeWithExtremeValues() {
        var today = DayMetrics(date: Date.now.startOfDay)
        today.hrv = 400; today.restingHR = 25; today.activeEnergy = 12_000
        today.workouts = [WorkoutSummary(name: "Ultra", start: .now, duration: 20 * 3600, energy: 9000)]
        let history = SampleData.days(count: 30).dropLast()
        let s = ScoreEngine.scores(today: today, history: Array(history))
        XCTAssertTrue((1...99).contains(s.recovery))
        XCTAssertTrue((0...100).contains(s.strain))
    }

    func testBaselineIgnoresNaN() {
        let b = ScoreEngine.baseline([50, 52, .nan, 54, 56, .infinity])
        XCTAssertNotNil(b)
        XCTAssertEqual(b!.mean, 53, accuracy: 0.001)
    }

    func testSampleDataLastThirtyDaysStable() {
        // Die Beispiel-Erholung soll unabhängig von der Länge des Verlaufs gleich sein.
        let short = SampleData.days(count: 30)
        let long = SampleData.days(count: 180).suffix(30)
        XCTAssertEqual(short.last?.hrv, long.last?.hrv)
        XCTAssertEqual(short.last?.restingHR, long.last?.restingHR)
    }
}

final class BodyAgeTests: XCTestCase {
    private func person(age: Double, sex: BiologicalSex = .male) -> PersonInfo {
        PersonInfo(birthDate: Date.now.addingTimeInterval(-age * 365.2425 * 86_400), sex: sex, origin: .manual)
    }

    func testNeedsProfileWithoutBirthDate() {
        let outcome = BodyAge.evaluate(days: SampleData.days(), person: PersonInfo(birthDate: nil, sex: .male, origin: .missing),
                                       strength: .init(perWeek: 0, recentPerWeek: 0))
        guard case .needsProfile = outcome else { return XCTFail("Profil sollte fehlen") }
    }

    func testNeedsDataWithFewDays() {
        let outcome = BodyAge.evaluate(days: SampleData.days(count: 10), person: person(age: 30),
                                       strength: .init(perWeek: 0, recentPerWeek: 0))
        guard case .needsData(let have, let need) = outcome else { return XCTFail("Zu wenige Tage") }
        XCTAssertEqual(have, 10)
        XCTAssertEqual(need, BodyAge.minimumDays)
    }

    func testSampleResultIsPlausible() {
        let outcome = BodyAge.evaluate(days: SampleData.days(), person: person(age: 30),
                                       strength: .init(perWeek: 150, recentPerWeek: 150))
        guard case .ready(let r) = outcome else { return XCTFail("Sollte rechnen") }
        XCTAssertEqual(r.age, 30, accuracy: 0.01)
        XCTAssertTrue((20...40).contains(r.bodyAge), "Körperalter \(r.bodyAge)")
        XCTAssertEqual(r.factors.count, 5)
        XCTAssertEqual(r.confidence, .high)
    }

    func testExtremeDataIsClamped() {
        var days = SampleData.days()
        for i in days.indices {
            days[i].steps = 150_000
            days[i].restingHR = 25
            days[i].vo2max = 95
        }
        let outcome = BodyAge.evaluate(days: days, person: person(age: 40), strength: .init(perWeek: 999, recentPerWeek: 999))
        guard case .ready(let r) = outcome else { return XCTFail("Sollte rechnen") }
        XCTAssertGreaterThanOrEqual(r.bodyAge, 25)
        XCTAssertLessThanOrEqual(r.bodyAge, 55)
        XCTAssertTrue(r.bodyAge.isFinite)
    }

    func testUnknownSexSkipsVO2() {
        let outcome = BodyAge.evaluate(days: SampleData.days(), person: person(age: 30, sex: .unknown),
                                       strength: .init(perWeek: 0, recentPerWeek: 0))
        guard case .ready(let r) = outcome else { return XCTFail("Sollte rechnen") }
        XCTAssertFalse(r.factors.contains { $0.id == "vo2" })
        XCTAssertTrue(r.missing.contains { $0.contains("Geschlecht") })
    }

    func testReferenceCurvesAreMonotonic() {
        XCTAssertGreaterThan(BodyAge.vo2Reference(age: 25, sex: .male), BodyAge.vo2Reference(age: 60, sex: .male))
        XCTAssertGreaterThan(BodyAge.vo2Reference(age: 30, sex: .male), BodyAge.vo2Reference(age: 30, sex: .female))
        XCTAssertEqual(BodyAge.vo2Reference(age: 10, sex: .male), 48.0)
        XCTAssertEqual(BodyAge.vo2Reference(age: 95, sex: .female), 18.3)
        var previous = BodyAge.stepsLogHazard(0)
        for steps in stride(from: 1000.0, through: 20_000, by: 500) {
            let h = BodyAge.stepsLogHazard(steps)
            XCTAssertLessThanOrEqual(h, previous + 1e-9)
            previous = h
        }
    }
}

final class TileArrangementTests: XCTestCase {
    func testDefaultContainsAllTiles() {
        let a = TileArrangement<TodayTile>(storage: "")
        XCTAssertEqual(a.visible.count, TodayTile.allCases.count)
    }

    func testRoundTripAndGarbage() {
        var a = TileArrangement<TodayTile>(storage: "")
        a.hide(.week)
        a.shift(.body, by: -1)
        let restored = TileArrangement<TodayTile>(storage: a.storage)
        XCTAssertEqual(restored, a)

        let garbage = TileArrangement<TodayTile>(storage: "hack,;DROP TABLE|||,,coach")
        XCTAssertEqual(Set(garbage.order), Set(TodayTile.allCases))
        XCTAssertEqual(garbage.order.count, TodayTile.allCases.count)
    }

    func testDuplicatesInStorageAreIgnored() {
        let a = TileArrangement<TodayTile>(storage: "coach,coach,next|")
        XCTAssertEqual(a.order.count, TodayTile.allCases.count)
    }

    func testMoveBeforeAndShowHide() {
        var a = TileArrangement<HealthTile>(storage: "")
        a.move(.sleepActivity, before: .bodyAge)
        XCTAssertEqual(a.visible.first, .sleepActivity)
        a.hide(.fitness)
        XCTAssertFalse(a.visible.contains(.fitness))
        a.show(.fitness)
        XCTAssertEqual(a.visible.last, .fitness)
        a.shift(.sleepActivity, by: -1) // schon oben: nichts passiert
        XCTAssertEqual(a.visible.first, .sleepActivity)
    }
}

@MainActor
final class LiveWorkoutTests: XCTestCase {
    private func workout() -> LiveWorkout {
        LiveWorkout(title: "Test", exercises: [
            LiveExercise(name: "Bankdrücken", muscle: "Brust", restSeconds: 90,
                         sets: [LiveSet(weight: 60, reps: 8, isWarmup: false), LiveSet(weight: 60, reps: 8, isWarmup: false)])
        ])
    }

    func testCompletingAllSetsFinishes() {
        defer { LiveWorkout.clearSaved() }
        let w = workout()
        w.completeCurrentSet()
        XCTAssertNotNil(w.restEndsAt)
        w.completeCurrentSet()
        XCTAssertTrue(w.allDone)
        XCTAssertNil(w.restEndsAt, "Nach dem letzten Satz keine Pause mehr")
    }

    func testWeightAndRepsAreBounded() {
        defer { LiveWorkout.clearSaved() }
        let w = workout()
        for _ in 0..<1000 { w.changeWeight(by: 2.5) }
        XCTAssertLessThanOrEqual(w.currentSet!.weight, 1000)
        for _ in 0..<1000 { w.changeWeight(by: -2.5) }
        XCTAssertEqual(w.currentSet!.weight, 0)
        for _ in 0..<500 { w.changeReps(by: -1) }
        XCTAssertEqual(w.currentSet!.reps, 1)
    }

    func testInvalidSelectionIsIgnored() {
        defer { LiveWorkout.clearSaved() }
        let w = workout()
        w.select(exercise: 99, set: 0)
        w.select(exercise: 0, set: -1)
        XCTAssertEqual(w.exerciseIndex, 0)
        XCTAssertEqual(w.setIndex, 0)
        w.addSet(to: 42)
        XCTAssertEqual(w.exercises[0].sets.count, 2)
    }

    func testSnapshotRestore() {
        defer { LiveWorkout.clearSaved() }
        let w = workout()
        w.changeWeight(by: 5)
        w.completeCurrentSet()
        let restored = LiveWorkout.restore()
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.exercises[0].sets[0].done, true)
        XCTAssertEqual(restored?.exercises[0].sets[0].weight, 65)
        XCTAssertEqual(restored?.start.timeIntervalSince1970 ?? 0, w.start.timeIntervalSince1970, accuracy: 0.01)
    }

    func testCorruptSnapshotIsDiscarded() {
        defer { LiveWorkout.clearSaved() }
        UserDefaults.standard.set(Data("kaputt".utf8), forKey: "forma.liveWorkout")
        XCTAssertNil(LiveWorkout.restore())
        XCTAssertNil(UserDefaults.standard.data(forKey: "forma.liveWorkout"))
    }

    func testOldSnapshotIsDiscarded() {
        defer { LiveWorkout.clearSaved() }
        let w = workout()
        w.persist()
        XCTAssertNil(LiveWorkout.restore(now: Date.now.addingTimeInterval(9 * 3600)))
    }
}
