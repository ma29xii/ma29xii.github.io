import SwiftUI
import SwiftData
import Charts

enum HealthTile: String, TileKind {
    // Messwerte zuerst, die Schätzung danach (Codex R-01-30).
    case heart, sleepActivity, fitness, bodyAge
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bodyAge: "Körperalter"
        case .heart: "Herz und Atmung"
        case .fitness: "Fitness"
        case .sleepActivity: "Schlaf und Aktivität"
        }
    }
    var systemImage: String {
        switch self {
        case .bodyAge: "hourglass"
        case .heart: "heart"
        case .fitness: "lungs"
        case .sleepActivity: "bed.double"
        }
    }
    var summary: String {
        switch self {
        case .bodyAge: "Wie alt dein Körper nach deinen Daten wirkt"
        case .heart: "HRV, Ruhepuls, Atemfrequenz, SpO₂"
        case .fitness: "VO₂max im Verlauf"
        case .sleepActivity: "Schlafdauer, Schritte, aktive Energie"
        }
    }
}

struct HealthView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var editingTiles = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s2) {
                        Text("Trends der letzten 30 Tage").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                        if hub.isSample { SampleDataBadge() }
                        Spacer()
                    }
                    .padding(.top, Space.s1)

                    TileStack<HealthTile, AnyView>(storageKey: "forma.tiles.health", screenTitle: "Gesundheit", isEditing: $editingTiles) { tile in
                        AnyView(view(for: tile))
                    }
                    .padding(.top, Space.s4)

                    Text("Quelle: \(hub.activeSource.title). „Dein Bereich“ = dein Mittel ± eine Standardabweichung der letzten 30 Tage – kein medizinischer Grenzwert.")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, Space.s4)
                    Color.clear.frame(height: Space.s7)
                }
                .padding(.horizontal, Space.page)
            }
            .refreshable { await hub.refresh() }
            .formaScreen()
            .navigationTitle("Gesundheit")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { editingTiles = true } label: { Image(systemName: "square.grid.2x2") }
                        .accessibilityLabel("Gesundheit anpassen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.showProfile = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Profil und Einstellungen")
                }
            }
            .navigationDestination(for: MetricKind.self) { MetricDetailView(kind: $0) }
            .navigationDestination(for: BodyAgeRoute.self) { _ in BodyAgeDetailView() }
        }
    }

    @ViewBuilder private func view(for tile: HealthTile) -> some View {
        switch tile {
        case .bodyAge:
            BodyAgeSummaryCard(outcome: bodyAgeOutcome(hub: hub, sessions: sessions),
                               open: { path.append(BodyAgeRoute()) },
                               openProfile: { app.showProfile = true })
        case .heart:
            WidgetCard(title: tile.title, systemImage: tile.systemImage) {
                ForEach(Array([MetricKind.hrv, .restingHR, .respiratoryRate, .spo2].enumerated()), id: \.element) { i, kind in
                    if i > 0 { RowDivider() }
                    NavigationLink(value: kind) { MetricSummaryRow(kind: kind) }.buttonStyle(.plain)
                }
            }
        case .fitness:
            WidgetCard(title: tile.title, systemImage: tile.systemImage) {
                NavigationLink(value: MetricKind.vo2max) { TrendRow(kind: .vo2max) }.buttonStyle(.plain)
            }
        case .sleepActivity:
            WidgetCard(title: tile.title, systemImage: tile.systemImage) {
                ForEach(Array([MetricKind.sleepDuration, .steps, .activeEnergy].enumerated()), id: \.element) { i, kind in
                    if i > 0 { RowDivider() }
                    NavigationLink(value: kind) { MetricSummaryRow(kind: kind) }.buttonStyle(.plain)
                }
            }
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
        let points = hub.days.suffix(range).compactMap { day in kind.value(day).map { (day.date, $0) } }
        let values = points.map(\.1)
        let base = ScoreEngine.baseline(hub.history.compactMap { kind.value($0) })
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(values.last.map { kind.formatted($0) } ?? "–").font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                        if kind != .sleepDuration { Text(kind.unit).font(.formaBody).foregroundStyle(Theme.textSecondary) }
                    }
                    if let b = base, let last = values.last {
                        let d = last - b.mean
                        let good = kind.higherIsBetter ? d >= 0 : d <= 0
                        Text("\(d >= 0 ? "+" : "−")\(kind.formatted(abs(d)))\(kind == .sleepDuration ? "" : " " + kind.unit) gegenüber deinem Mittel der letzten 30 Tage")
                            .font(.formaCaption)
                            .foregroundStyle(abs(b.z(last)) > 1.5 && !good ? Theme.warning : Theme.textSecondary)
                    }
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
                            } else if points.isEmpty {
                                Text("Keine Messungen in diesem Zeitraum")
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                Text("\(points.count) Messungen · Finger über das Diagramm ziehen")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .font(.formaCaptionStrong)
                        .contentTransition(.opacity)

                        if points.isEmpty {
                            Text("In diesem Zeitraum gibt es keine Messung. Quelle: \(hub.activeSource.title).")
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
                FormaSection(title: "Was der Wert bedeutet") {
                    Text(kind.explanation)
                        .font(.formaBody)
                        .foregroundStyle(Theme.textSecondary)
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
