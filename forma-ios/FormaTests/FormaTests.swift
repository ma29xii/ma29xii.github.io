import XCTest
import SwiftData
@testable import Forma

/// Angriffs- und Logiktests: kaputte Eingaben dürfen nie abstürzen oder Unsinn liefern.
final class ParsingAndMathTests: XCTestCase {

    // MARK: Google-Health-Zeit und OAuth

    func testGoogleHealthTimeValid() throws {
        let date = try XCTUnwrap(GoogleHealthTime.parse("2026-11-17T23:10:30.000+01:00"))
        XCTAssertEqual(GoogleHealthTime.physical(date), "2026-11-17T22:10:30Z")
    }

    func testGoogleHealthTimeMalformedNeverCrashes() {
        let evil = ["", "T", "2026-11-17T", "2026-11-17T.", "2026-11-17T..", "T23:10", "2026-13-01T10:00", "2026-11-17T25:00",
                    "2026-11-17T10:61", "abc", "2026-11-17T10", "2026-11-17T10:00:00:00", "😈T😈", String(repeating: "9", count: 10_000),
                    "2026-13-01T10:00:00Z", "2026-11-17T25:00:00Z", "2026-11-17T10:61:00Z", "2026-11-17T10:00:00"]
        for input in evil {
            XCTAssertNil(GoogleHealthTime.parse(input), "Sollte nil sein: \(input.prefix(40))")
        }
    }

    func testRetryAfterHeader() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(GoogleHealthService.retryDate("60", now: now), now.addingTimeInterval(60))
        XCTAssertEqual(GoogleHealthService.retryDate(" 120 ", now: now), now.addingTimeInterval(120))
        XCTAssertEqual(GoogleHealthService.retryDate("999999", now: now), now.addingTimeInterval(3 * 3600))
        XCTAssertEqual(GoogleHealthService.retryDate("Thu, 01 Jan 1970 00:01:30 GMT", now: now), now.addingTimeInterval(90))
        XCTAssertNil(GoogleHealthService.retryDate("abc", now: now))
        XCTAssertNil(GoogleHealthService.retryDate("-5", now: now))
        XCTAssertNil(GoogleHealthService.retryDate("nan", now: now))
        XCTAssertNil(GoogleHealthService.retryDate(nil, now: now))
    }

    func testPKCEChallengeIsBase64URL() throws {
        // RFC 7636, Anhang B
        XCTAssertEqual(GoogleHealthService.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let random = try GoogleHealthService.randomString()
        XCTAssertEqual(random.count, 43)
        XCTAssertTrue(random.utf8.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
        })
        XCTAssertNotEqual(random, try GoogleHealthService.randomString())
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

    func testMissingSleepDoesNotLowerRecovery() {
        let date = Date.now.startOfDay
        let history = (1...4).map { DayMetrics(date: date.adding(days: -$0), hrv: 50) }
        var today = DayMetrics(date: date, hrv: 50)
        let withoutSleep = ScoreEngine.scores(today: today, history: history)
        XCTAssertEqual(withoutSleep.sleep, 0)
        XCTAssertEqual(withoutSleep.recovery, 58)

        let start = date.adding(minutes: 60)
        let end = date.adding(minutes: 120)
        today.sleep = SleepNight(start: start, end: end,
                                 segments: [.init(stage: .unspecified, start: start, end: end)])
        XCTAssertLessThan(ScoreEngine.scores(today: today, history: history).recovery, withoutSleep.recovery)
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
    func testExampleProfileShowsHealthAgeAndTrend() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let days = SampleData.days(endingAt: date)
        let strength = BodyAge.strengthMinutes(days: days, formaSessions: [], now: date)
        let outcome = BodyAge.evaluate(days: days, person: SampleData.person(at: date), strength: strength, now: date)

        guard case .ready(let result) = outcome else {
            return XCTFail("Beispieldaten müssen Health Age zeigen")
        }
        XCTAssertEqual(result.daysWithData, 180)
        XCTAssertEqual(result.factors.count, 5)
        XCTAssertNotNil(result.trend)
    }

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
        let a = TileArrangement<HealthTile>(storage: "")
        XCTAssertEqual(a.visible.count, HealthTile.allCases.count)
    }

    func testRoundTripAndGarbage() {
        var a = TileArrangement<HealthTile>(storage: "")
        a.hide(.spo2)
        a.shift(.steps, by: -1)
        let restored = TileArrangement<HealthTile>(storage: a.storage)
        XCTAssertEqual(restored, a)

        let garbage = TileArrangement<HealthTile>(storage: "hack,;DROP TABLE|||,,hrv")
        XCTAssertEqual(Set(garbage.order), Set(HealthTile.allCases))
        XCTAssertEqual(garbage.order.count, HealthTile.allCases.count)
    }

    func testDuplicatesInStorageAreIgnored() {
        let a = TileArrangement<HealthTile>(storage: "hrv,hrv,steps|")
        XCTAssertEqual(a.order.count, HealthTile.allCases.count)
    }

    func testHealthLayoutExpandsOldGroups() {
        let a = TileArrangement<HealthTile>(storage: "fitness,heart,sleepActivity,bodyAge|heart,bodyAge")
        XCTAssertEqual(a.visible, [.vo2max, .sleepDuration, .steps, .activeEnergy])
        XCTAssertEqual(a.hiddenInOrder, [.hrv, .restingHR, .respiratoryRate, .spo2])
    }

    func testMoveBeforeAndShowHide() {
        var a = TileArrangement<HealthTile>(storage: "")
        a.move(.steps, before: .hrv)
        XCTAssertEqual(a.visible.first, .steps)
        a.hide(.vo2max)
        XCTAssertFalse(a.visible.contains(.vo2max))
        a.show(.vo2max)
        XCTAssertEqual(a.visible.last, .vo2max)
        a.shift(.steps, by: -1)
        XCTAssertEqual(a.visible.first, .steps)
    }
}

@MainActor
final class LiveWorkoutTests: XCTestCase {
    func testExampleTrainingHistoryContainsSetsAndSeedsOnce() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, SetRecord.self, configurations: configuration)
        let context = container.mainContext
        let days = SampleData.days()

        SampleData.seedWorkouts(days, in: context)
        let workouts = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertGreaterThan(workouts.count, 10)
        XCTAssertTrue(workouts.allSatisfy { !$0.workSets.isEmpty && $0.volume > 0 })

        SampleData.seedWorkouts(days, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), workouts.count)
    }

    func testDemoWorkoutLeavesRealDraftIntact() {
        let real = workout()
        real.persist()
        defer { LiveWorkout.clearSaved() }
        let demo = AppState(isDemo: true)
        demo.liveWorkout = LiveWorkout.empty()
        demo.liveWorkout = nil

        XCTAssertEqual(LiveWorkout.restore()?.draftID, real.draftID)
    }

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

/// Regressionstests zu Codex-Review 01.
final class ReviewRegressionTests: XCTestCase {
    private let t0 = Calendar.forma.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 23))!

    private func seg(_ stage: SleepNight.Stage, _ startMin: Double, _ endMin: Double) -> SleepNight.Segment {
        .init(stage: stage, start: t0.addingTimeInterval(startMin * 60), end: t0.addingTimeInterval(endMin * 60))
    }

    // R-01-06: Überlappende Phasen zählen nur einmal.
    func testUnionLengthCountsOverlapOnce() {
        let length = SleepNight.unionLength([seg(.core, 0, 60), seg(.core, 30, 90), seg(.deep, 120, 150)])
        XCTAssertEqual(length, 120 * 60, accuracy: 0.1)
    }

    // R-01-06: Nickerchen am Nachmittag wird nicht Teil der Nacht, zwei Tracker werden nicht addiert.
    func testMainNightIgnoresNapAndDuplicateTracker() {
        let watch = [seg(.core, 0, 120), seg(.deep, 120, 200), seg(.rem, 200, 260), seg(.core, 260, 450)]
        let phone = [seg(.core, 10, 440)]                      // zweiter Tracker, gleiche Nacht, ohne Phasen
        let nap = [seg(.core, 900, 940)]                        // am nächsten Nachmittag
        let nights = SleepNight.mainNights(bySource: ["watch": watch + nap, "phone": phone])
        let wakeDay = t0.addingTimeInterval(450 * 60).addingTimeInterval(6 * 3600).startOfDay
        let night = nights[wakeDay]
        XCTAssertNotNil(night)
        XCTAssertEqual(night!.asleep, 450 * 60, accuracy: 1)   // nicht 450 + 430
        XCTAssertTrue(night!.hasStages)                         // Uhr mit Phasen gewinnt
        XCTAssertLessThan(night!.end, t0.addingTimeInterval(500 * 60)) // Nickerchen nicht angehängt
    }

    // R-01-06: Ohne Phasen nicht bestraft.
    func testSleepScoreWithoutStagesIsNeutral() {
        let night = SleepNight(start: t0, end: t0.addingTimeInterval(8 * 3600), segments: [seg(.core, 0, 480)])
        let score = ScoreEngine.sleepScore(night, need: 8 * 3600)
        XCTAssertGreaterThanOrEqual(score, 85)
    }

    func testUnspecifiedSleepContributesToDurationButNotCore() {
        let known = seg(.core, 0, 60)
        let unspecified = seg(.unspecified, 60, 420)
        let night = SleepNight(start: known.start, end: unspecified.end, segments: [known, unspecified])

        XCTAssertEqual(night.asleep, 420 * 60, accuracy: 0.001)
        XCTAssertEqual(night.total(.core), 60 * 60, accuracy: 0.001)
        XCTAssertEqual(night.total(.unspecified), 360 * 60, accuracy: 0.001)
    }

    private func context(strain: Int, target: ClosedRange<Int>, trained: Bool, hrvDelta: Double?) -> CoachEngine.Context {
        let scores = DayScores(recovery: 70, sleep: 80, strain: strain, target: target, energy: 60, stress: 1.2, sleepNeed: 8 * 3600, sleepDebt: 0)
        return CoachEngine.Context(scores: scores, today: DayMetrics(date: Date.now.startOfDay), hrvDelta: hrvDelta, rhrDelta: nil,
                                   plannedRoutine: "Push", trainedToday: trained, isSample: false, hour: 10)
    }

    // R-01-05: 39 im Bereich 35–55 ist „im Zielbereich“, kein „es fehlen noch Punkte“.
    func testCoachMatchesTargetBand() {
        XCTAssertTrue(CoachEngine.dailyLine(context(strain: 39, target: 35...55, trained: true, hrvDelta: 3)).contains("Zielbereich (35–55)"))
        XCTAssertTrue(CoachEngine.dailyLine(context(strain: 34, target: 35...55, trained: true, hrvDelta: 3)).contains("noch 1 Punkte"))
        XCTAssertTrue(CoachEngine.dailyLine(context(strain: 56, target: 35...55, trained: true, hrvDelta: 3)).contains("über deinem Zielbereich"))
        XCTAssertTrue(CoachEngine.dailyLine(context(strain: 55, target: 35...55, trained: true, hrvDelta: 3)).contains("Zielbereich (35–55)"))
    }

    // R-01-05: Fehlende HRV wird nicht als „im Normalbereich“ behauptet.
    func testCoachSaysWhenHRVMissing() {
        let line = CoachEngine.dailyLine(context(strain: 10, target: 35...55, trained: false, hrvDelta: nil))
        XCTAssertTrue(line.contains("fehlt ein HRV-Wert"))
        XCTAssertNil(CoachEngine.suggestion(context(strain: 10, target: 35...55, trained: false, hrvDelta: nil)))
    }

    // C-01-06: „Wie viel Belastung ist heute gut?“ bekommt die Belastungsantwort.
    func testCoachRoutesStrainQuestion() {
        let answer = CoachEngine.localAnswer(to: "Wie viel Belastung ist heute gut?", context(strain: 20, target: 35...55, trained: false, hrvDelta: 1))
        XCTAssertTrue(answer.contains("Belastung bisher"))
    }
}

@MainActor
final class LiveWorkoutRegressionTests: XCTestCase {
    // R-01-26: Ein bewusst geändertes Folgegewicht wird nicht überschrieben.
    func testChangedFollowUpWeightIsKept() {
        defer { LiveWorkout.clearSaved() }
        let w = LiveWorkout(title: "Test", exercises: [
            LiveExercise(name: "Kniebeuge", muscle: "Beine", restSeconds: 90, sets: [
                LiveSet(weight: 100, reps: 5, isWarmup: false, plannedWeight: 100),
                LiveSet(weight: 90, reps: 8, isWarmup: false, plannedWeight: 100)   // vom Nutzer auf Backoff gesenkt
            ])
        ])
        w.changeWeight(by: 2.5)      // erster Satz 102,5
        w.completeCurrentSet()
        XCTAssertEqual(w.exercises[0].sets[1].weight, 90, "Backoff-Satz bleibt")
    }

    func testUnchangedFollowUpWeightFollows() {
        defer { LiveWorkout.clearSaved() }
        let w = LiveWorkout(title: "Test", exercises: [
            LiveExercise(name: "Kniebeuge", muscle: "Beine", restSeconds: 90, sets: [
                LiveSet(weight: 100, reps: 5, isWarmup: false, plannedWeight: 100),
                LiveSet(weight: 100, reps: 5, isWarmup: false, plannedWeight: 100)
            ])
        ])
        w.changeWeight(by: 2.5)
        w.completeCurrentSet()
        XCTAssertEqual(w.exercises[0].sets[1].weight, 102.5)
    }
}

/// Zuverlässigkeit der Synchronisierung: nie Daten verlieren.
final class SyncReliabilityTests: XCTestCase {
    private let today = Calendar.forma.date(from: DateComponents(year: 2026, month: 11, day: 18))!

    private func day(_ offset: Int, hrv: Double? = nil, steps: Double? = nil) -> DayMetrics {
        var d = DayMetrics(date: today.adding(days: offset))
        d.hrv = hrv; d.steps = steps
        return d
    }

    func testEmptyFetchDoesNotOverwriteData() {
        let old = [day(-2, hrv: 50), day(-1, hrv: 52), day(0, hrv: 55)]
        let empty = [day(-2), day(-1), day(0)]
        XCTAssertEqual(SyncStore.merge(old: old, new: empty, today: today), .rejectedEmpty)
    }

    // A-01: Fehlgeschlagene Reihe behält den letzten Stand, erfolgreiche Reihen gelten.
    func testFailedSeriesKeepsLastValue() {
        var oldToday = day(0, hrv: 55); oldToday.sleep = SleepNight(start: today, end: today.addingTimeInterval(7 * 3600), segments: [])
        let old = [day(-5, hrv: 50, steps: 8000), oldToday]
        let new = [day(-5, steps: 8100), day(0, hrv: 57, steps: 1200)]
        guard case .merged(let merged) = SyncStore.merge(old: old, new: new, failed: [.hrv, .sleep], today: today, keepDays: 10) else { return XCTFail() }
        let d5 = merged.first { $0.date == today.adding(days: -5) }
        XCTAssertEqual(d5?.hrv, 50, "HRV-Abruf fehlgeschlagen: alter Wert bleibt")
        XCTAssertEqual(d5?.steps, 8100, "Schritte erfolgreich: neuer Wert gilt")
        XCTAssertNotNil(merged.last?.sleep, "Schlaf-Abruf fehlgeschlagen: Nacht verschwindet nicht")
        XCTAssertEqual(merged.last?.hrv, 55)
    }

    // A-02: Erfolgreich gelesen und leer = in Apple Health gelöscht → auch hier weg.
    func testDeletionInHealthIsHonored() {
        let old = [day(-5, hrv: 50, steps: 8000), day(0, steps: 900)]
        let new = [day(-5, steps: 8000), day(0, steps: 1000)]
        guard case .merged(let merged) = SyncStore.merge(old: old, new: new, failed: [], today: today, keepDays: 10) else { return XCTFail() }
        XCTAssertNil(merged.first { $0.date == today.adding(days: -5) }?.hrv)
    }

    func testAllSeriesFailedChangesNothing() {
        let old = [day(0, hrv: 55)]
        XCTAssertEqual(SyncStore.merge(old: old, new: [day(0)], failed: Set(MetricSeries.allCases), today: today), .rejectedEmpty)
    }

    // A-09: Alter Stand nach Mitternacht erscheint nicht als „heute“.
    func testNormalizedEndsToday() {
        let yesterdayOnly = [day(-1, hrv: 50)]
        let n = SyncStore.normalized(yesterdayOnly, today: today, keepDays: 5)
        XCTAssertEqual(n.count, 5)
        XCTAssertEqual(n.last?.date, today)
        XCTAssertNil(n.last?.hrv)
        XCTAssertEqual(n[3].hrv, 50)
    }

    func testBedtimeAfterMidnightTargetsThisMorning() {
        let lateNight = Calendar.forma.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 0, minute: 30))!
        let plan = CoachNotifier.bedtimePlan(sleepNeed: 8 * 3600, now: lateNight, wakeMinutes: 7 * 60)
        XCTAssertEqual(Calendar.forma.component(.day, from: plan!.wake), 19, "Wecker heute früh, nicht morgen")
    }

    func testMergeProducesContinuousDays() {
        guard case .merged(let merged) = SyncStore.merge(old: [], new: [day(0, hrv: 50)], today: today, keepDays: 30) else { return XCTFail() }
        XCTAssertEqual(merged.count, 30)
        for (a, b) in zip(merged, merged.dropFirst()) {
            XCTAssertEqual(Calendar.forma.dateComponents([.day], from: a.date, to: b.date).day, 1)
        }
        XCTAssertEqual(merged.last?.date, today)
    }

    func testFirstFetchWithoutOldDataIsAccepted() {
        guard case .merged = SyncStore.merge(old: [], new: [day(0)], today: today) else { return XCTFail("leer, aber ohne alten Stand → übernehmen") }
    }

    func testSnapshotCodableRoundTrip() throws {
        let days = SampleData.days(count: 30)
        let snap = SyncStore.Snapshot(days: days, updated: today, source: "health")
        let decoded = try JSONDecoder().decode(SyncStore.Snapshot.self, from: JSONEncoder().encode(snap))
        XCTAssertEqual(decoded.days, days)
    }

    func testBedtimeIsPlausible() {
        let now = Calendar.forma.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))!
        let bed = CoachNotifier.bedtimeDate(sleepNeed: 8 * 3600, now: now)
        let c = Calendar.forma.dateComponents([.hour, .minute], from: bed!)
        XCTAssertEqual(c.hour, 22)
        XCTAssertEqual(c.minute, 45)
        XCTAssertNil(CoachNotifier.bedtimeDate(sleepNeed: .nan, now: now))
        XCTAssertNil(CoachNotifier.bedtimeDate(sleepNeed: 20 * 3600, now: now))
    }
}


@MainActor
final class LiveWorkoutAttackTests: XCTestCase {
    private func workout() -> LiveWorkout {
        LiveWorkout(title: "Test", exercises: [
            LiveExercise(name: "Bankdrücken", muscle: "Brust", restSeconds: 90,
                         sets: [LiveSet(weight: 60, reps: 8, isWarmup: false), LiveSet(weight: 60, reps: 8, isWarmup: false)])
        ])
    }

    // A-06: Doppeltipp auf „Satz abschließen“ schließt genau einen Satz.
    func testDoubleTapCompletesOnce() {
        defer { LiveWorkout.clearSaved() }
        let w = workout()
        let id = w.currentSet!.id
        XCTAssertTrue(w.completeCurrentSet(id: id))
        XCTAssertFalse(w.completeCurrentSet(id: id))
        XCTAssertEqual(w.exercises[0].sets.filter(\.done).count, 1)
    }

    // A-18: Ohne Eingabe bleibt die Reserve unbekannt.
    func testReserveDefaultsToUnknown() {
        defer { LiveWorkout.clearSaved() }
        let w = workout()
        w.completeCurrentSet(id: w.currentSet!.id)
        XCTAssertNil(w.exercises[0].sets[0].rir)
    }

    // R-02-04: Zeile antippen beendet die Pause nicht.
    func testSelectKeepsRest() {
        defer { LiveWorkout.clearSaved() }
        let w = workout()
        w.completeCurrentSet(id: w.currentSet!.id)
        XCTAssertNotNil(w.restEndsAt)
        w.select(exercise: 0, set: 1)
        XCTAssertNotNil(w.restEndsAt)
    }

    // A-19: Leeres Training gilt nicht als fertig; neuer Satz nach dem letzten wird ausgewählt.
    func testEmptyIsNotDoneAndAddSetSelects() {
        defer { LiveWorkout.clearSaved() }
        XCTAssertFalse(LiveWorkout(title: "Leer", exercises: [LiveExercise(name: "X", muscle: "Y", restSeconds: 60, sets: [])]).allDone)
        let w = LiveWorkout(title: "Eins", exercises: [LiveExercise(name: "X", muscle: "Y", restSeconds: 60, sets: [LiveSet(weight: 10, reps: 5, isWarmup: false)])])
        w.completeCurrentSet(id: w.currentSet!.id)
        w.addSet(to: 0)
        XCTAssertEqual(w.setIndex, 1)
        XCTAssertFalse(w.currentSet!.done)
    }

    // A-07: Schon gespeicherter Entwurf wird nicht erneut angeboten.
    func testAlreadySavedDraftIsNotRestored() {
        defer { LiveWorkout.clearSaved() }
        let w = workout()
        w.persist()
        XCTAssertNil(LiveWorkout.restore(alreadySaved: { $0 == w.draftID }))
    }

    // A-17: Teilweise absolvierte Einheit löst keine Steigerung aus.
    func testIncompleteSessionGivesNoIncrease() {
        let plan = Progression.plan(targetReps: 8, routineWeight: 60, lastWorkSets: [(70, 8, 3)], plannedSets: 4)
        XCTAssertFalse(plan.increased)
    }
}

/// Regressionstests zu Codex-Review 02 (Körperalter, Schlaf).
final class ReviewTwoTests: XCTestCase {
    private func person(age: Double, sex: BiologicalSex = .male) -> PersonInfo {
        PersonInfo(birthDate: Date.now.addingTimeInterval(-age * 365.2425 * 86_400), sex: sex, origin: .manual)
    }

    // A-04/R-02-10: Nur Schritte → kein Körperalter.
    func testStepsOnlyGivesNoBodyAge() {
        let days = SampleData.days().map { d -> DayMetrics in
            var x = DayMetrics(date: d.date); x.steps = d.steps; return x
        }
        let outcome = BodyAge.evaluate(days: days, person: person(age: 30), strength: .init(perWeek: 0, recentPerWeek: 0, hasRecord: false))
        guard case .insufficient = outcome else { return XCTFail("Nur Schritte darf kein Alter ergeben") }
    }

    // A-14: Alter außerhalb 18–90 → keine extrapolierte Zahl.
    func testAgeOutOfRange() {
        let outcome = BodyAge.evaluate(days: SampleData.days(), person: person(age: 12), strength: .init(perWeek: 0, recentPerWeek: 0))
        guard case .insufficient = outcome else { return XCTFail("12 Jahre ist außerhalb des Bereichs") }
    }

    // R-02-10: Ohne Aufzeichnung kein Krafttraining-Faktor, sondern ein Hinweis.
    func testNoStrengthRecordMeansNoFactor() {
        let outcome = BodyAge.evaluate(days: SampleData.days(), person: person(age: 30),
                                       strength: .init(perWeek: 0, recentPerWeek: 0, hasRecord: false))
        guard case .ready(let r) = outcome else { return XCTFail() }
        XCTAssertFalse(r.factors.contains { $0.id == "strength" })
        XCTAssertTrue(r.missing.contains { $0.contains("Krafttraining") })
    }

    // A-15: Anzeige-Differenz aus der ungerundeten Differenz.
    func testDifferenceFromUnroundedValues() {
        let r = BodyAge.Result(age: 30.8, bodyAge: 30.8, recent: nil, previous: nil, factors: [], missing: [],
                               daysWithData: 100, windowDays: 180, confidence: .medium)
        XCTAssertEqual(BodyAgeText.difference(r), "Etwa so alt wie du bist")
    }

    // A-13: Die Nacht bekommt denselben Wert, egal wie viel du heute trainierst.
    func testSleepScoreStableAfterTraining() {
        let history = Array(SampleData.days(count: 30).dropLast())
        var today = SampleData.days(count: 30).last!
        let previousNightNeed = ScoreEngine.sleepNeedForLastNight(history: history)
        let before = ScoreEngine.scores(today: today, history: history).sleep
        XCTAssertEqual(before, ScoreEngine.sleepScore(today.sleep, need: previousNightNeed))
        today.activeEnergy = 1500
        today.workouts.append(WorkoutSummary(name: "Beine", start: .now, duration: 5400, energy: 700, isStrength: true))
        let after = ScoreEngine.scores(today: today, history: history).sleep
        XCTAssertEqual(before, after)
    }

    // R-02-09: Überlappende Tief- und REM-Phasen zählen nur einmal.
    func testOverlappingDeepAndRemCountOnce() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func seg(_ s: SleepNight.Stage, _ a: Double, _ b: Double) -> SleepNight.Segment {
            .init(stage: s, start: t0.addingTimeInterval(a * 60), end: t0.addingTimeInterval(b * 60))
        }
        let overlapping = SleepNight(start: t0, end: t0.addingTimeInterval(480 * 60),
                                     segments: [seg(.core, 0, 480), seg(.deep, 60, 180), seg(.rem, 60, 180)])
        let score = ScoreEngine.sleepScore(overlapping, need: 8 * 3600)
        XCTAssertLessThanOrEqual(score, 100)
        XCTAssertGreaterThan(score, 0)
    }
}
