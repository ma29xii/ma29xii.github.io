import SwiftUI

// Schlaue Today-Kacheln (F6-03, F6-04): nur echte Messwerte, fehlende bleiben fehlend.

private struct SmartAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.45)) { shown = true } }
            }
    }
}

private extension View {
    /// Weiches Einblenden beim ersten Erscheinen; bei „Bewegung reduzieren“ ohne Bewegung.
    func smartAppear() -> some View { modifier(SmartAppear()) }
}

extension IllnessSignal.Level {
    var tint: Color {
        switch self {
        case .normal: Theme.younger
        case .watch: Theme.warning
        case .fighting: Theme.older
        }
    }
}

extension IllnessSignal.Reading {
    var directionWord: String { isAboveNormal ? "erhöht" : "erniedrigt" }
    var valueText: String { Format.number(value, decimals: kind.decimals) + " " + kind.unit }
}

private struct SmartTileHeader: View {
    let title: String
    let icon: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        Label(title, systemImage: icon)
            .font(.formaCaptionStrong)
            .foregroundStyle(tint)
    }
}

// MARK: Körpersignale

struct BodySignalsTile: View {
    let snapshot: DashboardDay
    let history: [DayMetrics]

    var body: some View {
        let signal = IllnessSignal.evaluate(day: snapshot.day, history: snapshot.history)
        NavigationLink {
            BodySignalsDetail(snapshot: snapshot, history: history)
        } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    SmartTileHeader(title: "Körpersignale", icon: "thermometer.medium")
                    if let signal {
                        let tint = signal.level.tint
                        Text(signal.level.title)
                            .font(.formaSection)
                            .foregroundStyle(tint)
                        if !signal.flagged.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: Space.s2, alignment: .leading)],
                                      alignment: .leading, spacing: Space.s2) {
                                ForEach(signal.flagged, id: \.kind) { chip($0, tint: tint) }
                            }
                        }
                    } else {
                        Text("Keine Messung").font(.formaBody).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .smartAppear()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Körpersignale")
        .accessibilityValue(Self.spoken(signal))
        .accessibilityIdentifier("today.bodysignals")
    }

    private func chip(_ reading: IllnessSignal.Reading, tint: Color) -> some View {
        HStack(spacing: Space.s1) {
            Image(systemName: reading.isAboveNormal ? "arrow.up" : "arrow.down")
                .font(.system(.caption2, weight: .bold))
            Text(reading.kind.title).font(.formaMicro)
            Text(Format.number(reading.value, decimals: reading.kind.decimals))
                .font(.formaMicro.monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s1)
        .background(tint.opacity(0.16), in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
    }

    nonisolated static func spoken(_ signal: IllnessSignal?) -> String {
        guard let signal else { return "Keine Messung" }
        let flagged = signal.flagged.map { "\($0.kind.title) \($0.directionWord)" }
        return ([signal.level.title] + flagged).joined(separator: ", ")
    }
}

struct BodySignalsDetail: View {
    let snapshot: DashboardDay
    let history: [DayMetrics]

    var body: some View {
        let signal = IllnessSignal.evaluate(day: snapshot.day, history: snapshot.history)
        let trail = IllnessSignal.trail(endingAt: snapshot.day.date, history: history)
        InsightPage(title: "Körpersignale") {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s2) {
                    DashboardHeading(title: "Letzte Nacht")
                    if let signal {
                        Text(signal.level.title)
                            .font(.formaHeadline)
                            .foregroundStyle(signal.level.tint)
                    } else {
                        Text("Keine Messung").font(.formaBody).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            ForEach(IllnessSignal.Kind.allCases, id: \.self) { kind in
                readingCard(kind, reading: signal?.readings.first { $0.kind == kind }, level: signal?.level ?? .normal)
            }
            trailCard(trail)
        }
    }

    private func readingCard(_ kind: IllnessSignal.Kind, reading: IllnessSignal.Reading?,
                             level: IllnessSignal.Level) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Label(kind.title, systemImage: kind.symbol)
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Space.s2)
                    if let reading {
                        Text(reading.valueText)
                            .font(.formaValue)
                            .foregroundStyle(reading.isFlagged ? level.tint : Theme.textPrimary)
                    } else {
                        Text("Keine Messung").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
                if let reading {
                    let sd = reading.baseline.sd
                    let mean = reading.baseline.mean
                    MetricScale(value: reading.value, tint: reading.isFlagged ? level.tint : Theme.younger,
                                domain: (mean - 3 * sd)...(mean + 3 * sd), target: reading.range)
                        .frame(height: 28)
                        .accessibilityHidden(true)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue(reading.map {
            $0.valueText + ($0.isFlagged ? ", \($0.directionWord)" : ", im persönlichen Bereich")
        } ?? "Keine Messung")
    }

    private func trailCard(_ trail: [(date: Date, signal: IllnessSignal?)]) -> some View {
        let marked = trail.filter { ($0.signal?.level ?? .normal) != .normal }.count
        return DashboardCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                DashboardHeading(title: "14 Tage")
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(trail, id: \.date) { entry in
                        VStack(spacing: Space.s1) {
                            Capsule()
                                .fill(entry.signal.map { $0.flagged.isEmpty ? Theme.track : $0.level.tint } ?? Theme.track)
                                .frame(height: entry.signal.map { 6 + CGFloat($0.flagged.count) * 10 } ?? 3)
                                .frame(maxHeight: 50, alignment: .bottom)
                            Text(String(Format.shortWeekday(entry.date).prefix(2)))
                                .font(.formaMicro)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 70, alignment: .bottom)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verlauf der letzten 14 Tage")
        .accessibilityValue(marked == 0 ? "Keine Auffälligkeiten" : "\(marked) Tage mit Auffälligkeiten")
    }
}

// MARK: Bereit für

struct ReadinessTile: View {
    let snapshot: DashboardDay

    var body: some View {
        let illness = IllnessSignal.evaluate(day: snapshot.day, history: snapshot.history)?.level
        let advice = ReadinessAdvice.make(recovery: snapshot.recovery, illness: illness)
        NavigationLink(value: RingKind.strain) {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    SmartTileHeader(title: "Bereit für", icon: "figure.run")
                    if let advice {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            Text(advice.kind.title)
                                .font(.formaDisplay)
                                .foregroundStyle(advice.kind == .rest ? Theme.older : Theme.textPrimary)
                            Spacer(minLength: Space.s2)
                            Text("Strain \(advice.rangeText)")
                                .font(.formaCaptionStrong.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        MetricScale(value: snapshot.strain.map(Double.init), tint: Theme.strain,
                                    target: Double(advice.strain.lowerBound)...Double(advice.strain.upperBound))
                            .frame(height: 12)
                            .accessibilityHidden(true)
                    } else {
                        Text("Keine Messung").font(.formaBody).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .smartAppear()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bereit für")
        .accessibilityValue(advice.map { "\($0.kind.title), Strain \($0.rangeText)" } ?? "Keine Messung")
        .accessibilityIdentifier("today.readiness")
    }
}

// MARK: Schlafschuld

struct SleepDebtTile: View {
    @Environment(DataHub.self) private var hub
    let snapshot: DashboardDay

    var body: some View {
        let info = SleepDebtInfo.make(history: snapshot.history)
        let store = FoodSettings.store(isSample: hub.isSample)
        NavigationLink {
            SleepPlanView(store: store)
        } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    SmartTileHeader(title: "Schlafschuld", icon: "bed.double")
                    if let info {
                        let text = Self.debtText(info.debt)
                        Text(text).font(.formaDisplay).foregroundStyle(Theme.textPrimary)
                        MetricScale(value: info.debt, tint: info.debt >= 3600 ? Theme.older : Theme.sleep,
                                    domain: 0...(3 * 3600))
                            .frame(height: 12)
                            .accessibilityHidden(true)
                        if info.hasExtra {
                            TimelineView(.everyMinute) { context in
                                Text(Self.bedtimeLine(info: info, strain: snapshot.strain, store: store, now: context.date))
                                    .font(.formaCaptionStrong)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    } else {
                        Text("Keine Messung").font(.formaBody).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .smartAppear()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schlafschuld")
        .accessibilityValue(info.map { Self.debtText($0.debt) + ($0.hasExtra ? ", " + Self.earlierText($0) : "") }
                            ?? "Keine Messung")
        .accessibilityIdentifier("today.sleepdebt")
    }

    nonisolated static func debtText(_ debt: TimeInterval) -> String {
        debt < 15 * 60 ? "Keine Schuld" : "−\(RingDetailView.clock(debt)) h"
    }

    nonisolated static func earlierText(_ info: SleepDebtInfo) -> String {
        "Heute \(Format.duration(info.extraTonight)) früher ins Bett"
    }

    private static func bedtimeLine(info: SleepDebtInfo, strain: Int?, store: UserDefaults, now: Date) -> String {
        let need = ScoreEngine.sleepNeed(strain: strain ?? 0, debt: info.debt)
        let bed = SleepPlanner.load(in: store).nextWindow(after: now, sleepNeed: need)?.bed
        return earlierText(info) + (bed.map { " · \(Format.clock($0))" } ?? "")
    }
}

// MARK: Erholte Zeit

struct CalmTimeTile: View {
    let signals: DaySignals
    let history: [DayMetrics]

    var body: some View {
        let info = CalmTimeInfo.make(slots: signals.stressSlots)
        NavigationLink {
            StressDetail(signals: signals, history: history)
        } label: {
            DashboardCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    SmartTileHeader(title: "Erholte Zeit", icon: "leaf")
                    if let info {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            Text(Format.duration(info.calm))
                                .font(.formaNumber)
                                .foregroundStyle(StressZone.low.tint)
                            Spacer(minLength: Space.s2)
                            Text("gestresst \(Format.duration(info.stressed))")
                                .font(.formaCaptionStrong)
                                .foregroundStyle(info.stressed > 0 ? StressZone.high.tint : Theme.textSecondary)
                        }
                        zoneBar(info)
                            .frame(height: 10)
                            .accessibilityHidden(true)
                    } else {
                        Text("Keine Messung").font(.formaBody).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .smartAppear()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Erholte Zeit")
        .accessibilityValue(info.map { "\(Format.duration($0.calm)) ruhig, \(Format.duration($0.stressed)) gestresst" }
                            ?? "Keine Messung")
        .accessibilityIdentifier("today.calmtime")
    }

    /// Anteile der gemessenen Zeit; Lücken zählen nicht mit.
    private func zoneBar(_ info: CalmTimeInfo) -> some View {
        GeometryReader { proxy in
            let parts: [(TimeInterval, Color)] = [(info.calm, StressZone.low.tint),
                                                  (info.medium, StressZone.medium.tint),
                                                  (info.stressed, StressZone.high.tint)].filter { $0.0 > 0 }
            let usable = max(0, proxy.size.width - CGFloat(parts.count - 1) * 2)
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { index in
                    Capsule()
                        .fill(parts[index].1)
                        .frame(width: usable * parts[index].0 / info.measured)
                }
            }
        }
    }
}

// MARK: Serie

struct StreakTile: View {
    let today: Date
    let history: [DayMetrics]

    var body: some View {
        let streak = GoalStreak.current(endingAt: today, history: history)
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                SmartTileHeader(title: "Serie", icon: "flame")
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text("\(streak.days)")
                        .font(.formaDisplay)
                        .foregroundStyle(streak.days > 0 ? Theme.textPrimary : Theme.textSecondary)
                        .formaNumberTransition(Double(streak.days))
                    Text(streak.days == 1 ? "Tag" : "Tage")
                        .font(.formaBody)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Space.s2)
                    Label(streak.todayReached ? "Heute erreicht" : "Heute offen",
                          systemImage: streak.todayReached ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(streak.todayReached ? Theme.younger : Theme.textSecondary)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .smartAppear()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Serie")
        .accessibilityValue("\(streak.days) \(streak.days == 1 ? "Tag" : "Tage") in Folge, "
                            + (streak.todayReached ? "heute erreicht" : "heute noch offen"))
        .accessibilityIdentifier("today.streak")
    }
}
