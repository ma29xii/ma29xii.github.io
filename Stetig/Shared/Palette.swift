import SwiftUI

struct HabitColor: Identifiable, Hashable {
    let id: String
    let name: String
    let hex: UInt32

    var color: Color { Color(hex: hex) }
}

enum Palette {
    static let all: [HabitColor] = [
        HabitColor(id: "red", name: "Rot", hex: 0xE5484D),
        HabitColor(id: "coral", name: "Koralle", hex: 0xF2714B),
        HabitColor(id: "orange", name: "Orange", hex: 0xF7931A),
        HabitColor(id: "amber", name: "Bernstein", hex: 0xF0B429),
        HabitColor(id: "lime", name: "Limette", hex: 0x8CC63F),
        HabitColor(id: "green", name: "Grün", hex: 0x3DBB6D),
        HabitColor(id: "teal", name: "Türkis", hex: 0x1FB5A3),
        HabitColor(id: "cyan", name: "Cyan", hex: 0x22B8D6),
        HabitColor(id: "blue", name: "Blau", hex: 0x3B8BF5),
        HabitColor(id: "indigo", name: "Indigo", hex: 0x5B6CF0),
        HabitColor(id: "violet", name: "Violett", hex: 0x8E5CF2),
        HabitColor(id: "purple", name: "Lila", hex: 0xB45CE6),
        HabitColor(id: "pink", name: "Pink", hex: 0xEC5FA5),
        HabitColor(id: "rose", name: "Rosé", hex: 0xF0567A),
        HabitColor(id: "brown", name: "Braun", hex: 0xA87C5F),
        HabitColor(id: "graphite", name: "Graphit", hex: 0x8B93A1),
    ]

    static func color(_ id: String) -> Color {
        (all.first { $0.id == id } ?? all[9]).color
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

/// Symbol einer Gewohnheit – SF Symbol oder Emoji – in einem farbigen Feld.
struct HabitIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                HabitGlyph(symbol: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(color)
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

struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
