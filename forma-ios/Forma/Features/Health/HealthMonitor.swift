import SwiftUI

/// Vitalwerte des Tages mit Haken, wenn sie in deinem üblichen Bereich liegen.
struct HealthMonitor: View {
    let snapshot: DashboardDay
    /// Today: nur die Symbole, ohne Titel und Zusammenfassung.
    var compact = false

    var body: some View {
        let check = NightVitals(day: snapshot.day, history: snapshot.history)
        let items = check.readings.map(MonitorReading.init)
        let summary = MonitorSummary(readings: items)
        let status = check.isMarked ? "\(check.outliers.count) Vitalwerte weichen ab" : summary.text
        NavigationLink {
            HealthMonitorDetail(date: snapshot.day.date, readings: items, markedNight: check.isMarked)
        } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if !compact {
                        DashboardHeading(title: "Health Monitor")
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
                    if !compact || check.isMarked {
                        Label(status, systemImage: check.isMarked ? "moon" : summary.icon)
                            .font(.formaCaptionStrong)
                            .foregroundStyle(check.isMarked ? Theme.warning : summary.tint)
                            .formaNumberTransition(Double(check.outliers.count))
                            .padding(.horizontal, Space.s3)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    }
                }
                .padding(Space.s4)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Health Monitor")
        .accessibilityValue(status)
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

/// Zeile unter den Symbolen, z. B. „4 von 4 im üblichen Bereich“.
/// Bewertet erst ab drei vergleichbaren Werten, sonst wirkt ein einzelner Wert wie ein vollständiger Check.
struct MonitorSummary {
    static let minimumCompared = 3
    let text: String
    let icon: String
    let tint: Color

    init(readings: [MonitorReading]) {
        let compared = readings.compactMap(\.inRange)
        let inside = compared.filter { $0 }.count
        if compared.count >= Self.minimumCompared {
            text = "\(inside) von \(compared.count) im üblichen Bereich"
            icon = inside == compared.count ? "checkmark.circle" : "circle.lefthalf.filled"
            tint = inside == compared.count ? Theme.textPrimary : Theme.textSecondary
        } else if !compared.isEmpty {
            text = "Erst \(compared.count) von \(readings.count) vergleichbar"
            icon = "minus.circle"
            tint = Theme.textSecondary
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

    /// Persönlicher Bereich: zwei Standardabweichungen um das Mittel der 30 Tage davor.
    var range: ClosedRange<Double>? {
        NightVitals.range(for: id, baseline: baseline)
    }

    var inRange: Bool? {
        guard let value, let range else { return nil }
        return range.contains(value)
    }

    /// Neutral: über oder unter dem eigenen üblichen Bereich, ohne „besser/schlechter“.
    var isAbove: Bool? {
        guard let value, let range, !range.contains(value) else { return nil }
        return value > range.upperBound
    }

    var statusIcon: String {
        switch inRange {
        case true?: "checkmark.circle"
        case false?: isAbove == true ? "arrow.up.circle" : "arrow.down.circle"
        case nil: "minus.circle"
        }
    }

    var tint: Color {
        inRange == nil ? Theme.textSecondary : Theme.textPrimary
    }

    func formatted(_ value: Double) -> String { Format.number(value, decimals: decimals) }

    var rangeText: String? {
        range.map { "\(formatted($0.lowerBound))–\(formatted($0.upperBound))" }
    }

}

extension MonitorReading {
    init(_ reading: NightVitals.Reading) {
        let metric = MetricKind(rawValue: reading.series.rawValue)
        let (icon, shortTitle) = switch reading.series {
        case .respiratoryRate: ("lungs", "Atmung")
        case .spo2: ("drop", "SpO₂")
        case .restingHR: ("heart", "Ruhepuls")
        case .hrv: ("waveform.path.ecg", "HRV")
        case .skinTemperature: ("thermometer.medium", "Hauttemp.")
        default: ("waveform", reading.series.title)
        }
        self.init(id: reading.series.rawValue, title: metric?.title ?? reading.series.title,
                  icon: icon, shortTitle: shortTitle, value: reading.value, baseline: reading.baseline,
                  decimals: metric?.decimals ?? 1, unit: metric?.unit ?? "°C")
    }
}

private struct HealthMonitorDetail: View {
    let date: Date
    let readings: [MonitorReading]
    let markedNight: Bool
    @Environment(DataHub.self) private var hub
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showInfo = false

    var body: some View {
        let summary = MonitorSummary(readings: readings)
        let sorted = readings.filter { $0.inRange == false } + readings.filter { $0.inRange != false }
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if hub.isSample { SampleDataBadge() }
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(Format.dayTitle(date))
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                    Label(markedNight ? "Auffällige Nacht" : summary.text,
                          systemImage: markedNight ? "moon" : summary.icon)
                        .font(.formaRowTitle)
                        .foregroundStyle(markedNight ? Theme.warning : summary.tint)
                }
                if markedNight {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        DashboardHeading(title: "Außerhalb deines Bereichs")
                        Text(sorted.filter { $0.inRange == false }.map(\.title).joined(separator: " · "))
                            .font(.formaBody)
                            .accessibilityIdentifier("health.monitor.outliers")
                    }
                }
                let columns = typeSize.isAccessibilitySize ? 1 : 2
                // Bei ungerader Zahl steht die letzte Kachel quer über die volle Breite statt allein halbbreit.
                let paired = columns == 2 && !sorted.count.isMultiple(of: 2) ? Array(sorted.dropLast()) : sorted
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: columns),
                          alignment: .leading, spacing: Space.s3) {
                    ForEach(paired) { tile($0) }
                }
                if paired.count < sorted.count, let last = sorted.last {
                    wideTile(last)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .dashboardScreen()
        .navigationTitle("Health Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Wie der Bereich entsteht")
                    .popover(isPresented: $showInfo) {
                        Text("Dein Bereich stammt aus mindestens sieben gemessenen Nächten der letzten 30 Tage. Der Ruhepuls ist ein Tageswert.")
                            .font(.formaBody)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 280)
                            .padding(Space.s4)
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }
    }

    private func tile(_ reading: MonitorReading) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                // Nur der Kurzname: alle Kacheln gleich hoch; der volle Name ist das VoiceOver-Label.
                tileTitle(reading)
                tileValue(reading)
                Spacer(minLength: 0)
                tileStatus(reading)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.title)
            .accessibilityValue(accessibilityValue(reading))
        }
    }

    /// Querformat für die einzelne letzte Kachel: Name und Wert links, Bereich rechts.
    private func wideTile(_ reading: MonitorReading) -> some View {
        DashboardCard {
            HStack(alignment: .bottom, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    tileTitle(reading)
                    tileValue(reading)
                }
                Spacer(minLength: Space.s2)
                tileStatus(reading)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.title)
            .accessibilityValue(accessibilityValue(reading))
        }
    }

    private func tileTitle(_ reading: MonitorReading) -> some View {
        Label(reading.shortTitle, systemImage: reading.icon)
            .font(.formaCaptionStrong)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }

    private func tileValue(_ reading: MonitorReading) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(reading.value.map { reading.formatted($0) } ?? "–")
                .font(.formaBigNumber)
                .formaNumberTransition(reading.value ?? 0)
                .minimumScaleFactor(0.7)
            if reading.value != nil {
                Text(reading.unit)
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func tileStatus(_ reading: MonitorReading) -> some View {
        Label(reading.value == nil ? "Keine Messung" : (reading.rangeText ?? "Noch kein Vergleich"),
              systemImage: reading.statusIcon)
            .font(.formaCaptionStrong)
            .monospacedDigit()
            .foregroundStyle(reading.tint)
    }

    private func accessibilityValue(_ reading: MonitorReading) -> String {
        guard let value = reading.value else { return "Keine Messung" }
        let measured = "\(reading.formatted(value)) \(reading.unit)"
        guard let inRange = reading.inRange, let range = reading.rangeText else { return measured + ", noch kein Vergleich" }
        if inRange { return measured + ", im üblichen Bereich " + range }
        return measured + (reading.isAbove == true ? ", über deinem üblichen Bereich " : ", unter deinem üblichen Bereich ") + range
    }
}
