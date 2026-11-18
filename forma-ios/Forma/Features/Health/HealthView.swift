import SwiftUI
import SwiftData
import Charts

enum HealthTile: String, TileKind {
    case hrv, restingHR, respiratoryRate, spo2, vo2max, sleepDuration, steps, activeEnergy, bodyAge

    var id: String { rawValue }
    var metric: MetricKind? { MetricKind(rawValue: rawValue) }
    var title: String { metric?.title ?? "Health Age" }
    var systemImage: String { metric == nil ? "hourglass" : "waveform.path.ecg" }
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
                    InlineTileStack<HealthTile, AnyView>(storageKey: "forma.tiles.health") { kind in
                        AnyView(tile(kind))
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.s4)
            }
            .refreshable { await hub.refresh() }
            .formaScreen()
            .navigationTitle("Gesundheit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .navigationDestination(for: MetricKind.self) { MetricDetailView(kind: $0) }
            .navigationDestination(for: HealthTile.self) { _ in BodyAgeDetailView() }
        }
    }

    @ViewBuilder private func tile(_ kind: HealthTile) -> some View {
        if let metric = kind.metric {
            NavigationLink(value: metric) {
                Plate { MetricSummaryRow(kind: metric) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("health.metric." + metric.rawValue)
        } else {
            NavigationLink(value: kind) {
                BodyAgeSummaryCard(outcome: bodyAgeOutcome(hub: hub, sessions: sessions))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("health.age")
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
