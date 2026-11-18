import SwiftUI
import SwiftData
import Charts

/// Verlauf einer Übung: geschätztes Maximum je Training, Bestwert, letzte Sätze.
struct ExerciseDetailView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutSession.start) private var sessions: [WorkoutSession]
    let exercise: Exercise

    private var points: [(Date, Double)] {
        sessions.compactMap { s in
            let best = s.bestOneRepMax(for: exercise.name)
            return best > 0 ? (s.start, best) : nil
        }
    }

    var body: some View {
        let pts = points
        let best = pts.map(\.1).max()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(exercise.muscle) · \(exercise.equipment)").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(best.map { Format.weight($0, unit: app.weightUnit) } ?? "–").font(.system(size: 48, weight: .semibold)).monospacedDigit()
                        Text(app.weightUnit.rawValue).font(.formaBody).foregroundStyle(Theme.textSecondary)
                    }
                    Text("bestes geschätztes Maximum (Epley)").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, Space.s4)

                if pts.count >= 2 {
                    Plate {
                        Chart {
                            ForEach(pts, id: \.0) { p in
                                LineMark(x: .value("Datum", p.0), y: .value("1RM", p.1))
                                    .interpolationMethod(.monotone)
                                    .foregroundStyle(Theme.textPrimary)
                                PointMark(x: .value("Datum", p.0), y: .value("1RM", p.1))
                                    .foregroundStyle(Theme.textPrimary)
                                    .symbolSize(18)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxis {
                            AxisMarks(position: .trailing) { _ in
                                AxisGridLine().foregroundStyle(Theme.hairline)
                                AxisValueLabel().foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textTertiary) }
                        }
                        .frame(height: 200)
                        .padding(Space.s4)
                    }
                    .padding(.top, Space.s5)
                } else {
                    Text("Nach zwei Trainings mit dieser Übung siehst du hier deinen Verlauf.")
                        .font(.formaBody).foregroundStyle(Theme.textSecondary).padding(.top, Space.s5)
                }

                let recent = sessions.reversed().filter { $0.sets.contains { $0.exerciseName == exercise.name } }.prefix(6)
                if !recent.isEmpty {
                    FormaSection(title: "Letzte Trainings") {
                        Plate {
                            ForEach(Array(recent.enumerated()), id: \.offset) { index, s in
                                if index > 0 { RowDivider() }
                                let work = s.workSets.filter { $0.exerciseName == exercise.name }
                                MetricRow(title: s.start.formatted(Date.FormatStyle(locale: .german).day().month(.wide)),
                                          subtitle: work.map { "\(Format.weight($0.weight, unit: app.weightUnit)) × \($0.reps)" }.joined(separator: " · "),
                                          value: Format.weight(s.bestOneRepMax(for: exercise.name), unit: app.weightUnit), unit: app.weightUnit.rawValue)
                            }
                        }
                    }
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.page)
        }
        .formaScreen()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
