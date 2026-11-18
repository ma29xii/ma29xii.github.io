import SwiftUI

enum TodayRoute: Hashable {
    case ring(RingKind, compact: Bool)
    case energy, steps, body
}

enum TodayTile: String, TileKind {
    case day, energy, body

    static let requiredVisible: Set<Self> = [.day]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Schritte"
        case .energy: "Energie und Stress"
        case .body: "Körper"
        }
    }

    var systemImage: String {
        switch self {
        case .day: "figure.walk"
        case .energy: "bolt"
        case .body: "waveform.path.ecg"
        }
    }

    var summary: String { title }
}

struct TodayView: View {
    @Environment(DataHub.self) private var hub
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoom
    @State private var path = NavigationPath()
    @State private var compactVisible = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    rings(compact: false)
                        .onScrollVisibilityChange(threshold: 0.2) { visible in
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                                compactVisible = !visible
                            }
                        }
                    InlineTileStack<TodayTile, AnyView>(storageKey: "forma.tiles.today") { kind in
                        AnyView(tile(kind))
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.s6)
            }
            .refreshable { await hub.refresh() }
            .formaScreen(tint: hub.availability.recovery && !hub.waitingForFitbit ? Theme.recovery(hub.ringScores.recovery) : nil)
            .navigationTitle("Heute")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    rings(compact: true)
                        .opacity(compactVisible ? 1 : 0)
                        .allowsHitTesting(compactVisible)
                        .accessibilityHidden(!compactVisible)
                }
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .ring(let kind, let compact):
                    RingDetailView(kind: kind)
                        .modifier(ZoomDestination(id: kind.zoomID(compact: compact), namespace: zoom))
                case .energy: EnergyStressDetail()
                case .steps: StepsDetail()
                case .body: BodyMetricsDetail()
                }
            }
            .navigationDestination(for: MetricKind.self) { MetricDetailView(kind: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(Format.dayTitle(.now))
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.textSecondary)
            if hub.isSample {
                SampleDataBadge()
            } else if let status = hub.todayDataNotice {
                Label(status, systemImage: "heart")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            } else if let updated = hub.lastUpdate {
                Text(Calendar.forma.isDateInToday(updated) ? "Stand \(Format.clock(updated))" : "Stand \(Format.shortDate(updated))")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func rings(compact: Bool) -> some View {
        let s = hub.ringScores
        let a = hub.availability
        return RingTrio(
            strain: a.strain ? s.strain : nil, recovery: a.recovery ? s.recovery : nil,
            sleep: a.sleep ? s.sleep : nil, target: a.recovery ? s.target : nil,
            dimmedRecoverySleep: hub.waitingForFitbit, compact: compact, zoomNamespace: zoom
        ) { kind in path.append(TodayRoute.ring(kind, compact: compact)) }
    }

    @ViewBuilder private func tile(_ kind: TodayTile) -> some View {
        let route: TodayRoute = switch kind {
        case .day: .steps
        case .energy: .energy
        case .body: .body
        }
        NavigationLink(value: route) {
            switch kind {
            case .day: StepsTile()
            case .energy: EnergyStressTile()
            case .body: BodyMetricsTile()
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.tile." + kind.rawValue)
    }
}
