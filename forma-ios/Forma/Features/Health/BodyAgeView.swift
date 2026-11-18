import SwiftUI
import SwiftData

struct BodyAgeRoute: Hashable {}

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
        if abs(rounded) < 0.5 { return "kaum Einfluss" }
        return (rounded < 0 ? "−" : "+") + Format.number(abs(rounded), decimals: rounded.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1) + " J."
    }

    static func difference(_ result: BodyAge.Result) -> String {
        let d = result.bodyAge.rounded() - result.age.rounded(.down)
        if d == 0 { return "Etwa so alt wie du bist" }
        let n = Int(abs(d))
        return "Etwa \(n) \(n == 1 ? "Jahr" : "Jahre") \(d < 0 ? "jünger" : "älter") als du bist"
    }

    static func color(_ difference: Double) -> Color {
        abs(difference) < 1 ? Theme.textPrimary : (difference < 0 ? Theme.younger : Theme.older)
    }
}

/// Skala: echtes Alter als Strich, Körperalter als leuchtender Punkt.
struct AgeScale: View {
    let age: Double
    let bodyAge: Double
    var span: Double = 12

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let lo = age - span, hi = age + span
            let x: (Double) -> CGFloat = { v in CGFloat((min(hi, max(lo, v)) - lo) / (hi - lo)) * w }
            let color = BodyAgeText.color(bodyAge - age)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(LinearGradient(colors: [Theme.younger.opacity(0.35), Color.white.opacity(0.08), Theme.older.opacity(0.35)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
                    .offset(y: 7)
                Capsule().fill(color)
                    .frame(width: max(2, abs(x(bodyAge) - x(age))), height: 6)
                    .offset(x: min(x(bodyAge), x(age)), y: 7)
                Rectangle().fill(Theme.textPrimary).frame(width: 2, height: 20)
                    .offset(x: x(age) - 1)
                Circle().fill(color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                    .shadow(color: color.opacity(0.7), radius: 6)
                    .offset(x: x(bodyAge) - 7, y: 3)
                Text("dein Alter").font(.formaMicro).foregroundStyle(Theme.textTertiary)
                    .fixedSize()
                    .offset(x: x(age) - 26, y: 24)
            }
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }
}

/// Kachel für „Heute“.
struct BodyAgeTile: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    var open: () -> Void

    var body: some View {
        BodyAgeSummaryCard(outcome: bodyAgeOutcome(hub: hub, sessions: sessions), open: open) { app.showProfile = true }
    }
}

/// Karte mit Körperalter, genutzt auf „Heute“ und in „Gesundheit“.
struct BodyAgeSummaryCard: View {
    let outcome: BodyAge.Outcome
    var open: () -> Void
    var openProfile: () -> Void

    var body: some View {
        switch outcome {
        case .ready(let r):
            Button(action: open) {
                WidgetCard(title: "Körperalter", systemImage: "hourglass", accessory: "Schätzung · \(r.windowDays) Tage") {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(BodyAgeText.years(r.bodyAge))
                                .font(.formaWidgetNumber)
                                .foregroundStyle(BodyAgeText.color(r.difference))
                            Text("Jahre").font(.formaBody).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textQuaternary)
                        }
                        Text(BodyAgeText.difference(r))
                            .font(.formaBody)
                            .foregroundStyle(Theme.textSecondary)
                        AgeScale(age: r.age, bodyAge: r.bodyAge)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.top, 4)
                    .padding(.bottom, Space.s4)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Körperalter \(BodyAgeText.years(r.bodyAge)) Jahre, \(BodyAgeText.difference(r))")
        case .needsProfile:
            WidgetCard(title: "Körperalter", systemImage: "hourglass") {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("Für dein Körperalter brauche ich dein Geburtsjahr. Das Geschlecht ist nur für den VO₂max-Vergleich nötig.")
                        .font(.formaBody).foregroundStyle(Theme.textSecondary)
                    Button("Im Profil eintragen", action: openProfile).buttonStyle(.glass)
                }
                .padding([.horizontal, .bottom], Space.s4)
                .padding(.top, 4)
            }
        case .needsData(let have, let need):
            WidgetCard(title: "Körperalter", systemImage: "hourglass", accessory: "\(have) von \(need) Tagen") {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("Ich brauche noch \(need - have) Tage mit Schlaf, Puls oder Schritten.")
                        .font(.formaBody).foregroundStyle(Theme.textSecondary)
                    ProgressLine(fraction: Double(have) / Double(need), height: 4)
                }
                .padding([.horizontal, .bottom], Space.s4)
                .padding(.top, 4)
            }
        }
    }
}

struct BodyAgeDetailView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        let outcome = bodyAgeOutcome(hub: hub, sessions: sessions)
        let tint: Color? = { if case .ready(let r) = outcome, abs(r.difference) >= 0.5 { return BodyAgeText.color(r.difference) }; return nil }()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch outcome {
                case .ready(let r): content(r)
                default:
                    BodyAgeSummaryCard(outcome: outcome, open: {}, openProfile: { app.showProfile = true })
                        .padding(.top, Space.s4)
                }
                method
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.page)
        }
        .formaScreen(tint: tint)
        .navigationTitle("Körperalter")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func content(_ r: BodyAge.Result) -> some View {
        VStack(spacing: Space.s2) {
            Text("Geschätztes Körperalter")
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(BodyAgeText.years(r.bodyAge))
                    .font(.system(size: 76, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BodyAgeText.color(r.difference))
                    .shadow(color: BodyAgeText.color(r.difference).opacity(0.35), radius: 24)
                    .contentTransition(.numericText(value: r.bodyAge.rounded()))
                Text("Jahre").font(.formaHeadline).foregroundStyle(Theme.textSecondary)
            }
            Text(BodyAgeText.difference(r))
                .font(.formaHeadline)
            Text("Dein Alter: \(Int(r.age.rounded(.down))) Jahre")
                .font(.formaBody).foregroundStyle(Theme.textSecondary)
            AgeScale(age: r.age, bodyAge: r.bodyAge)
                .padding(.top, Space.s4)
                .padding(.horizontal, Space.s4)
            personNote
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s5)

        VStack(spacing: Space.s3) {
            WidgetCard(title: "Letzte 30 Tage gegenüber den 30 Tagen davor", systemImage: "arrow.left.arrow.right") {
                if let recent = r.recentBodyAge, let previous = r.previousBodyAge, let trend = r.trend {
                    MetricRow(title: abs(trend) < 0.5 ? "Kein deutlicher Unterschied" : (trend < 0 ? "Zuletzt günstiger" : "Zuletzt ungünstiger"),
                              subtitle: "Davor etwa \(BodyAgeText.years(previous)), zuletzt etwa \(BodyAgeText.years(recent)) Jahre",
                              value: BodyAgeText.signedYears(trend), valueColor: BodyAgeText.color(trend * 2))
                } else {
                    MetricRow(title: "Noch kein Vergleich", subtitle: "Dafür brauche ich in beiden Zeiträumen genug Daten mit denselben Faktoren.")
                }
            }

            WidgetCard(title: "Was dein Körperalter ausmacht", systemImage: "list.bullet", accessory: "in Jahren") {
                ForEach(Array(r.factors.enumerated()), id: \.element.id) { i, f in
                    if i > 0 { RowDivider() }
                    FactorRow(factor: f)
                }
            }

            if !r.missing.isEmpty {
                WidgetCard(title: "Noch nicht berücksichtigt", systemImage: "questionmark.circle") {
                    ForEach(Array(r.missing.enumerated()), id: \.offset) { i, text in
                        if i > 0 { RowDivider() }
                        MetricRow(title: text)
                    }
                }
            }

            WidgetCard(title: "Datengrundlage", systemImage: "gauge.with.dots.needle.33percent") {
                MetricRow(title: "Datenabdeckung", subtitle: "\(r.daysWithData) von \(r.windowDays) Tagen mit Daten · \(r.factors.count) von 5 Faktoren",
                          value: r.confidence.title)
                RowDivider()
                Text("Die Abdeckung sagt, wie vollständig deine Daten sind – nicht, wie genau die Schätzung ist. Die Methode ist nicht an Einzelpersonen geprüft.")
                    .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    .padding(Space.s4)
            }
        }
        .padding(.top, Space.s6)
    }

    @ViewBuilder private var personNote: some View {
        let p = hub.person
        switch p.origin {
        case .assumed:
            Button { app.showProfile = true } label: {
                SampleDataBadge(text: "Beispielrechnung: 30 Jahre, \(p.sex.title.lowercased()) – im Profil ändern")
            }
            .buttonStyle(.plain)
            .padding(.top, Space.s3)
        case .health:
            Text("Alter und Geschlecht aus Apple Health").font(.formaCaption).foregroundStyle(Theme.textTertiary).padding(.top, Space.s2)
        default:
            EmptyView()
        }
    }

    private var method: some View {
        FormaSection(title: "So wird gerechnet") {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("**Deine Messwerte:** Für jeden Faktor nehme ich deinen Durchschnitt der letzten bis zu 180 Tage (VO₂max: letzte 90 Tage).")
                Text("**Vergleich in Studien:** Wie stark ein Unterschied mit dem Sterberisiko zusammenhängt, stammt aus großen Meta-Analysen. Das sind Gruppenbefunde, keine Aussagen über dich.")
                Text("**So entsteht die Zahl:** Das Risiko rechne ich mit der Faustregel „Verdopplung etwa alle 8 Jahre“ (Gompertz) in Jahre um. Weil die Faktoren zusammenhängen, zählt die Summe nur zu 70 %, höchstens ±15 Jahre. Vergleichswerte, 70 % und Grenzen sind Annahmen von Forma. Die Zeilen oben zeigen die Beiträge bereits mit 70 %, sie ergeben zusammen den Abstand zu deinem Alter.")
                Text("HRV fließt nicht ein: Apple misst SDNN, Fitbit RMSSD, und das Modell ist dafür nicht geprüft.")
                Text("Eine Schätzung zur Orientierung und Motivation, keine Diagnose.")
            }
            .font(.formaBody)
            .foregroundStyle(Theme.textSecondary)

            Plate {
                ForEach(Array(BodyAge.sources.enumerated()), id: \.offset) { i, source in
                    if i > 0 { RowDivider() }
                    if let url = URL(string: source.url) {
                        Link(destination: url) {
                            MetricRow(title: source.title) {
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, Space.s2)
        }
    }
}

private struct FactorRow: View {
    let factor: BodyAge.Factor
    @State private var expanded = false

    var body: some View {
        Button { withAnimation(.snappy) { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s3) {
                    Glyph(systemName: factor.systemImage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(factor.title).font(.formaRowTitle)
                        Text(factor.valueText).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                        Text(factor.coverage).font(.formaMicro).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: Space.s2)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(BodyAgeText.signedYears(factor.years * BodyAge.overlapDamping))
                            .font(.formaValue)
                            .foregroundStyle(BodyAgeText.color(factor.years * BodyAge.overlapDamping * 2))
                        DivergingBar(value: abs(factor.years * BodyAge.overlapDamping) < 0.5 ? 0 : factor.years * BodyAge.overlapDamping, limit: 4, width: 84)
                    }
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(factor.referenceText).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                        Text(factor.explanation).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                        Text(factor.source).font(.formaMicro).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.leading, 48)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded ? "Erklärung ausblenden" : "Erklärung zeigen")
    }
}
