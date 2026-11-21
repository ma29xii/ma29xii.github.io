import SwiftUI

struct HealthAgeWhatIfLink: View {
    let result: BodyAge.Result

    var body: some View {
        NavigationLink {
            HealthAgeWhatIfView(result: result)
        } label: {
            DashboardCard {
                Label("Was wäre wenn", systemImage: "slider.horizontal.3")
                    .font(.formaRowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(Space.card)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.formaCard)
        .accessibilityIdentifier("health.age.whatIf")
    }
}

private struct HealthAgeWhatIfView: View {
    let result: BodyAge.Result
    @Environment(DataHub.self) private var hub
    @State private var changes: [BodyAge.AdjustableFactor: Double] = [:]

    private var factors: [BodyAge.AdjustableFactor] {
        BodyAge.AdjustableFactor.allCases.filter { metric in result.factors.contains { $0.id == metric.rawValue } }
    }

    var body: some View {
        let age = BodyAge.projectedAge(result, changes: changes)
        let ageText = Format.number(age, decimals: BodyAgeText.decimals(result))
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if hub.isSample { SampleDataBadge() }
                DashboardCard {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        DashboardHeading(title: "Health Age")
                        Text(ageText)
                            .font(.formaBigNumber)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.card)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Health Age im Szenario")
                    .accessibilityValue("\(ageText) Jahre")
                }
                DashboardCard {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(factors, id: \.self) { metric in
                            control(metric)
                        }
                    }
                    .padding(Space.card)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .dashboardScreen()
        .navigationTitle("Was wäre wenn")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func control(_ metric: BodyAge.AdjustableFactor) -> some View {
        let config = metric.control
        let amount = changes[metric, default: 0]
        let sign = amount < 0 ? "−" : (amount > 0 ? "+" : "")
        let value = "\(sign)\(Format.number(abs(amount))) \(config.unit)"
        return VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s3) {
                    Text(config.title).fixedSize()
                    Spacer(minLength: 0)
                    Text(value).monospacedDigit().fixedSize()
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(config.title)
                    Text(value).monospacedDigit()
                }
            }
            .font(.formaBody)
            .foregroundStyle(Theme.textPrimary)
            .accessibilityHidden(true)
            Slider(value: Binding(get: { changes[metric, default: 0] }, set: { changes[metric] = $0 }),
                   in: -config.limit...config.limit, step: config.step)
                .frame(minHeight: 44)
                .accessibilityLabel(config.title)
                .accessibilityValue(value)
        }
    }
}

private extension BodyAge.AdjustableFactor {
    var control: (title: String, unit: String, limit: Double, step: Double) {
        switch self {
        case .sleep: ("Schlaf", "min", 60, 5)
        case .steps: ("Schritte", "pro Tag", 5_000, 500)
        case .strength: ("Krafttraining", "min/Woche", 120, 5)
        case .restingHR: ("Ruhepuls", "bpm", 5, 1)
        }
    }
}
