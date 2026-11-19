import SwiftUI
import SwiftData
import Charts

private func formaSessions(_ sessions: [WorkoutSession]) -> [HealthAgeTrend.Session] {
    sessions.map { (start: $0.start, minutes: $0.duration / 60) }
}

@MainActor
func bodyAgeOutcome(hub: DataHub, sessions: [WorkoutSession]) -> BodyAge.Outcome {
    HealthAgeTrend.outcome(days: hub.longDays, person: hub.person, sessions: formaSessions(sessions), now: .now)
}

@MainActor
func bodyAgeTrend(hub: DataHub, sessions: [WorkoutSession]) -> [BodyAge.Estimate] {
    HealthAgeTrend.points(days: hub.longDays, person: hub.person, sessions: formaSessions(sessions))
}

enum BodyAgeText {
    static func years(_ value: Double, confidence: BodyAge.Confidence) -> String {
        Format.number(value, decimals: confidence == .high ? 1 : 0)
    }

    static func signedYears(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let sign = rounded == 0 ? "" : (rounded < 0 ? "−" : "+")
        return sign + Format.number(abs(rounded), decimals: 1) + " Jahre"
    }

    static func difference(_ result: BodyAge.Result) -> String {
        let places = result.confidence == .high ? 10.0 : 1.0
        let difference = (result.difference * places).rounded() / places
        if difference == 0 { return "Etwa so alt wie du bist" }
        let amount = years(abs(difference), confidence: result.confidence)
        return "\(amount) \(abs(difference) == 1 ? "Jahr" : "Jahre") \(difference < 0 ? "jünger" : "älter")"
    }

    static func color(_ difference: Double) -> Color {
        if abs(difference) < 0.05 { return Theme.textSecondary }
        return difference < 0 ? Theme.younger : Theme.older
    }
}

// MARK: - Kopf

/// Hauptsache des Health-Tabs: Kugel, Zahl, „x Jahre jünger“, Datenlage.
struct HealthAgeHero: View {
    let outcome: BodyAge.Outcome

    private var result: BodyAge.Result? {
        if case .ready(let result) = outcome { return result }
        return nil
    }

    var body: some View {
        VStack(spacing: Space.s3) {
            ZStack {
                AgeOrb(mood: OrbMood(difference: result?.difference))
                VStack(spacing: 2) {
                    Text(number)
                        .font(.formaHero)
                        .foregroundStyle(Theme.textPrimary)
                        .formaNumberTransition(result?.bodyAge ?? 0)
                    Text("Health Age")
                        .font(.formaMicro)
                        .tracking(Tracking.label)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 252, height: 252)
            .padding(.top, Space.s2)

            let tint = result.map { BodyAgeText.color($0.difference) } ?? Theme.textSecondary
            Text("\(Text(headline).foregroundStyle(tint))\(Text("  ·  Schätzung").foregroundStyle(Theme.textTertiary))")
                .font(.formaRowTitle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health Age")
        .accessibilityValue(result == nil ? headline : "Schätzung \(number) Jahre, \(headline)")
        .accessibilityHint("Öffnet Tempo, Beiträge und Verlauf")
    }

    private var number: String {
        result.map { BodyAgeText.years($0.bodyAge, confidence: $0.confidence) } ?? "–"
    }

    private var headline: String {
        switch outcome {
        case .ready(let result): BodyAgeText.difference(result)
        case .needsProfile: "Geburtsjahr fehlt"
        case .needsData(let have, let need): "Noch \(need - have) \(need - have == 1 ? "Tag" : "Tage") mit Daten nötig"
        case .insufficient(let reason): reason
        }
    }
}

// MARK: - Abschnitte unter der Kugel

struct HealthAgeSections: View {
    let outcome: BodyAge.Outcome
    let trend: [BodyAge.Estimate]

    private var result: BodyAge.Result? {
        if case .ready(let result) = outcome { return result }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            // Bei dünner Datenlage schwankt das Tempo zu stark, um es zu zeigen (K-03-38).
            AgingPaceCard(pace: result?.confidence == .low ? nil : result?.pace)
            if let result, !result.factors.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    DashboardHeading(title: "Beiträge")
                    DashboardCard {
                        ForEach(result.factors) { factor in
                            if factor.id != result.factors.first?.id { RowDivider() }
                            NavigationLink {
                                AgeFactorDetail(factor: factor)
                            } label: {
                                AgeFactorRow(factor: factor)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("health.age.factor." + factor.id)
                        }
                    }
                }
            }
            HealthAgeTrendCard(points: trend)
        }
    }
}

private struct AgingPaceCard: View {
    let pace: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Alterungstempo")
                .accessibilityIdentifier("health.age.pace.title")
            DashboardCard {
                if let pace {
                    let band = AgingPace.band(pace)
                    VStack(alignment: .leading, spacing: Space.s3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(AgingPace.text(pace))
                                .font(.formaWidgetNumber)
                                .formaNumberTransition(pace)
                            Spacer()
                            Text(band.title)
                                .font(.formaCaptionStrong)
                                .foregroundStyle(band.color)
                        }
                        AgingPaceScale(pace: pace, tint: band.color)
                    }
                    .padding(Space.s4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Alterungstempo")
                    .accessibilityValue("\(AgingPace.text(pace)), \(band.title)")
                } else {
                    DashboardEmpty(title: "Noch nicht genug Verlauf")
                }
            }
        }
        .accessibilityIdentifier("health.age.pace")
    }
}

/// Feine Striche von −1,0× bis 3,0×; zwischen 1,0× und dem Wert leuchten die Striche.
private struct AgingPaceScale: View {
    let pace: Double
    let tint: Color
    private let ticks = 40

    var body: some View {
        VStack(spacing: Space.s2) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let marker = width * CGFloat(AgingPace.fraction(pace))
                let clock = width * CGFloat(AgingPace.fraction(1))
                let lit = min(marker, clock)...max(marker, clock)
                ZStack {
                    ForEach(0...ticks, id: \.self) { tick in
                        let x = width * CGFloat(tick) / CGFloat(ticks)
                        let major = tick.isMultiple(of: 10)
                        Capsule()
                            .fill(lit.contains(x) ? tint : (major ? Theme.textTertiary : Theme.textQuaternary))
                            .frame(width: 1.5, height: major ? 22 : 14)
                            .position(x: min(max(x, 1), width - 1), y: 18)
                    }
                    Capsule()
                        .fill(Theme.textPrimary)
                        .frame(width: 4, height: 34)
                        .shadow(color: tint.opacity(0.9), radius: 6)
                        .position(x: min(max(marker, 2), width - 2), y: 18)
                }
            }
            .frame(height: 36)
            HStack {
                Text("−1,0×")
                Spacer()
                Text("1,0×")
                Spacer()
                Text("3,0×")
            }
            .monospacedDigit()
            HStack {
                Label("Langsam", systemImage: "tortoise")
                Spacer()
                Label("Schnell", systemImage: "hare")
            }
        }
        .font(.formaCaption)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }
}

// MARK: - Faktoren

private func factorYears(_ factor: BodyAge.Factor) -> Double {
    factor.years * BodyAge.overlapDamping
}

private struct AgeFactorRow: View {
    let factor: BodyAge.Factor

    var body: some View {
        let years = factorYears(factor)
        let tint = BodyAgeText.color(years)
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(factor.title)
                    .formaLabelStyle()
                Spacer(minLength: Space.s2)
                Text(BodyAgeText.signedYears(years))
                    .font(.formaValue)
                    .foregroundStyle(tint)
                    .formaNumberTransition(years)
                Image(systemName: "chevron.right")
                    .font(.formaMicro)
                    .foregroundStyle(Theme.textTertiary)
            }
            FactorRangeBar(factor: factor, tint: tint)
        }
        .padding(Space.s4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(factor.title)
        .accessibilityValue("\(factor.valueText), \(BodyAgeText.signedYears(years))")
    }
}

/// Bereichsbalken: Vergleich als helles Band oder Strich, Wert als Marker mit Zahl,
/// die Strecke dazwischen in Grün (jünger) oder Orange (älter).
struct FactorRangeBar: View {
    let factor: BodyAge.Factor
    let tint: Color

    var body: some View {
        let domain = FactorScale.domain(value: factor.value, display: factor.displayRange)
        let gap = FactorScale.gap(value: factor.value, reference: factor.referenceRange, in: domain)
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let valueX = width * CGFloat(FactorScale.fraction(factor.value, in: domain))
                let low = width * CGFloat(FactorScale.fraction(factor.referenceRange.lowerBound, in: domain))
                let high = width * CGFloat(FactorScale.fraction(factor.referenceRange.upperBound, in: domain))
                ZStack {
                    Capsule()
                        .fill(Theme.track)
                        .frame(width: width, height: 4)
                        .position(x: width / 2, y: 28)
                    if high - low > 2 {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: high - low, height: 4)
                            .position(x: (low + high) / 2, y: 28)
                    } else {
                        Capsule()
                            .fill(Theme.textTertiary)
                            .frame(width: 2, height: 12)
                            .position(x: min(max(low, 1), width - 1), y: 28)
                    }
                    if let gap {
                        let from = width * CGFloat(gap.lowerBound)
                        let to = width * CGFloat(gap.upperBound)
                        Capsule()
                            .fill(tint)
                            .frame(width: max(4, to - from), height: 4)
                            .position(x: (from + to) / 2, y: 28)
                    }
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textPrimary)
                        .position(x: min(max(valueX, 4), width - 4), y: 19)
                    Text(FactorScale.compact(factor.value, id: factor.id))
                        .font(.formaMicro)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .formaNumberTransition(factor.value)
                        .fixedSize()
                        .position(x: min(max(valueX, 34), max(34, width - 34)), y: 6)
                }
            }
            .frame(height: 32)
            HStack {
                Text(FactorScale.end(domain.lowerBound, id: factor.id))
                    .formaNumberTransition(domain.lowerBound)
                Spacer()
                Text(FactorScale.end(domain.upperBound, id: factor.id))
                    .formaNumberTransition(domain.upperBound)
            }
            .font(.formaMicro)
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityHidden(true)
    }
}

struct AgeFactorDetail: View {
    let factor: BodyAge.Factor
    @Environment(DataHub.self) private var hub

    var body: some View {
        let years = factorYears(factor)
        let tint = BodyAgeText.color(years)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if hub.isSample { SampleDataBadge() }
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(BodyAgeText.signedYears(years))
                        .font(.formaDisplay)
                        .foregroundStyle(tint)
                        .formaNumberTransition(years)
                    Text(factor.valueText)
                        .font(.formaBody)
                        .foregroundStyle(Theme.textSecondary)
                        .formaNumberTransition(factor.value)
                }
                .accessibilityElement(children: .combine)
                DashboardCard {
                    FactorRangeBar(factor: factor, tint: tint).padding(Space.s4)
                }
                DashboardCard {
                    row("Vergleich", factor.referenceText)
                    RowDivider()
                    row("Datengrundlage", factor.coverage)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .dashboardScreen()
        .navigationTitle(factor.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.formaCaption).foregroundStyle(Theme.textSecondary)
            Text(value).font(.formaBody).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trend

/// Health Age gegen echtes Alter, eine Schätzung pro Woche.
private struct HealthAgeTrendCard: View {
    let points: [BodyAge.Estimate]
    @State private var selection: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Health Age Trend")
                .accessibilityIdentifier("health.age.trend.title")
            DashboardCard {
                if points.count >= 2 {
                    chart
                } else {
                    DashboardEmpty(title: "Noch nicht genug Verlauf")
                }
            }
        }
        .accessibilityIdentifier("health.age.trend")
    }

    private var selected: BodyAge.Estimate? {
        guard let selection else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }

    private var chart: some View {
        let last = points[points.count - 1]
        let tint = BodyAgeText.color(last.bodyAge - last.age)
        let values = points.flatMap { [$0.age, $0.bodyAge] }
        let scale = ((values.min() ?? 0) - 0.8)...((values.max() ?? 1) + 0.8)
        return VStack(alignment: .leading, spacing: Space.s3) {
            if let shown = selected {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(Format.number(shown.bodyAge, decimals: 1))
                        .font(.formaNumber)
                        .foregroundStyle(tint)
                        .formaNumberTransition(shown.bodyAge)
                    Text("Health Age")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(Format.shortDate(shown.date))
                        .font(.formaCaption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Datum", p.date),
                             yStart: .value("Alter", p.age),
                             yEnd: .value("Health Age", p.bodyAge))
                        .foregroundStyle(tint.opacity(0.14))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Datum", p.date), y: .value("Jahre", p.age),
                             series: .value("Reihe", "Alter"))
                        .foregroundStyle(Theme.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    LineMark(x: .value("Datum", p.date), y: .value("Jahre", p.bodyAge),
                             series: .value("Reihe", "Health Age"))
                        .foregroundStyle(tint)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                if let shown = selected {
                    PointMark(x: .value("Datum", shown.date), y: .value("Jahre", shown.bodyAge))
                        .foregroundStyle(tint)
                        .symbolSize(60)
                }
                if selection != nil, let shown = selected {
                    RuleMark(x: .value("Auswahl", shown.date))
                        .foregroundStyle(Theme.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: scale)
            .chartXSelection(value: $selection)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel().foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(height: 168)
            .sensoryFeedback(.selection, trigger: selected?.date) { _, new in new != nil }
            .accessibilityLabel("Health Age Trend, \(points.count) Wochen")
            .accessibilityValue("zuletzt \(Format.number(last.bodyAge, decimals: 1)) Jahre bei echtem Alter \(Format.number(last.age, decimals: 1))")
            HStack(spacing: Space.s4) {
                legend("Health Age", color: tint, dashed: false)
                legend("Echtes Alter", color: Theme.textTertiary, dashed: true)
            }
            .accessibilityHidden(true)
        }
        .padding(Space.s4)
    }

    private func legend(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 3] : []))
                .frame(width: 16, height: 2)
            Text(title)
        }
        .font(.formaCaption)
        .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Datengrundlage und Quellen

/// Health Age im Detail: Schätzung, Tempo, Beiträge, Verlauf, Datengrundlage, Quellen.
struct BodyAgeDetailView: View {
    @Environment(DataHub.self) private var hub
    let outcome: BodyAge.Outcome
    var trend: [BodyAge.Estimate] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                if hub.isSample { SampleDataBadge() }
                if case .ready(let result) = outcome {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            Text(BodyAgeText.years(result.bodyAge, confidence: result.confidence))
                                .font(.formaDisplay)
                                .formaNumberTransition(result.bodyAge)
                            Text("Jahre · Schätzung")
                                .font(.formaCaption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(BodyAgeText.difference(result))
                            .font(.formaRowTitle)
                            .foregroundStyle(BodyAgeText.color(result.difference))
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.top, Space.s3)

                    HealthAgeSections(outcome: outcome, trend: trend)

                    VStack(alignment: .leading, spacing: Space.s2) {
                        DashboardHeading(title: "Datengrundlage")
                        DashboardCard {
                            MetricRow(title: "Echtes Alter", value: Format.number(result.age, decimals: 0))
                            RowDivider()
                            MetricRow(title: "Tage mit Daten", value: "\(result.daysWithData) von \(result.windowDays)")
                            RowDivider()
                            MetricRow(title: "Datenlage", value: result.confidence.title)
                            ForEach(Array(result.missing.enumerated()), id: \.offset) { _, item in
                                RowDivider()
                                Text(item)
                                    .font(.formaBody)
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(Space.s4)
                            }
                        }
                    }
                } else {
                    HealthAgeSetupCard(outcome: outcome)
                }
                VStack(spacing: Space.s1) {
                    Text("Modellschätzung aus deinen Messwerten, keine Diagnose.")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                    NavigationLink {
                        HealthSourcesView()
                    } label: {
                        Text("Quellen")
                            .font(.formaCaption)
                            .underline()
                            .foregroundStyle(Theme.textTertiary)
                            .frame(minWidth: 88, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("health.sources")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.s6)
        }
        .dashboardScreen()
        .navigationTitle("Health Age")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Ohne Schätzung: eine einzige ruhige Karte mit dem einen nächsten Schritt (K-03-28).
struct HealthAgeSetupCard: View {
    @Environment(AppState.self) private var app
    let outcome: BodyAge.Outcome

    var body: some View {
        DashboardCard {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Health Age").formaLabelStyle()
                    Text(message)
                        .font(.formaBody)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .needsProfile = outcome {
                        Button("Geburtsjahr eintragen") { app.showProfile = true }
                            .font(.formaRowTitle)
                            .frame(minHeight: 44)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
        }
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch outcome {
        case .needsProfile: "person.crop.circle"
        case .needsData: "hourglass"
        default: "circle.dashed"
        }
    }

    private var message: String {
        switch outcome {
        case .ready: "Schätzung bereit."
        case .needsProfile: "Mit deinem Geburtsjahr schätzt Health, wie alt dein Körper wirkt."
        case .needsData(let have, let need): "Noch \(need - have) \(need - have == 1 ? "Tag" : "Tage") mit Messungen, dann gibt es die erste Schätzung."
        case .insufficient(let reason): reason
        }
    }
}

struct HealthSourcesView: View {
    var body: some View {
        ScrollView {
            DashboardCard {
                ForEach(Array(BodyAge.sources.enumerated()), id: \.offset) { index, source in
                    if let url = URL(string: source.url) {
                        if index > 0 { RowDivider() }
                        Link(destination: url) {
                            HStack(spacing: Space.s3) {
                                Text(source.title)
                                    .font(.formaBody)
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.up.right")
                                    .font(.formaCaptionStrong)
                                    .foregroundStyle(Theme.textTertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(Space.s4)
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .dashboardScreen()
        .navigationTitle("Quellen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
