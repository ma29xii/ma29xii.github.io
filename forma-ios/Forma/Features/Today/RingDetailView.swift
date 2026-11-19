import SwiftUI

struct RingDetailView: View {
    let kind: RingKind
    let snapshot: DashboardDay
    let history: [DayMetrics]

    private var day: DayMetrics { snapshot.day }

    var body: some View {
        let value = snapshot.value(for: kind)
        let tint = DashboardRing.tint(kind: kind, value: value)
        let target = kind == .strain ? Self.strainTarget(strain: value, recovery: snapshot.recovery) : nil

        VStack(alignment: .leading, spacing: Space.gap) {
            VStack(spacing: Space.s2) {
                hero(value: value, tint: tint, target: target?.range)
                    .accessibilityIdentifier("ring.detail." + kind.rawValue)
                if let target {
                    Text("Ziel \(target.range.lowerBound)–\(target.range.upperBound)")
                        .font(.formaCaptionStrong.monospacedDigit())
                        .foregroundStyle(tint)
                        .accessibilityLabel("Tagesziel")
                        .accessibilityValue("\(target.range.lowerBound) bis \(target.range.upperBound), \(target.status)")
                        .accessibilityIdentifier("strain.target")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s3)

            // Die gemessene Dauer steht immer da; der Bedarf nur, wenn er aus Messungen berechnet werden kann.
            if kind == .sleep, let night = day.sleep, night.asleep > 0 {
                sleepSummary(night: night, need: snapshot.sleepNeed)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                DashboardHeading(title: "Beiträge")
                DashboardCard {
                    switch kind {
                    case .sleep: sleepContributions(tint: tint)
                    case .recovery: recoveryContributions(tint: tint)
                    case .strain: strainContributions(tint: tint)
                    }
                }
            }
            if kind == .sleep {
                RingSleepConsistency(end: day.date, history: history)
            } else if kind == .strain {
                RingStrainPath(end: InsightHistory.lastCompletedDay(for: day.date), history: history, tint: tint)
            }
            if kind == .sleep, let night = day.sleep, night.asleep > 0 {
                sleepPhases(night)
            }
            RingTrendChart(kind: kind, anchor: day.date, days: history, color: tint)
        }
    }

    @ViewBuilder
    private func hero(value: Int?, tint: Color, target: ClosedRange<Int>?) -> some View {
        if kind == .recovery {
            DashboardRing(kind: kind, value: value, size: 220, expanded: true)
        } else {
            VStack(spacing: Space.s2) {
                Text(value.map { kind == .sleep ? "\($0)%" : "\($0)" } ?? "–")
                    .font(.formaDisplay)
                    .foregroundStyle(value == nil ? Theme.textSecondary : Theme.textPrimary)
                    .formaNumberTransition(Double(value ?? 0))
                MetricScale(value: value.map(Double.init), tint: tint, axis: .vertical,
                            target: target.map { Double($0.lowerBound)...Double($0.upperBound) })
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s4)
                    .frame(width: 96, height: 148)
                    .background(tint.opacity(0.08), in: Capsule())
                    .overlay { Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1) }
                Text(kind.title).formaLabelStyle()
                if value == nil {
                    Text("Keine Messung")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind.title)
            .accessibilityValue(DashboardRing.spokenValue(kind: kind, value: value))
        }
    }

    private func sleepContributions(tint: Color) -> some View {
        let night = day.sleep.flatMap { $0.asleep > 0 ? $0 : nil }
        let ratio = night.flatMap { night in snapshot.sleepNeed.map { night.asleep / $0 } }
        return Group {
            row("Stunden vs. Bedarf", icon: "moon", value: ratio, tint: tint, format: percent)
            RowDivider()
            row("Regelmäßigkeit", icon: "clock", value: snapshot.sleepRegularity, tint: tint, format: percent)
            RowDivider()
            row("Effizienz", icon: "bed.double", value: night?.efficiency, tint: tint, format: percent)
            RowDivider()
            row("Tief- und REM-Anteil", icon: "moon.stars", value: night.flatMap(DashboardDay.restorativeFraction),
                tint: tint, format: percent)
        }
    }

    private func recoveryContributions(tint: Color) -> some View {
        Group {
            metric(.hrv, icon: "waveform.path.ecg", tint: tint)
            RowDivider()
            metric(.restingHR, icon: "heart", tint: tint)
            RowDivider()
            metric(.respiratoryRate, icon: "lungs", tint: tint)
            RowDivider()
            row("Schlafleistung", icon: "moon", value: snapshot.sleepScore.map(Double.init),
                tint: tint, format: { Format.number($0) + " %" })
        }
    }

    private func strainContributions(tint: Color) -> some View {
        Group {
            row("Trainingszeit", icon: "stopwatch", value: DashboardDay.workoutTime(day),
                tint: tint, format: Format.duration)
            RowDivider()
            row("Krafttraining", icon: "dumbbell", value: DashboardDay.workoutTime(day, strengthOnly: true),
                tint: tint, format: Format.duration)
            RowDivider()
            metric(.steps, icon: "figure.walk", tint: tint)
            RowDivider()
            metric(.activeEnergy, icon: "flame", tint: tint)
        }
    }

    private func metric(_ kind: MetricKind, icon: String, tint: Color) -> some View {
        row(kind.title, icon: icon, value: kind.value(day), tint: tint, format: kind.measurement)
    }

    private func row(_ title: String, icon: String, value: Double?, tint: Color,
                     format: (Double) -> String) -> some View {
        let text = value.map(format) ?? "Keine Messung"
        return HStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(value == nil ? Theme.textSecondary : tint)
                .frame(minWidth: 20)
                .accessibilityHidden(true)
            Text(title)
                .formaLabelStyle()
                .layoutPriority(1)
            Spacer(minLength: Space.s1)
            Text(text)
                .font(value == nil ? .formaCaption : .formaValue)
                .foregroundStyle(value == nil ? Theme.textSecondary : Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .formaNumberTransition(value ?? 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(text)
    }

    private func percent(_ fraction: Double) -> String { Format.number(fraction * 100) + " %" }

    /// Tagesziel für Strain aus der heutigen Recovery; ohne gültige Recovery gibt es kein Ziel.
    nonisolated static func strainTarget(strain: Int?, recovery: Int?) -> (range: ClosedRange<Int>, status: String)? {
        guard let recovery else { return nil }
        let range = ScoreEngine.target(recovery: recovery)
        guard let strain else { return (range, "Noch keine Belastung") }
        if strain < range.lowerBound { return (range, "Unter dem Ziel") }
        if strain > range.upperBound { return (range, "Über dem Ziel") }
        return (range, "Im Ziel")
    }

    /// „6:08“ für Kapseln (Stunden:Minuten).
    nonisolated static func clock(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    private func sleepSummary(night: SleepNight, need: TimeInterval?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s2) {
                sleepPill("Schlafstunden", value: night.asleep, tint: Theme.sleep)
                    .fixedSize(horizontal: true, vertical: false)
                if let need {
                    sleepPill("Schlafbedarf", value: need, tint: Theme.textSecondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                sleepPill("Schlafstunden", value: night.asleep, tint: Theme.sleep)
                if let need { sleepPill("Schlafbedarf", value: need, tint: Theme.textSecondary) }
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
            MetricScale(value: fraction * 100, tint: Theme.sleep.opacity(stage == .awake ? 0.55 : 1))
                .frame(height: Space.s3)
                .accessibilityHidden(true)
        }
        .padding(Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.title)
        .accessibilityValue("\(percent(fraction)) der Zeit im Bett, \(Format.duration(duration))")
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
