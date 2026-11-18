import SwiftUI
import SwiftData
import Charts

@MainActor
func bodyAgeOutcome(hub: DataHub, sessions: [WorkoutSession]) -> BodyAge.Outcome {
    let forma = sessions.map { (start: $0.start, minutes: $0.duration / 60) }
    let strength = BodyAge.strengthMinutes(days: hub.longDays, formaSessions: forma)
    return BodyAge.evaluate(days: hub.longDays, person: hub.person, strength: strength)
}

enum BodyAgeText {
    /// Ganze Jahre: Eine Nachkommastelle würde Genauigkeit vortäuschen (Codex R-01-01).
    static func years(_ value: Double) -> String {
        Format.number(value.rounded(), decimals: 0)
    }

    static func signedYears(_ value: Double) -> String {
        let rounded = (value * 2).rounded() / 2
        if abs(rounded) < 0.5 { return "unter ½ Jahr" }
        return (rounded < 0 ? "−" : "+") + Format.number(abs(rounded), decimals: rounded.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1) + " J."
    }

    static func difference(_ result: BodyAge.Result) -> String {
        // Aus der *ungerundeten* Differenz – sonst entsteht aus 30,8 vs. 30,8 ein „1 Jahr älter“ (Codex A-15).
        let d = (result.bodyAge - result.age).rounded()
        if d == 0 { return "Etwa so alt wie du bist" }
        let n = Int(abs(d))
        return "Etwa \(n) \(n == 1 ? "Jahr" : "Jahre") \(d < 0 ? "jünger" : "älter") als du bist"
    }

    static func color(_ difference: Double) -> Color {
        abs(difference) < 1 ? Theme.textPrimary : (difference < 0 ? Theme.younger : Theme.older)
    }
}
struct HealthAgeHero: View {
    let outcome: BodyAge.Outcome
    var showsDetails = true

    var body: some View {
        Plate {
            VStack(spacing: Space.s3) {
                if case .ready(let result) = outcome {
                    AgePortrait(result: result)
                    RowDivider(inset: 0)
                    comparison(result)
                } else {
                    Text("–").font(.formaHero).foregroundStyle(Theme.textSecondary)
                    Text(status)
                        .font(.formaRowTitle)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if showsDetails {
                    HStack {
                        Text("Details").font(.formaCaptionStrong)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.formaCaptionStrong)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Space.s4)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func comparison(_ result: BodyAge.Result) -> some View {
        let age = BodyAgeText.years(result.age.rounded(.down)) + " Jahre"
        let trend = result.trend.map(BodyAgeText.signedYears) ?? "Noch kein Vergleich"
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.s4) {
                statistic("Dein Alter", value: age)
                statistic("30-Tage-Trend", value: trend)
            }
            VStack(alignment: .leading, spacing: Space.s3) {
                statistic("Dein Alter", value: age)
                statistic("30-Tage-Trend", value: trend)
            }
        }
    }

    private func statistic(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).font(.formaCaption).foregroundStyle(Theme.textSecondary)
            Text(value).font(.formaValue)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: String {
        switch outcome {
        case .ready: "Nicht validierte Schätzung"
        case .needsProfile: "Geburtsjahr fehlt"
        case .needsData(let have, let need): "\(have) von \(need) Tagen mit Daten"
        case .insufficient: "Keine Schätzung verfügbar"
        }
    }
}

struct BodyAgeDetailView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        let outcome = bodyAgeOutcome(hub: hub, sessions: sessions)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hub.isSample { SampleDataBadge() }
                switch outcome {
                case .ready(let result):
                    resultView(result)
                case .needsProfile:
                    empty("Für Health Age fehlt dein Geburtsjahr.", offersProfile: true)
                case .needsData(let have, let need):
                    empty("\(have) von \(need) Tagen mit Daten", offersProfile: false)
                case .insufficient(let reason):
                    empty(reason, offersProfile: true)
                }

                NavigationLink {
                    sources
                } label: {
                    Label("Quellen", systemImage: "book")
                        .font(.formaCaption)
                        .frame(minHeight: 44)
                }
                .padding(.top, Space.s4)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .formaScreen()
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultView(_ result: BodyAge.Result) -> some View {
        VStack(spacing: 0) {
            HealthAgeHero(outcome: .ready(result), showsDetails: false)
                .padding(.top, Space.s3)
            Text(hub.person.origin == .assumed ? "Beispiel mit angenommenem Alter" : "Nicht validierte Schätzung")
                .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                .padding(.top, Space.s1)

            FormaSection(title: "30-Tage-Vergleich") {
                if let previous = result.previousBodyAge, let recent = result.recentBodyAge {
                    AgeWindowChart(previous: previous, recent: recent, age: result.age)
                } else {
                    Plate { MetricRow(title: "Noch kein Vergleich verfügbar") }
                }
            }

            FormaSection(title: "Messwerte im Altersmodell") {
                Plate {
                    ForEach(result.factors) { factor in
                        AgeFactorRow(factor: factor)
                        if factor.id != result.factors.last?.id { RowDivider() }
                    }
                }
            }

            FormaSection(title: "Datengrundlage") {
                Plate {
                    MetricRow(title: "Tage mit Daten", value: "\(result.daysWithData) von \(result.windowDays)")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func empty(_ message: String, offersProfile: Bool) -> some View {
        VStack(spacing: Space.s3) {
            Text("–").font(.formaHero).foregroundStyle(Theme.textSecondary)
            Text(message)
                .font(.formaBody).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if offersProfile {
                Button("Profil öffnen") { app.showProfile = true }
                    .buttonStyle(.glass)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
    }

    private var sources: some View {
        List {
            ForEach(Array(BodyAge.sources.enumerated()), id: \.offset) { _, source in
                if let url = URL(string: source.url) { Link(source.title, destination: url) }
            }
        }
        .formaScreen()
        .navigationTitle("Quellen")
        .navigationBarTitleDisplayMode(.inline)
    }
}


private struct AgePortrait: View {
    let result: BodyAge.Result

    var body: some View {
        let tint = BodyAgeText.color(result.difference)
        VStack(spacing: Space.s1) {
            Text(BodyAgeText.years(result.bodyAge))
                .font(.formaHero)
                .foregroundStyle(Theme.textPrimary)
            Text("Geschätztes Alter · in Jahren")
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.textSecondary)
            Text(BodyAgeText.difference(result))
                .font(.formaRowTitle)
                .foregroundStyle(tint)
                .padding(.top, Space.s1)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s6)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background {
            GeometryReader { geometry in
                let width = min(geometry.size.width, 400)
                let height = geometry.size.height
                ZStack {
                    RadialGradient(colors: [tint.opacity(0.15), .clear],
                                   center: .center, startRadius: 25, endRadius: width * 0.58)
                    ForEach(0..<6) { index in
                        let offset = CGFloat(index)
                        let contourWidth = width * (0.9 - offset * 0.055)
                        let contourHeight = height * (0.67 + offset * 0.027)
                        Ellipse()
                            .stroke(
                                LinearGradient(colors: [.clear, tint.opacity(0.18), tint.opacity(0.59)],
                                               startPoint: .topTrailing, endPoint: .bottomLeading),
                                lineWidth: index == 0 ? 1.3 : 0.75
                            )
                            .frame(width: contourWidth, height: contourHeight)
                            .rotationEffect(.degrees(Double(index) * 5 - 18))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Geschätztes Alter \(BodyAgeText.years(result.bodyAge)) Jahre. \(BodyAgeText.difference(result)).")
    }
}

private struct AgeWindowChart: View {
    let previous: Double
    let recent: Double
    let age: Double

    private struct Window: Identifiable {
        let title: String
        let years: Double
        var id: String { title }
    }

    var body: some View {
        let windows = [Window(title: "30 Tage davor", years: previous), Window(title: "Letzte 30 Tage", years: recent)]
        let tint = BodyAgeText.color(recent - age)
        Plate {
            VStack(alignment: .leading, spacing: Space.s3) {
                Chart {
                    RuleMark(y: .value("Dein Alter", age))
                        .foregroundStyle(Theme.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    ForEach(windows) { window in
                        LineMark(x: .value("Zeitraum", window.title), y: .value("Geschätztes Alter", window.years))
                            .foregroundStyle(tint)
                        PointMark(x: .value("Zeitraum", window.title), y: .value("Geschätztes Alter", window.years))
                            .foregroundStyle(tint)
                            .symbolSize(52)
                    }
                }
                .chartXScale(domain: windows.map(\.title))
                .chartYScale(domain: (min(previous, recent, age) - 1)...(max(previous, recent, age) + 1))
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel().foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(height: 144)
                .accessibilityLabel("Health Age im Vergleich zu deinem Alter")
                Text("Dein Alter · \(BodyAgeText.years(age.rounded(.down))) Jahre")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Space.s4)
            RowDivider()
            MetricRow(title: "30 Tage davor", value: BodyAgeText.years(previous), unit: "Jahre")
            RowDivider()
            MetricRow(title: "Letzte 30 Tage", value: BodyAgeText.years(recent), unit: "Jahre")
        }
    }
}

private struct AgeFactorRow: View {
    let factor: BodyAge.Factor

    var body: some View {
        let years = factor.years * BodyAge.overlapDamping
        let normalized = max(-1, min(1, years / 4.5))
        let tint = years < 0 ? Theme.younger : Theme.older
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(factor.title).font(.formaRowTitle)
                    Text(factor.valueText).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: Space.s2)
                Text(BodyAgeText.signedYears(years))
                    .font(.formaValue)
                    .foregroundStyle(abs(years) < 0.5 ? Theme.textSecondary : tint)
            }
            GeometryReader { geometry in
                let center = geometry.size.width / 2
                let length = center * CGFloat(abs(normalized))
                Capsule().fill(Theme.track)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint)
                            .frame(width: length, height: 4)
                            .offset(x: normalized < 0 ? center - length : center)
                    }
                    .overlay {
                        Rectangle().fill(Theme.textTertiary).frame(width: 1, height: 9)
                    }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
    }
}
