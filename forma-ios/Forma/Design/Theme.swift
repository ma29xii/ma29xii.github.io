import SwiftUI

/// Health-Designsystem (Umbau 03).
/// Dunkles, kühl-neutrales Graphit mit sanftem Verlauf nach oben (kein sichtbares Blau),
/// ruhige matte Karten (Radius 20), Glas nur für Bedienung. Farbe kommt aus den Daten.
enum Theme {
    /// Gewähltes Design (Profil → Design). Wer `Theme.background`, `.accent` usw. liest, wird beim Wechsel neu gezeichnet.
    static var current: AppTheme { ThemeStore.shared.current }

    // Grund: je nach Design. Standard ist Graphit, oben etwas heller (Blau-Anteil nur +2–3 über Rot, kein sichtbares Blau).
    static var backgroundTop: Color { current.top }
    static var backgroundMid: Color { current.mid }
    static var background: Color { current.bottom }
    /// Verlauf für ganze Seiten.
    static var screenGradient: LinearGradient { current.gradient }
    /// Akzentfarbe (Auswahl, Schalter, kleine Hervorhebungen): eigene Wahl aus dem Profil, sonst die des Designs.
    static var accent: Color { ThemeStore.shared.accent }
    /// Farbe des weichen Scheins oben; `nil` beim Standard-Design, dort kommt der Schein aus den Daten.
    static var glow: Color? { current.glows.first }

    // Text
    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0x9C9DA1)
    static let textTertiary = Color.white.opacity(0.56)   // ≈ 5,5:1 auf Graphit (WCAG AA)
    static let textQuaternary = Color.white.opacity(0.36)  // ≈ 3:1 für Symbole und Konturen

    // Flächen und Linien
    /// Kartenfläche: deckend, damit Karten auf dem Verlauf überall gleich aussehen.
    static var card: Color { current.card }
    static var cardRaised: Color { current.cardRaised }
    static let plate = Color.white.opacity(0.05)
    static let plateEdge = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.08)
    static let barGray = Color(hex: 0x2C2D30)
    static let track = Color.white.opacity(0.08)

    // Bedeutung
    static let recoveryHigh = Color(hex: 0x16EC06)
    static let recoveryMid = Color(hex: 0xFFDE00)
    static let recoveryLow = Color(hex: 0xFF0026)
    /// Strain und Sleep folgen der Wahl im Profil (Standard: Blau und Violett). Die Recovery-Ampel bleibt fest.
    static var strain: Color { ThemeStore.shared.strain }
    static var sleep: Color { ThemeStore.shared.sleep }
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
    /// Innenabstand in Karten (F7-04)
    static let card: CGFloat = 20
}

enum Radius {
    /// Karten
    static let plate: CGFloat = 24
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

    /// Zahlen rollen beim Wechsel statt zu springen; bei „Bewegung reduzieren“ sofort der neue Wert.
    func formaNumberTransition(_ value: Double) -> some View {
        modifier(NumberTransition(value: value))
    }
}

private struct NumberTransition: ViewModifier {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText(value: value))
            .animation(reduceMotion ? nil : .snappy, value: value)
    }
}

/// Seitenhintergrund des gewählten Designs mit weichem Farbschein oben.
/// Beim Standard-Design nimmt der Schein auf „Today“ und in den Ring-Details die Farbe des Werts an (`tint`),
/// alle anderen Designs bringen ihre eigenen Farben mit.
struct ScreenBackground: View {
    var tint: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = Theme.current
        let layers = theme.glowLayers(tint: tint)
        ZStack(alignment: .top) {
            theme.gradient
            ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                let x: CGFloat = layers.count == 1 ? 0.5 : (index == 0 ? 0.2 : 0.8)
                RadialGradient(
                    colors: [layer.color.opacity(layer.opacity), .clear],
                    center: UnitPoint(x: x, y: 0), startRadius: 0, endRadius: layers.count == 1 ? 320 : 260
                )
                .scaleEffect(x: layers.count == 1 ? 1.6 : 1, y: 1, anchor: .top)
                .frame(height: 520)
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: tint)
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: theme)
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
