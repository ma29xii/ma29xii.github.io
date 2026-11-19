import Combine
import SwiftUI

struct TodayView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var zoomSpace
    @State private var compact = false

    var body: some View {
        let minute = Calendar.forma.dateInterval(of: .minute, for: .now)?.start ?? .now
        TimelineView(.periodic(from: minute, by: 60)) { context in
            dashboard(at: context.date)
        }
    }

    private func dashboard(at now: Date) -> some View {
        let today = now.startOfDay
        let history = hub.dashboardHistory(recent: hub.days)
        let day = hub.days.first { $0.date == today } ?? DayMetrics(date: today)
        let snapshot = DashboardDay(day: day, history: history)
        let period = WeeklyInsight.period(at: now)
        let stress = stressSlots(snapshot)

        return NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.gap) {
                        sourceStatus
                        header(snapshot)
                            .id(Self.top)
                            .padding(.bottom, Space.s2)
                        // Bearbeiten direkt hier: „Anpassen“ steht unter der letzten Karte.
                        InlineTileStack<TodayTile, AnyView>(storageKey: "forma.tiles.today.v2") { kind in
                            tile(kind, snapshot: snapshot, history: history, stress: stress, period: period)
                        }
                        updateFooter
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: period)
                    .padding(.horizontal, Space.page)
                    .padding(.top, Space.s2)
                    .padding(.bottom, Space.s6)
                }
                .refreshable { await hub.refresh() }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > Self.compactOffset
                } action: { _, isCompact in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { compact = isCompact }
                }
                .overlay(alignment: .top) {
                    if compact {
                        compactBar(snapshot) {
                            withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(Self.top, anchor: .top) }
                        }
                        .transition(.opacity)
                    }
                }
            }
            .background(alignment: .top) {
                if let recovery = snapshot.recovery {
                    TodayRecoveryGlow(recovery: recovery)
                }
            }
            .dashboardScreen()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .navigationDestination(for: RingRoute.self) { route in
                InsightPage(title: route.kind.title) {
                    RingDetailView(kind: route.kind, snapshot: snapshot, history: history)
                }
                // Teilen sitzt bewusst im Detail statt auf Today, damit der Kopf ruhig bleibt.
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareCardButton { .today(snapshot, isSample: hub.isSample) }
                    }
                }
                .todayZoom(route.zoom && !reduceMotion ? route.kind : nil, in: zoomSpace)
            }
        }
    }

    private static let top = "today.top"
    /// Ab hier ist der Kopf größtenteils aus dem Bild; die Kompaktleiste übernimmt.
    static let compactOffset: CGFloat = 220

    // MARK: Karten

    private func tile(_ kind: TodayTile, snapshot: DashboardDay, history: [DayMetrics],
                      stress: (slots: [StressSlot], energy: Int?), period: WeeklyInsight.Period?) -> AnyView {
        switch kind {
        case .coach:
            return AnyView(coachLine(snapshot))
        case .healthMonitor:
            return AnyView(HealthMonitor(snapshot: snapshot))
        case .stress:
            return AnyView(StressMonitorCard(day: snapshot.day, slots: stress.slots, energy: stress.energy,
                                             isLoading: false, history: history))
        case .weekly:
            // Nur im Zeitfenster Sonntagabend bis Montagmittag; sonst nimmt die Karte keinen Platz ein.
            guard let period else { return AnyView(EmptyView()) }
            return AnyView(WeeklyRecapLink(period: period).transition(.opacity))
        case .activities:
            return AnyView(activities(snapshot.day))
        case .metrics:
            return AnyView(comparison(snapshot, history: history))
        }
    }

    // MARK: Status

    @ViewBuilder private var sourceStatus: some View {
        if hub.isSample {
            SampleDataBadge()
        } else if let status = hub.todayDataNotice {
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
        }
    }

    /// Leise Fußzeile ganz unten: Oben stehen nur die Anzeigen.
    @ViewBuilder private var updateFooter: some View {
        if !hub.isSample, hub.todayDataNotice == nil, let updated = hub.lastUpdate {
            Text(Calendar.forma.isDateInToday(updated) ? "Abgerufen um \(Format.clock(updated))"
                 : "Abgerufen am \(Format.shortDate(updated))")
                .font(.formaCaption)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    nonisolated static func hasAnyMeasurement(_ day: DayMetrics) -> Bool {
        day.steps != nil || day.sleep != nil || day.hrv != nil || day.restingHR != nil
            || day.activeEnergy != nil || day.respiratoryRate != nil || day.spo2 != nil
            || day.skinTemperature != nil || day.vo2max != nil || !day.workouts.isEmpty
    }

    /// Schlafschuld als kurze Zeile unter der Schlaf-Kapsel, erst ab 15 Minuten.
    /// Kurz und einzeilig unter SLEEP, z. B. „−1:19 h“; VoiceOver liest die Langform.
    nonisolated static func debtNote(_ debt: TimeInterval) -> String? {
        debt >= 15 * 60 ? "−\(RingDetailView.clock(debt)) h" : nil
    }

    // MARK: Kopf

    /// Recovery groß in der Mitte, Strain und Sleep als Kapseln daneben, etwas tiefer gesetzt.
    /// Bei großer Schrift steht Recovery allein oben und die Kapseln darunter, statt alles zu stauchen.
    @ViewBuilder private func header(_ snapshot: DashboardDay) -> some View {
        let debt = snapshot.day.sleep == nil ? nil : Self.debtNote(ScoreEngine.sleepDebt(history: snapshot.history))
        let strain = side(.strain, snapshot, band: snapshot.recovery.map { ScoreEngine.target(recovery: $0) },
                          note: nil, delay: 0.08)
        let recovery = gauge(.recovery, snapshot) {
            DashboardRing(kind: .recovery, value: snapshot.recovery, size: 184)
        }
        let sleep = side(.sleep, snapshot, band: nil, note: debt, delay: 0.16)
        if typeSize >= .xxLarge {
            VStack(spacing: Space.s4) {
                recovery
                HStack(alignment: .top, spacing: Space.s4) {
                    strain
                    sleep
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .top, spacing: 0) {
                strain
                recovery.frame(width: 184)
                sleep
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func side(_ kind: RingKind, _ snapshot: DashboardDay, band: ClosedRange<Int>?, note: String?,
                      delay: Double) -> some View {
        gauge(kind, snapshot) {
            VStack(spacing: Space.s2) {
                DashboardRing(kind: kind, value: snapshot.value(for: kind), size: 104, band: band, delay: delay)
                Text(kind.title)
                    .font(.formaLabel)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let note {
                    Text(note)
                        .font(.formaMicro)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.top, typeSize >= .xxLarge ? 0 : Space.s5)
        }
        .frame(maxWidth: .infinity)
    }

    /// Antippbare Anzeige: öffnet die Detailseite per Push und zoomt aus genau dieser Form.
    private func gauge<Content: View>(_ kind: RingKind, _ snapshot: DashboardDay,
                                      @ViewBuilder label: () -> Content) -> some View {
        NavigationLink(value: RingRoute(kind: kind, zoom: true)) {
            label()
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: kind, in: zoomSpace) { source in
            source.background(.clear).clipShape(RoundedRectangle(cornerRadius: Radius.plate, style: .continuous))
        }
        .accessibilityLabel(kind.title)
        .accessibilityValue(DashboardRing.spokenValue(kind: kind, value: snapshot.value(for: kind)))
        .accessibilityHint("Öffnet die Details")
        .accessibilityIdentifier("ring." + kind.rawValue)
    }

    /// Ruhige Leiste, sobald der Kopf weggescrollt ist. Tippen springt zurück nach oben.
    private func compactBar(_ snapshot: DashboardDay, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s4) {
                ForEach([RingKind.strain, .recovery, .sleep]) { kind in
                    HStack(spacing: Space.s1) {
                        Circle()
                            .fill(DashboardRing.tint(kind: kind, value: snapshot.value(for: kind)))
                            .frame(width: 6, height: 6)
                        Text(kind.title)
                            .font(.formaMicro)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.textSecondary)
                        Text(snapshot.value(for: kind).map(String.init) ?? "–")
                            .font(.formaValue)
                            .formaNumberTransition(Double(snapshot.value(for: kind) ?? 0))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            Theme.backgroundTop.ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tageswerte")
        .accessibilityValue([RingKind.recovery, .strain, .sleep]
            .map { "\($0.title) \(DashboardRing.spokenValue(kind: $0, value: snapshot.value(for: $0)))" }
            .joined(separator: ", "))
        .accessibilityHint("Springt nach oben")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("today.compact")
    }

    // MARK: Coach-Zeile

    private func coachLine(_ snapshot: DashboardDay) -> some View {
        let sentence = TodayInsight.sentence(for: snapshot)
        return Button {
            app.openCoach(with: "Was bedeutet das für meinen Tag? \(sentence)")
        } label: {
            // Gleiche Kartenform wie alle anderen: eine Form-Sprache auf dem ganzen Bildschirm.
            DashboardCard {
                HStack(spacing: Space.s3) {
                    Image(systemName: "sparkle")
                        .font(.body.weight(.medium))
                        .foregroundStyle(DashboardRing.tint(kind: .recovery, value: snapshot.recovery))
                    Text(sentence)
                        .font(.system(.body))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(Space.s4)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Coach")
        .accessibilityValue(sentence)
        .accessibilityHint("Öffnet den Coach")
        .accessibilityIdentifier("today.insight")
    }

    // MARK: Stress

    private func stressSlots(_ snapshot: DashboardDay) -> (slots: [StressSlot], energy: Int?) {
        let hours: [HourlyMetrics] = hub.isSample ? HourlyMetrics.samples(for: snapshot.day) : hub.hours
        let estimates = HourlyEstimate.timeline(hours: hours, today: snapshot.day, history: snapshot.history)
        let slots = zip(hours, estimates).map { hour, estimate in
            StressSlot(start: hour.start, end: hour.end, value: estimate.stress)
        }
        return (slots, estimates.compactMap(\.energy).last)
    }

    // MARK: Kennzahlen

    private func comparison(_ snapshot: DashboardDay, history: [DayMetrics]) -> some View {
        let hours: [HourlyMetrics] = hub.isSample ? HourlyMetrics.samples(for: snapshot.day) : hub.hours
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
                detailRow(.recovery, id: "today.metric.hrv") {
                    ComparisonRow(title: "HRV", icon: "waveform.path.ecg", value: snapshot.day.hrv,
                                  baseline: snapshot.baseline { $0.hrv }?.mean, format: MetricKind.hrv.measurement,
                                  showsChevron: true)
                }
                RowDivider()
                detailRow(.sleep, id: "today.metric.sleep") {
                    ComparisonRow(title: "Schlafleistung", icon: "moon", value: snapshot.sleepScore.map(Double.init),
                                  baseline: sleepAverage, format: { Format.number($0) + " %" }, showsChevron: true)
                }
                RowDivider()
                detailRow(.strain, id: "today.metric.energy") {
                    ComparisonRow(title: "Aktive Kalorien", icon: "flame", value: snapshot.day.activeEnergy,
                                  baseline: snapshot.baseline { $0.activeEnergy }?.mean,
                                  format: MetricKind.activeEnergy.measurement, showsChevron: true)
                }
            }
            ComparisonFooter()
        }
    }

    /// Zeile, die die Detailseite des passenden Werts öffnet (ohne Zoom, der gehört dem Kopf).
    private func detailRow<Row: View>(_ kind: RingKind, id: String, @ViewBuilder label: () -> Row) -> some View {
        NavigationLink(value: RingRoute(kind: kind)) { label() }
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
                    NavigationLink(value: RingRoute(kind: entry.kind)) { activityRow(entry) }
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

private extension View {
    /// Zoom nur, wenn die Seite aus dem Kopf geöffnet wurde und Bewegung erlaubt ist.
    @ViewBuilder func todayZoom(_ source: RingKind?, in space: Namespace.ID) -> some View {
        if let source {
            navigationTransition(.zoom(sourceID: source, in: space))
        } else {
            self
        }
    }
}

private struct TodayRecoveryGlow: View {
    let recovery: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var visible = false

    var body: some View {
        let calm = reduceMotion || scenePhase != .active || lowPower || !visible
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
        .onAppear { visible = true }
        .onDisappear { visible = false }
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
