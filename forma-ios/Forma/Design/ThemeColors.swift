import SwiftUI
import UIKit

/// Eigene Farbwahl (Profil → Design), pro Gerät gespeichert. `nil` heißt: Standard des Designs.
/// Die Recovery-Ampel ist bewusst nicht dabei.
struct ThemeOverrides: Equatable, Sendable {
    var accent: UInt32?
    var strain: UInt32?
    var sleep: UInt32?

    static let defaultStrain: UInt32 = 0x0093E7
    static let defaultSleep: UInt32 = 0x8E8CFF

    static let accentKey = "forma.color.accent"
    static let strainKey = "forma.color.strain"
    static let sleepKey = "forma.color.sleep"

    var isEmpty: Bool { self == ThemeOverrides() }

    static func load(from defaults: UserDefaults) -> ThemeOverrides {
        func value(_ key: String) -> UInt32? {
            guard let number = defaults.object(forKey: key) as? Int, (0...0xFFFFFF).contains(number) else { return nil }
            return UInt32(number)
        }
        return ThemeOverrides(accent: value(accentKey), strain: value(strainKey), sleep: value(sleepKey))
    }

    func save(to defaults: UserDefaults) {
        for (key, value) in [(Self.accentKey, accent), (Self.strainKey, strain), (Self.sleepKey, sleep)] {
            if let value { defaults.set(Int(value), forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    /// sRGB-Wert einer SwiftUI-Farbe als 0xRRGGBB.
    static func hex(of color: Color) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    /// Relative Leuchtdichte nach WCAG 2.x.
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// Kontrastverhältnis zweier Farben, 1…21.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Auswahl im Profil: kräftige, auf dunklem Grund lesbare Farben.
    static let palette: [UInt32] = [
        0x34D26B, 0xC6FF00, 0xFFC93C, 0xFF9F0A, 0xFF6F61, 0xFF3D6E,
        0xFF3DAA, 0xB26BFF, 0x8E8CFF, 0x4D8DFF, 0x0093E7, 0x00E5FF
    ]
}

/// Profil → Design: Akzent- und Ringfarben wählen, Vorschau live, „Zurücksetzen“.
struct ThemeColorPicker: View {
    private let store = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            preview
            row("Akzent", selected: store.overrides.accent, fallback: store.current.accentHex,
                identifier: "accent") { value in store.setColors { $0.accent = value } }
            row("Strain", selected: store.overrides.strain, fallback: ThemeOverrides.defaultStrain,
                identifier: "strain") { value in store.setColors { $0.strain = value } }
            row("Sleep", selected: store.overrides.sleep, fallback: ThemeOverrides.defaultSleep,
                identifier: "sleep") { value in store.setColors { $0.sleep = value } }
            Button("Zurücksetzen") { store.resetColors() }
                .font(.formaRowTitle)
                .foregroundStyle(store.overrides.isEmpty ? Theme.textQuaternary : Theme.accent)
                .frame(minHeight: 44, alignment: .leading)
                .disabled(store.overrides.isEmpty)
                .accessibilityIdentifier("theme.colors.reset")
        }
        .padding(.vertical, Space.s2)
    }

    /// Zwei Ringe in den gewählten Farben und ein Knopf im Akzent.
    private var preview: some View {
        HStack(spacing: Space.s4) {
            miniRing(0.72, Theme.strain)
            miniRing(0.55, Theme.sleep)
            Spacer(minLength: 0)
            Text("Akzent")
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.onSelection)
                .padding(.horizontal, Space.s4)
                .frame(minHeight: 36)
                .background(Capsule().fill(Theme.accent))
        }
        .accessibilityHidden(true)
    }

    private func miniRing(_ fraction: Double, _ color: Color) -> some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 6)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 44, height: 44)
    }

    private func row(_ title: String, selected: UInt32?, fallback: UInt32, identifier: String,
                     set: @escaping (UInt32?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).formaLabelStyle()
            ScrollView(.horizontal) {
                HStack(spacing: Space.s2) {
                    ForEach(ThemeOverrides.palette, id: \.self) { hex in
                        let isSelected = (selected ?? fallback) == hex
                        Button { set(hex == fallback ? nil : hex) } label: {
                            Circle().fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(Theme.textPrimary, lineWidth: isSelected ? 2.5 : 0).padding(-4))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title) \(String(format: "#%06X", hex))")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        .accessibilityIdentifier("theme.\(identifier).\(String(format: "%06X", hex))")
                    }
                    ColorPicker("\(title) eigene Farbe", selection: Binding(
                        get: { Color(hex: selected ?? fallback) },
                        set: { set(ThemeOverrides.hex(of: $0)) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44, height: 44)
                }
            }
            .scrollClipDisabled()
        }
    }
}
