import SwiftUI

struct RingDetailView: View {
    @Environment(DataHub.self) private var hub
    let kind: RingKind

    var body: some View {
        let value = displayedValue
        let tint: Color = switch kind {
        case .strain: Theme.strain
        case .recovery: value.map(Theme.recovery) ?? Theme.textSecondary
        case .sleep: Theme.sleep
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hub.isSample { SampleDataBadge() }
                hero(value: value, tint: tint)
                    .padding(.top, hub.isSample ? Space.s3 : 0)
                switch kind {
                case .strain: strain
                case .recovery: recovery
                case .sleep: sleep
                }
                DailyHistoryChart(title: kind == .sleep ? "Schlafdauer" : "\(kind.title)-Verlauf",
                                  points: history, color: tint, valueText: { value in
                    kind == .sleep ? Format.duration(value * 3600) : Format.number(value)
                }, maximum: kind == .sleep ? nil : 100)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
            .padding(.bottom, Space.s4)
        }
        .formaScreen(tint: value == nil ? nil : tint)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayedValue: Int? {
        let available = hub.availability
        let scores = hub.ringScores
        switch kind {
        case .strain: return available.strain ? scores.strain : nil
        case .recovery: return available.recovery ? scores.recovery : nil
        case .sleep: return available.sleep ? scores.sleep : nil
        }
    }

    private func hero(value: Int?, tint: Color) -> some View {
        let status: String = {
            guard let value else { return "Keine Daten für heute" }
            switch kind {
            case .strain:
                guard hub.availability.recovery else { return "Belastung heute" }
                let target = hub.ringScores.target
                if target.contains(value) { return "Im Zielbereich" }
                return value < target.lowerBound ? "Unter dem Zielbereich" : "Über dem Zielbereich"
            case .recovery:
                return Theme.recoveryWord(value)
            case .sleep:
                return "Schlafqualität"
            }
        }()
        let target = hub.ringScores.target
        let ring = RingView(value: Double(value ?? 0), color: tint, size: 116, lineWidth: 6,
                            target: kind == .strain && hub.availability.recovery
                                ? Double(target.lowerBound)...Double(target.upperBound) : nil,
                            showsNumber: false, missing: value == nil)
            .padding(Space.s2)
            .accessibilityHidden(true)
        return Plate {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s3) {
                    scoreLabel(value, status: status)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ring
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    scoreLabel(value, status: status)
                    ring
                }
            }
            .padding(Space.s5)
        }
    }

    private func scoreLabel(_ value: Int?, status: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(hub.waitingForFitbit && kind != .strain ? "Gestern" : "Heute")
                .font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(value.map(String.init) ?? "–").font(.formaHero)
                if value != nil {
                    Text("von 100").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            Text(status).font(.formaRowTitle)
        }
        .accessibilityElement(children: .combine)
    }

    private var strain: some View {
        VStack(spacing: 0) {
            FormaSection(title: "Heute") {
                Plate {
                    MetricRow(title: "Zielbereich", value: hub.availability.recovery
                              ? "\(hub.ringScores.target.lowerBound)–\(hub.ringScores.target.upperBound)"
                              : "Keine Recovery")
                    RowDivider()
                    MetricRow(title: "Aktive Energie", value: hub.today.activeEnergy.map { Format.number($0) + " kcal" } ?? "–")
                    let minutes = hub.today.workouts.reduce(0) { $0 + $1.duration }
                    if minutes > 0 {
                        RowDivider()
                        MetricRow(title: "Trainingszeit", value: Format.duration(minutes))
                    }
                    if let steps = hub.today.steps {
                        RowDivider()
                        MetricRow(title: "Schritte", value: Format.number(steps))
                    }
                }
            }
            HourlyValueChart(title: "Belastung im Tagesverlauf", points: hub.hourlyEstimates.compactMap { hour in
                hour.strain.map { HealthChartPoint(date: hour.at, value: Double($0)) }
            }, color: Theme.strain, maximum: 100, valueText: { Format.number($0) })
        }
    }

    private var recovery: some View {
        let day = hub.waitingForFitbit ? hub.yesterday : hub.today
        let baselineDays = hub.waitingForFitbit ? Array(hub.history.dropLast()) : hub.history
        let hrv = hub.hours.compactMap { hour in hour.hrv.map { HealthChartPoint(date: hour.start, value: $0) } }
        return VStack(spacing: 0) {
            FormaSection(title: "Messwerte") {
                Plate {
                    recoveryMetric(.hrv, day: day, baselineDays: baselineDays)
                    RowDivider()
                    recoveryMetric(.restingHR, day: day, baselineDays: baselineDays)
                    RowDivider()
                    recoveryMetric(.respiratoryRate, day: day, baselineDays: baselineDays)
                }
            }
            HourlyValueChart(title: "HRV pro Stunde", points: hrv, color: Theme.younger,
                             maximum: max(10, (hrv.map(\.value).max() ?? 0) * 1.15),
                             valueText: { Format.number($0) + " ms" })
        }
    }

    private func recoveryMetric(_ metric: MetricKind, day: DayMetrics?, baselineDays: [DayMetrics]) -> some View {
        let baseline = ScoreEngine.baseline(baselineDays.compactMap(metric.value))
        return MetricRow(title: metric.title,
                         subtitle: baseline.map { "Dein Ø \(metric.measurement($0.mean))" },
                         value: day.flatMap(metric.value).map(metric.measurement) ?? "–")
    }

    private var recentNight: SleepNight? {
        hub.waitingForFitbit ? hub.yesterday?.sleep : hub.today.sleep
    }

    private var sleep: some View {
        let s = hub.scores
        let prior = hub.waitingForFitbit ? Array(hub.history.dropLast()) : hub.history
        return VStack(spacing: 0) {
            if let night = recentNight {
                FormaSection(title: hub.waitingForFitbit ? "Nacht zum Vortag" : "Letzte Nacht") {
                    Plate {
                        MetricRow(title: "Geschlafen", value: Format.duration(night.asleep))
                        RowDivider()
                        MetricRow(title: "Geschätzter Bedarf", value: Format.duration(ScoreEngine.sleepNeedForLastNight(history: prior)))
                        RowDivider()
                        MetricRow(title: "Schlafeffizienz", value: Format.number(night.efficiency * 100), unit: "%")
                    }
                }
                FormaSection(title: "Verlauf der Nacht") {
                    Plate {
                        SleepTimeline(night: night)
                            .padding(Space.s4)
                        RowDivider()
                        if night.hasStages {
                            ForEach(night.recordedStages, id: \.self) { stage in
                                MetricRow(title: stage.title, value: Format.duration(night.total(stage)))
                                if stage != night.recordedStages.last { RowDivider() }
                            }
                        } else {
                            MetricRow(title: "Schlafphasen", value: "Nicht erfasst")
                        }
                    }
                }
            }
            FormaSection(title: "Heute Nacht") {
                Plate {
                    MetricRow(title: "Empfohlene Bettzeit", value: CoachEngine.bedtime(s))
                    RowDivider()
                    MetricRow(title: "Schlafbedarf", value: Format.duration(s.sleepNeed))
                    RowDivider()
                    MetricRow(title: "Schlafschuld", subtitle: "Letzte 7 Nächte",
                              value: hub.history.suffix(7).contains { $0.sleep != nil } ? Format.duration(s.sleepDebt) : "–")
                }
            }
        }
    }

    private var history: [HealthChartPoint] {
        let recent = hub.days
        let all = (recent.first.map { first in hub.longDays.filter { $0.date < first.date } } ?? []) + recent
        return all.indices.suffix(30).compactMap { index in
            let day = all[index]
            let value: Double?
            switch kind {
            case .sleep:
                value = day.sleep.map { $0.asleep / 3600 }
            case .strain:
                value = day.activeEnergy == nil && day.workouts.isEmpty ? nil : Double(ScoreEngine.strain(day))
            case .recovery:
                // Wie beim heutigen Ring: Das 30-Tage-Fenster enthält den Tag selbst.
                let previous = Array(all[max(0, index - 29)..<index])
                let hasHRV = day.hrv != nil && ScoreEngine.baseline(previous.compactMap(\.hrv)) != nil
                let hasRHR = day.restingHR != nil && ScoreEngine.baseline(previous.compactMap(\.restingHR)) != nil
                value = hasHRV || hasRHR ? Double(ScoreEngine.scores(today: day, history: previous).recovery) : nil
            }
            return value.map { HealthChartPoint(date: day.date, value: $0) }
        }
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
                Spacer()
                Text(Format.clock(night.end))
            }
            .font(.formaCaption).monospacedDigit().foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schlaf von \(Format.clock(night.start)) bis \(Format.clock(night.end))")
    }
}
