import SwiftUI

enum MeasurementTileLayout: String, CaseIterable, Identifiable {
    case cards, columns

    var id: Self { self }
    var title: String { self == .cards ? "Karten" : "Balken" }
}

/// Tageswerte und persönlicher Bereich. Jede Kachel führt direkt zum zugehörigen Verlauf.
struct HealthMonitor: View {
    @AppStorage("forma.tiles.vitals.layout") private var layout = MeasurementTileLayout.cards
    @State private var showOverview = false
    let snapshot: DashboardDay

    var body: some View {
        let check = NightVitals(day: snapshot.day, history: snapshot.history)
        let readings = check.readings.map(MonitorReading.init)
        let byID = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0) })
        let items = [MetricKind.respiratoryRate, .restingHR, .hrv, .spo2, .skinTemperature]
            .compactMap { byID[$0.rawValue] } + [MonitorReading(sleepOf: snapshot)]
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Spacer()
                Menu {
                    Picker("Kacheldesign", selection: $layout) {
                        ForEach(MeasurementTileLayout.allCases) { style in Text(style.title).tag(style) }
                    }
                    Button("Messübersicht", systemImage: "heart.text.square") { showOverview = true }
                        .accessibilityIdentifier("health.monitor")
                } label: {
                    Image(systemName: "rectangle.grid.2x2")
                        .font(.formaCaptionStrong)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Vitalwerte-Kacheldesign")
                .accessibilityIdentifier("health.monitor.layout")
            }
            HealthVitalGrid(readings: items, layout: layout)
        }
        .sheet(isPresented: $showOverview) {
            NavigationStack {
                HealthMonitorDetail(readings: items, markedNight: check.isMarked)
            }
        }
    }
}

private struct HealthVitalGrid: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let readings: [MonitorReading]
    var layout: MeasurementTileLayout = .cards

    private var showsColumns: Bool { layout == .columns && !typeSize.isAccessibilitySize }

    var body: some View {
        if showsColumns {
            // Balken: alle Werte in einer Reihe (Maxi F5-03).
            HStack(spacing: 6) {
                ForEach(readings) { reading in link(reading) { VitalPill(reading: reading) } }
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2),
                                     count: typeSize.isAccessibilitySize ? 1 : 2),
                      alignment: .leading, spacing: Space.s2) {
                ForEach(readings) { reading in link(reading) { tile(reading) } }
            }
        }
    }

    @ViewBuilder
    private func link<Label: View>(_ reading: MonitorReading, @ViewBuilder label: () -> Label) -> some View {
        if let metric = MetricKind(rawValue: reading.id) {
            NavigationLink {
                MetricDetailView(kind: metric)
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.title)
            .accessibilityValue(reading.spokenValue)
            .accessibilityIdentifier("health.monitor.metric." + reading.id)
        }
    }

    private func tile(_ reading: MonitorReading) -> some View {
        DashboardCard {
            HStack(spacing: Space.s2) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Label(reading.shortTitle, systemImage: reading.icon)
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textSecondary)
                    ViewThatFits(in: .horizontal) {
                        Text(reading.measurement).font(.formaNumber).fixedSize(horizontal: true, vertical: false)
                        Text(reading.measurement).font(.formaValue)
                    }
                    Label(reading.status, systemImage: reading.statusIcon)
                        .font(.formaMicro)
                        .foregroundStyle(reading.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let value = reading.scaleValue, !typeSize.isAccessibilitySize {
                    MetricScale(value: value, tint: reading.tint, axis: .vertical, target: 25...75)
                        .frame(width: 22, height: 54)
                        .accessibilityHidden(true)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}

/// Hohe Kapsel: senkrechter Bereichsbalken mit Punkt, darunter Wert, Einheit und Symbol.
private struct VitalPill: View {
    let reading: MonitorReading

    var body: some View {
        VStack(spacing: Space.s1) {
            gauge
                .frame(width: 26, height: 84)
                .padding(.bottom, Space.s2)
                .accessibilityHidden(true)
            Text(reading.valueText)
                .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(reading.unitText)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: reading.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, Space.s1)
        }
        .padding(.vertical, Space.s3)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.plateEdge, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Mittlere Hälfte der Skala = persönlicher Bereich, Striche oben und unten = außerhalb.
    private var gauge: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 12
            let span = proxy.size.height - 2 * inset
            let fillTint = reading.inRange == false ? Theme.strain : reading.tint
            ZStack {
                Capsule().fill(Color.black.opacity(0.28))
                VStack {
                    Capsule().fill(Theme.textQuaternary).frame(width: 12, height: 4)
                    Spacer()
                    Capsule().fill(Theme.textQuaternary).frame(width: 12, height: 4)
                }
                .padding(.vertical, 4)
                if let value = reading.scaleValue {
                    let position = inset + span * (1 - value / 100)
                    let top = min(position, inset + span * 0.25)
                    let bottom = max(position, inset + span * 0.75)
                    Capsule()
                        .fill(LinearGradient(colors: [fillTint.opacity(0.95), fillTint.opacity(0.6)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 10, height: max(10, bottom - top))
                        .position(x: proxy.size.width / 2, y: (top + bottom) / 2)
                    Circle()
                        .fill(fillTint)
                        .overlay { Circle().strokeBorder(Theme.cardRaised, lineWidth: 3) }
                        .frame(width: 16, height: 16)
                        .shadow(color: fillTint.opacity(0.7), radius: 6)
                        .position(x: proxy.size.width / 2, y: position)
                }
            }
        }
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
        switch inRange {
        case true?: Theme.younger
        case false?: Theme.strain
        case nil: Theme.textSecondary
        }
    }

    var status: String {
        guard value != nil else { return "Keine Messung" }
        switch inRange {
        case true?: return "Im Bereich"
        case false?: return isAbove == true ? "Über Bereich" : "Unter Bereich"
        case nil: return "Ohne Vergleich"
        }
    }

    var measurement: String {
        guard let value else { return "–" }
        if id == MetricKind.sleepDuration.rawValue { return Format.duration(value * 3600) }
        return "\(formatted(value)) \(unit)"
    }

    /// Zahl ohne Einheit für die Balken-Kapseln („5:37“ bei Schlaf).
    var valueText: String {
        guard let value else { return "–" }
        if id == MetricKind.sleepDuration.rawValue {
            let minutes = Int((value * 60).rounded())
            return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
        }
        return formatted(value)
    }

    var unitText: String {
        id == MetricKind.sleepDuration.rawValue ? "Std." : unit.trimmingCharacters(in: .whitespaces)
    }

    var scaleValue: Double? {
        guard let value, let range, range.upperBound > range.lowerBound else { return nil }
        return min(100, max(0, 25 + 50 * (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    var spokenValue: String {
        guard value != nil else { return "Keine Messung" }
        return [measurement, status, rangeText].compactMap { $0 }.joined(separator: ", ")
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

    init(sleepOf snapshot: DashboardDay) {
        let kind = MetricKind.sleepDuration
        let previous = snapshot.history.compactMap { day -> Double? in
            guard ScoreEngine.sameBaselineSource(for: .sleep, today: snapshot.day, previous: day) else { return nil }
            return kind.value(day)
        }
        let value = kind.value(snapshot.day).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.init(id: kind.rawValue, title: kind.title, icon: "bed.double", shortTitle: "Schlaf",
                  value: value, baseline: previous.count >= 7 ? ScoreEngine.baseline(previous) : nil,
                  decimals: kind.decimals, unit: kind.unit)
    }
}

private struct HealthMonitorDetail: View {
    let readings: [MonitorReading]
    let markedNight: Bool
    @State private var showInfo = false

    var body: some View {
        InsightPage(title: "Health Monitor") {
            if markedNight {
                Label("Auffällige Nacht", systemImage: "moon")
                    .font(.formaRowTitle)
                    .foregroundStyle(Theme.warning)
                    .accessibilityIdentifier("health.monitor.outliers")
            }
            HealthVitalGrid(readings: readings)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Wie der Bereich entsteht")
                    .popover(isPresented: $showInfo) {
                        Text("Der persönliche Bereich nutzt mindestens sieben gemessene Nächte der letzten 30 Tage.")
                            .font(.formaBody)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 280)
                            .padding(Space.s4)
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }
    }
}
