import SwiftUI

struct StepsTile: View {
    @Environment(DataHub.self) private var hub
    static let goal = 10_000.0
    var showsChevron = true

    var body: some View {
        WidgetCard(title: "Schritte", systemImage: "figure.walk", accent: Theme.strain) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(hub.today.steps.map { Format.number($0) } ?? "–")
                        .font(.formaWidgetNumber)
                    Spacer(minLength: Space.s2)
                    Text("Ziel \(Format.number(Self.goal))")
                        .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    if showsChevron { TileChevron() }
                }
                if let steps = hub.today.steps {
                    ProgressLine(fraction: steps / Self.goal, color: Theme.strain, height: 5)
                        .accessibilityHidden(true)
                } else {
                    Text("Heute noch keine Daten").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding([.horizontal, .bottom], Space.s4)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct StepsDetail: View {
    @Environment(DataHub.self) private var hub

    var body: some View {
        let points = hub.hours.compactMap { hour in
            hour.steps.map { HealthChartPoint(date: hour.start, value: $0) }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hub.isSample { SampleDataBadge().padding(.bottom, Space.s2) }
                StepsTile(showsChevron: false)
                HourlyValueChart(title: "Schritte pro Stunde", points: points, color: Theme.strain,
                                 maximum: max(100, (points.map(\.value).max() ?? 0) * 1.1),
                                 valueText: { Format.number($0) })
                DailyHistoryChart(title: "Schritte pro Tag",
                                  points: hub.days.compactMap { day in day.steps.map { HealthChartPoint(date: day.date, value: $0) } },
                                  color: Theme.strain, valueText: { Format.number($0) })
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .formaScreen(tint: Theme.strain)
        .navigationTitle("Schritte")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EnergyStressTile: View {
    @Environment(DataHub.self) private var hub

    private let stressColor = Theme.warning
    private let energyColor = Theme.younger

    var body: some View {
        let estimates = hub.hourlyEstimates
        let values = estimates.compactMap(\.stress)
        let stress = values.last
        let energy = estimates.compactMap(\.energy).last
        WidgetCard(title: "Energie und Stress", systemImage: "bolt", accessory: "Geschätzt") {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stress").font(.formaRowTitle)
                        if let latest = estimates.last(where: { $0.stress != nil }) {
                            Text("Stand \(Format.clock(latest.at))")
                                .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                        } else {
                            Text("Keine Stundenwerte").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: Space.s2)
                    ZStack {
                        TrimmedGauge(fraction: stress.map { $0 / 3 }, color: stressColor)
                        VStack(spacing: 0) {
                            Text(stress.map { Format.number($0, decimals: 1) } ?? "–")
                                .font(.formaBigNumber)
                            Text("von 3").font(.formaMicro).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 72, height: 72)
                    TileChevron()
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.s4) { stressStats(values) }
                    VStack(alignment: .leading, spacing: Space.s2) { stressStats(values) }
                }
                Divider().overlay(Theme.hairline)
                HStack {
                    Text("Energie").font(.formaRowTitle)
                    Spacer()
                    Text(energy.map { "\($0) %" } ?? "–").font(.formaValue)
                }
                EnergySegments(value: energy, color: energyColor)
            }
            .padding(Space.s4)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func stressStats(_ values: [Double]) -> some View {
        stat("Höchster", value: values.max())
        stat("Niedrigster", value: values.min())
        stat("Mittel", value: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count))
    }

    private func stat(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { Format.number($0, decimals: 1) } ?? "–").font(.formaValue)
            Text(title).font(.formaCaption).foregroundStyle(Theme.textSecondary)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value.map { Format.number($0, decimals: 1) } ?? "kein Wert")")
    }
}

private struct TrimmedGauge: View {
    let fraction: Double?
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.76)
                .stroke(Theme.track, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            if let fraction, fraction > 0 {
                Circle()
                    .trim(from: 0, to: 0.76 * fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
        .rotationEffect(.degrees(133))
        .accessibilityHidden(true)
    }
}

private struct EnergySegments: View {
    let value: Int?
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<15, id: \.self) { index in
                let fraction = min(1, max(0, Double(value ?? 0) / 100 * 15 - Double(index)))
                GeometryReader { geometry in
                    Capsule().fill(Theme.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(color).frame(width: geometry.size.width * fraction)
                        }
                }
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

struct EnergyStressDetail: View {
    @Environment(DataHub.self) private var hub

    var body: some View {
        let estimates = hub.hourlyEstimates
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hub.isSample { SampleDataBadge().padding(.bottom, Space.s2) }
                HourlyValueChart(title: "Stress im Tagesverlauf", points: estimates.compactMap { hour in
                    hour.stress.map { HealthChartPoint(date: hour.at, value: $0) }
                }, color: Theme.warning, maximum: 3, valueText: { Format.number($0, decimals: 1) + " von 3" },
                emptyText: "Für die Schätzung fehlen Herzwerte")
                HourlyValueChart(title: "Energie im Tagesverlauf", points: estimates.compactMap { hour in
                    hour.energy.map { HealthChartPoint(date: hour.at, value: Double($0)) }
                }, color: Theme.younger, maximum: 100, valueText: { Format.number($0) + " %" },
                emptyText: "Für die Schätzung fehlen Schlaf-, Bewegungs- oder Herzwerte")
                Text("Stündliche Schätzungen").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    .padding(.top, Space.s3)
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.s6)
        }
        .formaScreen()
        .navigationTitle("Energie und Stress")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BodyMetricsTile: View {
    @Environment(DataHub.self) private var hub

    var body: some View {
        WidgetCard(title: "Körper", systemImage: "waveform.path.ecg") {
            HStack(spacing: Space.s4) {
                value("HRV", value: hub.today.hrv, unit: "ms")
                value("Ruhepuls", value: hub.today.restingHR, unit: "bpm")
                TileChevron()
            }
            .padding(Space.s4)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func value(_ label: String, value: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.formaCaption).foregroundStyle(Theme.textSecondary)
            Text(value.map { "\(Format.number($0)) \(unit)" } ?? "–")
                .font(.formaBigNumber).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BodyMetricsDetail: View {
    @Environment(DataHub.self) private var hub

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                if hub.isSample { SampleDataBadge() }
                Plate {
                    ForEach([MetricKind.hrv, .restingHR, .respiratoryRate, .spo2]) { kind in
                        if kind != .hrv { RowDivider() }
                        NavigationLink(value: kind) { MetricSummaryRow(kind: kind) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(Space.page)
        }
        .formaScreen()
        .navigationTitle("Körper")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TileChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.formaCaptionStrong)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)
    }
}
