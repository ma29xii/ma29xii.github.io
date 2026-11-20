import SwiftUI
import SwiftData

struct WorkoutSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Environment(DataHub.self) private var hub
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    let session: WorkoutSession
    @State private var confirmDelete = false

    private var previous: WorkoutSession? {
        sessions.first { $0.title == session.title && $0.start < session.start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.start.formatted(Date.FormatStyle(locale: .german).weekday(.wide).day().month(.wide)))
                            .font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                        Text(session.title).font(.formaLargeTitle)
                    }
                    .padding(.top, Space.s3)

                    let records = session.exerciseNames.filter { name in
                        PersonalRecord.isNew(weight: session.bestOneRepMax(for: name), reps: 1, previousBest: bestBefore(name))
                    }
                    if !records.isEmpty {
                        RecordHero(names: records).padding(.top, Space.s5)
                    }

                    Plate {
                        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow {
                                stat("Dauer", session.duration < 60 ? "< 1 min" : Format.duration(session.duration))
                                stat("Trainingsvolumen", "\(Format.weight(session.volume, unit: app.weightUnit)) \(app.weightUnit.rawValue)")
                            }
                            Divider().overlay(Theme.hairline).gridCellColumns(2)
                            GridRow {
                                stat("Arbeitssätze", "\(session.workSets.count)")
                                stat("Übungen", "\(session.exerciseNames.count)")
                            }
                        }
                    }
                    .padding(.top, Space.s5)

                    FormaSection(title: "Geschätztes Gewicht für 1 Wiederholung") {
                        Plate {
                            ForEach(Array(session.exerciseNames.enumerated()), id: \.offset) { index, name in
                                if index > 0 { RowDivider() }
                                let now = session.bestOneRepMax(for: name)
                                let before = bestBefore(name)
                                // Gleiche Regel wie Kopf und Live-Hinweis: kein Rekord aus Rundungsresten.
                                let isRecord = PersonalRecord.isNew(weight: now, reps: 1, previousBest: before)
                                MetricRow(title: name,
                                          subtitle: before > 0 ? (isRecord ? "Neuer Bestwert · +\(Format.weight(now - before, unit: app.weightUnit)) \(app.weightUnit.rawValue)" : "Bestwert \(Format.weight(before, unit: app.weightUnit)) \(app.weightUnit.rawValue)") : "erstes Mal erfasst",
                                          value: now > 0 ? Format.weight(now, unit: app.weightUnit) : "–", unit: app.weightUnit.rawValue,
                                          valueColor: isRecord ? Theme.record : Theme.textPrimary)
                            }
                        }
                    }

                    if let previous {
                        FormaSection(title: "Gegen letztes Mal") {
                            Plate {
                                compareRow("Heute", session.volume, max(session.volume, previous.volume), Theme.textPrimary)
                                RowDivider()
                                compareRow(previous.start.formatted(Date.FormatStyle(locale: .german).day().month(.abbreviated)), previous.volume, max(session.volume, previous.volume), Theme.textTertiary)
                            }
                        }
                    }

                    FormaSection(title: "Sätze") {
                        Plate {
                            ForEach(Array(session.sets.sorted { $0.order < $1.order }.enumerated()), id: \.offset) { index, set in
                                if index > 0 { RowDivider() }
                                MetricRow(title: set.exerciseName,
                                          subtitle: set.isWarmup ? "Aufwärmen" : (set.rir >= 0 ? "RIR \(set.rir)" : nil),
                                          value: "\(Format.weight(set.weight, unit: app.weightUnit)) × \(set.reps)")
                            }
                        }
                    }

                    Button("Training löschen", role: .destructive) { confirmDelete = true }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                    Color.clear.frame(height: Space.s6)
                }
                .padding(.horizontal, Space.page)
            }
            .formaScreen()
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) {
                AchievementUnlockBanner(scope: hub.achievementHealthScope, isSample: hub.isSample)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .confirmationDialog("Training löschen?", isPresented: $confirmDelete) {
                Button("Löschen", role: .destructive) {
                    context.delete(session)
                    try? context.save()
                    dismiss()
                }
            }
        }
    }

    private func bestBefore(_ name: String) -> Double {
        sessions.filter { $0.start < session.start }.map { $0.bestOneRepMax(for: name) }.max() ?? 0
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
    }

    private func compareRow(_ label: String, _ value: Double, _ maxValue: Double, _ color: Color) -> some View {
        HStack(spacing: Space.s3) {
            Text(label).font(.formaCaption).foregroundStyle(Theme.textSecondary).frame(width: 64, alignment: .leading)
            ProgressLine(fraction: value / max(1, maxValue), color: color, height: 6)
            Text("\(Format.weight(value, unit: app.weightUnit)) \(app.weightUnit.rawValue)").font(.formaValue).frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: 44)
    }
}
