import Foundation
import SwiftUI

/// Farben, die die App für die Widgets freigibt (App Group): Akzent des Designs und die zwei Ringfarben.
/// Die App schreibt hier den fertig aufgelösten Stand (Design plus eigene Wahl), das Widget liest nur.
struct WidgetPalette: Equatable, Sendable {
    var accent: UInt32
    var strain: UInt32
    var sleep: UInt32

    /// Werte des Standard-Designs, solange nichts veröffentlicht wurde.
    static let standard = WidgetPalette(accent: 0x34D26B, strain: 0x0093E7, sleep: 0x8E8CFF)

    static let accentKey = "forma.widget.accent"
    static let strainKey = "forma.widget.strain"
    static let sleepKey = "forma.widget.sleep"

    static var groupDefaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshotStore.groupID) }

    static func load(from defaults: UserDefaults? = groupDefaults) -> WidgetPalette {
        guard let defaults else { return .standard }
        func value(_ key: String, _ fallback: UInt32) -> UInt32 {
            guard let number = defaults.object(forKey: key) as? Int, (0...0xFFFFFF).contains(number) else { return fallback }
            return UInt32(number)
        }
        return WidgetPalette(accent: value(Self.accentKey, standard.accent),
                             strain: value(Self.strainKey, standard.strain),
                             sleep: value(Self.sleepKey, standard.sleep))
    }

    func save(to defaults: UserDefaults?) {
        guard let defaults else { return }
        defaults.set(Int(accent), forKey: Self.accentKey)
        defaults.set(Int(strain), forKey: Self.strainKey)
        defaults.set(Int(sleep), forKey: Self.sleepKey)
    }

    var accentColor: Color { Color(sharedHex: accent) }
    var strainColor: Color { Color(sharedHex: strain) }
    var sleepColor: Color { Color(sharedHex: sleep) }
}

extension Color {
    /// sRGB aus 0xRRGGBB, auch im Widget-Target (dort gibt es das Theme der App nicht).
    init(sharedHex hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
