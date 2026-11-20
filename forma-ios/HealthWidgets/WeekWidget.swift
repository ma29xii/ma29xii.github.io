import Foundation
import SwiftUI
import WidgetKit

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WeekWidgetSnapshotStore.widgetKind, provider: WeekWidgetProvider()) { entry in
            WeekWidgetView(entry: entry)
        }
        .configurationDisplayName("Woche")
        .description("Sieben Tage Recovery, Strain und Sleep auf einen Blick.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct WeekWidgetEntry: TimelineEntry {
    let date: Date
    let days: [WeekWidgetSnapshot.Day]
    let calendar: Calendar
}

private struct WeekWidgetProvider: TimelineProvider {
    private var localCalendar: Calendar {
        // Die App speichert gregorianische Kalendertage in der jeweils lokalen Zeitzone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    func placeholder(in context: Context) -> WeekWidgetEntry {
        WeekWidgetEntry(date: .now, days: [], calendar: localCalendar)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekWidgetEntry) -> Void) {
        guard !context.isPreview else {
            completion(placeholder(in: context))
            return
        }
        completion(entry(at: .now, snapshot: WeekWidgetSnapshotStore.shared.read(), calendar: localCalendar))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekWidgetEntry>) -> Void) {
        let now = Date.now
        let calendar = localCalendar
        let snapshot = WeekWidgetSnapshotStore.shared.read()
        let current = entry(at: now, snapshot: snapshot, calendar: calendar)
        let nextCheck = now.addingTimeInterval(60 * 60)
        guard let midnight = calendar.dateInterval(of: .day, for: now)?.end else {
            completion(Timeline(entries: [current], policy: .after(nextCheck)))
            return
        }
        let tomorrow = entry(at: midnight, snapshot: snapshot, calendar: calendar)
        completion(Timeline(entries: [current, tomorrow], policy: .after(min(midnight, nextCheck))))
    }

    private func entry(at date: Date, snapshot: WeekWidgetSnapshot?, calendar: Calendar) -> WeekWidgetEntry {
        let days = snapshot?.days(endingAt: date, calendar: calendar) ?? []
        return WeekWidgetEntry(date: date, days: days, calendar: calendar)
    }
}

private struct WeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    let entry: WeekWidgetEntry
    private let labelWidth: CGFloat = 66
    private let columnSpacing: CGFloat = 6

    private var isLarge: Bool { family == .systemLarge }
    private var usesAppColors: Bool { renderingMode == .fullColor && showsBackground }
    private var ink: Color { usesAppColors ? .white : .primary }

    var body: some View {
        Group {
            if entry.days.contains(where: \.hasMeasurements) {
                week
                    .privacySensitive()
            } else {
                Text("Öffne Health")
                    .font(.headline)
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { color(0x0D0E0F) }
    }

    private var week: some View {
        VStack(spacing: isLarge ? 9 : 5) {
            if isLarge {
                HStack(spacing: 8) {
                    ForEach(Metric.allCases) { metric in
                        todayNumber(metric)
                    }
                }
                .padding(.bottom, 3)
            }

            ForEach(Metric.allCases) { metric in
                chartRow(metric)
            }

            if isLarge {
                HStack(spacing: columnSpacing) {
                    Color.clear.frame(width: labelWidth, height: 0)
                    ForEach(entry.days) { day in
                        Text(verbatim: weekday(for: day.date, abbreviated: true))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(ink.opacity(day.date == entry.days.last?.date ? 0.9 : 0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func todayNumber(_ metric: Metric) -> some View {
        let score = entry.days.last.flatMap { metric.score(in: $0) }
        return VStack(spacing: 2) {
            Text(verbatim: score.map { $0.formatted() } ?? "–")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint(for: metric, score: score))
            Text(metric.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(ink.opacity(0.72))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.rawValue) heute")
        .accessibilityValue(spokenScore(score))
    }

    private func chartRow(_ metric: Metric) -> some View {
        HStack(spacing: columnSpacing) {
            Text(metric.rawValue)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: labelWidth, alignment: .leading)
                .accessibilityHidden(true)

            ForEach(entry.days) { day in
                let score = metric.score(in: day)
                GeometryReader { geometry in
                    Capsule()
                        .fill(tint(for: metric, score: score))
                        .frame(width: min(18, geometry.size.width),
                               height: max(2, geometry.size.height * CGFloat(score ?? 0) / 100))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metric.rawValue), \(weekday(for: day.date, abbreviated: false))")
                .accessibilityValue(spokenScore(score))
            }
        }
    }

    private func weekday(for date: Date, abbreviated: Bool) -> String {
        var calendar = entry.calendar
        calendar.locale = Locale(identifier: "de_DE")
        let names = abbreviated ? calendar.shortWeekdaySymbols : calendar.weekdaySymbols
        return names[calendar.component(.weekday, from: date) - 1].trimmingCharacters(in: .punctuationCharacters)
    }

    private func spokenScore(_ score: Int?) -> String {
        score.map { "\($0.formatted()) von 100" } ?? "Keine Messung"
    }

    private func tint(for metric: Metric, score: Int?) -> Color {
        guard let score else { return ink.opacity(0.28) }
        guard usesAppColors else { return ink }
        switch metric {
        case .recovery:
            switch WeekWidgetSnapshot.recoveryColor(for: score) {
            case .some(.green): return color(0x16EC06)
            case .some(.yellow): return color(0xFFDE00)
            case .some(.red): return color(0xFF0026)
            case .none: return ink
            }
        case .strain: return color(0x0093E7)
        case .sleep: return color(0x8E8CFF)
        }
    }

    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    private enum Metric: String, CaseIterable, Identifiable {
        case recovery = "Recovery"
        case strain = "Strain"
        case sleep = "Sleep"

        var id: Self { self }

        func score(in day: WeekWidgetSnapshot.Day) -> Int? {
            switch self {
            case .recovery: day.recovery
            case .strain: day.strain
            case .sleep: day.sleep
            }
        }
    }
}
