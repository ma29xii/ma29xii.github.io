import SwiftUI
import Observation
import WidgetKit

/// Wählbare Designs (Profil → Design). Sie färben Hintergrund, Karten, Schein und Akzent.
/// Recovery-Ampel und Textfarben bleiben in jedem Design gleich und lesbar; Strain, Sleep und Akzent lassen sich im Profil überschreiben.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case standard, neonLime, electric, blaze, synthwave, toxic, coral, gold, magenta, ice
    case black, blue, bordeaux, blend, dusk, ember, slate, lagoon, forest, aubergine
    case midnight, sand, graphite, ocean, rose, olive, sunset, aurora

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .neonLime: "Neon-Lime"
        case .electric: "Elektroblau"
        case .blaze: "Flamme"
        case .synthwave: "Synthwave"
        case .toxic: "Giftgrün"
        case .coral: "Koralle"
        case .gold: "Gold"
        case .magenta: "Magenta"
        case .ice: "Eisblau"
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
        case .midnight: "Mitternacht"
        case .sand: "Sand"
        case .graphite: "Graphit"
        case .ocean: "Ozean"
        case .rose: "Rosé"
        case .olive: "Olive"
        case .sunset: "Abendrot"
        case .aurora: "Polarlicht"
        }
    }

    /// Seitenverlauf von oben nach unten.
    var top: Color {
        switch self {
        case .standard: Color(hex: 0x222325)
        case .neonLime: Color(hex: 0x0A0D00)
        case .electric: Color(hex: 0x0A1840)
        case .blaze: Color(hex: 0x35101C)
        case .synthwave: Color(hex: 0x1E0B3D)
        case .toxic: Color(hex: 0x05220F)
        case .coral: Color(hex: 0x33120F)
        case .gold: Color(hex: 0x232427)
        case .magenta: Color(hex: 0x330A26)
        case .ice: Color(hex: 0x0B2630)
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
        case .midnight: Color(hex: 0x131A33)
        case .sand: Color(hex: 0x2A251D)
        case .graphite: Color(hex: 0x26282B)
        case .ocean: Color(hex: 0x0F2A3D)
        case .rose: Color(hex: 0x2E1A22)
        case .olive: Color(hex: 0x23261A)
        case .sunset: Color(hex: 0x2D1A26)
        case .aurora: Color(hex: 0x10282A)
        }
    }

    var mid: Color {
        switch self {
        case .standard: Color(hex: 0x161719)
        case .neonLime: Color(hex: 0x050700)
        case .electric: Color(hex: 0x060D26)
        case .blaze: Color(hex: 0x1E0B14)
        case .synthwave: Color(hex: 0x120726)
        case .toxic: Color(hex: 0x03150A)
        case .coral: Color(hex: 0x1E0C0A)
        case .gold: Color(hex: 0x17181A)
        case .magenta: Color(hex: 0x1E061A)
        case .ice: Color(hex: 0x071A22)
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
        case .midnight: Color(hex: 0x0E1226)
        case .sand: Color(hex: 0x1C1914)
        case .graphite: Color(hex: 0x1A1B1D)
        case .ocean: Color(hex: 0x0B1D2C)
        case .rose: Color(hex: 0x1F1217)
        case .olive: Color(hex: 0x191B12)
        case .sunset: Color(hex: 0x1B1220)
        case .aurora: Color(hex: 0x131C2B)
        }
    }

    var bottom: Color {
        switch self {
        case .standard: Color(hex: 0x0D0E0F)
        case .neonLime: Color(hex: 0x000000)
        case .electric: Color(hex: 0x03071A)
        case .blaze: Color(hex: 0x0F060A)
        case .synthwave: Color(hex: 0x080314)
        case .toxic: Color(hex: 0x010A04)
        case .coral: Color(hex: 0x0F0605)
        case .gold: Color(hex: 0x0C0C0D)
        case .magenta: Color(hex: 0x0F030C)
        case .ice: Color(hex: 0x040D12)
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
        case .midnight: Color(hex: 0x080A17)
        case .sand: Color(hex: 0x100F0C)
        case .graphite: Color(hex: 0x0E0F10)
        case .ocean: Color(hex: 0x070F18)
        case .rose: Color(hex: 0x120A0D)
        case .olive: Color(hex: 0x0E0F0A)
        case .sunset: Color(hex: 0x0E0A14)
        case .aurora: Color(hex: 0x0A0E18)
        }
    }

    var card: Color {
        switch self {
        case .standard: Color(hex: 0x1D1E20)
        case .neonLime: Color(hex: 0x0F1400)
        case .electric: Color(hex: 0x0B1636)
        case .blaze: Color(hex: 0x2A1118)
        case .synthwave: Color(hex: 0x1A0D36)
        case .toxic: Color(hex: 0x0A1D10)
        case .coral: Color(hex: 0x2B1512)
        case .gold: Color(hex: 0x1E1F22)
        case .magenta: Color(hex: 0x2A0F22)
        case .ice: Color(hex: 0x0C202A)
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
        case .midnight: Color(hex: 0x151B33)
        case .sand: Color(hex: 0x26221B)
        case .graphite: Color(hex: 0x202225)
        case .ocean: Color(hex: 0x112638)
        case .rose: Color(hex: 0x2A1A21)
        case .olive: Color(hex: 0x22251A)
        case .sunset: Color(hex: 0x261A27)
        case .aurora: Color(hex: 0x142329)
        }
    }

    var cardRaised: Color {
        switch self {
        case .standard: Color(hex: 0x26272A)
        case .neonLime: Color(hex: 0x182000)
        case .electric: Color(hex: 0x142450)
        case .blaze: Color(hex: 0x3B1A24)
        case .synthwave: Color(hex: 0x28154A)
        case .toxic: Color(hex: 0x122C1A)
        case .coral: Color(hex: 0x3C201B)
        case .gold: Color(hex: 0x2A2B2F)
        case .magenta: Color(hex: 0x3B1932)
        case .ice: Color(hex: 0x143240)
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
        case .midnight: Color(hex: 0x1E2644)
        case .sand: Color(hex: 0x322D24)
        case .graphite: Color(hex: 0x2B2D31)
        case .ocean: Color(hex: 0x1A3549)
        case .rose: Color(hex: 0x38242C)
        case .olive: Color(hex: 0x2E3224)
        case .sunset: Color(hex: 0x332335)
        case .aurora: Color(hex: 0x1D3138)
        }
    }

    /// Akzent: hell genug für Kontrast auf dem dunklen Grund (Bordeaux selbst wäre zu dunkel).
    var accent: Color {
        switch self {
        case .standard: Color(hex: 0x34D26B)
        case .neonLime: Color(hex: 0xC6FF00)
        case .electric: Color(hex: 0x4D8DFF)
        case .blaze: Color(hex: 0xFF7A45)
        case .synthwave: Color(hex: 0x00E5FF)
        case .toxic: Color(hex: 0x39FF5A)
        case .coral: Color(hex: 0xFF6F61)
        case .gold: Color(hex: 0xFFC93C)
        case .magenta: Color(hex: 0xFF3DAA)
        case .ice: Color(hex: 0x5CE1E6)
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
        case .midnight: Color(hex: 0x7C9CFF)
        case .sand: Color(hex: 0xD9C29A)
        case .graphite: Color(hex: 0xB4BBC4)
        case .ocean: Color(hex: 0x4FB4E8)
        case .rose: Color(hex: 0xE79AB0)
        case .olive: Color(hex: 0xC3CC7A)
        case .sunset: Color(hex: 0xF0946B)
        case .aurora: Color(hex: 0x7BE0B0)
        }
    }

    /// Akzent als 0xRRGGBB, für Widgets und Kontrastprüfung.
    var accentHex: UInt32 { ThemeOverrides.hex(of: accent) }

    /// Farben des Scheins oben (eine: mittig, zwei: links und rechts). Beim Standard leer, dort kommt der Schein aus den Daten.
    var glows: [Color] {
        switch self {
        case .standard, .black: []
        case .neonLime: [Color(hex: 0x7BA800)]
        case .electric: [Color(hex: 0x1F5CFF)]
        case .blaze: [Color(hex: 0xFF5A1F), Color(hex: 0xFF2E88)]
        case .synthwave: [Color(hex: 0xB026FF), Color(hex: 0x00E5FF)]
        case .toxic: [Color(hex: 0x14C73A)]
        case .coral: [Color(hex: 0xFF5A4D), Color(hex: 0xFFA07A)]
        case .gold: [Color(hex: 0xB8892B)]
        case .magenta: [Color(hex: 0xE0148C), Color(hex: 0x7A2CFF)]
        case .ice: [Color(hex: 0x1FB5C9)]
        case .blue: [Color(hex: 0x4D8EB6)]
        case .bordeaux: [Color(hex: 0x5C2624)]
        case .blend: [Color(hex: 0x4D8EB6), Color(hex: 0x5C2624)]
        case .dusk: [Color(hex: 0x6B5BA8), Color(hex: 0x4D8EB6)]
        case .ember: [Color(hex: 0x5C2624), Color(hex: 0xC57A3A)]
        case .slate: [Color(hex: 0x6C8DAC)]
        case .lagoon: [Color(hex: 0x4D8EB6), Color(hex: 0x348F78)]
        case .forest: [Color(hex: 0x536D3E)]
        case .aubergine: [Color(hex: 0x8764A7), Color(hex: 0x5C2624)]
        case .midnight: [Color(hex: 0x3A55C8)]
        case .sand: [Color(hex: 0x8A7552)]
        case .graphite: [Color(hex: 0x5B6168)]
        case .ocean: [Color(hex: 0x1F7FB5)]
        case .rose: [Color(hex: 0xB5516F)]
        case .olive: [Color(hex: 0x6E7A33)]
        case .sunset: [Color(hex: 0xC4524A), Color(hex: 0x6B5BA8)]
        case .aurora: [Color(hex: 0x2FA37F), Color(hex: 0x6B5BA8)]
        }
    }

    /// Dunkle Farben brauchen mehr Deckkraft, damit der Schein sichtbar bleibt.
    var glowStrength: Double {
        switch self {
        case .standard, .black: 0
        case .neonLime: 0.3
        case .electric: 0.45
        case .blaze: 0.4
        case .synthwave: 0.38
        case .toxic: 0.34
        case .coral: 0.34
        case .gold: 0.28
        case .magenta: 0.38
        case .ice: 0.3
        case .blue: 0.30
        case .bordeaux: 0.60
        case .blend: 0.34
        case .dusk: 0.30
        case .ember: 0.38
        case .slate: 0.14
        case .lagoon: 0.13
        case .forest: 0.24
        case .aubergine: 0.22
        case .midnight: 0.30
        case .sand: 0.20
        case .graphite: 0.16
        case .ocean: 0.28
        case .rose: 0.26
        case .olive: 0.24
        case .sunset: 0.30
        case .aurora: 0.22
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

/// Hält das gewählte Design und die eigenen Farben. Liest man `Theme.background` & Co. im `body`, zeichnet SwiftUI beim Wechsel neu.
/// Gespeichert unter `forma.theme` (dort liest auch `@AppStorage` im Profil). Eigene Farben: siehe `ThemeOverrides`.
@Observable
final class ThemeStore: @unchecked Sendable {
    static let key = "forma.theme"
    static let shared = ThemeStore(widgetDefaults: WidgetPalette.groupDefaults)

    private(set) var current: AppTheme
    private(set) var overrides: ThemeOverrides
    private let defaults: UserDefaults
    private let widgetDefaults: UserDefaults?

    /// `widgetDefaults`: Ziel für die Widget-Farben (App Group). `nil` schreibt nichts, z. B. in Tests.
    init(defaults: UserDefaults = .standard, widgetDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        self.widgetDefaults = widgetDefaults
        current = AppTheme.resolve(defaults.string(forKey: Self.key))
        overrides = ThemeOverrides.load(from: defaults)
        palette.save(to: widgetDefaults)
    }

    func select(_ theme: AppTheme, defaults override: UserDefaults? = nil) {
        guard theme != current else { return }
        current = theme
        (override ?? defaults).set(theme.rawValue, forKey: Self.key)
        publishPalette()
    }

    func setColors(_ change: (inout ThemeOverrides) -> Void) {
        var next = overrides
        change(&next)
        guard next != overrides else { return }
        overrides = next
        next.save(to: defaults)
        publishPalette()
    }

    func resetColors() { setColors { $0 = ThemeOverrides() } }

    /// Aufgelöste Farben für die Widgets (Design plus eigene Wahl).
    var palette: WidgetPalette {
        WidgetPalette(accent: overrides.accent ?? current.accentHex,
                      strain: overrides.strain ?? ThemeOverrides.defaultStrain,
                      sleep: overrides.sleep ?? ThemeOverrides.defaultSleep)
    }

    var accent: Color { overrides.accent.map { Color(hex: $0) } ?? current.accent }
    var strain: Color { Color(hex: overrides.strain ?? ThemeOverrides.defaultStrain) }
    var sleep: Color { Color(hex: overrides.sleep ?? ThemeOverrides.defaultSleep) }

    private func publishPalette() {
        let palette = palette
        guard widgetDefaults != nil, WidgetPalette.load(from: widgetDefaults) != palette else { return }
        palette.save(to: widgetDefaults)
        WidgetCenter.shared.reloadAllTimelines()
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
