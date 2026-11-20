import SwiftUI
import Charts

struct DaySignals {
    let day: DayMetrics
    let estimates: [HourlyEstimate]
    let stressSlots: [StressSlot]
    private let dailyStress: Double?

    init(day: DayMetrics, hours: [HourlyMetrics], history: [DayMetrics]) {
        self.day = day
        dailyStress = HourlyEstimate.dailyStress(today: day, history: history)
        let hours = hours.filter { $0.start.startOfDay == day.date.startOfDay }.sorted { $0.start < $1.start }
        let timeline = HourlyEstimate.timeline(hours: hours, today: day, history: history)
        estimates = timeline
        stressSlots = zip(hours, timeline).map { hour, estimate in
            StressSlot(start: hour.start, end: hour.end, value: estimate.stress)
        }
    }

    var stress: Double? { estimates.compactMap(\.stress).last ?? dailyStress }
    var energy: Int? { estimates.compactMap(\.energy).last }

    static func energyChanges(_ timeline: [HourlyEstimate]) -> (gained: Int, spent: Int)? {
        var gained = 0
        var spent = 0
        var hasComparison = false
        for (previous, current) in zip(timeline, timeline.dropFirst()) {
            let interval = current.at.timeIntervalSince(previous.at)
            guard interval > 0, interval <= 90 * 60,
                  let earlier = previous.energy, let later = current.energy else { continue }
            hasComparison = true
            let delta = later - earlier
            gained += max(0, delta)
            spent += max(0, -delta)
        }
        return hasComparison ? (gained, spent) : nil
    }

    var activities: [WorkoutSummary] {
        day.workouts.filter { $0.duration > 0 }.sorted { $0.start > $1.start }
    }

    var sleepInterval: DateInterval? {
        guard let sleep = day.sleep, sleep.asleep > 0, sleep.end > sleep.start else { return nil }
        return DateInterval(start: sleep.start, end: sleep.end)
    }
}

struct StressMonitorCard: View {
    let signals: DaySignals
    let history: [DayMetrics]

    var body: some View {
        NavigationLink {
            StressDetail(signals: signals, history: history)
        } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Label("Stress Monitor", systemImage: "waveform.path")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("today.stress.title")
                    if let value = signals.stress {
                        let zone = StressZone(value: value)
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            Text(Format.number(value, decimals: 1))
                                .font(.formaDisplay.monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                            Text("/ 3")
                                .font(.formaCaption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer(minLength: Space.s2)
                            Label(zone.title, systemImage: "circle.fill")
                                .font(.formaCaptionStrong)
                                .foregroundStyle(zone.tint)
                        }
                        stressTimeline
                    } else {
                        Text("Keine Messung").font(.formaBody).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stress")
        .accessibilityValue(Self.spokenValue(signals.stress))
        .accessibilityIdentifier("today.stress.open")
    }

    private var stressTimeline: some View {
        let hours = Dictionary(signals.stressSlots.compactMap { slot -> (Int, Double)? in
            guard let value = slot.value, value.isFinite else { return nil }
            return (Calendar.forma.component(.hour, from: slot.start), value)
        }, uniquingKeysWith: { _, last in last })

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let value = hours[hour]
                    Capsule()
                        .fill(value.map { StressZone(value: $0).tint } ?? Theme.track)
                        .frame(maxWidth: .infinity)
                        .frame(height: value.map { 5 + CGFloat(min(3, max(0, $0))) * 11 } ?? 3)
                }
            }
            .frame(height: 39, alignment: .bottom)
            HStack {
                Text("00:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("24:00")
            }
            .font(.formaMicro.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityHidden(true)
    }

    nonisolated static func spokenValue(_ value: Double?) -> String {
        guard let value else { return "Keine Messung" }
        return "\(Format.number(value, decimals: 1)) von 3, \(StressZone(value: value).title)"
    }
}

struct StressDetail: View {
    let signals: DaySignals
    let history: [DayMetrics]

    var body: some View {
        InsightPage(title: "Stress Monitor") {
            if let value = signals.stress {
                DashboardCard {
                    VStack(spacing: Space.s2) {
                        StressGauge(value: value, diameter: 192, lineWidth: 8, showsNumber: true)
                        Text(StressZone(value: value).title)
                            .font(.formaSection)
                            .foregroundStyle(StressZone(value: value).tint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stress")
                .accessibilityValue(StressMonitorCard.spokenValue(value))
            }
            BreathingLink()

            DaySignalChart(signals: signals, kind: .stress)
            if signals.stress != nil {
                DashboardHeading(title: "Zeit in Zonen")
                StressZoneTiles(slots: signals.stressSlots)
                stressAverages
            }
            StressTrendCard(end: InsightHistory.lastCompletedDay(for: signals.day.date), history: history)
        }
    }

    private var stressAverages: some View {
        let measured = signals.stressSlots.filter { $0.value != nil }
        let workouts = signals.activities
        let asleep = measured.filter { slot in
            signals.sleepInterval.map { $0.start < slot.end && slot.start < $0.end } ?? false
        }
        let outside = measured.filter { slot in
            !workouts.contains { $0.start < slot.end && slot.start < $0.end }
        }
        return VStack(spacing: Space.s2) {
            averageTile("Stresswert", slots: measured)
            if !workouts.isEmpty { averageTile("Außerhalb von Trainings", slots: outside) }
            if signals.sleepInterval != nil { averageTile("Während der Schlafzeit", slots: asleep) }
        }
    }

    private func averageTile(_ title: String, slots: [StressSlot]) -> some View {
        let measurements = slots.compactMap { slot in slot.value.map { ($0, slot.end.timeIntervalSince(slot.start)) } }
        let duration = measurements.reduce(0) { $0 + $1.1 }
        let average = duration > 0 ? measurements.reduce(0) { $0 + $1.0 * $1.1 } / duration : nil
        return DashboardCard {
            MetricRow(title: title, value: average.map { Format.number($0, decimals: 1) } ?? "–")
        }
    }
}

struct EnergyTile: View {
    let signals: DaySignals

    nonisolated static func tint(_ energy: Int) -> Color {
        energy >= 67 ? Theme.recoveryHigh : energy >= 34 ? Theme.recoveryMid : Theme.older
    }

    var body: some View {
        NavigationLink {
            EnergyDetail(signals: signals)
        } label: {
            EnergyMeter(energy: signals.energy, title: "Energie")
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energie")
        .accessibilityValue(signals.energy.map { "\($0) Prozent" } ?? "Keine Messung")
        .accessibilityHint("Öffnet den Tagesverlauf")
        .accessibilityIdentifier("today.energy")
    }
}

private struct EnergyMeter: View {
    let energy: Int?
    let title: String

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                DashboardHeading(title: title)
                if let energy {
                    Text("\(energy) %")
                        .font(.formaDisplay)
                        .foregroundStyle(Theme.textPrimary)
                        .formaNumberTransition(Double(energy))
                    MetricScale(value: Double(energy), tint: EnergyTile.tint(energy))
                        .frame(height: 16)
                        .accessibilityHidden(true)
                } else {
                    Text("Keine Messung").font(.formaBody).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}

private struct EnergyDetail: View {
    let signals: DaySignals
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        InsightPage(title: "Energie") {
            EnergyMeter(energy: signals.energy, title: "Energiereserve")
            if let changes = DaySignals.energyChanges(signals.estimates) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Space.s2))
                    : AnyLayout(HStackLayout(spacing: Space.s2))
                layout {
                    changeTile("Aufgeladen", value: "+\(changes.gained)", tint: Theme.younger)
                    changeTile("Verbraucht", value: "−\(changes.spent)", tint: Theme.older)
                }
            }
            DaySignalChart(signals: signals, kind: .energy)
            if signals.stress != nil {
                DaySignalChart(signals: signals, kind: .stress)
            }
            if signals.sleepInterval != nil || !signals.activities.isEmpty {
                DashboardHeading(title: "Schlaf und Aktivitäten")
                activityCards
            }
        }
        .accessibilityIdentifier("energy.detail")
    }

    private func changeTile(_ title: String, value: String, tint: Color) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(value + " Pkt.").font(.formaBigNumber).foregroundStyle(tint)
                Text(title).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value + " Prozentpunkte")
    }

    private var activityCards: some View {
        VStack(spacing: Space.s2) {
            if let sleep = signals.day.sleep, signals.sleepInterval != nil {
                activity("Schlaf", icon: "moon.fill", start: sleep.start, duration: sleep.asleep, energy: nil, tint: Theme.sleep)
            }
            ForEach(signals.activities) { workout in
                activity(workout.name, icon: workout.isStrength ? "dumbbell" : "figure.walk", start: workout.start,
                         duration: workout.duration, energy: workout.energy, tint: Theme.strain)
            }
        }
    }

    private func activity(_ name: String, icon: String, start: Date, duration: TimeInterval, energy: Double?,
                          tint: Color) -> some View {
        DashboardCard {
            Label {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(name).font(.formaRowTitle)
                    Text([Format.clock(start), Format.duration(duration), energy.map { "\(Format.number($0)) kcal" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            .padding(Space.s3)
        }
    }
}

private struct StressZoneTiles: View {
    let slots: [StressSlot]

    var body: some View {
        let durations = StressZone.allCases.map { $0.duration(in: slots) }
        let total = durations.reduce(0, +)
        if total > 0 {
            ForEach(StressZone.allCases.reversed()) { zone in
                let duration = durations[zone.rawValue]
                let share = 100 * duration / total
                DashboardCard {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        ViewThatFits(in: .horizontal) {
                            HStack { name(zone); Spacer(minLength: Space.s2); amount(duration, share: share) }
                                .fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: Space.s1) { name(zone); amount(duration, share: share) }
                        }
                        MetricScale(value: share, tint: zone.tint)
                            .frame(height: 12)
                            .accessibilityHidden(true)
                    }
                    .padding(Space.s3)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(zone.title)
                .accessibilityValue("\(Format.number(share)) Prozent, \(Format.duration(duration))")
            }
        }
    }

    private func name(_ zone: StressZone) -> some View {
        Text(zone.title).font(.formaRowTitle).foregroundStyle(zone.tint)
    }

    private func amount(_ duration: TimeInterval, share: Double) -> some View {
        Text("\(Format.number(share)) % · \(Format.duration(duration))")
            .font(.formaValue)
            .foregroundStyle(Theme.textPrimary)
    }
}

private struct DaySignalChart: View {
    enum Kind {
        case energy, stress
        var title: String { self == .energy ? "Energieverlauf" : "Stressverlauf" }
        var tint: Color { self == .energy ? Theme.warning : Theme.younger }
        var maximum: Double { self == .energy ? 100 : 3 }

        func value(_ estimate: HourlyEstimate) -> Double? {
            self == .energy ? estimate.energy.map(Double.init) : estimate.stress
        }
    }

    let signals: DaySignals
    let kind: Kind

    var body: some View {
        let points = segments
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: kind.title)
            DashboardCard {
                if points.isEmpty {
                    DashboardEmpty()
                } else {
                    chart(points)
                        .padding(Space.s4)
                }
            }
        }
    }

    private func chart(_ points: [Point]) -> some View {
        let start = signals.day.date.startOfDay
        let end = start.adding(days: 1)
        let sleep = signals.sleepInterval.flatMap { clipped($0.start, $0.end, start: start, end: end) }
        return Chart {
            if let sleep {
                RectangleMark(xStart: .value("Schlafbeginn", sleep.start), xEnd: .value("Schlafende", sleep.end),
                              yStart: .value("Minimum", 0.0), yEnd: .value("Maximum", kind.maximum))
                    .foregroundStyle(Theme.sleep.opacity(0.12))
                    .accessibilityHidden(true)
            }
            ForEach(signals.activities) { workout in
                if let interval = clipped(workout.start, workout.end, start: start, end: end) {
                    RectangleMark(xStart: .value("Trainingsbeginn", interval.start), xEnd: .value("Trainingsende", interval.end),
                                  yStart: .value("Minimum", 0.0), yEnd: .value("Maximum", kind.maximum))
                        .foregroundStyle(Theme.strain.opacity(0.12))
                        .accessibilityHidden(true)
                }
            }
            ForEach(points) { point in
                LineMark(x: .value("Uhrzeit", point.date), y: .value(kind.title, point.value),
                         series: .value("Abschnitt", point.segment))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(kind.tint)
                PointMark(x: .value("Uhrzeit", point.date), y: .value(kind.title, point.value))
                    .symbolSize(13)
                    .foregroundStyle(kind.tint)
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...kind.maximum)
        .chartXAxis {
            let ticks = [3, 9, 15, 21].compactMap {
                Calendar.forma.date(bySettingHour: $0, minute: 0, second: 0, of: start)
            }
            AxisMarks(values: ticks) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).locale(.german))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .chartYAxis { insightScale(kind == .energy ? [0, 25, 50, 75, 100] : [0, 1, 2, 3]) }
        .frame(height: 170)
    }

    private func clipped(_ from: Date, _ to: Date, start: Date, end: Date) -> DateInterval? {
        let lower = max(start, from)
        let upper = min(end, to)
        return lower < upper ? DateInterval(start: lower, end: upper) : nil
    }

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let segment: Int
        var id: Date { date }
    }

    private var segments: [Point] {
        var segment = 0
        var last: Date?
        return signals.estimates.compactMap { estimate in
            defer { last = estimate.at }
            if let last, estimate.at.timeIntervalSince(last) > 90 * 60 { segment += 1 }
            guard let value = kind.value(estimate) else {
                segment += 1
                return nil
            }
            return Point(date: estimate.at, value: value, segment: segment)
        }
    }
}

/// Halbkreis-Skala 0–3 (grün → gelb → orange) mit Punkt auf dem Wert.
struct StressGauge: View {
    let value: Double
    var diameter: CGFloat = 200
    var lineWidth: CGFloat = 6
    var showsNumber = false

    var body: some View {
        let radius = diameter / 2
        let angle = Double.pi * (1 - min(3, max(0, value)) / 3)
        let dot = max(6, lineWidth * 2)
        ZStack(alignment: .topLeading) {
            ForEach(StressZone.allCases) { zone in
                Circle()
                    .trim(from: Double(zone.rawValue) / 6 + 0.009, to: Double(zone.rawValue + 1) / 6 - 0.009)
                    .stroke(zone.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(180))
                    .frame(width: diameter, height: diameter)
            }
            Circle()
                .fill(Theme.textPrimary)
                .frame(width: dot, height: dot)
                .position(x: radius + cos(angle) * radius, y: radius - sin(angle) * radius)
            if showsNumber {
                Text(Format.number(value, decimals: 1))
                    .font(.system(size: diameter * 0.26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .formaNumberTransition(value)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: diameter, height: radius, alignment: .bottom)
            }
        }
        .frame(width: diameter, height: radius + dot / 2, alignment: .top)
        .accessibilityHidden(true)
    }
}

extension StressZone {
    var tint: Color {
        switch self {
        case .low: Theme.younger
        case .medium: Color(hex: 0xE7CD65)
        case .high: Theme.older
        }
    }
}
