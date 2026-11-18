import SwiftUI

struct RingDetailView: View {
    @Environment(DataHub.self) private var hub
    let kind: RingKind

    private var tint: Color {
        switch kind {
        case .recovery: Theme.recovery(hub.ringScores.recovery)
        case .sleep: Theme.sleep
        case .strain: Theme.strain
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch kind {
                case .recovery: RecoveryDetail()
                case .sleep: SleepDetail()
                case .strain: StrainDetail()
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.page)
        }
        .formaScreen(tint: tint)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Großer Ring mit Satz darunter.
struct DetailHero: View {
    let value: Int
    let color: Color
    var target: ClosedRange<Int>? = nil
    let headline: String
    let detail: String
    var dimmed = false

    @State private var shown: Double = 0

    var body: some View {
        VStack(spacing: Space.s4) {
            RingView(value: shown, color: color, size: 196, lineWidth: 4.5,
                     target: target.map { Double($0.lowerBound)...Double($0.upperBound) }, dimmed: dimmed, numberSize: 64)
                .padding(.top, Space.s4)
                .accessibilityLabel("\(value) von 100")
            VStack(spacing: 6) {
                Text(headline).font(.formaHeadline)
                Text(detail)
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(duration: 1.1, bounce: 0.05).delay(0.1)) { shown = Double(value) }
        }
    }
}

private func lastDaysLabels(_ days: [DayMetrics]) -> [String] {
    days.suffix(7).map { Format.shortWeekday($0.date) }
}

// MARK: - Erholung

private struct RecoveryDetail: View {
    @Environment(DataHub.self) private var hub
    @State private var showMethod = false

    var body: some View {
        let s = hub.ringScores
        let recoveries = (Swift.max(0, hub.days.count - 30)..<hub.days.count).map { hub.scores(for: $0).recovery }
        let mean = recoveries.dropLast().isEmpty ? s.recovery : recoveries.dropLast().reduce(0, +) / recoveries.dropLast().count
        let diff = s.recovery - mean
        VStack(alignment: .leading, spacing: 0) {
            DetailHero(value: s.recovery, color: Theme.recovery(s.recovery), headline: Theme.recoveryWord(s.recovery),
                       detail: "\(abs(diff)) Punkte \(diff >= 0 ? "über" : "unter") deinem 30-Tage-Mittel von \(mean).",
                       dimmed: hub.waitingForFitbit)

            FormaSection(title: "Was beiträgt") {
                Plate {
                    ForEach(Array(contributions.enumerated()), id: \.offset) { index, item in
                        if index > 0 { RowDivider() }
                        ContributionRow(title: item.0, detail: item.1, effect: item.2)
                    }
                }
            }

            FormaSection(title: "Letzte 7 Tage") {
                Plate {
                    DayBars(values: recoveries.suffix(7).map(Double.init), labels: lastDaysLabels(hub.days), maximum: 100) { v in Theme.recovery(Int(v)) }
                    Text("Mittel \(recoveries.suffix(7).reduce(0, +) / Swift.max(1, recoveries.suffix(7).count))")
                        .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                        .padding(Space.s4)
                }
            }

            FormaSection(title: "Messwerte") {
                Plate {
                    TrendRow(kind: .hrv)
                    RowDivider()
                    TrendRow(kind: .restingHR)
                    RowDivider()
                    TrendRow(kind: .respiratoryRate)
                }
            }

            FormaSection(title: "So wird gerechnet") {
                Plate {
                    Button { withAnimation(.snappy) { showMethod.toggle() } } label: {
                        MetricRow(title: showMethod ? "Weniger" : "Berechnung anzeigen") {
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(showMethod ? 180 : 0))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    if showMethod {
                        Text("Startwert 55. Dazu kommt deine HRV gegenüber dem Mittel der letzten 30 Tage (stärkster Faktor), abzüglich eines erhöhten Ruhepulses und einer erhöhten Atemfrequenz, plus der Schlafwert der letzten Nacht. Ergebnis auf 1 bis 99 begrenzt. Für einen Normalwert braucht Forma mindestens 4 Tage.")
                            .font(.formaBody)
                            .foregroundStyle(Theme.textSecondary)
                            .padding([.horizontal, .bottom], Space.s4)
                    }
                }
            }
        }
    }

    private var contributions: [(String, String, Double)] {
        var result: [(String, String, Double)] = []
        if let v = hub.today.hrv, let b = hub.baseline(\.hrv) {
            let d = v - b.mean
            result.append(("HRV", "\(d >= 0 ? "+" : "")\(Int(d.rounded())) ms", b.z(v) / 2.5))
        }
        if let v = hub.today.restingHR, let b = hub.baseline(\.restingHR) {
            let d = v - b.mean
            result.append(("Ruhepuls", "\(d >= 0 ? "+" : "")\(Int(d.rounded())) bpm", -b.z(v) / 2.5))
        }
        result.append(("Schlaf", "\(hub.scores.sleep)", Double(hub.scores.sleep - 70) / 50))
        if let v = hub.today.respiratoryRate, let b = hub.baseline(\.respiratoryRate) {
            result.append(("Atemfrequenz", Format.number(v - b.mean, decimals: 1), -b.z(v) / 2.5))
        }
        return result
    }
}

/// Balken um eine Mittellinie: rechts hilft, links bremst.
private struct ContributionRow: View {
    let title: String
    let detail: String
    let effect: Double

    var body: some View {
        HStack(spacing: Space.s3) {
            Text(title).font(.formaRowTitle).frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geo in
                let half = geo.size.width / 2
                let w = half * CGFloat(Swift.min(1, abs(effect)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06)).frame(height: 6)
                    Rectangle().fill(Theme.textTertiary).frame(width: 1, height: 12).offset(x: half)
                    Capsule().fill(effect >= 0 ? Theme.recoveryHigh : Theme.recoveryMid)
                        .frame(width: w, height: 6)
                        .offset(x: effect >= 0 ? half : half - w)
                }
                .frame(height: geo.size.height)
            }
            .frame(width: 120, height: 12)
            Text(detail).font(.formaCaption).foregroundStyle(Theme.textSecondary).monospacedDigit().frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// Zeile mit Wert und 30-Tage-Verlauf.
struct TrendRow: View {
    @Environment(DataHub.self) private var hub
    let kind: MetricKind

    var body: some View {
        let values = hub.days.compactMap { kind.value($0) }
        let base = ScoreEngine.baseline(hub.history.compactMap { kind.value($0) })
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title).font(.formaRowTitle)
                Spacer()
                if let last = values.last {
                    Text(kind.formatted(last)).font(.formaValue)
                    if kind != .sleepDuration { Text(kind.unit).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary) }
                }
            }
            if values.count > 1 {
                Sparkline(values: Array(values.suffix(14)), band: base.map { ($0.mean - $0.sd)...($0.mean + $0.sd) }, height: 44)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 12)
    }
}

// MARK: - Schlaf

private struct SleepDetail: View {
    @Environment(DataHub.self) private var hub

    var body: some View {
        let s = hub.ringScores
        let night = hub.waitingForFitbit ? hub.yesterday?.sleep : hub.today.sleep
        VStack(alignment: .leading, spacing: 0) {
            DetailHero(value: s.sleep, color: Theme.sleep,
                       headline: night.map { "\(Format.duration($0.asleep)) geschlafen" } ?? "Keine Schlafdaten",
                       detail: night.map { "\(Format.clock($0.start)) bis \(Format.clock($0.end)) · Bedarf zu \(Int(min(1, $0.asleep / max(1, s.sleepNeed)) * 100)) % gedeckt." } ?? "Trag deine Uhr oder deinen Tracker in der Nacht.",
                       dimmed: hub.waitingForFitbit)

            if let night {
                FormaSection(title: "Verlauf der Nacht") {
                    Plate {
                        Hypnogram(night: night).padding(Space.s4)
                        PhaseLegend(night: night)
                    }
                }
                FormaSection(title: "Kennzahlen") {
                    Plate {
                        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow {
                                stat("Effizienz", "\(Int(night.efficiency * 100))", "%")
                                stat("Im Bett", Format.duration(night.inBed), nil)
                            }
                            Divider().overlay(Theme.hairline).gridCellColumns(2)
                            GridRow {
                                stat("Tiefschlaf", Format.duration(night.total(.deep)), nil)
                                stat("REM", Format.duration(night.total(.rem)), nil)
                            }
                        }
                    }
                }
            }

            FormaSection(title: "Heute Nacht") {
                Plate {
                    MetricRow(title: "Ins Bett", subtitle: "für einen Wecker um 6:55", value: CoachEngine.bedtime(s))
                    RowDivider()
                    MetricRow(title: "Schlafbedarf", subtitle: "Grundbedarf, Belastung von heute und Schlafschuld", value: Format.duration(s.sleepNeed))
                    RowDivider()
                    MetricRow(title: "Schlafschuld", subtitle: "aus den letzten 7 Nächten", value: Format.duration(s.sleepDebt))
                }
            }

            FormaSection(title: "Letzte 7 Nächte") {
                Plate {
                    let hours = hub.days.suffix(7).map { ($0.sleep?.asleep ?? 0) / 3600 }
                    DayBars(values: hours, labels: lastDaysLabels(hub.days), maximum: 9.5) { _ in Theme.sleep }
                    Text("Mittel \(Format.duration(hours.reduce(0, +) / Double(Swift.max(1, hours.count)) * 3600))")
                        .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                        .padding(Space.s4)
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                if let unit { Text(unit).font(.formaCaption).foregroundStyle(Theme.textSecondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
    }
}

/// Schlafphasen als Stufenbild: oben wach, unten tief.
struct Hypnogram: View {
    let night: SleepNight

    nonisolated static func color(_ stage: SleepNight.Stage) -> Color {
        switch stage {
        case .awake: Color.white.opacity(0.55)
        case .rem: Color(hex: 0xB9C8FF)
        case .core: Color(hex: 0x6E9BD8)
        case .deep: Color(hex: 0x3B66B8)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .leading) {
                    ForEach(SleepNight.Stage.allCases, id: \.self) { stage in
                        Text(stage.title).font(.formaMicro).foregroundStyle(Theme.textTertiary)
                        if stage != .deep { Spacer(minLength: 0) }
                    }
                }
                .frame(width: 34, height: 104)
                Canvas { ctx, size in
                    let total = night.end.timeIntervalSince(night.start)
                    guard total > 0 else { return }
                    let rowH = size.height / 4
                    for seg in night.segments {
                        let x0 = CGFloat(seg.start.timeIntervalSince(night.start) / total) * size.width
                        let w = Swift.max(1.5, CGFloat(seg.duration / total) * size.width)
                        let rect = CGRect(x: x0, y: CGFloat(seg.stage.level) * rowH + rowH * 0.18, width: w, height: rowH * 0.64)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Self.color(seg.stage)))
                    }
                }
                .frame(height: 104)
            }
            HStack {
                Text(Format.clock(night.start))
                Spacer()
                Text(Format.clock(night.end))
            }
            .font(.formaMicro)
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, 42)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verlauf der Nacht von \(Format.clock(night.start)) bis \(Format.clock(night.end))")
    }
}

private struct PhaseLegend: View {
    let night: SleepNight
    var body: some View {
        let stages: [SleepNight.Stage] = [.deep, .rem, .core, .awake]
        let asleepOrBed = Swift.max(1, night.segments.reduce(0) { $0 + $1.duration })
        VStack(alignment: .leading, spacing: Space.s3) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(stages, id: \.self) { st in
                        Rectangle().fill(Hypnogram.color(st))
                            .frame(width: Swift.max(0, geo.size.width * CGFloat(night.total(st) / asleepOrBed) - 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            FlowLegend(items: stages.map { ($0.title + " " + Format.duration(night.total($0)), Hypnogram.color($0)) })
        }
        .padding([.horizontal, .bottom], Space.s4)
    }
}

private struct FlowLegend: View {
    let items: [(String, Color)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle().fill(item.1).frame(width: 7, height: 7)
                    Text(item.0).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

// MARK: - Belastung

private struct StrainDetail: View {
    @Environment(DataHub.self) private var hub

    var body: some View {
        let s = hub.scores
        let status: (String, String) = {
            if s.strain < s.target.lowerBound { return ("Noch unter dem Ziel", "Dein Bereich heute ist \(s.target.lowerBound) bis \(s.target.upperBound), gestrichelt am Ring. Noch \(s.target.lowerBound - s.strain) Punkte bis dorthin.") }
            if s.strain > s.target.upperBound { return ("Über dem Ziel", "Du liegst \(s.strain - s.target.upperBound) Punkte über deinem Bereich. Plane heute Abend genug Schlaf ein.") }
            return ("Im Zielbereich", "Dein Bereich heute ist \(s.target.lowerBound) bis \(s.target.upperBound), gestrichelt am Ring.")
        }()
        VStack(alignment: .leading, spacing: 0) {
            DetailHero(value: s.strain, color: Theme.strain, target: s.target, headline: status.0, detail: status.1)

            FormaSection(title: "Aktivitäten heute") {
                Plate {
                    if hub.today.workouts.isEmpty {
                        MetricRow(title: "Noch keine Aktivität erfasst")
                    }
                    ForEach(Array(hub.today.workouts.enumerated()), id: \.element.id) { index, w in
                        if index > 0 { RowDivider() }
                        MetricRow(title: w.name, subtitle: "\(Format.clock(w.start)) · \(Format.duration(w.duration))", value: w.energy.map { "\(Format.number($0)) kcal" })
                    }
                    RowDivider()
                    MetricRow(title: "Aktive Energie", value: Format.number(hub.today.activeEnergy ?? 0), unit: "kcal")
                    RowDivider()
                    MetricRow(title: "Schritte", value: Format.number(hub.today.steps ?? 0))
                }
            }

            FormaSection(title: "Letzte 7 Tage") {
                Plate {
                    let values = (Swift.max(0, hub.days.count - 7)..<hub.days.count).map { Double(hub.scores(for: $0).strain) }
                    DayBars(values: values, labels: lastDaysLabels(hub.days), maximum: 100) { _ in Theme.strain }
                    Text("Summe \(Int(values.reduce(0, +)))")
                        .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                        .padding(Space.s4)
                }
            }

            FormaSection(title: "So wird gerechnet") {
                Plate {
                    Text("Belastung entsteht aus aktiver Energie und Trainingszeit und nähert sich 100 an, ohne sie zu erreichen. Der empfohlene Bereich richtet sich nach deiner Erholung: gut erholt 35–55, mittel 25–40, wenig erholt 10–25.")
                        .font(.formaBody)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(Space.s4)
                }
            }
        }
    }
}
