import Foundation

struct ShareCardContent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case today, training, healthAge

        var title: String {
            switch self {
            case .today: "Today"
            case .training: "Training"
            case .healthAge: "Health Age"
            }
        }
    }

    struct Metric: Equatable, Sendable, Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    struct Display: Equatable, Sendable {
        let kind: Kind
        let isSample: Bool
        let date: String?
        let metrics: [Metric]
    }

    private let kind: Kind
    private let isSample: Bool
    private let date: Date?
    private let metrics: [Metric]

    var hasMeasurements: Bool { !metrics.isEmpty }

    func display(includeMeasurements: Bool) -> Display {
        guard includeMeasurements && hasMeasurements else {
            return Display(kind: kind, isSample: isSample, date: nil, metrics: [])
        }
        return Display(kind: kind, isSample: isSample, date: date.map { Format.dayTitle($0) }, metrics: metrics)
    }

    static func today(_ snapshot: DashboardDay, isSample: Bool) -> Self {
        let metrics: [Metric] = [
            score(snapshot.strain, label: "Strain", unit: ""),
            score(snapshot.recovery, label: "Recovery", unit: " %"),
            score(snapshot.sleepScore, label: "Sleep", unit: " %")
        ].compactMap { $0 }
        return Self(kind: .today, isSample: isSample, date: snapshot.day.date, metrics: metrics)
    }

    @MainActor
    static func training(_ session: WorkoutSession, unit: WeightUnit, isSample: Bool) -> Self {
        var metrics: [Metric] = []
        let duration = session.duration
        if duration > 0, Int(exactly: (duration / 60).rounded()) != nil {
            metrics.append(Metric(label: "Dauer", value: duration < 60 ? "< 1 min" : Format.duration(duration)))
        }
        metrics.append(Metric(label: "Arbeitssätze", value: Format.number(Double(session.workSets.count))))
        let volume = session.volume
        if volume > 0, (volume * (unit == .kg ? 1 : 2.20462) * 10).isFinite {
            metrics.append(Metric(label: "Volumen", value: "\(Format.weight(volume, unit: unit)) \(unit.rawValue)"))
        }
        return Self(kind: .training, isSample: isSample, date: session.start, metrics: metrics)
    }

    static func healthAge(_ result: BodyAge.Result, isSample: Bool) -> Self {
        let metrics = result.bodyAge.isFinite
            ? [Metric(label: "Schätzung", value: BodyAgeText.spokenAge(result))]
            : []
        return Self(kind: .healthAge, isSample: isSample, date: nil, metrics: metrics)
    }

    private static func score(_ number: Int?, label: String, unit: String) -> Metric? {
        guard let number, (0...100).contains(number) else { return nil }
        return Metric(label: label, value: "\(number)\(unit)")
    }
}
