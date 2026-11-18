import SwiftUI
import SwiftData

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


struct BodyAgeSummaryCard: View {
    let outcome: BodyAge.Outcome

    var body: some View {
        WidgetCard(title: "Health Age", systemImage: "hourglass") {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    if case .ready(let result) = outcome {
                        Text("\(BodyAgeText.years(result.bodyAge)) Jahre")
                            .font(.formaBigNumber)
                            .foregroundStyle(BodyAgeText.color(result.difference))
                    }
                    Text(status)
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(Space.s4)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
        .navigationTitle("Health Age")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultView(_ result: BodyAge.Result) -> some View {
        VStack(spacing: 0) {
            AgeArc(age: result.age, estimate: result.bodyAge)
            Text(BodyAgeText.difference(result))
                .font(.formaHeadline)
                .multilineTextAlignment(.center)
                .padding(.top, Space.s4)
            Text(hub.person.origin == .assumed ? "Beispiel mit angenommenem Alter" : "Nicht validierte Schätzung")
                .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                .padding(.top, Space.s1)

            FormaSection(title: "Trend") {
                Plate {
                    if let previous = result.previousBodyAge, let recent = result.recentBodyAge, let change = result.trend {
                        MetricRow(title: "Letzte 30 Tage", value: "\(BodyAgeText.years(recent)) Jahre")
                        RowDivider()
                        MetricRow(title: "30 Tage davor", value: "\(BodyAgeText.years(previous)) Jahre")
                        RowDivider()
                        MetricRow(title: "Veränderung", value: BodyAgeText.signedYears(change))
                    } else {
                        MetricRow(title: "Noch kein Vergleich verfügbar")
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

/// Ein offener Bogen mit dem eigenen Alter in der Mitte und der Schätzung auf der Skala.
private struct AgeArc: View {
    let age: Double
    let estimate: Double
    private let span = 15.0

    var body: some View {
        let tint = BodyAgeText.color(estimate - age)
        VStack(spacing: Space.s2) {
            ZStack(alignment: .bottom) {
                Canvas { context, size in
                    let radius = min(size.width / 2 - 12, size.height - 12)
                    guard radius > 0 else { return }
                    let center = CGPoint(x: size.width / 2, y: size.height - 6)
                    func point(_ degrees: Double, radius: CGFloat) -> CGPoint {
                        let angle = degrees * .pi / 180
                        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    }
                    var arc = Path()
                    arc.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                    context.stroke(arc, with: .color(Theme.track), lineWidth: 9)
                    for step in 0...30 {
                        let angle = 180 + Double(step) * 6
                        var tick = Path()
                        tick.move(to: point(angle, radius: radius - (step % 5 == 0 ? 8 : 3)))
                        tick.addLine(to: point(angle, radius: radius + 4))
                        context.stroke(tick, with: .color(step == 15 ? Theme.textSecondary : Theme.textQuaternary), lineWidth: 1)
                    }
                    let fraction = (min(span, max(-span, estimate - age)) + span) / (span * 2)
                    let mark = point(180 + fraction * 180, radius: radius)
                    let marker = Path(ellipseIn: CGRect(x: mark.x - 5, y: mark.y - 5, width: 10, height: 10))
                    context.fill(marker, with: .color(tint))
                }
                .accessibilityHidden(true)
                VStack(spacing: 0) {
                    Text(BodyAgeText.years(estimate)).font(.formaHero)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(tint)
                    Text("Jahre").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
                .padding(.bottom, Space.s2)
            }
            .frame(height: 145)

            HStack(spacing: Space.s1) {
                Text(BodyAgeText.years(age - span)).frame(maxWidth: .infinity, alignment: .leading)
                Text("Dein Alter \(BodyAgeText.years(age.rounded(.down)))").frame(maxWidth: .infinity)
                Text(BodyAgeText.years(age + span)).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.formaCaption).monospacedDigit().foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: 310)
        .padding(.top, Space.s5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Geschätzt \(BodyAgeText.years(estimate)) Jahre. Dein Alter \(BodyAgeText.years(age.rounded(.down))) Jahre.")
    }
}
