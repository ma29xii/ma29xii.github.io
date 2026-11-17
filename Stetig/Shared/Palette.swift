import SwiftUI

/// Eine Gewohnheitsfarbe ist ein Verlaufs-Duo: Farbe A geht in Farbe B über.
struct HabitColor: Identifiable, Hashable {
    let id: String
    let name: String
    let start: UInt32
    let end: UInt32

    var color: Color { Color(hex: start) }
    var endColor: Color { Color(hex: end) }

    var gradient: LinearGradient {
        LinearGradient(colors: [color, endColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Helle Duos bekommen dunkle Symbole, dunkle Duos weiße.
    var isLight: Bool {
        func luminance(_ hex: UInt32) -> Double {
            let r = Double((hex >> 16) & 0xFF) / 255
            let g = Double((hex >> 8) & 0xFF) / 255
            let b = Double(hex & 0xFF) / 255
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return (luminance(start) + luminance(end)) / 2 > 0.66
    }

    var onColor: Color { isLight ? Color.black.opacity(0.78) : .white }
}

enum Palette {
    /// Kuratierte Duos mit ähnlicher Leuchtkraft – sie passen untereinander zusammen
    /// und wirken auf hellem wie auf schwarzem Grund.
    static let all: [HabitColor] = [
        HabitColor(id: "sunset", name: "Sonnenuntergang", start: 0xFF5F6D, end: 0xFFC371),
        HabitColor(id: "lava", name: "Lava", start: 0xFF3D57, end: 0xFF8A3D),
        HabitColor(id: "mango", name: "Mango", start: 0xFF9F1C, end: 0xFFD23F),
        HabitColor(id: "neon", name: "Neon", start: 0xE8F23A, end: 0x2BD96F),
        HabitColor(id: "volt", name: "Volt", start: 0xB6F23A, end: 0x24C6A2),
        HabitColor(id: "aurora", name: "Polarlicht", start: 0x2BE7B5, end: 0x22A6F0),
        HabitColor(id: "lagoon", name: "Lagune", start: 0x00C6FB, end: 0x2F6BFF),
        HabitColor(id: "glacier", name: "Gletscher", start: 0x9CC2FF, end: 0xB8F0FF),
        HabitColor(id: "iris", name: "Iris", start: 0x6E5BFF, end: 0xB57BFF),
        HabitColor(id: "ultra", name: "Ultraviolett", start: 0x8E2DE2, end: 0x4A3AFF),
        HabitColor(id: "orchid", name: "Orchidee", start: 0xD62BFF, end: 0x8B3DFF),
        HabitColor(id: "flamingo", name: "Flamingo", start: 0xFF4FA3, end: 0xFF8A65),
        HabitColor(id: "candy", name: "Zuckerwatte", start: 0xF472B6, end: 0x8B8CFF),
        HabitColor(id: "graphite", name: "Graphit", start: 0x8E9AAF, end: 0x5C677D),
    ]

    static let defaultID = "iris"

    /// Farben älterer Versionen bzw. Backups auf die neue Palette abbilden.
    private static let legacy: [String: String] = [
        "red": "lava", "coral": "sunset", "orange": "mango", "amber": "mango",
        "lime": "volt", "green": "neon", "teal": "aurora", "cyan": "lagoon",
        "blue": "lagoon", "indigo": "iris", "violet": "ultra", "purple": "orchid",
        "pink": "flamingo", "rose": "candy", "brown": "sunset",
    ]

    static func entry(_ id: String) -> HabitColor {
        let resolved = legacy[id] ?? id
        return all.first { $0.id == resolved } ?? all.first { $0.id == defaultID } ?? all[0]
    }

    static func color(_ id: String) -> Color { entry(id).color }

    /// Eine harmonische Begleitfarbe – liegt in der Palette ein Stück weiter.
    static func companion(of tint: HabitColor) -> HabitColor {
        let index = all.firstIndex { $0.id == tint.id } ?? 0
        return all[(index + 5) % all.count]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Symbol einer Gewohnheit – SF Symbol oder Emoji – auf einer zart getönten Fläche.
struct HabitIcon: View {
    let symbol: String
    let tint: HabitColor
    var size: CGFloat = 40

    init(symbol: String, tint: HabitColor, size: CGFloat = 40) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    init(symbol: String, colorID: String, size: CGFloat = 40) {
        self.init(symbol: symbol, tint: Palette.entry(colorID), size: size)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(tint.gradient.opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                HabitGlyph(symbol: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(tint.gradient)
            }
            .accessibilityHidden(true)
    }
}

/// Zeichnet ein SF Symbol oder – wenn der Text kein ASCII ist – ein Emoji.
struct HabitGlyph: View {
    let symbol: String

    static func isEmoji(_ symbol: String) -> Bool {
        !symbol.isEmpty && !symbol.allSatisfy(\.isASCII)
    }

    var body: some View {
        if Self.isEmoji(symbol) {
            Text(symbol)
        } else {
            Image(systemName: symbol.isEmpty ? "checkmark" : symbol)
        }
    }
}

/// Fortschrittsring, optional mit Farbverlauf.
struct ProgressRing: View {
    let progress: Double
    let color: Color
    var endColor: Color?
    var lineWidth: CGFloat = 8

    var body: some View {
        let style: AnyShapeStyle = endColor.map {
            AnyShapeStyle(AngularGradient(colors: [color, $0, color], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
        } ?? AnyShapeStyle(color)
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
