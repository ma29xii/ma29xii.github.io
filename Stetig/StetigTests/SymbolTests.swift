import Testing
import UIKit
@testable import Stetig

/// Stellt sicher, dass jedes verwendete SF Symbol auf dem System wirklich existiert –
/// ein Tippfehler im Namen würde sonst nur als leere Fläche auffallen.
@MainActor
struct SymbolTests {
    @Test func pickerAndTemplateSymbolsExist() {
        let picker = SymbolPickerView.groups.flatMap { $0.symbols }
        let templates = HabitTemplates.groups.flatMap { $0.templates.map(\.symbol) }
        #expect(picker.count > 80)
        #expect(Set(picker).count == picker.count, "Symbol doppelt in der Auswahl")
        for symbol in picker + templates {
            #expect(UIImage(systemName: symbol) != nil, "Symbol fehlt: \(symbol)")
        }
    }

    @Test func interfaceSymbolsExist() {
        let symbols = [
            "square.grid.3x3.fill", "square.grid.3x3", "checkmark.circle.fill", "checkmark.circle", "chart.bar.fill",
            "chart.bar", "gearshape.fill", "line.3.horizontal.decrease", "plus", "arrow.up.arrow.down", "pencil",
            "forward.end", "forward.end.fill", "arrow.uturn.backward", "play", "pause", "pause.fill", "archivebox",
            "trash", "plus.square.on.square", "flame.fill", "trophy.fill", "checkmark.seal.fill", "percent",
            "calendar", "sum", "clock.fill", "square.and.arrow.up", "square.and.pencil", "ellipsis",
            "pause.circle.fill", "minus", "timer", "chevron.left", "chevron.right", "xmark", "eraser", "faceid",
            "lock.fill", "folder", "bell", "square.and.arrow.down", "tablecells", "sparkles", "wand.and.stars",
            "star.fill", "crown.fill", "medal.fill", "shield.fill", "bolt.fill", "figure.walk", "sun.max",
            "play.fill", "checkmark", "plus.circle.fill", "heart.fill", "brain.head.profile", "figure.run",
            "list.bullet", "lightbulb", "hand.tap", "hand.point.up.left", "nosign", "square.grid.2x2", "mic",
        ]
        for symbol in symbols {
            #expect(UIImage(systemName: symbol) != nil, "Symbol fehlt: \(symbol)")
        }
    }

    @Test func paletteIsConsistent() {
        #expect(Palette.all.count == 16)
        #expect(Set(Palette.all.map(\.id)).count == Palette.all.count)
        for group in HabitTemplates.groups {
            for template in group.templates {
                #expect(Palette.all.contains { $0.id == template.colorID }, "Unbekannte Farbe: \(template.colorID)")
                #expect(template.isValid)
            }
        }
    }
}
