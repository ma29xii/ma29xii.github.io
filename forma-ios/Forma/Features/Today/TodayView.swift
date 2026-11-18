import SwiftUI

private enum TodayPage: Hashable, Identifiable {
    case overview, ring(RingKind)

    static let all: [Self] = [.overview, .ring(.sleep), .ring(.recovery), .ring(.strain)]
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .ring(let kind): kind.title
        }
    }
}

/// Die Zahl, das Detail und der Verlauf benutzen dieselbe Verfügbarkeitsprüfung.
extension DashboardDay {
    func value(for kind: RingKind) -> Int? {
        switch kind {
        case .sleep: sleepScore
        case .recovery: recovery
        case .strain: strain
        }
    }
}

struct TodayView: View {
    @Environment(DataHub.self) private var hub
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedDate: Date?
    @State private var page = TodayPage.overview
    @State private var historicalHours: HistoricalHours?

    private struct HistoricalHours {
        let date: Date
        let hours: [HourlyMetrics]
    }

    var body: some View {
        let today = Date.now.startOfDay
        let daily = hub.days
        let history = hub.dashboardHistory(recent: daily)
        let firstDay = min(daily.first?.date ?? today, today)
        let date = min(today, max(firstDay, selectedDate ?? today))
        let day = daily.first { $0.date == date } ?? DayMetrics(date: date)
        let snapshot = DashboardDay(day: day, history: history)
        let historyRequest: Date? = date < today && hub.activeSource == .health && page == .overview ? date : nil

        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: Space.s2) {
                    DateStepper(title: date == today ? "Heute" : Format.dayTitle(date),
                                canPrevious: date > firstDay, canNext: date < today,
                                previous: { selectedDate = date.adding(days: -1) },
                                next: {
                                    let nextDay = date.adding(days: 1)
                                    selectedDate = nextDay == today ? nil : nextDay
                                })
                    tabStrip
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.s2)
                RowDivider(inset: 0)

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        sourceStatus(for: date, today: today)
                        switch page {
                        case .overview:
                            overview(snapshot, history: history, today: today, historyRequest: historyRequest)
                        case .ring(let kind):
                            RingDetailView(kind: kind, snapshot: snapshot, history: history)
                        }
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.vertical, Space.s4)
                    .padding(.bottom, Space.s6)
                }
                .id(page)
                .refreshable { await hub.refresh() }
            }
            .dashboardScreen()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
        }
        .task(id: historyRequest) {
            guard let historyRequest else {
                if hub.activeSource != .health { historicalHours = nil }
                return
            }
            let hours = await hub.health.loadHours(from: historyRequest, until: historyRequest.adding(days: 1))
            guard !Task.isCancelled else { return }
            historicalHours = HistoricalHours(date: historyRequest, hours: hours)
        }
        .onChange(of: hub.activeSource) { _, _ in selectedDate = nil }
    }

    private var tabStrip: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ScrollView(.horizontal) { tabs }
                    .scrollIndicators(.hidden)
            } else {
                tabs
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today-Reiter")
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(TodayPage.all) { item in
                Button {
                    page = item
                } label: {
                    VStack(spacing: 0) {
                        Text(item.title)
                            .font(.formaCaptionStrong)
                            .textCase(.uppercase)
                            .tracking(0.65)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                        Capsule().fill(page == item ? Theme.textPrimary : .clear)
                            .frame(height: 2)
                    }
                    .foregroundStyle(page == item ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, Space.s2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == item ? [.isSelected] : [])
                .accessibilityIdentifier("today.tab." + item.title.lowercased())
            }
        }
    }

    @ViewBuilder private func sourceStatus(for date: Date, today: Date) -> some View {
        if hub.isSample {
            SampleDataBadge()
        } else if date == today {
            if let status = hub.todayDataNotice {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Label(status, systemImage: "heart")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                    if !hub.days.contains(where: SyncStore.hasData) {
                        Button("Beispieldaten anzeigen") { hub.preferredSource = .sample }
                            .font(.formaCaptionStrong)
                            .frame(minHeight: 44)
                    }
                }
            } else if let updated = hub.lastUpdate {
                Text(Calendar.forma.isDateInToday(updated) ? "Abgerufen um \(Format.clock(updated))"
                     : "Abgerufen am \(Format.shortDate(updated))")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func overview(_ snapshot: DashboardDay, history: [DayMetrics], today: Date, historyRequest: Date?) -> some View {
        let hours: [HourlyMetrics] = if hub.isSample {
            HourlyMetrics.samples(for: snapshot.day)
        } else if snapshot.day.date == today {
            hub.hours
        } else if hub.activeSource == .health, historicalHours?.date == snapshot.day.date {
            historicalHours?.hours ?? []
        } else {
            []
        }
        let estimates = HourlyEstimate.timeline(hours: hours, today: snapshot.day, history: snapshot.history)
        let slots = zip(hours, estimates).map { hour, estimate in
            StressSlot(start: hour.start, end: hour.end, value: estimate.stress)
        }

        return VStack(alignment: .leading, spacing: Space.s4) {
            ringTrio(snapshot)
            DashboardCard {
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: "sparkle").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    Text(insight(snapshot)).font(.formaBody).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s4)
            }
            comparison(snapshot, history: history, hours: hours)
            HealthMonitor(snapshot: snapshot)
            StressMonitor(day: snapshot.day, slots: slots, energy: estimates.compactMap(\.energy).last,
                          isLoading: historyRequest != nil && historicalHours?.date != historyRequest)
            activities(snapshot.day)
        }
    }

    private func ringTrio(_ snapshot: DashboardDay) -> some View {
        GeometryReader { geometry in
            let size = min(101, max(44, (geometry.size.width - 30) / 3))
            HStack(alignment: .top, spacing: 0) {
                ForEach([RingKind.sleep, .recovery, .strain]) { kind in
                    Button {
                        page = .ring(kind)
                    } label: {
                        VStack(spacing: Space.s2) {
                            DashboardRing(kind: kind, value: snapshot.value(for: kind), size: size)
                            HStack(spacing: Space.s1) {
                                Text(kind.title)
                                    .font(.formaCaptionStrong)
                                    .tracking(0.7)
                                    .textCase(.uppercase)
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.title)
                    .accessibilityValue(snapshot.value(for: kind).map { kind == .strain ? "\($0) von 100" : "\($0) Prozent" } ?? "Keine Messung")
                    .accessibilityIdentifier("ring." + kind.rawValue)
                }
            }
        }
        .frame(height: typeSize.isAccessibilitySize ? 158 : 132)
        .padding(.top, Space.s1)
    }

    private func insight(_ snapshot: DashboardDay) -> String {
        if let pulse = snapshot.day.restingHR, let base = snapshot.baseline({ $0.restingHR }),
           abs(pulse - base.mean) >= 2 {
            let delta = Format.number(abs(pulse - base.mean))
            return "Dein Ruhepuls liegt \(delta) Schläge pro Minute \(pulse < base.mean ? "unter" : "über") deinem 30-Tage-Durchschnitt."
        }
        if let sleep = snapshot.day.sleep, sleep.asleep > 0 {
            return "Du hast \(Format.duration(sleep.asleep)) geschlafen."
        }
        if let steps = snapshot.day.steps { return "Für diesen Tag wurden \(Format.number(steps)) Schritte aufgezeichnet." }
        if let strain = snapshot.strain { return "Deine geschätzte Belastung liegt bei \(strain) von 100." }
        return "Für diesen Tag fehlen bisher Daten für eine Einordnung."
    }

    private func comparison(_ snapshot: DashboardDay, history: [DayMetrics], hours: [HourlyMetrics]) -> some View {
        let sleepAverage = DashboardTrends.mean(points: DashboardTrends.points(kind: .sleep, days: history,
            domain: snapshot.day.date.adding(days: -30)...snapshot.day.date.adding(days: -1)))
        return VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Kennzahlen")
            DashboardCard {
                NavigationLink {
                    StepsDetail(snapshot: snapshot, hours: hours)
                } label: {
                    ComparisonRow(title: "Schritte", icon: "figure.walk", value: snapshot.day.steps,
                                  baseline: snapshot.baseline { $0.steps }?.mean, format: { Format.number($0) })
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.steps")
                RowDivider()
                ComparisonRow(title: "HRV", icon: "waveform.path.ecg", value: snapshot.day.hrv,
                              baseline: snapshot.baseline { $0.hrv }?.mean, format: MetricKind.hrv.measurement)
                RowDivider()
                ComparisonRow(title: "Schlafleistung", icon: "moon", value: snapshot.sleepScore.map(Double.init),
                              baseline: sleepAverage, format: { Format.number($0) + " %" })
                RowDivider()
                ComparisonRow(title: "Aktive Kalorien", icon: "flame", value: snapshot.day.activeEnergy,
                              baseline: snapshot.baseline { $0.activeEnergy }?.mean, format: MetricKind.activeEnergy.measurement)
            }
            ComparisonFooter()
        }
    }

    @ViewBuilder private func activities(_ day: DayMetrics) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Mein Tag")
                .accessibilityIdentifier("today.activities.title")
            DashboardCard {
                let entries = DayActivity.entries(for: day)
                if entries.isEmpty { DashboardEmpty(title: "Kein Schlaf oder Training aufgezeichnet") }
                ForEach(entries) { entry in
                    if entry.id != entries.first?.id { RowDivider() }
                    activityRow(entry)
                }
            }
        }
    }

    private func activityRow(_ entry: DayActivity) -> some View {
        HStack(spacing: Space.s3) {
            Text(entry.amount)
                .font(.formaValue)
                .foregroundStyle(entry.tint)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 6)
                .background(entry.tint.opacity(0.14), in: Capsule())
                .accessibilityHidden(true)
            Text(entry.title)
                .font(.formaCaptionStrong)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.clock)
                .font(.formaCaption)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .frame(minHeight: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title)
        .accessibilityValue("\(entry.spokenAmount), \(entry.clock)")
    }
}

private struct DayActivity: Identifiable {
    let id: String
    let title: String
    let amount: String
    let spokenAmount: String
    let date: Date
    let clock: String
    let tint: Color

    static func entries(for day: DayMetrics) -> [Self] {
        var entries = day.workouts.map { workout in
            let load = ScoreEngine.strain(DayMetrics(date: day.date, activeEnergy: workout.energy, workouts: [workout]))
            return Self(id: workout.id.uuidString, title: workout.name, amount: String(load),
                        spokenAmount: "Geschätzte Belastung \(load) von 100", date: workout.start,
                        clock: Format.clock(workout.start), tint: DashboardRing.tint(kind: .strain, value: load))
        }
        if let sleep = day.sleep, sleep.asleep > 0 {
            let duration = Format.duration(sleep.asleep)
            entries.append(Self(id: "sleep", title: "Schlaf", amount: duration, spokenAmount: duration,
                                date: sleep.end, clock: "\(Format.clock(sleep.start))–\(Format.clock(sleep.end))",
                                tint: Theme.sleep))
        }
        return entries.sorted { $0.date > $1.date }
    }
}
