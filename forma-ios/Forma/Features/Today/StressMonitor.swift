import SwiftUI
import Charts

/// Kompakte Karte auf Overview: Titel, aktueller Wert, kleiner Verlauf. Tippen öffnet den ganzen Monitor.
/// Der Titel liegt bewusst außerhalb des Links, damit er als eigene Überschrift lesbar bleibt.
struct StressMonitorCard: View {
    let day: DayMetrics
    let slots: [StressSlot]
    let energy: Int?
    let isLoading: Bool
    let history: [DayMetrics]

    var body: some View {
        let measured = slots.filter { $0.value != nil }
        DashboardCard {
            DashboardHeading(title: "Stress Monitor")
                .accessibilityIdentifier("today.stress.title")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
            NavigationLink {
                StressDetail(day: day, slots: slots, energy: energy, isLoading: isLoading, history: history)
            } label: {
                // Skala, Stufe und Zeit in Zonen: alles auf einen Blick, ohne Kurve und ohne Uhrzeit.
                HStack(spacing: Space.s4) {
                    if let value = measured.last?.value {
                        let zone = StressZone(value: value)
                        StressGauge(value: value, diameter: 84, lineWidth: 6, showsNumber: true)
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text(zone.title).formaLabelStyle(zone.tint)
                            StressZoneBar(slots: slots)
                        }
                    } else {
                        Text("Keine Messung")
                            .font(.formaBody)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Space.s4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stress")
            .accessibilityValue(Self.spokenValue(measured.last?.value))
            .accessibilityHint("Öffnet Verlauf und Zeit in Zonen")
            .accessibilityIdentifier("today.stress.open")
        }
        .accessibilityIdentifier("today.stress")
    }

    nonisolated static func spokenValue(_ value: Double?) -> String {
        guard let value else { return "Keine Messung" }
        return "\(Format.number(value, decimals: 1)) von 3, \(StressZone(value: value).title)"
    }
}

/// Eigene Seite: Skala, Zeit in Zonen und Langzeit-Verlauf, alles ohne weiteren Tipp.
struct StressDetail: View {
    @Environment(DataHub.self) private var hub
    let day: DayMetrics
    let slots: [StressSlot]
    let energy: Int?
    let isLoading: Bool
    let history: [DayMetrics]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.gap) {
                if hub.isSample { SampleDataBadge() }
                StressMonitorPanel(day: day, slots: slots, isLoading: isLoading)
                StressTrendCard(end: InsightHistory.lastCompletedDay(for: day.date), history: history)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .dashboardScreen()
        .navigationTitle("Stress Monitor")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Zeit in den drei Zonen als ein farbiger Balken, nur Stunden mit Messung.
struct StressZoneBar: View {
    let slots: [StressSlot]

    var body: some View {
        let durations = StressZone.allCases.map { $0.duration(in: slots) }
        let total = durations.reduce(0, +)
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(StressZone.allCases) { zone in
                    Capsule()
                        .fill(zone.tint)
                        .frame(width: total > 0 ? max(0, geometry.size.width * durations[zone.rawValue] / total - 2) : 0)
                }
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zeit in Zonen")
        .accessibilityValue(StressZone.allCases.map { "\($0.title) \(Format.duration($0.duration(in: slots)))" }
            .joined(separator: ", "))
    }
}

/// Eigene Today-Kachel „Energie“: große Zahl in Zustandsfarbe und Segmentbalken.
struct EnergyTile: View {
    let energy: Int?

    nonisolated static func tint(_ energy: Int) -> Color {
        energy >= 67 ? Theme.recoveryHigh : energy >= 34 ? Theme.recoveryMid : Theme.older
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                DashboardHeading(title: "Energie")
                if let energy {
                    let tint = Self.tint(energy)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(energy)").font(.formaDisplay).formaNumberTransition(Double(energy))
                        Text("%").font(.formaBody).foregroundStyle(Theme.textSecondary)
                    }
                    .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 3) {
                        ForEach(0..<24, id: \.self) { index in
                            Capsule()
                                .fill(Double(index + 1) / 24 <= Double(energy) / 100 ? tint : Theme.track)
                                .frame(height: 8)
                        }
                    }
                    .accessibilityHidden(true)
                } else {
                    Text("Keine Messung").font(.formaBody).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Space.s4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energie")
        .accessibilityValue(energy.map { "\($0) Prozent" } ?? "Keine Messung")
        .accessibilityIdentifier("today.energy")
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

/// Der ganze Monitor: großer Wert und Zeit in Zonen.
struct StressMonitorPanel: View {
    let day: DayMetrics
    let slots: [StressSlot]
    let isLoading: Bool

    private var measurements: [StressSlot] { slots.filter { $0.value != nil } }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let value = measurements.last?.value {
                    stressReading(value)
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
    }

    private func stressReading(_ value: Double) -> some View {
        let zone = StressZone(value: value)
        let diameter: CGFloat = 200
        return VStack(spacing: Space.s2) {
            ZStack(alignment: .bottom) {
                StressGauge(value: value, diameter: diameter)
                VStack(spacing: 2) {
                    Text(Format.number(value, decimals: 1))
                        .font(.formaWidgetNumber)
                        .foregroundStyle(Theme.textPrimary)
                        .formaNumberTransition(value)
                    Text(zone.title).formaLabelStyle(zone.tint)
                }
            }
            HStack {
                Text("0")
                Spacer()
                Text("3")
            }
            .frame(width: diameter)
        }
        .font(.formaCaption)
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stress")
        .accessibilityValue(StressMonitorCard.spokenValue(value))
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
        }
    }

    private func zoneTime(_ zone: StressZone, duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(zone.title).formaLabelStyle(zone.tint)
            Text(Format.duration(duration)).font(.formaValue)
                .formaNumberTransition(duration)
        }
        .accessibilityElement(children: .combine)
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
