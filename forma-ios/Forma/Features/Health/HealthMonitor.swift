import SwiftUI

/// Vitalwerte des Tages mit Haken, wenn sie im persönlichen Normalbereich liegen.
struct HealthMonitor: View {
    let snapshot: DashboardDay

    private var readings: [MonitorReading] { MonitorReading.all(for: snapshot) }

    var body: some View {
        let items = readings
        let summary = MonitorSummary(readings: items)
        NavigationLink {
            HealthMonitorDetail(date: snapshot.day.date, readings: items)
        } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack {
                        DashboardHeading(title: "Health Monitor")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.formaCaptionStrong)
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityHidden(true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 0) {
                            ForEach(items) { reading in
                                indicator(reading)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: Space.s3)], spacing: Space.s3) {
                            ForEach(items) { indicator($0) }
                        }
                    }
                    Label(summary.text, systemImage: summary.icon)
                        .font(.formaCaptionStrong)
                        .foregroundStyle(summary.tint)
                        .padding(.horizontal, Space.s3)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                }
                .padding(Space.s4)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Health Monitor")
        .accessibilityValue(summary.text)
        .accessibilityIdentifier("health.monitor")
    }

    private func indicator(_ reading: MonitorReading) -> some View {
        VStack(spacing: 6) {
            Image(systemName: reading.icon)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(height: 22)
            Text(reading.shortTitle)
                .font(.formaMicro)
                .tracking(Tracking.micro)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: reading.statusIcon)
                .font(.formaCaptionStrong)
                .foregroundStyle(reading.tint)
        }
        .accessibilityHidden(true)
    }
}

/// Zeile unter den Symbolen, z. B. „4/4 Werte im Normalbereich“.
struct MonitorSummary {
    let text: String
    let icon: String
    let tint: Color

    init(readings: [MonitorReading]) {
        let compared = readings.compactMap(\.inRange)
        let inside = compared.filter { $0 }.count
        if !compared.isEmpty {
            text = "\(inside)/\(compared.count) Werte im Normalbereich"
            icon = inside == compared.count ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            tint = inside == compared.count ? Theme.younger : Theme.warning
        } else {
            text = readings.contains { $0.value != nil } ? "Noch kein Vergleich" : "Keine Messung"
            icon = "minus.circle"
            tint = Theme.textSecondary
        }
    }
}

struct MonitorReading: Identifiable {
    let id: String
    let title: String
    let icon: String
    let shortTitle: String
    let value: Double?
    let baseline: ScoreEngine.Baseline?
    let decimals: Int
    let unit: String

    /// Persönlicher Normalbereich: Mittel ± eine Standardabweichung der 30 Tage davor.
    var range: ClosedRange<Double>? {
        baseline.map { base in
            let upper = id == MetricKind.spo2.rawValue ? min(100, base.mean + base.sd) : base.mean + base.sd
            return max(0, base.mean - base.sd)...max(0, upper)
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

    func formatted(_ value: Double) -> String { Format.number(value, decimals: decimals) }

    var rangeText: String? {
        range.map { "\(formatted($0.lowerBound))–\(formatted($0.upperBound))" }
    }

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
        let summary = MonitorSummary(readings: readings)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if hub.isSample { SampleDataBadge() }
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(Format.dayTitle(date))
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                    Label(summary.text, systemImage: summary.icon)
                        .font(.formaRowTitle)
                        .foregroundStyle(summary.tint)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3),
                                          count: typeSize.isAccessibilitySize ? 1 : 2),
                          alignment: .leading, spacing: Space.s3) {
                    ForEach(readings) { tile($0) }
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .dashboardScreen()
        .navigationTitle("Health Monitor")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ reading: MonitorReading) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Label(reading.title, systemImage: reading.icon)
                    .font(.formaMicro)
                    .tracking(Tracking.micro)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(reading.value.map { reading.formatted($0) } ?? "–")
                        .font(.formaBigNumber)
                        .minimumScaleFactor(0.7)
                    if reading.value != nil {
                        Text(reading.unit)
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Label(reading.rangeText ?? (reading.value == nil ? "Keine Messung" : "Noch kein Vergleich"),
                      systemImage: reading.statusIcon)
                    .font(.formaCaptionStrong)
                    .monospacedDigit()
                    .foregroundStyle(reading.tint)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.title)
            .accessibilityValue(accessibilityValue(reading))
        }
    }

    private func accessibilityValue(_ reading: MonitorReading) -> String {
        guard let value = reading.value else { return "Keine Messung" }
        let measured = "\(reading.formatted(value)) \(reading.unit)"
        guard let inRange = reading.inRange, let range = reading.rangeText else { return measured + ", noch kein Vergleich" }
        return measured + (inRange ? ", im Normalbereich " : ", außerhalb des Normalbereichs ") + range
    }
}
