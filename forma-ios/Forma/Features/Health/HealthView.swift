import SwiftUI
import SwiftData
import Charts

enum HealthTile: String, TileKind {
    case hrv, restingHR, respiratoryRate, spo2, vo2max, sleepDuration, steps, activeEnergy

    var id: String { rawValue }
    var metric: MetricKind? { MetricKind(rawValue: rawValue) }
    var title: String { metric?.title ?? rawValue }
    var systemImage: String { "waveform.path.ecg" }
    var summary: String { title }

    static func storedKinds(for id: String) -> [Self] {
        switch id {
        case "heart": [.hrv, .restingHR, .respiratoryRate, .spo2]
        case "fitness": [.vo2max]
        case "sleepActivity": [.sleepDuration, .steps, .activeEnergy]
        default: Self(rawValue: id).map { [$0] } ?? []
        }
    }
}

struct HealthView: View {
    @Environment(DataHub.self) private var hub
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if hub.isSample {
                        SampleDataBadge()
                    } else if let status = hub.todayDataNotice {
                        Text(status).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    }
                    NavigationLink {
                        BodyAgeDetailView()
                    } label: {
                        HealthAgeHero(outcome: bodyAgeOutcome(hub: hub, sessions: sessions))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("health.age")

                    Text("Biomarker")
                        .font(.formaSection)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, Space.s3)
                    InlineTileStack<HealthTile, AnyView>(storageKey: "forma.tiles.health") { kind in
                        AnyView(tile(kind))
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.s4)
            }
            .refreshable { await hub.refresh() }
            .formaScreen()
            .navigationTitle("Health Age")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .navigationDestination(for: MetricKind.self) { MetricDetailView(kind: $0) }
        }
    }

    @ViewBuilder private func tile(_ kind: HealthTile) -> some View {
        if let metric = kind.metric {
            NavigationLink(value: metric) {
                Plate { MetricSummaryRow(kind: metric) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("health.metric." + metric.rawValue)
        }
    }
}

struct MetricDetailView: View {
    @Environment(DataHub.self) private var hub
    let kind: MetricKind
    @State private var range = 30
    @State private var selection: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fester Zeitraum der Auswahl, damit 7 Tage auch 7 Tage breit sind.
    private var domain: ClosedRange<Date> {
        let end = Date.now.startOfDay
        return end.adding(days: -(range - 1))...end
    }

    private struct SegmentPoint { let date: Date; let value: Double; let segment: Int }

    /// Neue Linie, sobald zwischen zwei Messungen mehr als ein Tag fehlt.
    private func segmented(_ points: [(Date, Double)]) -> [SegmentPoint] {
        var result: [SegmentPoint] = []
        var segment = 0
        for (i, p) in points.enumerated() {
            if i > 0, p.0.timeIntervalSince(points[i - 1].0) > 1.5 * 86_400 { segment += 1 }
            result.append(SegmentPoint(date: p.0, value: p.1, segment: segment))
        }
        return result
    }

    /// Nur eine Messung am *gewählten Tag* – in Lücken keine weiter entfernte Messung (Codex R-02-20/A-28).
    private func selectedPoint(_ points: [(Date, Double)]) -> (Date, Double)? {
        guard let selection else { return nil }
        return points.first { Calendar.forma.isDate($0.0, inSameDayAs: selection) }
    }

    var body: some View {
        let points = hub.days.filter { domain.contains($0.date) }.compactMap { day in
            kind.value(day).map { (day.date, $0) }
        }
        let values = points.map(\.1)
        let base = ScoreEngine.baseline(hub.history.compactMap { kind.value($0) })
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    if hub.isSample { SampleDataBadge().padding(.bottom, Space.s2) }
                    Text(points.last.map { kind.measurement($0.1) } ?? "–")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text(points.last.map { "Stand \(Format.shortDate($0.0))" } ?? "Keine Messung")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, Space.s4)

                Picker("Zeitraum", selection: $range) {
                    Text("7 Tage").tag(7)
                    Text("14 Tage").tag(14)
                    Text("30 Tage").tag(30)
                }
                .pickerStyle(.segmented)
                .padding(.top, Space.s5)
                .onChange(of: range) { _, _ in selection = nil }

                Plate {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        // Ausgewählter Tag oder Hinweis zum Abfahren mit dem Finger.
                        Group {
                            if let sel = selectedPoint(points) {
                                Text("\(sel.0.formatted(Date.FormatStyle(locale: .german).weekday(.abbreviated).day().month(.abbreviated))): \(kind.formatted(sel.1))\(kind == .sleepDuration ? "" : " " + kind.unit)")
                                    .foregroundStyle(Theme.textPrimary)
                            } else if let selection {
                                Text("\(selection.formatted(Date.FormatStyle(locale: .german).weekday(.abbreviated).day().month(.abbreviated))): keine Messung")
                                    .foregroundStyle(Theme.textSecondary)
                            } else if !points.isEmpty {
                                Text("\(points.count) Messungen")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .font(.formaCaptionStrong)
                        .contentTransition(.opacity)

                        if points.isEmpty {
                            Text("Keine Messungen in diesem Zeitraum")
                                .font(.formaBody).foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                        } else {
                            Chart {
                                if let b = base {
                                    RectangleMark(xStart: .value("Start", domain.lowerBound), xEnd: .value("Ende", domain.upperBound),
                                                  yStart: .value("unten", b.mean - b.sd), yEnd: .value("oben", b.mean + b.sd))
                                        .foregroundStyle(Color.white.opacity(0.06))
                                }
                                // Linear verbinden und bei Lücken unterbrechen: keine erfundenen Zwischenwerte (Codex R-01-31).
                                ForEach(segmented(points), id: \.date) { p in
                                    LineMark(x: .value("Tag", p.date), y: .value(kind.title, p.value), series: .value("Abschnitt", p.segment))
                                        .interpolationMethod(.linear)
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                    PointMark(x: .value("Tag", p.date), y: .value(kind.title, p.value))
                                        .symbolSize(14)
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                if let sel = selectedPoint(points) {
                                    RuleMark(x: .value("Auswahl", sel.0))
                                        .foregroundStyle(Theme.textTertiary)
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    PointMark(x: .value("Tag", sel.0), y: .value(kind.title, sel.1))
                                        .symbolSize(70)
                                        .foregroundStyle(Theme.textPrimary)
                                }
                            }
                            .chartXScale(domain: domain)
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartXSelection(value: $selection)
                            .chartXAxis {
                                // .aligned hält die Randbeschriftungen im Diagramm (keine abgeschnittenen Daten).
                                AxisMarks(preset: .aligned, values: .stride(by: .day, count: range > 14 ? 7 : 2)) { _ in
                                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .trailing) { _ in
                                    AxisGridLine().foregroundStyle(Theme.hairline)
                                    AxisValueLabel().foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .chartPlotStyle { $0.padding(.trailing, 6) }
                            .frame(height: 220)
                            .sensoryFeedback(.selection, trigger: selectedPoint(points)?.0)
                            .accessibilityLabel("\(kind.title), \(points.count) Messungen in \(range) Tagen")
                            .accessibilityValue(points.last.map { "zuletzt \(kind.formatted($0.1)) \(kind.unit)" } ?? "keine Messung")
                        }
                    }
                    .padding(Space.s4)
                }
                .padding(.top, Space.s4)
                .animation(reduceMotion ? nil : .smooth, value: range)

                FormaSection(title: "Zusammenfassung") {
                    Plate {
                        MetricRow(title: "Mittel", value: values.isEmpty ? "–" : kind.formatted(values.reduce(0, +) / Double(values.count)), unit: kind == .sleepDuration ? nil : kind.unit)
                        RowDivider()
                        MetricRow(title: "Niedrigster Wert", value: values.min().map { kind.formatted($0) } ?? "–", unit: kind == .sleepDuration ? nil : kind.unit)
                        RowDivider()
                        MetricRow(title: "Höchster Wert", value: values.max().map { kind.formatted($0) } ?? "–", unit: kind == .sleepDuration ? nil : kind.unit)
                    }
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.page)
        }
        .formaScreen()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
