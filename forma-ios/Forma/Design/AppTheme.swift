import SwiftUI
import Observation

/// Wählbare Designs (Profil → Design). Sie färben Hintergrund, Karten, Schein und Akzent.
/// Ringfarben (Recovery, Strain, Sleep) und Textfarben bleiben in jedem Design gleich und lesbar.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case standard, black, blue, bordeaux, blend, dusk, ember, slate, lagoon, forest, aubergine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .black: "Schwarz"
        case .blue: "Blau"
        case .bordeaux: "Bordeaux"
        case .blend: "Verlauf"
        case .dusk: "Dämmerung"
        case .ember: "Glut"
        case .slate: "Schiefer"
        case .lagoon: "Lagune"
        case .forest: "Wald"
        case .aubergine: "Aubergine"
        }
    }

    /// Seitenverlauf von oben nach unten.
    var top: Color {
        switch self {
        case .standard: Color(hex: 0x222325)
        case .black: Color(hex: 0x000000)
        case .blue: Color(hex: 0x1A2A35)
        case .bordeaux: Color(hex: 0x2B1514)
        case .blend: Color(hex: 0x2B1514)
        case .dusk: Color(hex: 0x201B33)
        case .ember: Color(hex: 0x2A1712)
        case .slate: Color(hex: 0x172330)
        case .lagoon: Color(hex: 0x10282B)
        case .forest: Color(hex: 0x18241B)
        case .aubergine: Color(hex: 0x28182E)
        }
    }

    var mid: Color {
        switch self {
        case .standard: Color(hex: 0x161719)
        case .black: Color(hex: 0x000000)
        case .blue: Color(hex: 0x111B23)
        case .bordeaux: Color(hex: 0x1B0E0E)
        case .blend: Color(hex: 0x181620)
        case .dusk: Color(hex: 0x151222)
        case .ember: Color(hex: 0x1B0F0C)
        case .slate: Color(hex: 0x141D25)
        case .lagoon: Color(hex: 0x112127)
        case .forest: Color(hex: 0x151F16)
        case .aubergine: Color(hex: 0x241523)
        }
    }

    var bottom: Color {
        switch self {
        case .standard: Color(hex: 0x0D0E0F)
        case .black: Color(hex: 0x000000)
        case .blue: Color(hex: 0x0A1015)
        case .bordeaux: Color(hex: 0x100808)
        case .blend: Color(hex: 0x0C171E)
        case .dusk: Color(hex: 0x0C0B14)
        case .ember: Color(hex: 0x100807)
        case .slate: Color(hex: 0x0F151C)
        case .lagoon: Color(hex: 0x0C171E)
        case .forest: Color(hex: 0x0D150F)
        case .aubergine: Color(hex: 0x16101A)
        }
    }

    var card: Color {
        switch self {
        case .standard: Color(hex: 0x1D1E20)
        case .black: Color(hex: 0x111112)
        case .blue: Color(hex: 0x162029)
        case .bordeaux: Color(hex: 0x221413)
        case .blend: Color(hex: 0x1C1A24)
        case .dusk: Color(hex: 0x1A1729)
        case .ember: Color(hex: 0x23140F)
        case .slate: Color(hex: 0x1B2833)
        case .lagoon: Color(hex: 0x182B30)
        case .forest: Color(hex: 0x1B291E)
        case .aubergine: Color(hex: 0x281C2C)
        }
    }

    var cardRaised: Color {
        switch self {
        case .standard: Color(hex: 0x26272A)
        case .black: Color(hex: 0x1B1B1D)
        case .blue: Color(hex: 0x1F2C37)
        case .bordeaux: Color(hex: 0x2D1C1B)
        case .blend: Color(hex: 0x272431)
        case .dusk: Color(hex: 0x252136)
        case .ember: Color(hex: 0x2E1C16)
        case .slate: Color(hex: 0x273544)
        case .lagoon: Color(hex: 0x22383D)
        case .forest: Color(hex: 0x28362B)
        case .aubergine: Color(hex: 0x39283D)
        }
    }

    /// Akzent: hell genug für Kontrast auf dem dunklen Grund (Bordeaux selbst wäre zu dunkel).
    var accent: Color {
        switch self {
        case .standard: Color(hex: 0x34D26B)
        case .black: Color(hex: 0xF5F5F7)
        case .blue: Color(hex: 0x4D8EB6)
        case .bordeaux: Color(hex: 0xC4605B)
        case .blend: Color(hex: 0x9B80AE)
        case .dusk: Color(hex: 0x8F82D6)
        case .ember: Color(hex: 0xD98A4A)
        case .slate: Color(hex: 0xA3BBD5)
        case .lagoon: Color(hex: 0x71D5C9)
        case .forest: Color(hex: 0xA8C793)
        case .aubergine: Color(hex: 0xD5A8DB)
        }
    }

    /// Farben des Scheins oben (eine: mittig, zwei: links und rechts). Beim Standard leer, dort kommt der Schein aus den Daten.
    var glows: [Color] {
        switch self {
        case .standard, .black: []
        case .blue: [Color(hex: 0x4D8EB6)]
        case .bordeaux: [Color(hex: 0x5C2624)]
        case .blend: [Color(hex: 0x4D8EB6), Color(hex: 0x5C2624)]
        case .dusk: [Color(hex: 0x6B5BA8), Color(hex: 0x4D8EB6)]
        case .ember: [Color(hex: 0x5C2624), Color(hex: 0xC57A3A)]
        case .slate: [Color(hex: 0x6C8DAC)]
        case .lagoon: [Color(hex: 0x4D8EB6), Color(hex: 0x348F78)]
        case .forest: [Color(hex: 0x536D3E)]
        case .aubergine: [Color(hex: 0x8764A7), Color(hex: 0x5C2624)]
        }
    }

    /// Dunkle Farben brauchen mehr Deckkraft, damit der Schein sichtbar bleibt.
    var glowStrength: Double {
        switch self {
        case .standard, .black: 0
        case .blue: 0.30
        case .bordeaux: 0.60
        case .blend: 0.34
        case .dusk: 0.30
        case .ember: 0.38
        case .slate: 0.14
        case .lagoon: 0.13
        case .forest: 0.24
        case .aubergine: 0.22
        }
    }

    var gradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: top, location: 0),
            .init(color: mid, location: 0.32),
            .init(color: bottom, location: 0.72)
        ], startPoint: .top, endPoint: .bottom)
    }

    /// Entscheidet, welche Scheine hinter einer Seite liegen. Standard: Farbe der Daten (`tint`), sonst keine.
    /// Alle anderen Designs: ihre eigenen Farben, die Datenfarbe bleibt in den Ringen.
    func glowLayers(tint: Color?) -> [(color: Color, opacity: Double)] {
        if self == .standard {
            guard let tint else { return [] }
            return [(tint, tint == Theme.recoveryMid ? 0.07 : 0.11)]
        }
        return glows.map { (color: $0, opacity: glowStrength) }
    }

    static func resolve(_ raw: String?) -> AppTheme {
        raw.flatMap(AppTheme.init(rawValue:)) ?? .standard
    }
}

/// Hält das gewählte Design. Liest man `Theme.background` & Co. im `body`, zeichnet SwiftUI beim Wechsel neu.
/// Gespeichert unter `forma.theme` (dort liest auch `@AppStorage` im Profil).
@Observable
final class ThemeStore: @unchecked Sendable {
    static let key = "forma.theme"
    static let shared = ThemeStore()

    private(set) var current: AppTheme

    init(defaults: UserDefaults = .standard) {
        current = AppTheme.resolve(defaults.string(forKey: Self.key))
    }

    func select(_ theme: AppTheme, defaults: UserDefaults = .standard) {
        guard theme != current else { return }
        current = theme
        defaults.set(theme.rawValue, forKey: Self.key)
    }
}

/// Seitenverlauf des gewählten Designs. Eigene View, damit der Wechsel sicher neu zeichnet.
struct ThemeGradient: View {
    var body: some View { Theme.screenGradient }
}

/// Auswahl im Profil: kleine Vorschau-Kacheln mit Verlauf, Schein und Akzent.
struct ThemePicker: View {
    @AppStorage(ThemeStore.key) private var raw = AppTheme.standard.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.s3) {
                ForEach(AppTheme.allCases) { theme in
                    tile(theme)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
        }
        .scrollClipDisabled()
        .onChange(of: raw) { _, new in
            ThemeStore.shared.select(AppTheme.resolve(new))
        }
        .sensoryFeedback(.selection, trigger: raw)
    }

    private func tile(_ theme: AppTheme) -> some View {
        let selected = AppTheme.resolve(raw) == theme
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { raw = theme.rawValue }
        } label: {
            VStack(spacing: Space.s2) {
                ZStack(alignment: .top) {
                    theme.gradient
                    ForEach(Array(theme.glows.enumerated()), id: \.offset) { index, color in
                        let x: CGFloat = theme.glows.count == 1 ? 0.5 : (index == 0 ? 0.1 : 0.9)
                        RadialGradient(colors: [color.opacity(min(0.9, theme.glowStrength * 2)), .clear],
                                       center: UnitPoint(x: x, y: 0), startRadius: 0, endRadius: 70)
                    }
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(theme.card)
                            .frame(height: 16)
                        Circle().fill(theme.accent).frame(width: 12, height: 12)
                    }
                    .padding(8)
                }
                .frame(width: 76, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? theme.accent : Color.white.opacity(0.14), lineWidth: selected ? 2 : 0.75)
                )
                Text(theme.title)
                    .font(.formaMicro)
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .fixedSize()
            }
            .frame(minWidth: 76, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("theme." + theme.rawValue)
    }
}
