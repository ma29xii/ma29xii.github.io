import SwiftUI

/// Erster Start: Datenquelle wählen. Erscheint einmal.
struct OnboardingView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("forma.onboarded") private var onboarded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Space.s6)
            HStack(spacing: -10) {
                RingView(value: 42, color: Theme.strain, size: 64, lineWidth: 4, showsNumber: false)
                RingView(value: 75, color: Theme.recoveryHigh, size: 80, lineWidth: 4.5, showsNumber: false)
                RingView(value: 88, color: Theme.sleep, size: 64, lineWidth: 4, showsNumber: false)
            }
            .accessibilityHidden(true)
            Text("Willkommen bei Health").font(.formaLargeTitle).padding(.top, Space.s6)
            Text("Drei Werte für jeden Morgen: wie erholt du bist, wie gut du geschlafen hast und wie viel Belastung heute passt. Dazu dein Krafttraining.")
                .font(.formaBodyLarge).foregroundStyle(Theme.textSecondary).padding(.top, Space.s3)
            Spacer()
            VStack(spacing: Space.s3) {
                Button {
                    Task {
                        await hub.requestHealthAccess()
                        finish()
                    }
                } label: { Text("Mit Apple Health verbinden") }
                .buttonStyle(PrimaryButtonStyle())
                Button("Erst mit Beispieldaten ansehen") {
                    hub.preferredSource = .sample
                    finish()
                }
                    .font(.formaBody)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
            }
            Text("Health rechnet auf deinem iPhone. Nur wenn du später den Claude-Coach einschaltest, gehen ausgewählte Werte an Anthropic – das fragt dich Health vorher.")
                .font(.formaCaption).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.bottom, Space.s4)
        .background(ScreenBackground())
        .foregroundStyle(Theme.textPrimary)
        .interactiveDismissDisabled()
    }

    private func finish() {
        onboarded = true
        dismiss()
    }
}
