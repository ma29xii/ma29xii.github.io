import SwiftUI

struct RingDetailView: View {
    let kind: RingKind
    let snapshot: DashboardDay
    let history: [DayMetrics]

    private var day: DayMetrics { snapshot.day }

    var body: some View {
        let value = snapshot.value(for: kind)
        let tint = DashboardRing.tint(kind: kind, value: value)

        VStack(alignment: .leading, spacing: Space.gap) {
            VStack(spacing: Space.s2) {
                DashboardRing(kind: kind, value: value, size: kind == .recovery ? 220 : 168, expanded: true,
                              band: kind == .strain ? snapshot.recovery.map { ScoreEngine.target(recovery: $0) } : nil)
                    .accessibilityIdentifier("ring.detail." + kind.rawValue)
                Text(value == nil ? "Keine Messung" : Format.dayTitle(day.date))
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s3)

            if kind == .sleep, let night = day.sleep, let need = snapshot.sleepNeed {
                sleepSummary(night: night, need: need)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                DashboardHeading(title: "Beiträge")
                DashboardCard {
                    switch kind {
                    case .sleep: sleepContributions
                    case .recovery: recoveryContributions
                    case .strain: strainContributions
                    }
                }
                ComparisonFooter()
            }
            DashboardCard {
                Text(interpretation(value))
                    .font(.formaBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s4)
            }
            .accessibilityIdentifier("ring.detail.summary")
            if kind == .sleep {
                SleepConsistencyLink(end: day.date, history: history)
            } else if kind == .strain {
                StrainPathLink(end: InsightHistory.lastCompletedDay(for: day.date), history: history)
            }
            if kind == .sleep, let night = day.sleep, night.asleep > 0 {
                sleepPhases(night)
            }
            RingTrendChart(kind: kind, anchor: day.date, days: history, color: tint)
        }
    }

    private var sleepContributions: some View {
        let night = day.sleep.flatMap { $0.asleep > 0 ? $0 : nil }
        let ratio = night.flatMap { night in snapshot.sleepNeed.map { night.asleep / $0 } }
        return Group {
            row("Stunden vs. Bedarf", icon: "moon", value: ratio,
                baseline: sleepBaseline { night, prior in night.asleep / ScoreEngine.sleepNeedForLastNight(history: prior) },
                format: percent)
            RowDivider()
            row("Regelmäßigkeit", icon: "clock", value: snapshot.sleepRegularity,
                baseline: sleepBaseline { DashboardDay.sleepRegularity($0, history: $1) }, format: percent)
            RowDivider()
            row("Effizienz", icon: "bed.double", value: night?.efficiency,
                baseline: sleepBaseline { night, _ in night.efficiency }, format: percent)
            RowDivider()
            row("Tief- und REM-Anteil", icon: "moon.stars", value: night.flatMap(DashboardDay.restorativeFraction),
                baseline: sleepBaseline { night, _ in DashboardDay.restorativeFraction(night) }, format: percent)
        }
    }

    private var recoveryContributions: some View {
        let sleepAverage = DashboardTrends.mean(points: DashboardTrends.points(
            kind: .sleep, days: history, domain: day.date.adding(days: -30)...day.date.adding(days: -1)))
        return Group {
            metric(.hrv, icon: "waveform.path.ecg")
            RowDivider()
            metric(.restingHR, icon: "heart")
            RowDivider()
            metric(.respiratoryRate, icon: "lungs")
            RowDivider()
            row("Schlafleistung", icon: "moon", value: snapshot.sleepScore.map(Double.init),
                baseline: sleepAverage, format: { Format.number($0) + " %" })
        }
    }

    private var strainContributions: some View {
        Group {
            row("Trainingszeit", icon: "stopwatch", value: DashboardDay.workoutTime(day),
                baseline: snapshot.baseline { DashboardDay.workoutTime($0) }?.mean, format: Format.duration)
            RowDivider()
            row("Krafttraining", icon: "dumbbell", value: DashboardDay.workoutTime(day, strengthOnly: true),
                baseline: snapshot.baseline { DashboardDay.workoutTime($0, strengthOnly: true) }?.mean, format: Format.duration)
            RowDivider()
            metric(.steps, icon: "figure.walk")
            RowDivider()
            metric(.activeEnergy, icon: "flame")
        }
    }

    private func sleepBaseline(_ value: (SleepNight, [DayMetrics]) -> Double?) -> Double? {
        let values = snapshot.history.compactMap { historical -> Double? in
            guard let night = historical.sleep, night.asleep > 0 else { return nil }
            let start = historical.date.adding(days: -30)
            let prior = history.filter { $0.date >= start && $0.date < historical.date }
            return value(night, prior)
        }
        return ScoreEngine.baseline(values)?.mean
    }

    private func metric(_ kind: MetricKind, icon: String) -> some View {
        row(kind.title, icon: icon, value: kind.value(day),
            baseline: snapshot.baseline(kind.value)?.mean, format: kind.measurement)
    }

    private func row(_ title: String, icon: String, value: Double?, baseline: Double?,
                     format: @escaping (Double) -> String) -> some View {
        ComparisonRow(title: title, icon: icon, value: value, baseline: baseline, format: format)
    }

    private func percent(_ fraction: Double) -> String { Format.number(fraction * 100) + " %" }

    /// „6:08“ für Kapseln (Stunden:Minuten).
    nonisolated static func clock(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    private func sleepSummary(night: SleepNight, need: TimeInterval) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s2) {
                sleepPill("Schlafstunden", value: night.asleep, tint: Theme.sleep)
                    .fixedSize(horizontal: true, vertical: false)
                sleepPill("Schlafbedarf", value: need, tint: Theme.younger)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                sleepPill("Schlafstunden", value: night.asleep, tint: Theme.sleep)
                sleepPill("Schlafbedarf", value: need, tint: Theme.younger)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sleepPill(_ title: String, value: TimeInterval, tint: Color) -> some View {
        VStack(spacing: Space.s1) {
            Text(Self.clock(value)).font(.formaBigNumber).foregroundStyle(tint)
                .formaNumberTransition(value)
            Text(title).font(.formaMicro).textCase(.uppercase).tracking(Tracking.micro)
        }
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay { Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Format.duration(value))
    }

    private func interpretation(_ value: Int?) -> String {
        guard let value else { return "Für diesen Tag fehlen die Daten für eine Einordnung." }
        switch kind {
        case .sleep:
            guard let night = day.sleep, let need = snapshot.sleepNeed else { return "Für diese Nacht liegt eine Schlafmessung vor." }
            return night.asleep < need ? "Du hast kürzer als dein geschätzter Bedarf geschlafen."
                : "Deine Schlafdauer hat den geschätzten Bedarf erreicht."
        case .recovery:
            return "Deine Messwerte deuten darauf hin, dass du \(Theme.recoveryWord(value).lowercased()) bist."
        case .strain:
            if value < 35 { return "Deine aufgezeichnete Tagesbelastung war niedrig." }
            if value < 67 { return "Deine aufgezeichnete Tagesbelastung war mittel." }
            return "Deine aufgezeichnete Tagesbelastung war hoch."
        }
    }

    private func sleepPhases(_ night: SleepNight) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Schlafphasen")
            DashboardCard {
                SleepTimeline(night: night).padding(Space.s4)
                RowDivider(inset: 0)
                if night.hasStages {
                    ForEach(night.recordedStages, id: \.self) { stage in
                        phase(stage, night: night)
                        if stage != night.recordedStages.last { RowDivider() }
                    }
                } else {
                    DashboardEmpty(title: "Schlafphasen wurden nicht erfasst")
                }
            }
            if night.hasStages {
                Text("Anteil an der aufgezeichneten Zeit im Bett")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func phase(_ stage: SleepNight.Stage, night: SleepNight) -> some View {
        let duration = night.total(stage)
        let fraction = min(1, duration / max(1, night.inBed))
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(stage.title).font(.formaCaptionStrong).textCase(.uppercase)
                Spacer(minLength: Space.s2)
                Text("\(percent(fraction)) · \(Format.duration(duration))")
                    .font(.formaValue)
                    .multilineTextAlignment(.trailing)
                    .formaNumberTransition(duration)
            }
            ProgressLine(fraction: fraction, color: Theme.sleep.opacity(stage == .awake ? 0.55 : 1), height: 5)
                .accessibilityHidden(true)
        }
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
    }
}

private struct SleepTimeline: View {
    let night: SleepNight
    @ScaledMetric(relativeTo: .caption) private var laneHeight = 26.0

    var body: some View {
        let stages: [SleepNight.Stage] = night.hasStages ? night.recordedStages : [.awake, .unspecified]
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(stages, id: \.self) { stage in
                        Text(stage == .unspecified ? "Schlaf" : stage.title)
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxHeight: .infinity)
                    }
                }
                Canvas { context, size in
                    let lane = size.height / CGFloat(stages.count)
                    for (index, stage) in stages.enumerated() {
                        let y = lane * CGFloat(index)
                        context.fill(Path(CGRect(x: 0, y: y + lane / 2, width: size.width, height: 1)),
                                     with: .color(Theme.hairline))
                        for segment in night.segments where segment.stage == stage
                            || (!night.hasStages && stage == .unspecified && segment.stage != .awake) {
                            let lo = max(0, segment.start.timeIntervalSince(night.start))
                            let hi = min(night.inBed, segment.end.timeIntervalSince(night.start))
                            guard night.inBed > 0, hi > lo else { continue }
                            let rect = CGRect(x: size.width * lo / night.inBed, y: y + lane / 4,
                                              width: size.width * (hi - lo) / night.inBed, height: lane / 2)
                            context.fill(Path(roundedRect: rect, cornerRadius: 2),
                                         with: .color(Theme.sleep.opacity(stage == .awake ? 0.45 : 0.9)))
                        }
                    }
                }
            }
            .frame(height: CGFloat(stages.count) * laneHeight)
            HStack {
                Text(Format.clock(night.start))
                    .formaNumberTransition(night.start.timeIntervalSinceReferenceDate)
                Spacer()
                Text(Format.clock(night.end))
                    .formaNumberTransition(night.end.timeIntervalSinceReferenceDate)
            }
            .font(.formaCaption).monospacedDigit().foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schlaf von \(Format.clock(night.start)) bis \(Format.clock(night.end))")
    }
}
