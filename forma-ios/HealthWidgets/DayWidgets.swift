import SwiftUI
import WidgetKit

// Fünf Widgets aus einem Tagesstand (`DayWidgetSnapshot`): Health Age, Schlaf, Schritte, Energie, Körpersignale.

struct HealthAgeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ma29xii.forma.healthage", provider: DayProvider()) {
            DayWidgetView(kind: .healthAge, snapshot: $0.snapshot)
        }
        .configurationDisplayName("Health Age")
        .description("Wie alt dein Körper nach deinen Messwerten wirkt.")
        .supportedFamilies([.systemSmall])
    }
}

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ma29xii.forma.sleep", provider: DayProvider()) {
            DayWidgetView(kind: .sleep, snapshot: $0.snapshot)
        }
        .configurationDisplayName("Schlaf")
        .description("Letzte Nacht und deine Bettzeit für heute.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ma29xii.forma.steps", provider: DayProvider()) {
            DayWidgetView(kind: .steps, snapshot: $0.snapshot)
        }
        .configurationDisplayName("Schritte")
        .description("Schritte heute und dein Tagesziel.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct EnergyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ma29xii.forma.energy", provider: DayProvider()) {
            DayWidgetView(kind: .energy, snapshot: $0.snapshot)
        }
        .configurationDisplayName("Energie")
        .description("Aktive Energie heute und dein Strain.")
        .supportedFamilies([.systemSmall])
    }
}

struct SignalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ma29xii.forma.signals", provider: DayProvider()) {
            DayWidgetView(kind: .signals, snapshot: $0.snapshot)
        }
        .configurationDisplayName("Körpersignale")
        .description("Frühwarnung aus deinen Nachtwerten.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: DayWidgetSnapshot?
}

private struct DayProvider: TimelineProvider {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    func placeholder(in context: Context) -> DayEntry {
        let now = Date.now
        return DayEntry(date: now, snapshot: DayWidgetSnapshot(
            updatedAt: now, day: calendar.startOfDay(for: now), healthAge: 31.4, chronologicalAge: 34.0,
            steps: 6_240, stepGoal: 10_000, sleepMinutes: 442, sleepNeedMinutes: 480, sleepScore: 86,
            bedtime: now.addingTimeInterval(4 * 3_600), activeEnergy: 412, strain: 54, signalLevel: 0, signalTitles: []))
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date.now
        let current = entry(at: now)
        let nextCheck = now.addingTimeInterval(30 * 60)
        guard let midnight = calendar.dateInterval(of: .day, for: now)?.end else {
            completion(Timeline(entries: [current], policy: .after(nextCheck)))
            return
        }
        completion(Timeline(entries: [current, entry(at: midnight)], policy: .after(min(midnight, nextCheck))))
    }

    private func entry(at date: Date) -> DayEntry {
        let snapshot = DayWidgetSnapshotStore.shared.read()
        return DayEntry(date: date, snapshot: snapshot.flatMap { $0.isCurrent(at: date, calendar: calendar) ? $0 : nil })
    }
}

private struct DayWidgetView: View {
    enum Kind { case healthAge, sleep, steps, energy, signals }

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let kind: Kind
    let snapshot: DayWidgetSnapshot?

    private var isAccessory: Bool { family == .accessoryCircular || family == .accessoryRectangular }
    private var style: WidgetStyle { WidgetStyle(renderingMode: renderingMode, showsBackground: !isAccessory && showsBackground) }

    var body: some View {
        content
            .foregroundStyle(style.ink)
            .privacySensitive()
            .containerBackground(for: .widget) { if !isAccessory { style.background() } }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .healthAge: healthAge
        case .sleep: family == .accessoryRectangular ? AnyView(sleepLock) : AnyView(sleep)
        case .steps: family == .accessoryCircular ? AnyView(stepsLock) : AnyView(steps)
        case .energy: energy
        case .signals: family == .accessoryRectangular ? AnyView(signalsLock) : AnyView(signals)
        }
    }

    // MARK: Bausteine

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(style.muted)
            .lineLimit(1)
    }

    private func big(_ text: String, size: CGFloat = 44) -> some View {
        Text(verbatim: text)
            .font(.widgetNumber(size))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func clock(_ minutes: Int) -> String { "\(minutes / 60):" + String(format: "%02d", minutes % 60) }

    private func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }

    // MARK: Health Age

    private var healthAge: some View {
        let age = snapshot?.healthAge
        let diff = snapshot?.healthAgeDifference
        let tint: Color = {
            guard style.usesAppColors, let diff else { return style.muted }
            return diff <= 0 ? Color(sharedHex: 0x3DDC97) : Color(sharedHex: 0xFF8A5B)
        }()
        return VStack(alignment: .leading, spacing: 4) {
            caption("Health Age")
            Spacer(minLength: 0)
            big(age.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "–", size: 56)
            Text(verbatim: diff.map(differenceText) ?? "Noch zu wenig Daten")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health Age")
        .accessibilityValue(age.map { "\($0.formatted(.number.precision(.fractionLength(0)))) Jahre. \(diff.map(differenceText) ?? "")" }
                            ?? "Noch zu wenig Daten")
    }

    private func differenceText(_ years: Double) -> String {
        let value = abs(years).formatted(.number.precision(.fractionLength(1)))
        if abs(years) < 0.05 { return "so alt wie du" }
        return years < 0 ? "\(value) Jahre jünger" : "\(value) Jahre älter"
    }

    // MARK: Schlaf

    private var sleep: some View {
        let minutes = snapshot?.sleepMinutes
        let ring = ZStack {
            WidgetGauge(fraction: snapshot?.sleepFraction ?? 0, tint: style.sleep, track: style.track, line: 6)
            VStack(spacing: 0) {
                big(minutes.map(clock) ?? "–", size: family == .systemMedium ? 30 : 28)
                Text("Std").font(.system(size: 10, weight: .semibold)).foregroundStyle(style.muted)
            }
            .padding(12)
        }
        return Group {
            if family == .systemMedium {
                HStack(spacing: 20) {
                    ring.frame(maxWidth: 110)
                    VStack(alignment: .leading, spacing: 10) {
                        caption("Schlaf")
                        statLine("Letzte Nacht", minutes.map(clock).map { "\($0) Std" } ?? "–")
                        statLine("Score", snapshot?.sleepScore.map { $0.formatted() } ?? "–")
                        statLine("Bettzeit heute", snapshot?.bedtime.map(time) ?? "–")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    caption("Schlaf")
                    ring
                    Label(snapshot?.bedtime.map(time) ?? "–", systemImage: "bed.double.fill")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(style.muted)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schlaf")
        .accessibilityValue(sleepSpoken)
    }

    private func statLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(style.muted)
            Spacer(minLength: 6)
            Text(verbatim: value).font(.system(.callout, design: .rounded, weight: .semibold)).monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var sleepSpoken: String {
        guard let minutes = snapshot?.sleepMinutes else { return "Keine Messung" }
        var text = "Letzte Nacht \(minutes / 60) Stunden \(minutes % 60) Minuten"
        if let bed = snapshot?.bedtime { text += ", Bettzeit \(time(bed))" }
        return text
    }

    private var sleepLock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Schlaf", systemImage: "moon.fill").font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                Text(verbatim: snapshot?.sleepMinutes.map(clock) ?? "–")
                    .font(.system(.headline, design: .rounded, weight: .semibold)).monospacedDigit()
            }
            WidgetBar(fraction: snapshot?.sleepFraction ?? 0, tint: style.ink, track: style.track, height: 5)
            Text(verbatim: snapshot?.bedtime.map { "Bettzeit \(time($0))" } ?? "Keine Bettzeit")
                .font(.caption2).foregroundStyle(style.muted)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schlaf")
        .accessibilityValue(sleepSpoken)
    }

    // MARK: Schritte

    private var steps: some View {
        VStack(spacing: 8) {
            caption("Schritte")
            ZStack {
                WidgetGauge(fraction: snapshot?.stepFraction ?? 0, tint: style.accent, track: style.track, line: 6)
                big(snapshot?.steps.map { $0.formatted() } ?? "–", size: 26).padding(14)
            }
            Text(verbatim: snapshot?.stepGoal.map { "Ziel \($0.formatted())" } ?? "Kein Ziel")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(style.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schritte")
        .accessibilityValue(stepsSpoken)
    }

    private var stepsLock: some View {
        ZStack {
            AccessoryWidgetBackground()
            WidgetGauge(fraction: snapshot?.stepFraction ?? 0, tint: style.ink, track: style.track, line: 5).padding(3)
            VStack(spacing: 0) {
                Image(systemName: "figure.walk").font(.system(size: 10))
                Text(verbatim: snapshot?.steps.map(compactSteps) ?? "–")
                    .font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
            .lineLimit(1)
            .padding(8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schritte")
        .accessibilityValue(stepsSpoken)
    }

    private func compactSteps(_ steps: Int) -> String {
        steps >= 10_000 ? "\((Double(steps) / 1_000).formatted(.number.precision(.fractionLength(0))))k"
            : steps >= 1_000 ? "\((Double(steps) / 1_000).formatted(.number.precision(.fractionLength(1))))k" : "\(steps)"
    }

    private var stepsSpoken: String {
        guard let steps = snapshot?.steps else { return "Keine Messung" }
        return snapshot?.stepGoal.map { "\(steps.formatted()) von \($0.formatted())" } ?? steps.formatted()
    }

    // MARK: Energie

    private var energy: some View {
        VStack(alignment: .leading, spacing: 4) {
            caption("Energie")
            Spacer(minLength: 0)
            big(snapshot?.activeEnergy.map { $0.formatted() } ?? "–", size: 48)
            Text("kcal aktiv").font(.footnote.weight(.semibold)).foregroundStyle(style.muted)
            Spacer(minLength: 6)
            WidgetBar(fraction: Double(snapshot?.strain ?? 0) / 100, tint: style.strain, track: style.track)
            Text(verbatim: snapshot?.strain.map { "Strain \($0)" } ?? "Strain –")
                .font(.caption2.weight(.semibold)).foregroundStyle(style.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energie")
        .accessibilityValue(snapshot?.activeEnergy.map {
            "\($0.formatted()) Kilokalorien aktiv" + (snapshot?.strain.map { ", Strain \($0)" } ?? "")
        } ?? "Keine Messung")
    }

    // MARK: Körpersignale

    private var level: Int? { snapshot?.signalLevel }

    private var levelTitle: String {
        switch level {
        case 0: "Unauffällig"
        case 1: "Beobachten"
        case 2: "Dein Körper kämpft"
        default: "Keine Nachtdaten"
        }
    }

    private var levelTint: Color {
        guard style.usesAppColors else { return style.ink }
        switch level {
        case 0: return Color(sharedHex: 0x16EC06)
        case 1: return Color(sharedHex: 0xFFDE00)
        case 2: return Color(sharedHex: 0xFF0026)
        default: return style.muted
        }
    }

    private var flaggedText: String {
        let titles = snapshot?.signalTitles ?? []
        return titles.isEmpty ? "Alle Werte im Rahmen" : titles.joined(separator: ", ")
    }

    private var signals: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Körpersignale")
            Spacer(minLength: 0)
            Image(systemName: level == 2 ? "waveform.path.ecg.rectangle.fill" : "waveform.path.ecg")
                .font(.system(size: 28, weight: .semibold)).foregroundStyle(levelTint)
            Text(levelTitle).font(.system(.title3, design: .rounded, weight: .semibold))
                .lineLimit(2).minimumScaleFactor(0.7)
            if level != nil {
                Text(flaggedText).font(.caption2.weight(.medium)).foregroundStyle(style.muted).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Körpersignale")
        .accessibilityValue(level == nil ? levelTitle : "\(levelTitle). \(flaggedText)")
    }

    private var signalsLock: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg").font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(levelTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                if level != nil { Text(flaggedText).font(.caption2).foregroundStyle(style.muted).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Körpersignale")
        .accessibilityValue(level == nil ? levelTitle : "\(levelTitle). \(flaggedText)")
    }
}
