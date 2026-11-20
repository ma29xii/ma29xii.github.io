import SwiftUI

/// Einstieg im Stress Monitor.
struct BreathingLink: View {
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            DashboardCard {
                HStack(spacing: Space.s3) {
                    Image(systemName: "wind")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.sleep)
                        .frame(width: 28)
                    DashboardHeading(title: "Atmen")
                    Spacer(minLength: Space.s2)
                    Image(systemName: "play.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Theme.plate, in: Circle())
                }
                .padding(Space.s4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Atemübung starten")
        .accessibilityIdentifier("breathing.open")
        .fullScreenCover(isPresented: $open) { BreathingSession() }
    }
}

/// Resonanzatmung: 5,5 s ein, 5,5 s aus (≈ 5,5 Atemzüge pro Minute).
struct BreathingSession: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var minutes = 1
    @State private var start: Date?
    @State private var phases = 0
    @State private var finished = false

    nonisolated static let half = 5.5

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(colors: [Theme.sleep.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 460)
                .ignoresSafeArea()
            if finished {
                summary
            } else if let start {
                TimelineView(.animation) { tick in
                    running(elapsed: tick.date.timeIntervalSince(start))
                }
            } else {
                setup
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.plate, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(Space.page)
            .accessibilityLabel("Schließen")
            .accessibilityIdentifier("breathing.close")
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .light), trigger: phases)
        .task(id: start) { await run() }
    }

    // MARK: Ablauf

    private func run() async {
        guard let start else { return }
        let total = Double(minutes) * 60
        while true {
            let elapsed = Date.now.timeIntervalSince(start)
            if elapsed >= total { break }
            let next = (floor(elapsed / Self.half) + 1) * Self.half
            do { try await Task.sleep(for: .seconds(min(next, total) - elapsed)) } catch { return }
            phases += 1
            if Date.now.timeIntervalSince(start) < total {
                AccessibilityNotification.Announcement(Self.isInhale(phases) ? "Einatmen" : "Ausatmen").post()
            }
        }
        withAnimation(.easeOut(duration: 0.4)) { finished = true }
    }

    nonisolated static func isInhale(_ phase: Int) -> Bool { phase.isMultiple(of: 2) }

    /// 0 = ausgeatmet, 1 = eingeatmet; weich über eine Kosinuskurve.
    nonisolated static func fill(at elapsed: TimeInterval) -> Double {
        let cycle = elapsed.truncatingRemainder(dividingBy: 2 * half)
        let progress = cycle < half ? cycle / half : 1 - (cycle - half) / half
        return (1 - cos(progress * .pi)) / 2
    }

    // MARK: Ansichten

    private var setup: some View {
        VStack(spacing: Space.s6) {
            Spacer()
            orb(fill: 0.35, phase: 0)
            Text("Atmen")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("breathing.title")
            HStack(spacing: Space.s2) {
                ForEach([1, 3, 5], id: \.self) { value in
                    Button { minutes = value } label: {
                        Text("\(value) min")
                            .font(.formaRowTitle)
                            .monospacedDigit()
                            .foregroundStyle(minutes == value ? Theme.onSelection : Theme.textPrimary)
                            .frame(width: 84, height: 44)
                            .background(minutes == value ? Theme.selection : Theme.plate, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(minutes == value ? .isSelected : [])
                }
            }
            Spacer()
            Button { start = .now; phases = 0 } label: {
                Text("Starten")
                    .font(.formaRowTitle)
                    .foregroundStyle(Theme.onSelection)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.selection, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("breathing.start")
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.s5)
    }

    private func running(elapsed: TimeInterval) -> some View {
        let remaining = max(0, Double(minutes) * 60 - elapsed)
        let inhale = Self.isInhale(Int(elapsed / Self.half))
        return VStack(spacing: Space.s6) {
            Spacer()
            ZStack {
                orb(fill: reduceMotion ? 0.6 : Self.fill(at: elapsed), phase: elapsed)
                Text(inhale ? "Einatmen" : "Ausatmen")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: inhale)
            }
            Spacer()
            Text(Format.clock(remaining: remaining))
                .font(.formaNumber)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Verbleibend")
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.s6)
    }

    private var summary: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.younger)
                .frame(width: 96, height: 96)
                .background(Theme.younger.opacity(0.14), in: Circle())
            Text("\(max(1, phases / 2)) Atemzüge")
                .font(.formaTitle)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text("\(minutes) min")
                .font(.formaHeadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { dismiss() } label: {
                Text("Fertig")
                    .font(.formaRowTitle)
                    .foregroundStyle(Theme.onSelection)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.selection, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("breathing.done")
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.s5)
    }

    /// Weiche, leuchtende Kugel aus drei Farbschichten, die mit dem Atem wächst.
    private func orb(fill: Double, phase: TimeInterval) -> some View {
        let size = 140 + 140 * fill
        let drift = reduceMotion ? 0 : phase * 0.35
        return ZStack {
            Circle().fill(Theme.sleep.opacity(0.55))
                .frame(width: size, height: size)
                .offset(x: cos(drift) * 14, y: sin(drift) * 14)
                .blur(radius: 28)
            Circle().fill(Theme.strain.opacity(0.45))
                .frame(width: size * 0.82, height: size * 0.82)
                .offset(x: cos(drift + 2.1) * 16, y: sin(drift + 2.1) * 16)
                .blur(radius: 24)
            Circle().fill(Theme.younger.opacity(0.35))
                .frame(width: size * 0.7, height: size * 0.7)
                .offset(x: cos(drift + 4.2) * 12, y: sin(drift + 4.2) * 12)
                .blur(radius: 22)
            Circle().strokeBorder(Theme.textPrimary.opacity(0.35), lineWidth: 1.5)
                .frame(width: size, height: size)
        }
        .frame(width: 300, height: 300)
        .accessibilityHidden(true)
    }
}

private extension Format {
    /// „0:42“ bzw. „4:05“.
    static func clock(remaining: TimeInterval) -> String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
