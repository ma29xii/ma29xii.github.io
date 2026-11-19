import SwiftUI

/// Ein Bestwert-Moment im Live-Training.
struct RecordMoment: Equatable, Identifiable {
    let id = UUID()
    let exercise: String
    let oneRepMax: Double
}

/// Farbe der Bestwerte: warmes Gold, einmalig in Training – nie für Bewertungen.
extension Theme {
    static let record = Theme.warning
}

/// Leiser Hinweis am Satzende: Stern hüpft einmal, die Kapsel gleitet ein. Reduce Motion: nur Einblenden.
struct RecordToast: View {
    let moment: RecordMoment
    let unit: WeightUnit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "star.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.record)
                .symbolEffect(.bounce, value: shown && !reduceMotion)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Neuer Bestwert").font(.formaRowTitle)
                Text("\(moment.exercise) · \(Format.weight(moment.oneRepMax, unit: unit)) \(unit.rawValue) geschätzt")
                    .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .glassEffect(.regular, in: .capsule)
        .scaleEffect(shown || reduceMotion ? 1 : 0.94)
        .opacity(shown ? 1 : 0)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.25)) { shown = true }
            AccessibilityNotification.Announcement("Neuer Bestwert bei \(moment.exercise)").post()
        }
    }
}

/// Bestwerte oben in der Zusammenfassung. Erscheint einmal mit Haptik, sonst still.
struct RecordHero: View {
    let names: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "star.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.record)
                .shadow(color: Theme.record.opacity(appeared ? 0.45 : 0), radius: 10)
                .symbolEffect(.bounce, value: appeared && !reduceMotion)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(names.count == 1 ? "Neuer Bestwert" : "\(names.count) neue Bestwerte").font(.formaHeadline)
                Text(names.joined(separator: " · "))
                    .font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 6)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.6).delay(0.15)) { appeared = true }
        }
        .sensoryFeedback(.success, trigger: appeared) { _, new in new }
    }
}
