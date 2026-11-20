import SwiftUI

struct TodayView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var ringEntrance = 0
    /// Gemessene Breite des Kopfs; der Recovery-Bogen richtet sich danach.
    @State private var headerWidth: CGFloat = 358

    var body: some View {
        let minute = Calendar.forma.dateInterval(of: .minute, for: .now)?.start ?? .now
        NavigationStack {
            TimelineView(.periodic(from: minute, by: 60)) { context in
                dashboard(at: context.date)
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .navigationDestination(for: RingKind.self) { kind in
                TodayRingPage(kind: kind)
            }
        }
        .onChange(of: app.selectedTab, initial: true) { _, tab in
            if tab == .today, !reduceMotion { ringEntrance += 1 }
        }
    }

    private func dashboard(at now: Date) -> some View {
        let today = now.startOfDay
        let recent = hub.days
        let day = recent.last { $0.date == today } ?? DayMetrics(date: today)
        let snapshot = DashboardDay(day: day, history: recent)
        let period = WeeklyInsight.displayPeriod(at: now)
        let hours = hub.isSample ? HourlyMetrics.samples(for: day) : hub.hours
        let signals = DaySignals(day: day, hours: hours, history: snapshot.history)

        return ScrollView {
            VStack(alignment: .leading, spacing: Space.gap) {
                sourceStatus
                header(snapshot)
                    .id(ringEntrance)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { headerWidth = $0 }
                    .contextMenu {
                        Button("Aktualisieren", systemImage: "arrow.clockwise") {
                            Task { await hub.refresh() }
                        }
                    }
                    .padding(.bottom, Space.s2)
                InlineTileStack<TodayTile, AnyView>(storageKey: "forma.tiles.today.v2") { kind in
                    tile(kind, snapshot: snapshot, recent: recent, hours: hours, signals: signals, period: period)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: period)
            .padding(.horizontal, Space.page)
            .padding(.top, Space.s2)
            .padding(.bottom, Space.s6)
        }
        .refreshable { await hub.refresh() }
        .formaScreen(tint: snapshot.recovery.map(Theme.recovery))
    }

    // MARK: Karten

    private func tile(_ kind: TodayTile, snapshot: DashboardDay, recent: [DayMetrics], hours: [HourlyMetrics],
                      signals: DaySignals, period: WeeklyInsight.Period?) -> AnyView {
        switch kind {
        case .coach:
            return AnyView(coachLine(snapshot))
        case .healthMonitor:
            return AnyView(HealthMonitor(snapshot: snapshot))
        case .stress:
            return AnyView(StressMonitorCard(signals: signals, history: hub.dashboardHistory(recent: recent)))
        case .energy:
            return AnyView(EnergyTile(signals: signals))
        case .food:
            return AnyView(TodayFoodCard(day: snapshot.day).foodSettingsStore().id(hub.isSample))
        case .weekly:
            // Nur im Zeitfenster Sonntagabend bis Montagmittag; sonst nimmt die Karte keinen Platz ein.
            guard let period else { return AnyView(EmptyView()) }
            return AnyView(WeeklyRecapLink(period: period).transition(.opacity))
        case .metrics:
            return AnyView(steps(snapshot, hours: hours))
        case .sleepPlan:
            return AnyView(SleepPlanCard())
        case .hydration:
            return AnyView(TodayWaterCard(day: snapshot.day.date).foodSettingsStore().id(hub.isSample))
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
        let stacked = Self.stacksHeader(width: headerWidth, largeText: typeSize >= .xxLarge)
        let debt = snapshot.day.sleep == nil ? nil : Self.debtNote(ScoreEngine.sleepDebt(history: snapshot.history))
        let strain = side(.strain, snapshot, band: snapshot.recovery.map { ScoreEngine.target(recovery: $0) },
                          note: nil, delay: 0.08)
        let recovery = gauge(.recovery, snapshot) {
            DashboardRing(kind: .recovery, value: snapshot.recovery,
                          size: stacked ? min(184, headerWidth) : Self.recoverySize(width: headerWidth))
        }
        let sleep = side(.sleep, snapshot, band: nil, note: debt, delay: 0.16)
        if stacked {
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
                recovery.frame(width: Self.recoverySize(width: headerWidth))
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

    /// Native Navigation behält den Zustand auch während einer Synchronisierung.
    private func gauge<Content: View>(_ kind: RingKind, _ snapshot: DashboardDay,
                                      @ViewBuilder label: () -> Content) -> some View {
        NavigationLink(value: kind) {
            label()
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityValue(DashboardRing.spokenValue(kind: kind, value: snapshot.value(for: kind)))
        .accessibilityHint("Öffnet die Details")
        .accessibilityIdentifier("ring." + kind.rawValue)
    }

    /// Zwei Zeilen (Recovery oben, Kapseln darunter), sobald nebeneinander keine 80 pt je Kapsel bleiben
    /// oder die Schrift groß ist. 292 = Mindestbogen 132 + 2 × 80.
    nonisolated static func stacksHeader(width: CGFloat, largeText: Bool) -> Bool {
        largeText || width < 132 + 2 * 80
    }

    /// Recovery bleibt die Hauptsache: bis 184 pt, links und rechts aber immer 80 pt für die Kapseln.
    nonisolated static func recoverySize(width: CGFloat) -> CGFloat {
        min(184, max(132, width - 2 * 80))
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

    // MARK: Schritte

    /// Schritte als Halbkreis aus Strichen: gefüllt bis zum Tagesziel vom Coach; ohne Ziel nur der Wert.
    private func steps(_ snapshot: DashboardDay, hours: [HourlyMetrics]) -> some View {
        let goal = hub.stepGoalToday
        let value = snapshot.day.steps
        return NavigationLink {
            StepsDetail(snapshot: snapshot, hours: hours)
        } label: {
            DashboardCard {
                VStack(spacing: Space.s2) {
                    DashboardHeading(title: "Schritte")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack(alignment: .bottom) {
                        StepArcView(fraction: Self.stepFraction(steps: value, goal: goal))
                            .frame(width: 220, height: 110)
                        VStack(spacing: 0) {
                            Text(value.map { Format.number($0) } ?? "–")
                                .font(.formaDisplay)
                                .foregroundStyle(value == nil ? Theme.textSecondary : Theme.textPrimary)
                                .formaNumberTransition(value ?? 0)
                            if let goal {
                                Text("von \(Format.number(Double(goal)))")
                                    .font(.formaCaption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(Space.s4)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Schritte")
        .accessibilityValue(Self.spokenSteps(steps: value, goal: goal))
        .accessibilityIdentifier("today.steps")
    }

    /// Anteil am Ziel; ohne Ziel oder ohne Messung kein Fortschritt.
    nonisolated static func stepFraction(steps: Double?, goal: Int?) -> Double {
        guard let steps, let goal, goal > 0 else { return 0 }
        return max(0, steps / Double(goal))
    }

    nonisolated static func spokenSteps(steps: Double?, goal: Int?) -> String {
        guard let steps else { return "Keine Messung" }
        let value = Format.number(steps)
        return goal.map { "\(value) von \(Format.number(Double($0)))" } ?? value
    }
}

/// Strich-Halbkreis mit Hochzählen beim Erscheinen.
private struct StepArcView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0
    let fraction: Double

    var body: some View {
        TickArc(fraction: shown, color: Theme.strain)
            .onChange(of: fraction, initial: true) { _, latest in
                withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.85)) { shown = latest }
            }
            .accessibilityHidden(true)
    }
}

private struct TodayRingPage: View {
    @Environment(DataHub.self) private var hub
    let kind: RingKind

    var body: some View {
        let today = Date.now.startOfDay
        let recent = hub.days
        let day = recent.last { $0.date == today } ?? DayMetrics(date: today)
        let snapshot = DashboardDay(day: day, history: recent)
        RingDetailView(kind: kind, snapshot: snapshot, history: hub.dashboardHistory(recent: recent))
    }
}
