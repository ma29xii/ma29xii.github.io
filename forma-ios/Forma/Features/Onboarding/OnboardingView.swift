import SwiftUI

/// Erster Start: ein ruhiger Bildschirm. Google Health verbinden oder erst mit Beispieldaten ansehen.
struct OnboardingView: View {
    @Environment(DataHub.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @AppStorage("forma.onboarded") private var onboarded = false

    var body: some View {
        let status = GoogleStatus(hub.google)
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Space.s6)
            HStack(spacing: -10) {
                RingView(value: 88, color: Theme.sleep, size: 64, lineWidth: 4, showsNumber: false)
                RingView(value: 75, color: Theme.recoveryHigh, size: 80, lineWidth: 4.5, showsNumber: false)
                RingView(value: 42, color: Theme.strain, size: 64, lineWidth: 4, showsNumber: false)
            }
            .accessibilityHidden(true)
            Text("Health").formaLabelStyle().padding(.top, Space.s6)
            Text("Jeden Morgen wissen, was heute passt.")
                .font(.formaLargeTitle)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s2)
            Text("Sleep, Recovery und Strain aus deinen Google-Health-Daten. Dazu dein Krafttraining.")
                .font(.formaBodyLarge)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s3)
            Spacer()
            VStack(spacing: Space.s2) {
                Button {
                    Task { await connect() }
                } label: {
                    HStack(spacing: Space.s2) {
                        if status.isBusy { ProgressView().tint(Theme.onSelection) }
                        Text("Mit Google Health verbinden")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(status.isBusy || hub.google == .notConfigured)
                .accessibilityIdentifier("onboarding.google")

                if hub.google == .notConfigured || status.tone == .problem {
                    Text(status.detail ?? status.title)
                        .font(.formaCaption)
                        .foregroundStyle(status.tone == .problem ? Theme.warning : Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Button("Erst mit Beispieldaten ansehen") {
                    hub.preferredSource = .sample
                    finish()
                }
                .font(.system(.callout, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("onboarding.sample")
            }
            Text("Du kannst das jederzeit im Profil ändern.")
                .font(.formaCaption).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s1)
        }
        .padding(.horizontal, Space.s5)
        .padding(.bottom, Space.s4)
        .background(ScreenBackground())
        .foregroundStyle(Theme.textPrimary)
        .interactiveDismissDisabled()
    }

    private func connect() async {
        await hub.connectGoogle()
        guard case .connected = hub.google else { return }
        if hub.isSample { hub.preferredSource = .google }
        finish()
    }

    private func finish() {
        onboarded = true
        dismiss()
    }
}
