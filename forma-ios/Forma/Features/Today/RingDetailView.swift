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
                return recentNight.map { Format.duration($0.asleep) + " Schlaf" } ?? "Schlaf"
            }
        }()
        let target = hub.ringScores.target
        return VStack(spacing: Space.s3) {
            RingView(value: Double(value ?? 0), color: tint, size: 166, lineWidth: 7,
                     target: kind == .strain && hub.availability.recovery
                        ? Double(target.lowerBound)...Double(target.upperBound) : nil,
                     numberSize: 58, missing: value == nil)
                .accessibilityLabel(value.map { "\(kind.title), \($0) von 100" } ?? "Keine Messung")
            Text(status).font(.formaHeadline).multilineTextAlignment(.center)
            if hub.waitingForFitbit && kind != .strain {
                Text("Stand gestern").font(.formaCaption).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s4)
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
                }
            }
            HourlyValueChart(title: "Belastung im Tagesverlauf", points: hub.hourlyEstimates.compactMap { hour in
                hour.strain.map { HealthChartPoint(date: hour.at, value: Double($0)) }
            }, color: Theme.strain, maximum: 100, valueText: { Format.number($0) })
        }
    }

    private var recovery: some View {
        let day = hub.waitingForFitbit ? hub.yesterday : hub.today
        let hrv = hub.hours.compactMap { hour in hour.hrv.map { HealthChartPoint(date: hour.start, value: $0) } }
        return VStack(spacing: 0) {
            FormaSection(title: "Messwerte") {
                Plate {
                    MetricRow(title: "HRV", value: day?.hrv.map { Format.number($0) + " ms" } ?? "–")
                    RowDivider()
                    MetricRow(title: "Ruhepuls", value: day?.restingHR.map { Format.number($0) + " bpm" } ?? "–")
                    RowDivider()
                    MetricRow(title: "Atemfrequenz", value: day?.respiratoryRate.map { Format.number($0, decimals: 1) + " /min" } ?? "–")
                }
            }
            HourlyValueChart(title: "HRV pro Stunde", points: hrv, color: Theme.younger,
                             maximum: max(10, (hrv.map(\.value).max() ?? 0) * 1.15),
                             valueText: { Format.number($0) + " ms" })
        }
    }

    private var recentNight: SleepNight? {
        hub.waitingForFitbit ? hub.yesterday?.sleep : hub.today.sleep
    }

    private var sleep: some View {
        let s = hub.scores
        return VStack(spacing: 0) {
            if let night = recentNight {
                FormaSection(title: "Verlauf der Nacht") {
                    Plate {
                        SleepTimeline(night: night)
                            .padding(Space.s4)
                        RowDivider()
                        if night.hasStages {
                            ForEach(SleepNight.Stage.allCases, id: \.self) { stage in
                                MetricRow(title: stage.title, value: Format.duration(night.total(stage)))
                                if stage != .deep { RowDivider() }
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
        let all = Array(hub.longDays.dropLast(min(recent.count, hub.longDays.count))) + recent
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
        let stages: [SleepNight.Stage] = night.hasStages ? SleepNight.Stage.allCases : [.awake, .core]
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(stages, id: \.self) { stage in
                        Text(!night.hasStages && stage == .core ? "Schlaf" : stage.title)
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
                        for segment in night.segments where segment.stage == stage {
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
