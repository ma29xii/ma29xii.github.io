import SwiftUI

/// Health-Designsystem (Umbau 03).
/// Dunkles, kühl-neutrales Graphit mit sanftem Verlauf nach oben (kein sichtbares Blau),
/// ruhige matte Karten (Radius 20), Glas nur für Bedienung. Farbe kommt aus den Daten.
enum Theme {
    // Grund: Graphit, oben etwas heller. Blau-Anteil nur +2–3 über Rot, damit es kühl wirkt, aber nicht blau.
    static let backgroundTop = Color(hex: 0x222325)
    static let backgroundMid = Color(hex: 0x161719)
    static let background = Color(hex: 0x0D0E0F)
    /// Verlauf für ganze Seiten.
    static var screenGradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: backgroundTop, location: 0),
            .init(color: backgroundMid, location: 0.32),
            .init(color: background, location: 0.72)
        ], startPoint: .top, endPoint: .bottom)
    }

    // Text
    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0x9C9DA1)
    static let textTertiary = Color.white.opacity(0.56)   // ≈ 5,5:1 auf Graphit (WCAG AA)
    static let textQuaternary = Color.white.opacity(0.36)  // ≈ 3:1 für Symbole und Konturen

    // Flächen und Linien
    /// Kartenfläche: deckend, damit Karten auf dem Verlauf überall gleich aussehen.
    static let card = Color(hex: 0x1D1E20)
    static let cardRaised = Color(hex: 0x26272A)
    static let plate = Color.white.opacity(0.05)
    static let plateEdge = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.08)
    static let barGray = Color(hex: 0x2C2D30)
    static let track = Color.white.opacity(0.08)

    // Bedeutung
    static let recoveryHigh = Color(hex: 0x16EC06)
    static let recoveryMid = Color(hex: 0xFFDE00)
    static let recoveryLow = Color(hex: 0xFF0026)
    static let strain = Color(hex: 0x0093E7)
    static let sleep = Color(hex: 0x8E8CFF)
    static let warning = Color(hex: 0xFFB547)
    static let selection = Color(hex: 0xF5F5F7)
    static let onSelection = Color(hex: 0x0A0A0A)
    /// Körperalter: jünger = mint, älter = warm.
    static let younger = Color(hex: 0x3DDC97)
    static let older = Color(hex: 0xFF8A5B)

    static func recovery(_ value: Int) -> Color {
        if value >= 67 { return recoveryHigh }
        if value >= 34 { return recoveryMid }
        return recoveryLow
    }

    static func recoveryWord(_ value: Int) -> String {
        if value >= 67 { return "Gut erholt" }
        if value >= 34 { return "Mittel erholt" }
        return "Wenig erholt"
    }
}

/// 4-pt-Raster
enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
    /// Seitenrand
    static let page: CGFloat = 16
    /// Abstand zwischen Karten
    static let gap: CGFloat = 12
}

enum Radius {
    /// Karten
    static let plate: CGFloat = 20
    static let small: CGFloat = 12
    static let dock: CGFloat = 30
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Locale {
    static let german = Locale(identifier: "de_DE")
}

/// Typografie: Systemschrift auf Textstilen, damit Dynamic Type wirkt (Codex R-01-10).
/// Zahlen sind rund (`.rounded`) und gleich breit (`monospacedDigit`), damit sie beim Wechsel nicht springen.
/// Große Anzeigezahlen (Ringe, Hero) bleiben fest, sie sind Grafik und haben Text-Alternativen.
extension Font {
    static let formaLargeTitle = Font.system(.largeTitle, weight: .bold)
    static let formaHero = Font.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit()
    static let formaTitle = Font.system(.title, weight: .bold)
    static let formaHeadline = Font.system(.title2, weight: .semibold)
    static let formaSection = Font.system(.title3, weight: .semibold)
    static let formaBodyLarge = Font.system(.body)
    static let formaRowTitle = Font.system(.callout, weight: .medium)
    static let formaBody = Font.system(.subheadline)
    static let formaValue = Font.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit()
    static let formaCaption = Font.system(.footnote)
    static let formaCaptionStrong = Font.system(.footnote, weight: .semibold)
    static let formaMicro = Font.system(.caption2, weight: .semibold)
    static let formaBigNumber = Font.system(.title, design: .rounded, weight: .semibold).monospacedDigit()
    static let formaWidgetNumber = Font.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit()
    /// Kleiner Abschnittstitel in GROSSBUCHSTABEN, zusammen mit `.formaLabelStyle()` (Laufweite).
    static let formaLabel = Font.system(.caption, weight: .semibold)
    /// Mittlere runde Zahl in Karten (z. B. 62 bpm).
    static let formaNumber = Font.system(.title2, design: .rounded, weight: .semibold).monospacedDigit()
    /// Große runde Zahl als Hauptsache eines Bildschirms (wächst mit Dynamic Type).
    static let formaDisplay = Font.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit()
}

/// Laufweite für Großbuchstaben-Titel.
enum Tracking {
    static let label: CGFloat = 1.4
    static let micro: CGFloat = 1.0
}

extension View {
    /// Abschnittstitel: klein, GROSSBUCHSTABEN, Laufweite, gedämpft. VoiceOver liest ihn als Überschrift.
    func formaLabelStyle(_ color: Color = Theme.textSecondary) -> some View {
        self
            .font(.formaLabel)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }

    /// Zahlen rollen beim Wechsel statt zu springen (ohne Bewegung bei „Bewegung reduzieren“ durch das System).
    func formaNumberTransition(_ value: Double) -> some View {
        self
            .contentTransition(.numericText(value: value))
            .animation(.snappy, value: value)
    }
}

/// Graphit-Verlauf mit optionalem weichem Farbschein oben.
/// Auf „Today“ und in den Ring-Details nimmt der Schein die Farbe des Werts an.
struct ScreenBackground: View {
    var tint: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Gelb wirkt auf Graphit schnell schmutzig (oliv): dort schwächer leuchten.
    private var strength: Double {
        guard let tint else { return 0 }
        return tint == Theme.recoveryMid ? 0.07 : 0.11
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.screenGradient
            if let tint {
                RadialGradient(
                    colors: [tint.opacity(strength), .clear],
                    center: .top, startRadius: 0, endRadius: 320
                )
                .scaleEffect(x: 1.6, y: 1, anchor: .top)
                .frame(height: 520)
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: tint)
    }
}

extension View {
    /// Standard-Hintergrund für Seiten: Graphit-Verlauf und weiche Kanten unter Navigations- und Tab-Leiste.
    func formaScreen(tint: Color? = nil) -> some View {
        self
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .background(ScreenBackground(tint: tint))
            .foregroundStyle(Theme.textPrimary)
    }
}
