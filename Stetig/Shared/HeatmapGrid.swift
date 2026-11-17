import SwiftUI

/// Das Kachel-Raster: Spalten sind Wochen, Zeilen sind Wochentage, die letzte
/// Spalte ist die aktuelle Woche. Wird mit `Canvas` gezeichnet und ist damit
/// auch bei vielen Gewohnheiten und in Widgets schnell.
///
/// Mit `endColor` verläuft die Farbe von links (älteste Woche) nach rechts (heute).
struct HeatmapGrid: View {
    let today: Day
    let weekStart: Int
    let color: Color
    var endColor: Color?
    /// Feste Spaltenzahl (Höhe ergibt sich aus der Breite). `nil` = so viele
    /// Wochen, wie in die verfügbare Breite passen.
    var columns: Int?
    var showMonths: Bool = false
    let cell: (Day) -> HeatCell

    /// Abstand zwischen Kacheln relativ zur Kachelgröße.
    static let gap: CGFloat = 0.26
    /// Höhe der Monatszeile relativ zur Kachelgröße.
    static let monthBand: CGFloat = 1.6

    init(
        today: Day,
        weekStart: Int,
        color: Color,
        endColor: Color? = nil,
        columns: Int? = nil,
        showMonths: Bool = false,
        cell: @escaping (Day) -> HeatCell
    ) {
        self.today = today
        self.weekStart = weekStart
        self.color = color
        self.endColor = endColor
        self.columns = columns
        self.showMonths = showMonths
        self.cell = cell
    }

    init(snapshot: HabitSnapshot, tint: HabitColor, columns: Int? = nil, showMonths: Bool = false) {
        self.init(
            today: snapshot.today,
            weekStart: snapshot.rule.weekStart,
            color: tint.color,
            endColor: tint.endColor,
            columns: columns,
            showMonths: showMonths,
            cell: { snapshot.cell($0) }
        )
    }

    init(snapshot: HabitSnapshot, color: Color, columns: Int? = nil, showMonths: Bool = false) {
        self.init(
            today: snapshot.today,
            weekStart: snapshot.rule.weekStart,
            color: color,
            columns: columns,
            showMonths: showMonths,
            cell: { snapshot.cell($0) }
        )
    }

    static func aspectRatio(columns: Int, showMonths: Bool) -> CGFloat {
        let count = CGFloat(max(1, columns))
        let width = count + (count - 1) * gap
        let height = 7 + 6 * gap + (showMonths ? monthBand : 0)
        return width / height
    }

    var body: some View {
        if let columns {
            canvas.aspectRatio(Self.aspectRatio(columns: columns, showMonths: showMonths), contentMode: .fit)
        } else {
            canvas
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            let band = showMonths ? Self.monthBand : 0
            let side = size.height / (7 + 6 * Self.gap + band)
            guard side > 0.5 else { return }
            let pitch = side * (1 + Self.gap)
            let count = columns ?? max(1, Int((size.width + side * Self.gap) / pitch))
            let totalWidth = CGFloat(count) * pitch - side * Self.gap
            let originX = size.width - totalWidth
            let originY = side * band
            let currentWeek = today.startOfWeek(weekStart: weekStart)
            let radius = side * 0.32

            let start = color.resolve(in: context.environment)
            let end = (endColor ?? color).resolve(in: context.environment)
            let empty = Color.primary.opacity(0.08)
            let future = Color.primary.opacity(0.035)

            var labelledMonth = -1
            var lastLabelColumn = -10

            for column in 0..<count {
                let firstDayOfWeek = currentWeek.adding(-(count - 1 - column) * 7)
                let x = originX + CGFloat(column) * pitch
                let t = count > 1 ? Float(column) / Float(count - 1) : 1
                let columnColor = Color(Color.Resolved(
                    colorSpace: .sRGB,
                    red: start.red + (end.red - start.red) * t,
                    green: start.green + (end.green - start.green) * t,
                    blue: start.blue + (end.blue - start.blue) * t,
                    opacity: 1
                ))

                if showMonths {
                    let month = firstDayOfWeek.adding(6).month
                    if month != labelledMonth {
                        if column - lastLabelColumn >= 3, column <= count - 2 || count < 4 {
                            let label = Text(Day.monthSymbolsShort[month - 1])
                                .font(.system(size: max(8, side * 0.95), weight: .medium))
                                .foregroundStyle(.secondary)
                            context.draw(label, at: CGPoint(x: x, y: 0), anchor: .topLeading)
                            lastLabelColumn = column
                        }
                        labelledMonth = month
                    }
                }

                for row in 0..<7 {
                    let day = firstDayOfWeek.adding(row)
                    let rect = CGRect(x: x, y: originY + CGFloat(row) * pitch, width: side, height: side)
                    let path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)

                    if day > today {
                        context.fill(path, with: .color(future))
                        continue
                    }

                    let value = cell(day)
                    let level = min(1, max(0, value.level))
                    if level > 0 {
                        context.fill(path, with: .color(columnColor.opacity(0.3 + 0.7 * level)))
                    } else {
                        context.fill(path, with: .color(empty))
                    }

                    if value.skipped {
                        let inset = max(0.5, side * 0.07)
                        let ring = Path(
                            roundedRect: rect.insetBy(dx: inset, dy: inset),
                            cornerRadius: max(0, radius - inset),
                            style: .continuous
                        )
                        context.stroke(ring, with: .color(columnColor.opacity(0.6)), lineWidth: max(1, side * 0.11))
                    }
                    if value.slipped {
                        let dot = Path(ellipseIn: rect.insetBy(dx: side * 0.32, dy: side * 0.32))
                        context.fill(dot, with: .color(columnColor.opacity(0.85)))
                    }
                }
            }
        }
        .accessibilityLabel("Verlauf als Kachel-Raster")
    }
}
