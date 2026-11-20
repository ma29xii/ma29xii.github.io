import SwiftUI

struct HealthStartupView: View {
    var body: some View {
        VStack(spacing: Space.s4) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Health").font(.formaDisplay).foregroundStyle(Theme.textPrimary)
            ProgressView()
                .tint(Theme.accent)
                .accessibilityLabel("Health wird geladen")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Theme.backgroundTop
                RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .center,
                               startRadius: 24, endRadius: 220)
            }
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .combine)
    }
}
