import Charts
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
            if kind == .sleep {
                SleepPlanCard()
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                DashboardHeading(title: kind == .recovery ? "Erholung im Detail" : "Beiträge")
                ForEach(metrics(tint: tint)) { metric in
                    RingMetricCard(metric: metric, day: day, history: history)
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

    private func metrics(tint: Color) -> [RingMetric] {
        switch kind {
        case .sleep: sleepMetrics(tint: tint)
        case .recovery: recoveryMetrics(tint: tint)
        case .strain: strainMetrics(tint: tint)
        }
    }

    private func sleepMetrics(tint: Color) -> [RingMetric] {
        [
            RingMetric(id: "sleep.need", title: "Stunden vs. Bedarf", icon: "moon", tint: tint, formatted: percent) { day, history in
                guard let night = day.sleep, night.asleep > 0,
                      let need = ScoreEngine.measuredNeedForLastNight(on: day.date, history: history), need > 0 else { return nil }
                return night.asleep / need
            },
            RingMetric(id: "sleep.regularity", title: "Regelmäßigkeit", icon: "clock", tint: tint, formatted: percent) { day, history in
                guard let night = day.sleep, night.asleep > 0 else { return nil }
                return DashboardDay.sleepRegularity(night, history: history)
            },
            RingMetric(id: "sleep.efficiency", title: "Effizienz", icon: "bed.double", tint: tint, formatted: percent) { day, _ in
                day.sleep.flatMap { $0.asleep > 0 ? $0.efficiency : nil }
            },
            RingMetric(id: "sleep.restorative", title: "Tief- und REM-Anteil", icon: "moon.stars", tint: tint, formatted: percent) { day, _ in
                day.sleep.flatMap(DashboardDay.restorativeFraction)
            }
        ]
    }

    private func recoveryMetrics(tint: Color) -> [RingMetric] {
        let vitals = NightVitals(day: day, history: snapshot.history)
        func vital(_ kind: MetricKind, icon: String, series: MetricSeries) -> RingMetric {
            let reading = vitals.readings.first { $0.series == series }
            let range = NightVitals.range(for: series.rawValue, baseline: reading?.baseline)
            return RingMetric(kind: kind, icon: icon, tint: tint, range: range, series: series)
        }

        return [
            RingMetric(id: "recovery", title: "Erholungswert", icon: "heart.circle", tint: tint,
                       formatted: { Format.number($0) + " %" }) { day, history in
                DashboardDay(day: day, history: history).recovery.map(Double.init)
            },
            vital(.hrv, icon: "waveform.path.ecg", series: .hrv),
            vital(.restingHR, icon: "heart", series: .restingHR),
            vital(.respiratoryRate, icon: "lungs", series: .respiratoryRate),
            vital(.spo2, icon: "drop", series: .spo2),
            vital(.skinTemperature, icon: "thermometer.medium", series: .skinTemperature),
            RingMetric(id: "sleep.score", title: "Schlafleistung", icon: "moon", tint: Theme.sleep,
                       formatted: { Format.number($0) + " %" }) { day, history in
                DashboardDay.sleepScore(day, history: history).map(Double.init)
            }
        ]
    }

    private func strainMetrics(tint: Color) -> [RingMetric] {
        [
            RingMetric(id: "workouts", title: "Trainingszeit", icon: "stopwatch", tint: tint, formatted: Format.duration) { day, _ in
                DashboardDay.workoutTime(day)
            },
            RingMetric(id: "strength", title: "Krafttraining", icon: "dumbbell", tint: tint, formatted: Format.duration) { day, _ in
                DashboardDay.workoutTime(day, strengthOnly: true)
            },
            RingMetric(kind: .steps, icon: "figure.walk", tint: tint),
            RingMetric(kind: .activeEnergy, icon: "flame", tint: tint)
        ]
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

private struct RingMetric: Identifiable {
    let id: String
    let title: String
    let icon: String
    let tint: Color
    var range: ClosedRange<Double>? = nil
    var series: MetricSeries? = nil
    let formatted: (Double) -> String
    let measurement: (DayMetrics, [DayMetrics]) -> Double?

    func points(in domain: ClosedRange<Date>, endingAt current: DayMetrics, history: [DayMetrics]) -> [HealthChartPoint] {
        let days = history.filter { $0.date < current.date }.sorted { $0.date < $1.date }
        return (days + [current]).filter { domain.contains($0.date) }.compactMap { day in
            if let series, range != nil, day.date != current.date,
               !ScoreEngine.sameBaselineSource(for: series, today: current, previous: day) { return nil }
            let previous = days.filter { $0.date < day.date }
            return value(day: day, history: previous).map { HealthChartPoint(date: day.date, value: $0) }
        }
    }

    func value(day: DayMetrics, history: [DayMetrics]) -> Double? {
        measurement(day, history).flatMap { $0.isFinite ? $0 : nil }
    }

    func status(_ value: Double?) -> String? {
        guard let value, let range else { return nil }
        if range.contains(value) { return "Im üblichen Bereich" }
        return value > range.upperBound ? "Über dem üblichen Bereich" : "Unter dem üblichen Bereich"
    }
}

private extension RingMetric {
    init(kind: MetricKind, icon: String, tint: Color, range: ClosedRange<Double>? = nil,
         series: MetricSeries? = nil) {
        self.init(id: kind.rawValue, title: kind.title, icon: icon, tint: tint, range: range, series: series,
                  formatted: kind.measurement, measurement: { day, _ in kind.value(day) })
    }
}

private struct RingMetricCard: View {
    let metric: RingMetric
    let day: DayMetrics
    let history: [DayMetrics]

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let prior = history.filter { $0.date < day.date }.sorted { $0.date < $1.date }
        let value = metric.value(day: day, history: prior)
        let text = value.map(metric.formatted) ?? "Keine Messung"
        let status = metric.status(value)
        let domain = day.date.adding(days: -13)...day.date
        let points = metric.points(in: domain, endingAt: day, history: prior)
        NavigationLink {
            InsightPage(title: metric.title) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(text).font(value == nil ? .formaRowTitle : .formaDisplay)
                    if let status { statusLabel(status, value: value) }
                }
                RingTrendCard(title: metric.title, anchor: day.date, tint: metric.tint, usual: metric.range,
                              valueText: metric.formatted) { domain in
                    metric.points(in: domain, endingAt: day, history: prior)
                }
            }
        } label: {
            DashboardCard {
                HStack(alignment: .center, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Label(metric.title, systemImage: metric.icon)
                            .font(.formaRowTitle)
                            .foregroundStyle(Theme.textSecondary)
                        Text(text)
                            .font(value == nil ? .formaCaption : .formaNumber)
                            .foregroundStyle(value == nil ? Theme.textSecondary : Theme.textPrimary)
                            .monospacedDigit()
                        if let status { statusLabel(status, value: value) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !typeSize.isAccessibilitySize, !points.isEmpty {
                        RingMetricSparkline(points: points, domain: domain, usual: metric.range, tint: metric.tint)
                            .frame(width: 94, height: 38)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .frame(minHeight: 72)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(metric.title)
        .accessibilityValue([text, status].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("ring.metric." + metric.id)
    }

    private func statusLabel(_ status: String, value: Double?) -> some View {
        let inRange = value.map { metric.range?.contains($0) == true } ?? false
        return Label(status, systemImage: inRange ? "checkmark.circle" : "circle.lefthalf.filled")
            .font(.formaCaption)
            .foregroundStyle(inRange ? metric.tint : Theme.textSecondary)
    }
}

private struct RingMetricSparkline: View {
    let points: [HealthChartPoint]
    let domain: ClosedRange<Date>
    let usual: ClosedRange<Double>?
    let tint: Color

    var body: some View {
        Chart {
            if let usual {
                RectangleMark(xStart: .value("Start", domain.lowerBound),
                              xEnd: .value("Ende", domain.upperBound.adding(days: 1)),
                              yStart: .value("Untergrenze", usual.lowerBound),
                              yEnd: .value("Obergrenze", usual.upperBound))
                    .foregroundStyle(tint.opacity(0.1))
            }
            ForEach(RingChartSeries.segments(points), id: \.point.date) { entry in
                let point = entry.point
                let date = insightDayCenter(point.date)
                LineMark(x: .value("Tag", date), y: .value("Wert", point.value),
                         series: .value("Abschnitt", entry.segment))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Tag", date), y: .value("Wert", point.value))
                    .foregroundStyle(tint)
                    .symbolSize(point.date == points.last?.date ? 22 : 9)
            }
        }
        .chartXScale(domain: domain.lowerBound...domain.upperBound.adding(days: 1))
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
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
