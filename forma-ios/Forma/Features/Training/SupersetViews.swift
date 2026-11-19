import SwiftUI

/// Supersatz-Faden: eine feine Linie links neben den gekoppelten Übungen, ein Punkt an jedem Übungsnamen.
/// Eigene Form statt Klammer: ruhig, in der gedämpften Akzentfarbe der Muskelkarte.
enum SupersetStyle {
    static let tint = Theme.strain.mix(with: Color(white: 0.62), by: 0.3)
    static let lineWidth: CGFloat = 1.5
    static let node: CGFloat = 7
}

extension View {
    /// Durchgehender Faden über die ganze Höhe; `overhang` verlängert ihn nach unten bis zur nächsten Zeile.
    func supersetThread(_ visible: Bool, inset: CGFloat = 10, overhang: CGFloat = 0) -> some View {
        overlay(alignment: .leading) {
            if visible {
                Rectangle().fill(SupersetStyle.tint.opacity(0.6))
                    .frame(width: SupersetStyle.lineWidth)
                    .padding(.bottom, -overhang)
                    .offset(x: -inset - SupersetStyle.lineWidth / 2)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Punkt auf Höhe dieser Zeile; der Faden läuft nach oben bzw. unten weiter, je nach Lage in der Gruppe.
    func supersetNode(_ position: Superset.Position?, inset: CGFloat = 10, overhang: CGFloat = 0) -> some View {
        overlay(alignment: .leading) {
            if let position {
                ZStack {
                    VStack(spacing: 0) {
                        Rectangle().fill(SupersetStyle.tint.opacity(position == .first ? 0 : 0.6))
                            .padding(.top, -overhang)
                        Rectangle().fill(SupersetStyle.tint.opacity(position == .last ? 0 : 0.6))
                            .padding(.bottom, -overhang)
                    }
                    .frame(width: SupersetStyle.lineWidth)
                    Circle().fill(SupersetStyle.tint)
                        .frame(width: SupersetStyle.node, height: SupersetStyle.node)
                }
                .frame(width: SupersetStyle.node)
                .offset(x: -inset - SupersetStyle.node / 2)
                .accessibilityHidden(true)
            }
        }
    }
}
