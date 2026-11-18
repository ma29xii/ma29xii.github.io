import SwiftUI
import SwiftData
import Charts

enum HealthTile: String, TileKind {
    case bodyAge, heart, fitness, sleepActivity
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

                    TileStack<HealthTile, AnyView>(storageKey: "forma.tiles.health", screenTitle: "Gesundheit") { tile in
                        AnyView(view(for: tile))
                    }
                    .padding(.top, Space.s4)

                    Text("Quelle: \(hub.activeSource.title). Normalbereich = dein Mittel ± eine Standardabweichung der letzten 30 Tage.")
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

    var body: some View {
        let points = hub.days.suffix(range).compactMap { day in kind.value(day).map { (day.date, $0) } }
        let values = points.map(\.1)
        let base = ScoreEngine.baseline(hub.history.compactMap { kind.value($0) })
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(values.last.map { kind.formatted($0) } ?? "–").font(.system(size: 48, weight: .semibold)).monospacedDigit()
                        if kind != .sleepDuration { Text(kind.unit).font(.formaBody).foregroundStyle(Theme.textSecondary) }
                    }
                    if let b = base, let last = values.last {
                        let d = last - b.mean
                        let good = kind.higherIsBetter ? d >= 0 : d <= 0
                        Text("\(d >= 0 ? "+" : "−")\(kind.formatted(abs(d))) zum 30-Tage-Mittel")
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

                Plate {
                    Chart {
                        if let b = base {
                            ForEach(points, id: \.0) { p in
                                AreaMark(x: .value("Tag", p.0), yStart: .value("unten", b.mean - b.sd), yEnd: .value("oben", b.mean + b.sd))
                                    .foregroundStyle(Color.white.opacity(0.06))
                            }
                        }
                        ForEach(points, id: \.0) { p in
                            LineMark(x: .value("Tag", p.0), y: .value(kind.title, p.1))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Theme.textPrimary)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        if let last = points.last {
                            PointMark(x: .value("Tag", last.0), y: .value(kind.title, last.1))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: range > 14 ? 7 : 2)) { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) { _ in
                            AxisGridLine().foregroundStyle(Theme.hairline)
                            AxisValueLabel().foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(height: 220)
                    .padding(Space.s4)
                }
                .padding(.top, Space.s4)

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
