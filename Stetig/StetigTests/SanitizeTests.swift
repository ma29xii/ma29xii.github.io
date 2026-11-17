import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Stetig

/// Kaputte oder manipulierte Werte von außen dürfen die App weder abstürzen
/// lassen noch zum Hängen bringen.
@MainActor
struct SanitizeTests {
    @Test func formatNeverCrashes() {
        #expect(Format.number(1e300).isEmpty == false)
        #expect(Format.number(-1e300).isEmpty == false)
        #expect(Format.number(.nan) == "–")
        #expect(Format.number(.infinity) == "–")
        #expect(Format.number(3) == "3")
        #expect(Format.number(1.5) == "1,5")
    }

    @Test func dayKeys() {
        #expect(Sanitize.dayKey(20_260_115) == 20_260_115)
        #expect(Sanitize.dayKey(10_101) == nil)            // Jahr 1
        #expect(Sanitize.dayKey(20_260_231) == nil)        // 31. Februar
        #expect(Sanitize.dayKey(20_261_301) == nil)        // Monat 13
        #expect(Sanitize.dayKey(99_991_231) == nil)
        #expect(Sanitize.optionalDayKey(0) == 0)
        #expect(Sanitize.optionalDayKey(-5) == 0)
        #expect(Sanitize.minutes(2000) == 1439)
        #expect(Sanitize.minutes(-3) == 0)
        #expect(Sanitize.amount(.infinity) == 0)
        #expect(Sanitize.amount(-2) == 0)
        #expect(Sanitize.amount(1e300) == 1_000_000)
    }

    @Test func hostileBackupIsTamed() throws {
        let today = Day.today
        let json = """
        {"format":"stetig-backup","version":1,"exportedAt":"2026-01-01T00:00:00Z","categories":[],
         "habits":[{"uuid":"\(UUID().uuidString)","name":"Kaputt","details":"","symbol":"book.fill","colorID":"mono",
           "createdAt":"2026-01-01T00:00:00Z","sortOrder":0,"isArchived":false,"kind":"build","frequency":"daily","weekdayMask":-1,
           "timesPerPeriod":999999,"dailyTarget":1e300,"unit":"","step":-4,"reminderEnabled":false,
           "reminderMinutes":99999,"startDay":10101,"endDay":0,"pausedSinceDay":10101,
           "entries":[{"day":10101,"amount":1e300,"skipped":false,"note":""},
                      {"day":\(today.key),"amount":1e300,"skipped":false,"note":"ok"}]}]}
        """
        let file = try Backup.decode(Data(json.utf8))
        let context = ModelContext(Store.make(inMemory: true))
        let summary = Backup.restore(file, into: context)
        #expect(summary.habits == 1)

        let habit = try #require(try context.fetch(FetchDescriptor<Habit>()).first)
        #expect(habit.entries.count == 1)                  // Jahr 1 verworfen
        #expect(habit.entries.first?.amount == 1_000_000)
        #expect(habit.weekdayMask == 0x7F)
        #expect(habit.timesPerPeriod == 31)
        #expect(habit.dailyTarget == 100_000)
        #expect(habit.step == 1)
        #expect(habit.reminderMinutes == 1439)
        #expect(habit.startDay == 0)
        #expect(habit.pausedSinceDay == 0)

        // Auswertung bleibt schnell und stürzt nicht ab.
        let snapshot = habit.snapshot(today: today)
        #expect(snapshot.rule.firstDay >= Sanitize.earliestDay)
        _ = snapshot.currentStreak
        _ = Format.amount(snapshot.amount(today), unit: habit.unit)
    }

    @Test func oldPauseBackfillIsBounded() {
        let context = ModelContext(Store.make(inMemory: true))
        let habit = Habit(name: "Pause")
        context.insert(habit)
        habit.pausedSinceDay = 20_000_101
        let today = Day.today
        habit.setPaused(false, today: today, in: context)
        #expect(habit.entries.count <= 366)
        #expect(!habit.isPaused)
    }

    @Test func monoAdaptsToAppearance() {
        let mono = Palette.entry("mono")
        #expect(mono.isAdaptive)
        #expect(Palette.companion(of: mono).id == "graphite")
        // So löst auch das Raster (Canvas) die Farbe auf.
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        var light = EnvironmentValues()
        light.colorScheme = .light
        #expect(mono.color.resolve(in: dark).red > 0.9)
        #expect(mono.color.resolve(in: light).red < 0.2)
        #expect(mono.endColor.resolve(in: dark).green > 0.8)
    }

    @Test func voiceShortcutActivityCarriesHabit() {
        let activity = VoiceShortcut.activity(habitID: "ABC", name: "Lesen")
        #expect(VoiceShortcut.habitID(from: activity) == "ABC")
        #expect(activity.suggestedInvocationPhrase == "Heute Lesen gemacht")
        #expect(activity.activityType.hasSuffix(".complete-habit"))
        #expect(activity.isEligibleForPrediction)
    }
}
