import SwiftUI

/// Forma-Designsystem (Iteration 6, siehe DESIGN.md).
/// Neutrales Schwarz statt Blaugrau, Licht nur aus den Daten (Erholungsfarbe als Schein oben),
/// Glas für Bedienelemente und Chips, Inhalte auf matten Karten mit Lichtkante.
enum Theme {
    // Grund: neutrales Schwarz, kein Farbstich
    static let background = Color(hex: 0x030303)

    // Text
    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0x9A9AA0)
    static let textTertiary = Color.white.opacity(0.40)
    static let textQuaternary = Color.white.opacity(0.22)

    // Flächen und Linien
    static let plate = Color.white.opacity(0.05)
    static let plateEdge = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.08)
    static let barGray = Color(hex: 0x2C2C2E)
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
}

enum Radius {
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

/// Typografie: Systemschrift (SF Pro) mit tabellarischen Ziffern für alle Werte.
extension Font {
    static let formaLargeTitle = Font.system(size: 34, weight: .bold)
    static let formaHero = Font.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit()
    static let formaTitle = Font.system(size: 28, weight: .bold)
    static let formaHeadline = Font.system(size: 22, weight: .semibold)
    static let formaSection = Font.system(size: 20, weight: .semibold)
    static let formaBodyLarge = Font.system(size: 17, weight: .regular)
    static let formaRowTitle = Font.system(size: 16, weight: .medium)
    static let formaBody = Font.system(size: 15, weight: .regular)
    static let formaValue = Font.system(size: 15, weight: .semibold).monospacedDigit()
    static let formaCaption = Font.system(size: 13, weight: .regular)
    static let formaCaptionStrong = Font.system(size: 13, weight: .semibold)
    static let formaMicro = Font.system(size: 11, weight: .semibold)
    static let formaBigNumber = Font.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit()
    static let formaWidgetNumber = Font.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit()
}

/// Neutrales Schwarz mit weichem Lichtschein oben.
/// Auf „Heute“ und in den Ring-Details nimmt der Schein die Farbe des Werts an.
struct ScreenBackground: View {
    var tint: Color? = nil

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            RadialGradient(
                colors: [(tint ?? .white).opacity(tint == nil ? 0.07 : 0.20), .clear],
                center: .top, startRadius: 0, endRadius: 380
            )
            .scaleEffect(x: 1.7, y: 1, anchor: .top)
            .frame(height: 520)
            RadialGradient(
                colors: [(tint ?? .white).opacity(tint == nil ? 0.03 : 0.08), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 300
            )
            .frame(height: 420)
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.8), value: tint)
    }
}

extension View {
    /// Standard-Hintergrund für Seiten.
    func formaScreen(tint: Color? = nil) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(ScreenBackground(tint: tint))
            .foregroundStyle(Theme.textPrimary)
    }
}
