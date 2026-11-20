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

/// Health Age, Vitalwerte und Biomarker mit direktem Zugang zu ihren Details.
struct HealthView: View {
    @Environment(DataHub.self) private var hub
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        let age = bodyAgeOutcome(hub: hub, sessions: sessions)
        let today = Date.now.startOfDay
        let day = hub.days.last.flatMap { $0.date == today ? $0 : nil } ?? DayMetrics(date: today)
        let snapshot = DashboardDay(day: day, history: hub.dashboardHistory(recent: hub.days))
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    if hub.isSample {
                        SampleDataBadge()
                    } else if let status = hub.todayDataNotice {
                        Text(status).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    }
                    if case .ready = age {
                        NavigationLink {
                            BodyAgeDetailView(outcome: age, trend: bodyAgeTrend(hub: hub, sessions: sessions))
                        } label: {
                            HealthAgeHero(outcome: age)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("health.age")
                    } else {
                        HealthAgeSetupCard(outcome: age)
                            .accessibilityIdentifier("health.age")
                    }

                    HealthMonitor(snapshot: snapshot)

                    InlineTileStack<HealthTile, AnyView>(storageKey: "forma.tiles.health") { kind in
                        AnyView(tile(kind))
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.s4)
            }
            .refreshable { await hub.refresh() }
            .dashboardScreen()
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .navigationDestination(for: MetricKind.self) { MetricDetailView(kind: $0) }
        }
    }

    @ViewBuilder private func tile(_ kind: HealthTile) -> some View {
        if let metric = kind.metric {
            NavigationLink(value: metric) {
                DashboardCard { MetricSummaryRow(kind: metric) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("health.metric." + metric.rawValue)
        }
    }
}

/// Diagramm eines Biomarkers über 7, 30 oder 90 Tage mit deinem üblichen Bereich als Band.
struct MetricDetailView: View {
    @Environment(DataHub.self) private var hub
    let kind: MetricKind
    @State private var range = 30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fester Zeitraum der Auswahl, damit 7 Tage auch 7 Tage breit sind.
    private var domain: ClosedRange<Date> {
        let end = Date.now.startOfDay
        return end.adding(days: -(range - 1))...end
    }

    private var axisStride: Int {
        switch range {
        case 7: 2
        case 30: 7
        default: 30
        }
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

    var body: some View {
        let all = hub.longDays.compactMap { day in kind.value(day).map { (day.date, $0) } }
        let points = all.filter { domain.contains($0.0) }
        let values = points.map(\.1)
        let evaluation = BiomarkerComparison.evaluate(kind, days: hub.longDays)
        let usual = evaluation.range
        let status = evaluation.status
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    if hub.isSample { SampleDataBadge().padding(.bottom, Space.s2) }
                    Text(all.last.map { kind.measurement($0.1) } ?? "–")
                        .font(.formaDisplay)
                        .formaNumberTransition(all.last?.1 ?? 0)
                    HStack(spacing: 6) {
                        if let symbol = status.symbol { Image(systemName: symbol).accessibilityHidden(true) }
                        Text(status.title)
                        // Bei älteren Werten steht das Datum schon im Zustandswort.
                        if status == .within || status == .above || status == .below, let last = all.last {
                            Text("· \(Format.shortDate(last.0))").foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .font(.formaCaptionStrong)
                    .foregroundStyle(status.color)
                }
                .padding(.top, Space.s4)

                Picker("Zeitraum", selection: $range) {
                    Text("7 Tage").tag(7)
                    Text("30 Tage").tag(30)
                    Text("90 Tage").tag(90)
                }
                .pickerStyle(.segmented)
                .padding(.top, Space.s5)

                DashboardCard {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        if !points.isEmpty {
                            Text("\(points.count) von \(range) Tagen gemessen")
                                .font(.formaCaptionStrong)
                                .foregroundStyle(Theme.textSecondary)
                                .formaNumberTransition(Double(points.count))
                        }

                        if points.isEmpty {
                            Text("Keine Messungen in diesem Zeitraum")
                                .font(.formaBody).foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                        } else {
                            chart(points: points, usual: usual)
                        }
                    }
                    .padding(Space.s4)
                }
                .padding(.top, Space.s4)
                .animation(reduceMotion ? nil : .smooth, value: range)

                VStack(alignment: .leading, spacing: Space.s2) {
                    DashboardHeading(title: "Zusammenfassung")
                    DashboardCard {
                        MetricRow(title: "Mittel", value: values.isEmpty ? "–" : kind.formatted(values.reduce(0, +) / Double(values.count)), unit: kind == .sleepDuration ? nil : kind.unit)
                        RowDivider()
                        MetricRow(title: "Niedrigster Wert", value: values.min().map { kind.formatted($0) } ?? "–", unit: kind == .sleepDuration ? nil : kind.unit)
                        RowDivider()
                        MetricRow(title: "Höchster Wert", value: values.max().map { kind.formatted($0) } ?? "–", unit: kind == .sleepDuration ? nil : kind.unit)
                        if let usual {
                            RowDivider()
                            MetricRow(title: "Dein Bereich", value: "\(kind.formatted(usual.lowerBound))–\(kind.formatted(usual.upperBound))", unit: kind == .sleepDuration ? nil : kind.unit)
                        }
                    }
                }
                .padding(.top, Space.s5)
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.page)
        }
        .dashboardScreen()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chart(points: [(Date, Double)], usual: ClosedRange<Double>?) -> some View {
        Chart {
            if let usual {
                RectangleMark(xStart: .value("Start", domain.lowerBound), xEnd: .value("Ende", domain.upperBound),
                              yStart: .value("unten", usual.lowerBound), yEnd: .value("oben", usual.upperBound))
                    .foregroundStyle(Color.white.opacity(0.07))
            }
            // Linear verbinden und bei Lücken unterbrechen: keine erfundenen Zwischenwerte.
            ForEach(segmented(points), id: \.date) { p in
                LineMark(x: .value("Tag", p.date), y: .value(kind.title, p.value), series: .value("Abschnitt", p.segment))
                    .interpolationMethod(.linear)
                    .foregroundStyle(Theme.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Tag", p.date), y: .value(kind.title, p.value))
                    .symbolSize(range == 90 ? 6 : 14)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            // .aligned hält die Randbeschriftungen im Diagramm.
            AxisMarks(preset: .aligned, values: .stride(by: .day, count: axisStride)) { _ in
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
        .accessibilityLabel("\(kind.title), \(points.count) Messungen in \(range) Tagen")
        .accessibilityValue(points.last.map { "zuletzt \(kind.measurement($0.1))" } ?? "keine Messung")
    }
}
