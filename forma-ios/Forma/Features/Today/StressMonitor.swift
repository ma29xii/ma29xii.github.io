import SwiftUI
import Charts

struct StressMonitor: View {
    let day: DayMetrics
    let slots: [StressSlot]
    let energy: Int?
    let isLoading: Bool

    private var measurements: [StressSlot] { slots.filter { $0.value != nil } }

    var body: some View {
        VStack(spacing: Space.s2) {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack {
                        DashboardHeading(title: "Stress Monitor")
                            .accessibilityIdentifier("today.stress.title")
                        Spacer(minLength: Space.s2)
                        Text("Schätzung").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    }
                    if let latest = measurements.last, let value = latest.value {
                        stressReading(value, at: latest.end)
                        StressDayChart(day: day, slots: slots)
                        RowDivider(inset: 0)
                        zoneSummary
                    } else if isLoading {
                        ProgressView("Stundenwerte werden geladen …")
                            .font(.formaBody)
                            .tint(Theme.textSecondary)
                    } else {
                        Text("Keine stündlichen Stresswerte für diesen Tag.")
                            .font(.formaBody)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Space.s4)
            }
            energyBar
        }
        .accessibilityIdentifier("today.stress")
    }

    private func stressReading(_ value: Double, at date: Date) -> some View {
        let zone = StressZone(value: value)
        let diameter = 200.0
        let radius = diameter / 2
        let angle = Double.pi * (1 - min(3, max(0, value)) / 3)
        return VStack(spacing: Space.s2) {
            ZStack(alignment: .topLeading) {
                ForEach(StressZone.allCases) { zone in
                    Circle()
                        .trim(from: Double(zone.rawValue) / 6 + 0.009, to: Double(zone.rawValue + 1) / 6 - 0.009)
                        .stroke(zone.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(180))
                        .frame(width: diameter, height: diameter)
                }
                Circle()
                    .fill(Theme.textPrimary)
                    .frame(width: 12, height: 12)
                    .position(x: radius + cos(angle) * radius, y: radius - sin(angle) * radius)
                VStack(spacing: 2) {
                    Text(Format.number(value, decimals: 1))
                        .font(.formaWidgetNumber)
                    Text(zone.title)
                        .font(.formaCaptionStrong).tracking(1.3).textCase(.uppercase)
                        .foregroundStyle(zone.tint)
                }
                .frame(width: diameter, height: radius, alignment: .bottom)
            }
            .frame(width: diameter, height: radius + 6, alignment: .top)
            .accessibilityHidden(true)
            HStack {
                Text("0")
                Spacer()
                Text("3")
            }
            .frame(width: diameter)
            .accessibilityHidden(true)
            Text("Stand \(Format.clock(date))")
        }
        .font(.formaCaption)
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Geschätzter Stress")
        .accessibilityValue("\(Format.number(value, decimals: 1)) von 3, \(zone.title), Stand \(Format.clock(date))")
    }

    private var zoneSummary: some View {
        let zones = StressZone.allCases
        let durations = zones.map { $0.duration(in: slots) }
        let total = durations.reduce(0, +)
        return VStack(alignment: .leading, spacing: Space.s3) {
            DashboardHeading(title: "Zeit in Zonen")
            if total > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(zones) { zone in
                            Rectangle()
                                .fill(zone.tint)
                                .frame(width: geometry.size.width * durations[zone.rawValue] / total)
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s3) {
                    ForEach(zones) { zone in
                        zoneTime(zone, duration: durations[zone.rawValue])
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(zones) { zone in zoneTime(zone, duration: durations[zone.rawValue]) }
                }
            }
            Text("Nur Stunden mit Messwerten")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func zoneTime(_ zone: StressZone, duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(zone.title).font(.formaCaption).foregroundStyle(zone.tint)
            Text(Format.duration(duration)).font(.formaValue)
        }
        .accessibilityElement(children: .combine)
    }

    private var energyBar: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Label("Energie", systemImage: "bolt.fill")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(energy.map { "\($0) %" } ?? (isLoading ? "Wird geladen …" : "Keine Schätzung"))
                        .font(.formaValue)
                }
                if let energy {
                    HStack(spacing: 3) {
                        ForEach(0..<24) { index in
                            Capsule()
                                .fill(Double(index + 1) / 24 <= Double(energy) / 100 ? Theme.younger : Theme.track)
                                .frame(height: 7)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .padding(Space.s4)
            .accessibilityElement(children: .combine)
        }
    }
}

private extension StressZone {
    var tint: Color {
        switch self {
        case .low: Theme.younger
        case .medium: Color(hex: 0xE7CD65)
        case .high: Theme.older
        }
    }
}

private struct StressDayChart: View {
    let day: DayMetrics
    let slots: [StressSlot]

    private struct Reading: Identifiable {
        let date: Date
        let value: Double
        let segment: Int
        var id: Date { date }
    }

    private struct Event: Identifiable {
        let hour: Date
        var sleep = false
        var activity = false
        var id: Date { hour }
    }

    private var readings: [Reading] {
        var result: [Reading] = []
        var previousEnd: Date?
        var segment = 0
        for slot in slots {
            guard let value = slot.value else { continue }
            if previousEnd != slot.start { segment += 1 }
            let midpoint = slot.start.addingTimeInterval(slot.end.timeIntervalSince(slot.start) / 2)
            result.append(Reading(date: midpoint, value: value, segment: segment))
            previousEnd = slot.end
        }
        return result
    }

    private var events: [Event] {
        var entries: [Date: Event] = [:]
        if let night = day.sleep, let hour = Calendar.forma.dateInterval(of: .hour, for: night.end)?.start {
            entries[hour] = Event(hour: hour, sleep: true)
        }
        for workout in day.workouts {
            guard let hour = Calendar.forma.dateInterval(of: .hour, for: workout.start)?.start else { continue }
            entries[hour, default: Event(hour: hour)].activity = true
        }
        return entries.values.sorted { $0.hour < $1.hour }
    }

    var body: some View {
        let end = day.date.adding(days: 1)
        return VStack(alignment: .leading, spacing: Space.s2) {
            Chart {
                ForEach(readings) { point in
                    LineMark(x: .value("Uhrzeit", point.date), y: .value("Stress", point.value),
                             series: .value("Abschnitt", point.segment))
                        .foregroundStyle(Theme.younger)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Uhrzeit", point.date), y: .value("Stress", point.value))
                        .symbolSize(14)
                        .foregroundStyle(StressZone(value: point.value).tint)
                }
                ForEach(events.filter { $0.hour >= day.date && $0.hour < end }) { event in
                    PointMark(x: .value("Uhrzeit", event.hour), y: .value("Ereignis", 0))
                        .symbolSize(1)
                        .annotation(position: .top, spacing: 2) {
                            HStack(spacing: 2) {
                                if event.sleep { Image(systemName: "moon.fill") }
                                if event.activity { Image(systemName: "figure.walk") }
                            }
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                        }
                }
            }
            .chartXScale(domain: day.date...end)
            .chartYScale(domain: 0.0...3.0)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .stride(by: .hour, count: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 1, 2, 3]) { _ in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel().foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(height: 125)
            .accessibilityLabel("Geschätzter Stress im Tagesverlauf")
            HStack(spacing: Space.s4) {
                Label("Schlafende", systemImage: "moon.fill")
                Label("Aktivität", systemImage: "figure.walk")
            }
            .font(.formaCaption)
            .foregroundStyle(Theme.textSecondary)
        }
    }
}
