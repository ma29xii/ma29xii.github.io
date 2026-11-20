import SwiftUI

/// Zentrale, wiederverwendbare Bewegung (F6-09). Alles hier blendet bei „Bewegung reduzieren“ nur über.
enum FormaMotion {
    /// Feder fürs Aufspringen von Kacheln.
    static let pop = Animation.spring(response: 0.42, dampingFraction: 0.72)
    /// Sanftes Erscheinen von Karten.
    static let appear = Animation.spring(response: 0.5, dampingFraction: 0.9)
    /// Kurzes Überblenden, wenn Bewegung reduziert ist.
    static let calm = Animation.easeOut(duration: 0.15)
    /// Verzögerung je Position; ab der achten bleibt sie gleich, damit nichts spürbar wartet.
    static func stagger(_ index: Int, step: Double = 0.04) -> Double { Double(min(max(index, 0), 8)) * step }
}

private struct FormaAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    // UI-Tests und Bildschirmfotos zeigen sofort den Endzustand.
    @State private var shown = FormaApp.isUITest

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? FormaMotion.calm : FormaMotion.appear.delay(FormaMotion.stagger(index)), value: shown)
            .onAppear { shown = true }
    }
}

/// Aufspringen aus einer Ecke, gestaffelt nach Position. `visible` schaltet den Endzustand ein.
private struct FormaPop: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let visible: Bool
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(visible || reduceMotion ? 1 : 0.3, anchor: anchor)
            .opacity(visible ? 1 : 0)
            .animation(reduceMotion ? FormaMotion.calm : FormaMotion.pop.delay(FormaMotion.stagger(index, step: 0.035)), value: visible)
    }
}

/// Leichtes Einsinken beim Drücken.
struct FormaPressStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        Pressable(configuration: configuration, scale: scale)
    }

    private struct Pressable: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(reduceMotion ? FormaMotion.calm : .snappy(duration: 0.18), value: configuration.isPressed)
        }
    }
}

private struct FormaNumberRoll: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText(value: value))
            .animation(reduceMotion ? FormaMotion.calm : .snappy(duration: 0.4), value: value)
    }
}

extension View {
    /// Blendet beim ersten Erscheinen sanft ein und gleitet leicht hoch. `index` staffelt Reihen.
    func formaAppear(index: Int = 0) -> some View { modifier(FormaAppear(index: index)) }

    /// Federndes Aufspringen aus `anchor`, gestaffelt nach `index`.
    func formaPop(index: Int, visible: Bool, anchor: UnitPoint = .bottomTrailing) -> some View {
        modifier(FormaPop(index: index, visible: visible, anchor: anchor))
    }

    /// Ziffern rollen, wenn sich `value` ändert (bei „Bewegung reduzieren“ Überblenden).
    func formaNumberRoll(_ value: Double) -> some View { modifier(FormaNumberRoll(value: value)) }
}
