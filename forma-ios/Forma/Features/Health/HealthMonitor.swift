import SwiftUI

struct HealthMonitor: View {
    @Environment(DataHub.self) private var hub
    @State private var temperatures: TemperatureReading?
    let snapshot: DashboardDay

    private struct TemperatureReading {
        let date: Date
        let value: Double?
        let baseline: ScoreEngine.Baseline?
    }

    private var readings: [MonitorReading] {
        var readings = MonitorReading.all(for: snapshot)
        if let temperatures, temperatures.date == snapshot.day.date, let value = temperatures.value {
            readings.append(.init(id: "temperature", title: "Handgelenktemperatur", icon: "thermometer.medium",
                                  shortTitle: "Temp.", value: value, baseline: temperatures.baseline,
                                  decimals: 1, unit: "°C"))
        }
        return readings
    }

    private var temperatureDate: Date? {
        hub.isSample || hub.activeSource == .health ? snapshot.day.date : nil
    }

    var body: some View {
        NavigationLink {
            HealthMonitorDetail(date: snapshot.day.date, readings: readings)
        } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack {
                        DashboardHeading(title: "Health Monitor")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.formaCaptionStrong)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Space.s3) {
                            ForEach(readings) { reading in
                                indicator(reading).fixedSize(horizontal: true, vertical: false)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: Space.s3)], spacing: Space.s3) {
                            ForEach(readings) { indicator($0) }
                        }
                    }
                    Text(summary)
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(Space.s4)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Health Monitor")
        .accessibilityValue(summary)
        .accessibilityIdentifier("health.monitor")
        .task(id: TemperatureRequest(date: temperatureDate, source: hub.activeSource)) {
            await loadTemperatures()
        }
    }

    private struct TemperatureRequest: Equatable {
        let date: Date?
        let source: DataSourceKind
    }

    private func loadTemperatures() async {
        guard let date = temperatureDate else {
            temperatures = nil
            return
        }
        temperatures = nil
        let start = date.adding(days: -30)
        let values: [Date: Double]
        if hub.isSample {
            values = Dictionary(uniqueKeysWithValues: (0...30).map { offset in
                (date.adding(days: -offset), 35.5 + 0.25 * sin(Double(offset)))
            })
        } else {
            values = await hub.health.wristTemperatures(from: start, until: min(.now, date.adding(days: 1)))
        }
        guard !Task.isCancelled else { return }
        let prior = values.filter { $0.key >= start && $0.key < date }.map(\.value)
        temperatures = TemperatureReading(date: date, value: values[date],
                                          baseline: ScoreEngine.baseline(prior, minimumRelativeSpread: 0))
    }

    private var summary: String {
        let available = readings.filter { $0.inRange != nil }
        let inRange = available.filter { $0.inRange == true }.count
        if !available.isEmpty { return "\(inRange) von \(available.count) im persönlichen Bereich" }
        return readings.contains { $0.value != nil } ? "Noch kein persönlicher Vergleich" : "Keine Messung"
    }

    private func indicator(_ reading: MonitorReading) -> some View {
        VStack(spacing: 6) {
            Image(systemName: reading.icon)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(reading.shortTitle)
                .font(.formaMicro)
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: reading.statusIcon)
                .font(.formaCaptionStrong)
                .foregroundStyle(reading.tint)
        }
        .accessibilityHidden(true)
    }
}

private struct MonitorReading: Identifiable {
    let id: String
    let title: String
    let icon: String
    let shortTitle: String
    let value: Double?
    let baseline: ScoreEngine.Baseline?
    let decimals: Int
    let unit: String

    var range: ClosedRange<Double>? {
        baseline.map { base in
            let halfWidth = id == "temperature" ? max(base.sd, 0.10) : base.sd
            return max(0, base.mean - halfWidth)...min(id == MetricKind.spo2.rawValue ? 100 : .infinity, base.mean + halfWidth)
        }
    }
    var inRange: Bool? {
        guard let value, let range else { return nil }
        return range.contains(value)
    }

    var statusIcon: String {
        switch inRange {
        case true?: "checkmark.circle.fill"
        case false?: "exclamationmark.circle.fill"
        case nil: "minus.circle"
        }
    }

    var tint: Color {
        switch inRange {
        case true?: Theme.younger
        case false?: Theme.warning
        case nil: Theme.textSecondary
        }
    }

    var status: String {
        switch inRange {
        case true?: "Im persönlichen Bereich"
        case false?: "Außerhalb deines Bereichs"
        case nil: value == nil ? "Keine Messung" : "Noch kein Vergleich"
        }
    }

    func formatted(_ value: Double) -> String { Format.number(value, decimals: decimals) }

    var measurement: String { value.map { formatted($0) + " " + unit } ?? "–" }

    static func all(for snapshot: DashboardDay) -> [Self] {
        let keys: [(MetricKind, String, String)] = [
            (.respiratoryRate, "lungs", "Atmung"),
            (.spo2, "drop", "SpO₂"),
            (.restingHR, "heart", "Ruhepuls"),
            (.hrv, "waveform.path.ecg", "HRV")
        ]
        return keys.map { metric, icon, title in
            Self(id: metric.rawValue, title: metric.title, icon: icon, shortTitle: title, value: metric.value(snapshot.day),
                 baseline: snapshot.baseline(metric.value), decimals: metric.decimals, unit: metric.unit)
        }
    }
}

private struct HealthMonitorDetail: View {
    let date: Date
    let readings: [MonitorReading]
    @Environment(DataHub.self) private var hub
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if hub.isSample { SampleDataBadge() }
                Text(Format.dayTitle(date))
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3),
                                          count: typeSize.isAccessibilitySize ? 1 : 2),
                          alignment: .leading, spacing: Space.s3) {
                    ForEach(readings) { reading in
                        tile(reading)
                    }
                }
                Text("Persönlicher Vergleich aus den 30 Tagen davor.")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Space.s4)
        }
        .dashboardScreen()
        .navigationTitle("Health Monitor")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ reading: MonitorReading) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Image(systemName: reading.icon)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Text(reading.title)
                    .font(.formaCaptionStrong)
                Text(reading.measurement)
                    .font(.formaBigNumber)
                    .minimumScaleFactor(0.65)
                Label(reading.status, systemImage: reading.statusIcon)
                    .foregroundStyle(reading.tint)
                    .font(.formaCaptionStrong)
                if let range = reading.range {
                    Text("\(reading.formatted(range.lowerBound))–\(reading.formatted(range.upperBound)) \(reading.unit)")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }
}
