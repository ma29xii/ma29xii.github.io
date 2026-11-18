import SwiftUI

/// Forma-Designsystem.
/// Prinzipien (siehe README): Glas nur für Bedienelemente, Inhalte auf ruhigen Flächen,
/// Farbe nur mit Bedeutung, 4-pt-Raster mit zwei linken Kanten (16 und 32).
enum Theme {
    // Grund
    static let background = Color(hex: 0x080C0F)
    static let backgroundTop = Color(hex: 0x16212A)
    static let backgroundMid = Color(hex: 0x0D1418)

    // Text
    static let textPrimary = Color(hex: 0xF2F5F7)
    static let textSecondary = Color(hex: 0x8B949C)
    static let textTertiary = Color.white.opacity(0.40)
    static let textQuaternary = Color.white.opacity(0.22)

    // Flächen und Linien
    static let plate = Color.white.opacity(0.045)
    static let plateEdge = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.075)
    static let barGray = Color(hex: 0x2A3036)
    static let track = Color.white.opacity(0.075)

    // Bedeutung
    static let recoveryHigh = Color(hex: 0x16EC06)
    static let recoveryMid = Color(hex: 0xFFDE00)
    static let recoveryLow = Color(hex: 0xFF0026)
    static let strain = Color(hex: 0x0093E7)
    static let sleep = Color(hex: 0x67AEE6)
    static let warning = Color(hex: 0xFFB547)
    static let selection = Color(hex: 0xEEF2F5)
    static let onSelection = Color(hex: 0x0B0F12)

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

/// Typografie: Systemschrift (SF Pro) mit tabellarischen Ziffern für alle Werte.
extension Font {
    static let formaLargeTitle = Font.system(size: 34, weight: .bold)
    static let formaHero = Font.system(size: 64, weight: .semibold).monospacedDigit()
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
    static let formaBigNumber = Font.system(size: 28, weight: .semibold).monospacedDigit()
}

/// Ruhiger, dunkler Grund mit leichtem Blaugrau oben.
struct ScreenBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.backgroundTop, location: 0),
                .init(color: Theme.backgroundMid, location: 0.34),
                .init(color: Theme.background, location: 0.72)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// Standard-Hintergrund für Seiten.
    func formaScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .foregroundStyle(Theme.textPrimary)
    }
}
