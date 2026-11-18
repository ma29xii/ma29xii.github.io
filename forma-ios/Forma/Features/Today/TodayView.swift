import Combine
import SwiftUI

struct TodayView: View {
    @Environment(DataHub.self) private var hub
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabUnderline
    @State private var selectedDate: Date?
    @State private var page = TodayPage.overview

    var body: some View {
        let minute = Calendar.forma.dateInterval(of: .minute, for: .now)?.start ?? .now
        TimelineView(.periodic(from: minute, by: 60)) { context in
            dashboard(at: context.date)
        }
    }

    private func dashboard(at now: Date) -> some View {
        let today = now.startOfDay
        let daily = hub.days
        let history = hub.dashboardHistory(recent: daily)
        let firstDay = min(daily.first?.date ?? today, today)
        let date = min(today, max(firstDay, selectedDate ?? today))
        let day = daily.first { $0.date == date } ?? DayMetrics(date: date)
        let snapshot = DashboardDay(day: day, history: history)
        let period = date == today ? WeeklyInsight.period(at: now) : nil

        return NavigationStack {
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
                RowDivider(inset: 0)

                // Kein `.id(page)` am ScrollView: der Seitenwechsel tauscht nur den Inhalt
                // und scrollt nach oben, damit Zustand, Pull-to-Refresh und Tippziele stabil bleiben.
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.gap) {
                            Color.clear.frame(height: 0).id(Self.top)
                            sourceStatus(for: date, today: today)
                            switch page {
                            case .overview:
                                overview(snapshot, history: history, today: today, weeklyPeriod: period)
                                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: period)
                                    .transition(.opacity)
                            case .ring(let kind):
                                RingDetailView(kind: kind, snapshot: snapshot, history: history)
                                    .id(kind)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, Space.page)
                        .padding(.top, Space.s3)
                        .padding(.bottom, Space.s6)
                    }
                    .refreshable { await hub.refresh() }
                    .onChange(of: page) { _, _ in proxy.scrollTo(Self.top, anchor: .top) }
                }
            }
            .background(alignment: .top) {
                if let recovery = snapshot.recovery {
                    TodayRecoveryGlow(recovery: recovery, isOverview: page == .overview)
                }
            }
            .dashboardScreen()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
        }
        .sensoryFeedback(.selection, trigger: page)
        .onChange(of: hub.activeSource) { _, _ in selectedDate = nil }
    }

    private static let top = "today.top"

    private func select(_ target: TodayPage) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { page = target }
    }

    // MARK: Reiter

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
                let isSelected = page == item
                Button {
                    select(item)
                } label: {
                    VStack(spacing: 0) {
                        Text(item.title)
                            .font(.formaLabel)
                            .tracking(Tracking.micro)
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                        ZStack {
                            Capsule().fill(.clear)
                            if isSelected {
                                Capsule().fill(Theme.textPrimary)
                                    .matchedGeometryEffect(id: "underline", in: tabUnderline)
                            }
                        }
                        .frame(height: 2)
                    }
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, Space.s2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityIdentifier(item.identifier)
            }
        }
    }

    // MARK: Status

    @ViewBuilder private func sourceStatus(for date: Date, today: Date) -> some View {
        if hub.isSample {
            SampleDataBadge()
        } else if date == today {
            if let status = hub.todayDataNotice {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Label(status, systemImage: "heart")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                    if !hub.days.contains(where: Self.hasAnyMeasurement) {
                        Button("Beispieldaten anzeigen") { hub.preferredSource = .sample }
                            .font(.formaCaptionStrong)
                            .frame(minHeight: 44)
                    }
                }
            } else if let updated = hub.lastUpdate {
                Text(Calendar.forma.isDateInToday(updated) ? "Abgerufen um \(Format.clock(updated))"
                     : "Abgerufen am \(Format.shortDate(updated))")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    nonisolated static func hasAnyMeasurement(_ day: DayMetrics) -> Bool {
        day.steps != nil || day.sleep != nil || day.hrv != nil || day.restingHR != nil
            || day.activeEnergy != nil || day.respiratoryRate != nil || day.spo2 != nil
            || day.skinTemperature != nil || day.vo2max != nil || !day.workouts.isEmpty
    }

    // MARK: Overview

    private func overview(_ snapshot: DashboardDay, history: [DayMetrics], today: Date,
                          weeklyPeriod: WeeklyInsight.Period?) -> some View {
        // Stundenwerte gibt es nur für heute (bzw. als Beispiel); frühere Tage zeigen eine Lücke statt Ersatzwerten.
        let hours: [HourlyMetrics] = if hub.isSample {
            HourlyMetrics.samples(for: snapshot.day)
        } else if snapshot.day.date == today {
            hub.hours
        } else {
            []
        }
        let estimates = HourlyEstimate.timeline(hours: hours, today: snapshot.day, history: snapshot.history)
        let slots = zip(hours, estimates).map { hour, estimate in
            StressSlot(start: hour.start, end: hour.end, value: estimate.stress)
        }

        return VStack(alignment: .leading, spacing: Space.gap) {
            ringTrio(snapshot)
            Text(TodayInsight.sentence(for: snapshot))
                .font(.formaBodyLarge)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Space.s2)
                .accessibilityIdentifier("today.insight")
            comparison(snapshot, history: history, hours: hours)
            HealthMonitor(snapshot: snapshot)
            if let weeklyPeriod {
                WeeklyRecapLink(period: weeklyPeriod, days: history)
                    .transition(.opacity)
            }
            StressMonitorCard(day: snapshot.day, slots: slots, energy: estimates.compactMap(\.energy).last,
                              isLoading: false, history: history)
            activities(snapshot.day)
        }
    }

    private func ringTrio(_ snapshot: DashboardDay) -> some View {
        GeometryReader { geometry in
            let size = min(104, max(44, (geometry.size.width - 2 * Space.s5) / 3))
            HStack(alignment: .top, spacing: 0) {
                ForEach([RingKind.sleep, .recovery, .strain]) { kind in
                    Button {
                        select(.ring(kind))
                    } label: {
                        VStack(spacing: Space.s2) {
                            DashboardRing(kind: kind, value: snapshot.value(for: kind), size: size)
                            HStack(spacing: 3) {
                                Text(kind.title)
                                    .font(.formaLabel)
                                    .tracking(Tracking.micro)
                                    .textCase(.uppercase)
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.title)
                    .accessibilityValue(DashboardRing.spokenValue(kind: kind, value: snapshot.value(for: kind)))
                    .accessibilityHint("Öffnet die Details")
                    .accessibilityIdentifier("ring." + kind.rawValue)
                }
            }
        }
        .frame(height: typeSize.isAccessibilitySize ? 160 : 136)
        .padding(.top, Space.s1)
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
                                  baseline: snapshot.baseline { $0.steps }?.mean, format: { Format.number($0) },
                                  showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.steps")
                RowDivider()
                pageRow(.recovery, id: "today.metric.hrv") {
                    ComparisonRow(title: "HRV", icon: "waveform.path.ecg", value: snapshot.day.hrv,
                                  baseline: snapshot.baseline { $0.hrv }?.mean, format: MetricKind.hrv.measurement,
                                  showsChevron: true)
                }
                RowDivider()
                pageRow(.sleep, id: "today.metric.sleep") {
                    ComparisonRow(title: "Schlafleistung", icon: "moon", value: snapshot.sleepScore.map(Double.init),
                                  baseline: sleepAverage, format: { Format.number($0) + " %" }, showsChevron: true)
                }
                RowDivider()
                pageRow(.strain, id: "today.metric.energy") {
                    ComparisonRow(title: "Aktive Kalorien", icon: "flame", value: snapshot.day.activeEnergy,
                                  baseline: snapshot.baseline { $0.activeEnergy }?.mean,
                                  format: MetricKind.activeEnergy.measurement, showsChevron: true)
                }
            }
            ComparisonFooter()
        }
    }

    /// Zeile, die zum passenden Reiter wechselt (Detail des Rings).
    private func pageRow<Row: View>(_ kind: RingKind, id: String, @ViewBuilder label: () -> Row) -> some View {
        Button { select(.ring(kind)) } label: { label() }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet \(kind.title)")
            .accessibilityIdentifier(id)
    }

    // MARK: Mein Tag

    private func activities(_ day: DayMetrics) -> some View {
        let entries = DayActivity.entries(for: day)
        return VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Mein Tag")
                .accessibilityIdentifier("today.activities.title")
            DashboardCard {
                if entries.isEmpty { DashboardEmpty(title: "Kein Schlaf oder Training aufgezeichnet") }
                ForEach(entries) { entry in
                    if entry.id != entries.first?.id { RowDivider() }
                    Button { select(.ring(entry.kind)) } label: { activityRow(entry) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.activity." + entry.id)
                }
            }
        }
    }

    private func activityRow(_ entry: DayActivity) -> some View {
        HStack(spacing: Space.s3) {
            Text(entry.amount)
                .font(.formaValue)
                .formaNumberTransition(entry.number)
                .foregroundStyle(entry.tint)
                .frame(minWidth: 52)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 6)
                .background(entry.tint.opacity(0.14), in: Capsule())
            Text(entry.title)
                .font(.formaLabel)
                .tracking(Tracking.micro)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.clock)
                .font(.formaCaption)
                .monospacedDigit()
                .formaNumberTransition(entry.date.timeIntervalSinceReferenceDate)
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Theme.textQuaternary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title)
        .accessibilityValue("\(entry.spokenAmount), \(entry.clock)")
    }
}

private struct TodayRecoveryGlow: View {
    let recovery: Int
    let isOverview: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        let calm = reduceMotion || scenePhase != .active || lowPower || !isOverview
        let tint = Theme.recovery(recovery)
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: calm)) { context in
            let drift: Float = calm ? 0 : Float(sin(context.date.timeIntervalSinceReferenceDate * 0.6)) * 0.055
            MeshGradient(width: 3, height: 3,
                         points: [SIMD2<Float>(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                                  SIMD2(0, 0.5), SIMD2(0.5 + drift, 0.26 + drift / 2), SIMD2(1, 0.5),
                                  SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)],
                         colors: [.clear, tint.opacity(0.2), .clear,
                                  .clear, tint.opacity(0.13), .clear,
                                  .clear, .clear, .clear])
        }
        .frame(height: 235)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

struct DayActivity: Identifiable {
    let id: String
    let title: String
    let amount: String
    let number: Double
    let spokenAmount: String
    let date: Date
    let clock: String
    let tint: Color
    let kind: RingKind

    /// Neueste zuerst; Schlaf zählt mit seinem Ende.
    static func entries(for day: DayMetrics) -> [Self] {
        var entries = day.workouts.map { workout in
            let load = ScoreEngine.strain(DayMetrics(date: day.date, activeEnergy: workout.energy, workouts: [workout]))
            return Self(id: workout.id.uuidString, title: workout.name, amount: String(load), number: Double(load),
                        spokenAmount: "Geschätzte Belastung \(load) von 100", date: workout.start,
                        clock: Format.clock(workout.start), tint: DashboardRing.tint(kind: .strain, value: load),
                        kind: .strain)
        }
        if let sleep = day.sleep, sleep.asleep > 0 {
            entries.append(Self(id: "sleep", title: "Schlaf", amount: RingDetailView.clock(sleep.asleep),
                                number: sleep.asleep,
                                spokenAmount: Format.duration(sleep.asleep), date: sleep.end,
                                clock: "\(Format.clock(sleep.start))–\(Format.clock(sleep.end))",
                                tint: Theme.sleep, kind: .sleep))
        }
        return entries.sorted { $0.date > $1.date }
    }
}
