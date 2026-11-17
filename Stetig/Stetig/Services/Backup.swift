import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupEntry: Codable, Equatable {
    var day: Int
    var amount: Double
    var skipped: Bool
    var note: String
}

struct BackupCategory: Codable, Equatable {
    var uuid: UUID
    var name: String
    var symbol: String
    var sortOrder: Int
}

struct BackupHabit: Codable, Equatable {
    var uuid: UUID
    var name: String
    var details: String
    var symbol: String
    var colorID: String
    var createdAt: Date
    var sortOrder: Int
    var isArchived: Bool
    var kind: String
    var frequency: String
    var weekdayMask: Int
    var timesPerPeriod: Int
    var dailyTarget: Double
    var unit: String
    var step: Double
    var reminderEnabled: Bool
    var reminderMinutes: Int
    var startDay: Int
    var endDay: Int
    var pausedSinceDay: Int
    var categoryUUID: UUID?
    var entries: [BackupEntry]
}

struct BackupFile: Codable, Equatable {
    var format = "stetig-backup"
    var version = 1
    var exportedAt = Date()
    var categories: [BackupCategory] = []
    var habits: [BackupHabit] = []
}

enum BackupError: LocalizedError {
    case wrongFormat

    var errorDescription: String? {
        "Die Datei ist kein Stetig-Backup."
    }
}

enum Backup {
    // MARK: Export

    static func snapshot(of context: ModelContext) -> BackupFile {
        let categories = (try? context.fetch(FetchDescriptor<HabitCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let habits = (try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        var file = BackupFile()
        file.categories = categories.map {
            BackupCategory(uuid: $0.uuid, name: $0.name, symbol: $0.symbol, sortOrder: $0.sortOrder)
        }
        file.habits = habits.map { habit in
            BackupHabit(
                uuid: habit.uuid,
                name: habit.name,
                details: habit.details,
                symbol: habit.symbol,
                colorID: habit.colorID,
                createdAt: habit.createdAt,
                sortOrder: habit.sortOrder,
                isArchived: habit.isArchived,
                kind: habit.kindRaw,
                frequency: habit.frequencyRaw,
                weekdayMask: habit.weekdayMask,
                timesPerPeriod: habit.timesPerPeriod,
                dailyTarget: habit.dailyTarget,
                unit: habit.unit,
                step: habit.step,
                reminderEnabled: habit.reminderEnabled,
                reminderMinutes: habit.reminderMinutes,
                startDay: habit.startDay,
                endDay: habit.endDay,
                pausedSinceDay: habit.pausedSinceDay,
                categoryUUID: habit.category?.uuid,
                entries: habit.entries
                    .filter { $0.amount > 0 || $0.skipped || !$0.note.isEmpty }
                    .sorted { $0.day < $1.day }
                    .map { BackupEntry(day: $0.day, amount: $0.amount, skipped: $0.skipped, note: $0.note) }
            )
        }
        return file
    }

    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)
        guard file.format == "stetig-backup" else { throw BackupError.wrongFormat }
        return file
    }

    static func exportJSON(from context: ModelContext) throws -> Data {
        try encode(snapshot(of: context))
    }

    /// CSV mit Semikolon – öffnet sich in deutschem Excel/Numbers direkt richtig.
    static func exportCSV(from context: ModelContext) -> Data {
        func quote(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = ["Gewohnheit;Datum;Menge;Einheit;Übersprungen;Notiz"]
        for habit in snapshot(of: context).habits {
            for entry in habit.entries {
                let day = Day(key: entry.day)
                let c = day.components
                let date = String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
                lines.append([
                    quote(habit.name),
                    date,
                    Format.number(entry.amount),
                    quote(habit.unit),
                    entry.skipped ? "ja" : "nein",
                    quote(entry.note),
                ].joined(separator: ";"))
            }
        }
        // BOM, damit Excel UTF-8 erkennt.
        return Data("\u{FEFF}".utf8) + Data(lines.joined(separator: "\r\n").utf8)
    }

    // MARK: Import

    /// Führt ein Backup mit den vorhandenen Daten zusammen: Gleiche Gewohnheiten
    /// (gleiche ID) werden aktualisiert, Einträge tageweise übernommen.
    @discardableResult
    static func restore(_ file: BackupFile, into context: ModelContext) -> (habits: Int, entries: Int) {
        var categories: [UUID: HabitCategory] = [:]
        for category in (try? context.fetch(FetchDescriptor<HabitCategory>())) ?? [] {
            categories[category.uuid] = category
        }
        for item in file.categories {
            let category: HabitCategory
            if let existing = categories[item.uuid] {
                category = existing
            } else {
                category = HabitCategory(name: item.name)
                category.uuid = item.uuid
                context.insert(category)
                categories[item.uuid] = category
            }
            category.name = item.name
            category.symbol = item.symbol
            category.sortOrder = item.sortOrder
        }

        var habits: [UUID: Habit] = [:]
        for habit in (try? context.fetch(FetchDescriptor<Habit>())) ?? [] {
            habits[habit.uuid] = habit
        }

        var entryCount = 0
        for item in file.habits {
            let habit: Habit
            if let existing = habits[item.uuid] {
                habit = existing
            } else {
                habit = Habit(name: item.name)
                habit.uuid = item.uuid
                context.insert(habit)
                habits[item.uuid] = habit
            }
            habit.name = item.name
            habit.details = item.details
            habit.symbol = item.symbol
            habit.colorID = item.colorID
            habit.createdAt = item.createdAt
            habit.sortOrder = item.sortOrder
            habit.isArchived = item.isArchived
            habit.kindRaw = HabitKind(rawValue: item.kind)?.rawValue ?? HabitKind.build.rawValue
            habit.frequencyRaw = HabitFrequency(rawValue: item.frequency)?.rawValue ?? HabitFrequency.daily.rawValue
            habit.weekdayMask = item.weekdayMask & 0x7F
            habit.timesPerPeriod = min(max(item.timesPerPeriod, 0), 31)
            habit.dailyTarget = Sanitize.amount(item.dailyTarget, max: 100_000)
            habit.unit = item.unit
            habit.step = item.step.isFinite && item.step >= 0 ? min(item.step, 10_000) : 1
            habit.reminderEnabled = item.reminderEnabled
            habit.reminderMinutes = Sanitize.minutes(item.reminderMinutes)
            habit.startDay = Sanitize.optionalDayKey(item.startDay)
            habit.endDay = Sanitize.optionalDayKey(item.endDay)
            habit.pausedSinceDay = Sanitize.optionalDayKey(item.pausedSinceDay)
            habit.category = item.categoryUUID.flatMap { categories[$0] }

            var existingEntries: [Int: HabitEntry] = [:]
            for entry in habit.entries {
                existingEntries[entry.day] = entry
            }
            for item in item.entries {
                // Ungültige Tage (z. B. Jahr 1 oder 31. Februar) überspringen.
                guard let key = Sanitize.dayKey(item.day) else { continue }
                let entry: HabitEntry
                if let existing = existingEntries[key] {
                    entry = existing
                } else {
                    entry = HabitEntry(day: key)
                    habit.entries.append(entry)
                    existingEntries[key] = entry
                }
                entry.amount = Sanitize.amount(item.amount)
                entry.skipped = item.skipped
                entry.note = item.note
                entry.updatedAt = Date()
                entryCount += 1
            }
        }
        Store.commit(context)
        return (file.habits.count, entryCount)
    }

    static func deleteEverything(in context: ModelContext) {
        for habit in (try? context.fetch(FetchDescriptor<Habit>())) ?? [] {
            Reminders.cancel(uuid: habit.uuid)
            context.delete(habit)
        }
        for category in (try? context.fetch(FetchDescriptor<HabitCategory>())) ?? [] {
            context.delete(category)
        }
        Store.commit(context)
    }
}

/// Rohdaten für den Datei-Export (JSON oder CSV).
struct DataDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
