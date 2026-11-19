import SwiftUI

/// Strichskala für einen Messwert, einen optionalen Zielbereich und einen einzelnen Zielstrich.
struct MetricScale: View {
    let value: Double?
    let tint: Color
    var domain: ClosedRange<Double> = 0...100
    var axis: Axis = .horizontal
    var target: ClosedRange<Double>? = nil
    var goal: Double? = nil

    private let intervals = 20

    var body: some View {
        let marker = value.flatMap(fraction)
        let goalMarker = goal.flatMap(fraction)
        let band = target.flatMap { range -> ClosedRange<Double>? in
            guard range.overlaps(domain), let lower = fraction(range.lowerBound),
                  let upper = fraction(range.upperBound) else { return nil }
            return lower...upper
        }

        Canvas { context, size in
            let vertical = axis == .vertical
            let length = vertical ? size.height : size.width
            let breadth = vertical ? size.width : size.height
            let span = max(0, length - 6)
            func rect(at fraction: Double, along: CGFloat, across: CGFloat) -> CGRect {
                let position = 3 + span * fraction
                if vertical {
                    return CGRect(x: (breadth - across) / 2, y: length - position - along / 2,
                                  width: across, height: along)
                }
                return CGRect(x: position - along / 2, y: (breadth - across) / 2,
                              width: along, height: across)
            }

            if let band {
                let center = (band.lowerBound + band.upperBound) / 2
                let background = rect(at: center, along: max(2, span * (band.upperBound - band.lowerBound)),
                                      across: breadth * 0.90)
                context.fill(Path(roundedRect: background, cornerRadius: 3), with: .color(tint.opacity(0.2)))
            }

            for index in 0...intervals {
                let tick = Double(index) / Double(intervals)
                let major = index.isMultiple(of: 5)
                let color: Color
                if band?.contains(tick) == true {
                    color = tint
                } else if let marker, tick <= marker {
                    color = tint.opacity(0.75)
                } else {
                    color = Theme.textQuaternary
                }
                let stroke = rect(at: tick, along: 1, across: breadth * (major ? 0.62 : 0.40))
                context.fill(Path(stroke), with: .color(color))
            }

            if let goalMarker {
                let stroke = rect(at: goalMarker, along: 2, across: breadth * 0.84)
                context.fill(Path(stroke), with: .color(tint))
            }
            if let marker {
                let stroke = rect(at: marker, along: 3, across: breadth)
                context.fill(Path(roundedRect: stroke, cornerRadius: 1.5), with: .color(Theme.textPrimary))
            }
        }
    }

    private func fraction(_ value: Double) -> Double? {
        let width = domain.upperBound - domain.lowerBound
        guard value.isFinite, width.isFinite, width > 0 else { return nil }
        let clamped = min(domain.upperBound, max(domain.lowerBound, value))
        return (clamped - domain.lowerBound) / width
    }
}
