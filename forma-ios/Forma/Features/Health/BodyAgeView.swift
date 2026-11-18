import SwiftUI
import SwiftData
import Charts

@MainActor
func bodyAgeOutcome(hub: DataHub, sessions: [WorkoutSession]) -> BodyAge.Outcome {
    let now = Date.now
    let days = hub.longDays
    let forma = sessions.map { (start: $0.start, minutes: $0.duration / 60) }
    let strength = BodyAge.strengthMinutes(days: days, formaSessions: forma, now: now)
    return BodyAge.evaluate(days: days, person: hub.person, strength: strength, now: now)
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

struct HealthAgeHero: View {
    let outcome: BodyAge.Outcome

    var body: some View {
        DashboardCard {
            VStack(spacing: Space.s3) {
                if case .ready(let result) = outcome {
                    portrait(result)
                    Text("Datenlage \(result.confidence.title.lowercased()) · Modellschätzung")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    orb(value: "–", tint: Theme.textSecondary)
                    Text(status).font(.formaBody).foregroundStyle(Theme.textSecondary)
                }
                RowDivider(inset: 0)
                HStack {
                    Text("Datengrundlage").font(.formaCaptionStrong)
                    Spacer()
                    Image(systemName: "chevron.right").font(.formaCaptionStrong).accessibilityHidden(true)
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 44)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding([.top, .horizontal], Space.s4)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }

    private func portrait(_ result: BodyAge.Result) -> some View {
        let tint = BodyAgeText.color(result.difference)
        return VStack(spacing: Space.s2) {
            orb(value: BodyAgeText.years(result.bodyAge, confidence: result.confidence), tint: tint)
            Text(BodyAgeText.difference(result))
                .font(.formaRowTitle)
                .foregroundStyle(tint)
        }
    }

    private func orb(value: String, tint: Color) -> some View {
        ZStack {
            AgeOrb(tint: tint).accessibilityHidden(true)
            VStack(spacing: Space.s1) {
                Text(value)
                    .font(.formaHero)
                    .monospacedDigit()
                    .accessibilityLabel(value == "–" ? "Keine Schätzung" : value + " Jahre")
                DashboardHeading(title: "Health Age")
            }
        }
        .frame(width: 208, height: 208)
        .padding(.vertical, Space.s2)
    }

    private var status: String {
        switch outcome {
        case .ready: "Modellschätzung"
        case .needsProfile: "Geburtsjahr fehlt"
        case .needsData(let have, let need): "\(have) von \(need) Tagen mit Daten"
        case .insufficient(let reason): reason
        }
    }
}

private struct AgeOrb: View {
    let tint: Color

    var body: some View {
        let outline = OrbOutline()
        ZStack {
            RadialGradient(colors: [tint.opacity(0.20), .clear], center: .center, startRadius: 36, endRadius: 120)
                .scaleEffect(1.25)
            outline
                .fill(RadialGradient(colors: [Color(hex: 0x0C0D0E), Color(hex: 0x0C0D0E), tint.opacity(0.45)],
                                     center: .center, startRadius: 15, endRadius: 124))
                .shadow(color: tint.opacity(0.24), radius: 22)
            outline
                .stroke(LinearGradient(colors: [tint.opacity(0.8), tint.opacity(0.1), tint.opacity(0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.3)
        }
    }
}

private struct OrbOutline: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0.52, 0.04))
        path.addCurve(to: p(0.95, 0.53), control1: p(0.80, 0.01), control2: p(0.98, 0.27))
        path.addCurve(to: p(0.46, 0.96), control1: p(0.92, 0.80), control2: p(0.71, 0.99))
        path.addCurve(to: p(0.05, 0.47), control1: p(0.22, 0.95), control2: p(0.01, 0.72))
        path.addCurve(to: p(0.52, 0.04), control1: p(0.10, 0.22), control2: p(0.28, 0.07))
        path.closeSubpath()
        return path
    }

}

struct HealthAgeSections: View {
    let outcome: BodyAge.Outcome

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            if case .ready(let result) = outcome {
                AgingPaceCard(pace: result.pace)
                VStack(alignment: .leading, spacing: Space.s2) {
                    DashboardHeading(title: "Beiträge zum Health Age")
                    DashboardCard {
                        ForEach(result.factors) { factor in
                            if factor.id != result.factors.first?.id { RowDivider() }
                            AgeFactorRow(factor: factor)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    DashboardHeading(title: "Health Age Trend")
                        .accessibilityIdentifier("health.age.trend.title")
                    DashboardCard {
                        if let previous = result.previous, let recent = result.recent {
                            AgeWindowChart(estimates: [previous, recent])
                        } else {
                            DashboardEmpty(title: "Noch nicht genug Verlauf")
                        }
                    }
                }
                .accessibilityIdentifier("health.age.trend")
            } else {
                AgingPaceCard(pace: nil)
            }
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
                    VStack(alignment: .leading, spacing: Space.s3) {
                        Text(Format.number(pace, decimals: 1) + "×")
                            .font(.formaWidgetNumber)
                            .accessibilityLabel(Format.number(pace, decimals: 1) + "-faches Alterungstempo")
                        paceScale(pace)
                        Text("1,0× entspricht dem Kalenderalter. Vergleich aus zwei 30-Tage-Fenstern.")
                            .font(.formaCaption)
                            .foregroundStyle(Theme.textSecondary)
                        if !(-1...3).contains(pace) {
                            Text("Der Wert liegt außerhalb der Skala.").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(Space.s4)
                } else {
                    DashboardEmpty(title: "Noch nicht genug Verlauf")
                }
            }
        }
        .accessibilityIdentifier("health.age.pace")
    }

    private func paceScale(_ pace: Double) -> some View {
        VStack(spacing: Space.s2) {
            HStack {
                Text("Langsam")
                Spacer()
                Text("Schnell")
            }
            GeometryReader { geometry in
                let span = geometry.size.width - 8
                let fraction = (min(3, max(-1, pace)) + 1) / 4
                ZStack(alignment: .leading) {
                    ForEach(0...40, id: \.self) { tick in
                        Capsule().fill(tick.isMultiple(of: 10) ? Theme.textTertiary : Theme.hairline)
                            .frame(width: 1, height: tick.isMultiple(of: 10) ? 20 : 12)
                            .offset(x: 4 + span * Double(tick) / 40)
                    }
                    Capsule().fill(Theme.textPrimary)
                        .frame(width: 4, height: 27)
                        .offset(x: 2 + span * fraction)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 29)
            HStack {
                Text("−1,0×")
                Spacer()
                Text("1,0×")
                Spacer()
                Text("3,0×")
            }
            .monospacedDigit()
        }
        .font(.formaCaption)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }
}

private struct AgeFactorRow: View {
    let factor: BodyAge.Factor

    var body: some View {
        let years = factor.years * BodyAge.overlapDamping
        let tint = BodyAgeText.color(years)
        let domain = min(factor.value, factor.displayRange.lowerBound)...max(factor.value, factor.displayRange.upperBound)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Label(factor.title, systemImage: factor.systemImage)
                    .font(.formaCaptionStrong)
                    .textCase(.uppercase)
                    .layoutPriority(1)
                Spacer(minLength: Space.s1)
                Text(BodyAgeText.signedYears(years))
                    .font(.formaValue)
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
            }
            Text(factor.valueText).font(.formaBody)
            GeometryReader { geometry in
                RangeBar(low: factor.referenceRange.lowerBound, high: factor.referenceRange.upperBound,
                         value: factor.value, minimum: domain.lowerBound, maximum: domain.upperBound,
                         dotColor: tint, width: geometry.size.width)
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            Text(factor.referenceText)
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
    }
}

private struct AgeWindowChart: View {
    let estimates: [BodyAge.Estimate]

    private var scale: ClosedRange<Double> {
        let values = estimates.flatMap { [$0.age, $0.bodyAge] }
        return ((values.min() ?? 0) - 0.6)...((values.max() ?? 1) + 0.6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Chart {
                ForEach(estimates) { period in
                    LineMark(x: .value("Fenstermitte", period.date), y: .value("Jahre", period.bodyAge),
                             series: .value("Reihe", "Health Age"))
                        .foregroundStyle(Theme.younger)
                    PointMark(x: .value("Fenstermitte", period.date), y: .value("Jahre", period.bodyAge))
                        .foregroundStyle(Theme.younger)
                        .symbolSize(45)
                    LineMark(x: .value("Fenstermitte", period.date), y: .value("Jahre", period.age),
                             series: .value("Reihe", "Kalenderalter"))
                        .foregroundStyle(Theme.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
            .chartYScale(domain: scale)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: estimates.map(\.date)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel().foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(height: 150)
            .accessibilityLabel("Health Age und Kalenderalter an den Mitten der zwei Zeitfenster")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s3) {
                    legend("Health Age", icon: "circle.fill", color: Theme.younger)
                    legend("Kalenderalter", icon: "line.diagonal", color: Theme.textTertiary)
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    legend("Health Age", icon: "circle.fill", color: Theme.younger)
                    legend("Kalenderalter", icon: "line.diagonal", color: Theme.textTertiary)
                }
            }
        }
        .padding(Space.s4)
    }

    private func legend(_ title: String, icon: String, color: Color) -> some View {
        Label {
            Text(title).foregroundStyle(Theme.textSecondary)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .font(.formaCaption)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct BodyAgeDetailView: View {
    @Environment(AppState.self) private var app
    let outcome: BodyAge.Outcome

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                switch outcome {
                case .ready(let result):
                    DashboardCard {
                        MetricRow(title: "Datenabdeckung", value: "\(result.daysWithData) von \(result.windowDays) Tagen")
                        RowDivider()
                        MetricRow(title: "Datenlage", value: result.confidence.title)
                    }
                    Text("Health Age und Alterungstempo sind Modellschätzungen. Für die Methode gibt es keine klinische Validierung.")
                        .font(.formaBody).foregroundStyle(Theme.textSecondary)
                    if !result.missing.isEmpty {
                        DashboardHeading(title: "Fehlende Daten")
                        ForEach(result.missing, id: \.self) { item in
                            Text(item).font(.formaBody).foregroundStyle(Theme.textSecondary)
                        }
                    }
                case .needsProfile:
                    Text("Für Health Age fehlt dein Geburtsjahr.").font(.formaBody)
                    Button("Profil öffnen") { app.showProfile = true }
                        .buttonStyle(.glass)
                        .frame(minHeight: 44)
                case .needsData(let have, let need):
                    Text("\(have) von \(need) Tagen mit Daten").font(.formaBody)
                case .insufficient(let reason):
                    Text(reason).font(.formaBody)
                }
                DashboardHeading(title: "Quellen")
                ForEach(Array(BodyAge.sources.enumerated()), id: \.offset) { _, source in
                    if let url = URL(string: source.url) {
                        Link(source.title, destination: url)
                            .font(.formaBody)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
            .padding(Space.s4)
        }
        .dashboardScreen()
        .navigationTitle("Datengrundlage")
        .navigationBarTitleDisplayMode(.inline)
    }
}
