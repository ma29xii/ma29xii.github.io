import SwiftUI

enum MeasurementTileLayout: String, CaseIterable, Identifiable {
    case cards, columns

    var id: Self { self }
    var title: String { self == .cards ? "Karten" : "Balken" }
    var symbol: String { self == .cards ? "rectangle.grid.1x2" : "rectangle.split.3x1" }
}

/// Karten ↔ Balken. Erscheint nur im Anpassen-Modus; ein Tipp wechselt das Design.
struct TileLayoutToggle: View {
    @Binding var layout: MeasurementTileLayout

    var body: some View {
        Button {
            layout = layout == .cards ? .columns : .cards
        } label: {
            Label(layout.title, systemImage: layout.symbol)
                .font(.formaCaptionStrong)
                .frame(minHeight: 44)
                .padding(.horizontal, Space.s2)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Kacheldesign")
        .accessibilityValue(layout.title)
        .accessibilityIdentifier("tiles.layout")
    }
}

/// Dasselbe mit gespeicherter Wahl, für die Kopfzeile im Bearbeitungsmodus.
struct StoredTileLayoutToggle: View {
    @AppStorage private var layout: MeasurementTileLayout

    init(key: String) { _layout = AppStorage(wrappedValue: .cards, key) }

    var body: some View { TileLayoutToggle(layout: $layout) }
}

/// Tageswerte und persönlicher Bereich. Jede Kachel führt direkt zum zugehörigen Verlauf.
struct HealthMonitor: View {
    static let layoutKey = "forma.tiles.vitals.layout"
    @AppStorage(HealthMonitor.layoutKey) private var layout = MeasurementTileLayout.cards
    @Environment(\.tilesEditing) private var editing
    @State private var showOverview = false
    let snapshot: DashboardDay

    var body: some View {
        let check = NightVitals(day: snapshot.day, history: snapshot.history)
        let readings = check.readings.map(MonitorReading.init)
        let byID = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0) })
        let items = [MetricKind.respiratoryRate, .restingHR, .hrv, .spo2, .skinTemperature]
            .compactMap { byID[$0.rawValue] } + [MonitorReading(sleepOf: snapshot)]
        // Keine sichtbare Überschrift mehr (Maxi F7-01); der Titel steht im Anpassen-Modus und für VoiceOver.
        VStack(alignment: .leading, spacing: Space.s2) {
            if editing { TileLayoutToggle(layout: $layout) }
            HealthVitalGrid(readings: items, layout: layout)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Health Monitor")
        .accessibilityIdentifier("health.monitor")
        .accessibilityAction(named: "Messübersicht öffnen") { showOverview = true }
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

    var body: some View {
        if layout == .columns {
            // Balken: sechs einzelne Kapseln in einer Reihe, ab Bedienungshilfe-Schrift 3 × 2.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2),
                                     count: typeSize.isAccessibilitySize ? 3 : 6),
                      spacing: Space.s2) {
                ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                    link(reading) { VitalPill(reading: reading, order: index) }
                }
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
            .buttonStyle(.formaCard)
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

private struct VitalPill: View {
    let reading: MonitorReading
    var order = 0

    var body: some View {
        VitalCapsule(value: reading.valueText, unit: reading.unitText, icon: reading.icon,
                     scale: reading.scaleValue, tint: reading.inRange == false ? Theme.strain : reading.tint,
                     order: order)
    }
}

/// Hohe Kapsel: dunkler Schacht mit Bereichsbalken und Punkt, darunter Wert, Einheit und Symbol.
/// Die mittlere Hälfte der Skala (25–75) ist der persönliche Bereich, die Striche oben und unten liegen außerhalb.
struct VitalCapsule: View {
    let value: String
    let unit: String
    let icon: String
    /// 0–100 oder nil ohne Messung.
    let scale: Double?
    let tint: Color
    /// Balken wächst vom unteren Strich bis zum Punkt (für Prozentwerte ohne eigenen Bereich).
    var fromBottom = false
    var order = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        VStack(spacing: Space.s1) {
            gauge
                .frame(height: 96)
                .padding(.bottom, Space.s1)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit.isEmpty ? " " : unit)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textQuaternary)
                .padding(.top, Space.s1)
        }
        .padding(.vertical, Space.s3)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.plateEdge, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onAppear {
            guard !arrived else { return }
            if reduceMotion { arrived = true } else {
                withAnimation(.smooth(duration: 0.8).delay(0.06 * Double(order))) { arrived = true }
            }
        }
    }

    private var gauge: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let inset: CGFloat = 16
            let span = proxy.size.height - 2 * inset
            let shaft = RoundedRectangle(cornerRadius: width * 0.46, style: .continuous)
            ZStack {
                shaft.fill(Color.black.opacity(0.34))
                shaft.strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                VStack {
                    Capsule().fill(tint.opacity(0.32)).frame(width: width * 0.3, height: 4)
                    Spacer()
                    Capsule().fill(tint.opacity(0.32)).frame(width: width * 0.3, height: 4)
                }
                .padding(.vertical, 7)
                if let scale {
                    // Beim Erscheinen gleitet der Punkt aus der Mitte an seinen Platz.
                    let shown = arrived ? scale : 50
                    let position = inset + span * (1 - shown / 100)
                    let top = fromBottom ? position : min(position, inset + span * 0.25)
                    let bottom = fromBottom ? inset + span : max(position, inset + span * 0.75)
                    let dot = min(22, width * 0.44)
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.62)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: width * 0.4, height: max(dot, bottom - top))
                        .position(x: width / 2, y: (top + bottom) / 2)
                    Circle()
                        .fill(tint)
                        .overlay { Circle().strokeBorder(Color(white: 0.17), lineWidth: 4) }
                        .frame(width: dot, height: dot)
                        .shadow(color: tint.opacity(0.75), radius: 7)
                        .position(x: width / 2, y: position)
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
