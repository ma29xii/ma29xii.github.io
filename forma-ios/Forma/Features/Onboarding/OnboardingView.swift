import SwiftUI

/// Erster Start: ein ruhiger Bildschirm. Google Health verbinden oder erst mit Beispieldaten ansehen.
struct OnboardingView: View {
    @Environment(DataHub.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @AppStorage("forma.onboarded") private var onboarded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ringe füllen sich beim Erscheinen einmal ruhig (0 → 1).
    @State private var fill: Double = 0
    /// Große Überschrift, wächst mit Dynamic Type (die ScrollView fängt Überlänge ab).
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40

    var body: some View {
        let status = GoogleStatus(hub.google)
        // ScrollView, damit bei großer Schrift nichts abgeschnitten wird; auf großen Bildschirmen füllt der Inhalt die Höhe.
        GeometryReader { proxy in
        ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Space.s6)
            HStack(spacing: -10) {
                RingView(value: 88 * fill, color: Theme.sleep, size: 64, lineWidth: 4, showsNumber: false)
                RingView(value: 75 * fill, color: Theme.recoveryHigh, size: 80, lineWidth: 4.5, showsNumber: false)
                RingView(value: 42 * fill, color: Theme.strain, size: 64, lineWidth: 4, showsNumber: false)
            }
            .accessibilityHidden(true)
            Text("Jeden Morgen wissen, was heute passt.")
                .font(.system(size: titleSize, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s6)
            Spacer()
            VStack(spacing: Space.s2) {
                if hub.google != .notConfigured {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack(spacing: Space.s2) {
                            if status.isBusy { ProgressView().tint(Theme.onSelection) }
                            Text("Mit Google Health verbinden")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(status.isBusy)
                    .accessibilityIdentifier("onboarding.google")

                    if status.tone == .problem {
                        Text(status.detail ?? status.title)
                            .font(.formaCaption)
                            .foregroundStyle(Theme.warning)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    Button("Erst mit Beispieldaten ansehen") { startWithSample() }
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("onboarding.sample")
                } else {
                    // Ohne Google-Anmeldung im Build ist Ansehen der einzige Weg: dann als Hauptknopf.
                    Button("Mit Beispieldaten ansehen") { startWithSample() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("onboarding.sample")
                }
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.bottom, Space.s4)
        .frame(minHeight: proxy.size.height)
        }
        .scrollBounceBehavior(.basedOnSize)
        }
        .background(ScreenBackground())
        .foregroundStyle(Theme.textPrimary)
        .interactiveDismissDisabled()
        .onAppear {
            guard fill == 0 else { return }
            if reduceMotion { fill = 1 } else { withAnimation(.smooth(duration: 1.4).delay(0.2)) { fill = 1 } }
        }
    }

    private func startWithSample() {
        hub.preferredSource = .sample
        finish()
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
