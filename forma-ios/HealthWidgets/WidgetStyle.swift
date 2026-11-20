import SwiftUI
import WidgetKit

/// Gemeinsamer Look aller Widgets: große runde Zahlen, feine Ringe, viel Luft, Akzent und Ringfarben aus dem Profil.
struct WidgetStyle {
    let palette: WidgetPalette
    let usesAppColors: Bool

    init(renderingMode: WidgetRenderingMode, showsBackground: Bool, palette: WidgetPalette = .load()) {
        self.palette = palette
        usesAppColors = renderingMode == .fullColor && showsBackground
    }

    var ink: Color { usesAppColors ? .white : .primary }
    var muted: Color { ink.opacity(0.62) }
    var track: Color { ink.opacity(0.14) }
    var accent: Color { usesAppColors ? palette.accentColor : ink }
    var strain: Color { usesAppColors ? palette.strainColor : ink }
    var sleep: Color { usesAppColors ? palette.sleepColor : ink }

    static let base = Color(red: 13 / 255, green: 14 / 255, blue: 15 / 255)

    /// Tiefes Schwarz mit einem weichen Hauch der Akzentfarbe oben rechts.
    func background() -> some View {
        ZStack {
            Self.base
            RadialGradient(colors: [palette.accentColor.opacity(0.20), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 190)
        }
    }

    /// Recovery bleibt eine Ampel.
    func recovery(_ value: Int?) -> Color {
        guard usesAppColors, let value else { return ink }
        if value >= 67 { return Color(sharedHex: 0x16EC06) }
        if value >= 34 { return Color(sharedHex: 0xFFDE00) }
        return Color(sharedHex: 0xFF0026)
    }
}

/// Feiner Ring mit runden Enden. `fraction` 0…1.
struct WidgetGauge: View {
    let fraction: Double
    let tint: Color
    let track: Color
    var line: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().inset(by: line / 2).stroke(track, lineWidth: line)
            if fraction > 0 {
                Circle().inset(by: line / 2)
                    .trim(from: 0, to: CGFloat(min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Dünner Fortschrittsbalken.
struct WidgetBar: View {
    let fraction: Double
    let tint: Color
    let track: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint)
                    .frame(width: max(fraction > 0 ? height : 0, geometry.size.width * CGFloat(min(1, max(0, fraction)))))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}

extension Font {
    /// Große Zahl eines Widgets, skaliert bei Bedarf herunter (mit `minimumScaleFactor`).
    static func widgetNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}
