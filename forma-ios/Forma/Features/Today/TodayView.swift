import SwiftUI
import SwiftData

enum TodayRoute: Hashable {
    case ring(RingKind)
    case metric(MetricKind)
}

struct TodayView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var path: [TodayRoute] = []
    @State private var showCompactRings = false

    private var planned: Routine? {
        routines.min { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
    }
    private var trainedToday: Bool { sessions.contains { Calendar.forma.isDateInToday($0.start) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    rings
                    coachLine
                    nextSection
                    energySection
                    bodySection
                    daySection
                    weekSection
                    insightSection
                    Color.clear.frame(height: Space.s7)
                }
                .padding(.horizontal, Space.page)
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 250
            } action: { _, isPast in
                withAnimation(.snappy(duration: 0.25)) { showCompactRings = isPast }
            }
            .overlay(alignment: .top) {
                if showCompactRings { compactRings.transition(.move(edge: .top).combined(with: .opacity)) }
            }
            .refreshable { await hub.refresh() }
            .formaScreen()
            .navigationTitle("Heute")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.showProfile = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Profil und Einstellungen")
                }
            }
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .ring(let kind): RingDetailView(kind: kind)
                case .metric(let kind): MetricDetailView(kind: kind)
                }
            }
        }
    }

    // MARK: Kopf und Ringe

    private var header: some View {
        HStack(spacing: Space.s2) {
            Text(Format.dayTitle(.now))
                .font(.formaCaptionStrong)
                .foregroundStyle(Theme.textSecondary)
            if hub.isSample {
                Button { app.showProfile = true } label: { SampleDataBadge() }
                    .buttonStyle(.plain)
                    .accessibilityHint("Öffnet die Datenquellen")
            }
            Spacer()
        }
        .padding(.top, Space.s1)
    }

    private var rings: some View {
        let s = hub.ringScores
        return VStack(spacing: Space.s3) {
            RingTrio(strain: s.strain, recovery: s.recovery, sleep: s.sleep, target: s.target,
                     dimmedRecoverySleep: hub.waitingForFitbit) { kind in path.append(.ring(kind)) }
                .padding(.top, Space.s5)
            if hub.waitingForFitbit {
                Label("Warte auf Fitbit – du siehst die Werte von gestern", systemImage: "arrow.triangle.2.circlepath")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                InfoChip(text: "Ziel \(s.target.lowerBound)–\(s.target.upperBound)")
                if s.sleepDebt >= 10 * 60 { InfoChip(text: "Schlafschuld \(Format.duration(s.sleepDebt))") }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var compactRings: some View {
        let s = hub.ringScores
        return RingTrio(strain: s.strain, recovery: s.recovery, sleep: s.sleep, target: s.target,
                        dimmedRecoverySleep: hub.waitingForFitbit, compact: true) { kind in path.append(.ring(kind)) }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s2)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, Space.s2)
    }

    private var coachContext: CoachEngine.Context {
        CoachEngine.Context(
            scores: hub.scores, today: hub.today,
            hrvDelta: hub.today.hrv.flatMap { v in hub.baseline(\.hrv).map { v - $0.mean } },
            rhrDelta: hub.today.restingHR.flatMap { v in hub.baseline(\.restingHR).map { v - $0.mean } },
            plannedRoutine: planned?.name, trainedToday: trainedToday, isSample: hub.isSample,
            hour: Calendar.forma.component(.hour, from: .now))
    }

    private var coachLine: some View {
        let line = CoachEngine.dailyLine(coachContext)
        return Button {
            app.openCoach(with: line)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(line)
                    .font(.formaBodyLarge)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textQuaternary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Space.s5)
        .accessibilityHint("Öffnet den Coach mit diesem Thema")
    }

    // MARK: Abschnitte

    private var nextSection: some View {
        let s = hub.scores
        return FormaSection(title: "Als Nächstes") {
            Plate {
                if let routine = planned, !trainedToday {
                    MetricRow(title: "\(routine.name) · \(routine.items.count) Übungen",
                              subtitle: "\(routine.totalSets) Sätze · etwa \(routine.totalSets * 2 + 5) min") {
                        Button("Start") { start(routine) }
                            .buttonStyle(SmallPillButtonStyle())
                    }
                    RowDivider()
                } else if trainedToday, let last = sessions.first {
                    Button { app.finishedSession = last } label: {
                        MetricRow(title: "\(last.title) erledigt", subtitle: "\(Format.duration(last.duration)) · \(Format.number(last.volume)) kg Volumen", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    RowDivider()
                }
                Button { path.append(.ring(.sleep)) } label: {
                    MetricRow(title: "Ins Bett um \(CoachEngine.bedtime(s))", subtitle: "für \(Format.duration(s.sleepNeed)) Schlaf", showsChevron: true)
                }
                .buttonStyle(.plain)
                RowDivider()
                Button { app.showJournal = true } label: {
                    MetricRow(title: "Journal", subtitle: "Ein paar Ja/Nein-Fragen zu gestern", showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var energySection: some View {
        let s = hub.scores
        return FormaSection(title: "Energie und Stress") {
            Plate {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Energie").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                        Text("\(s.energy)").font(.formaBigNumber)
                        HStack(spacing: 3) {
                            ForEach(0..<10, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(i < s.energy / 10 ? Theme.textPrimary : Color.white.opacity(0.08))
                                    .frame(height: 6)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Theme.hairline).frame(width: 0.5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stress").font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Format.number(s.stress, decimals: 1)).font(.formaBigNumber)
                            Text("von 3").font(.formaCaption).foregroundStyle(Theme.textSecondary)
                        }
                        Text("geschätzt").font(.formaMicro).foregroundStyle(Theme.textTertiary).padding(.top, 6)
                    }
                    .padding(Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var bodySection: some View {
        FormaSection(title: "Körper") {
            Plate {
                let kinds: [MetricKind] = [.hrv, .restingHR, .respiratoryRate, .spo2]
                ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                    if index > 0 { RowDivider() }
                    Button { path.append(.metric(kind)) } label: { MetricSummaryRow(kind: kind) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var daySection: some View {
        let t = hub.today
        return FormaSection(title: "Tag") {
            Plate {
                HStack(spacing: 0) {
                    miniStat("Schritte", value: Format.number(t.steps ?? 0), fraction: (t.steps ?? 0) / 10000)
                    Rectangle().fill(Theme.hairline).frame(width: 0.5)
                    miniStat("Aktive Energie", value: "\(Format.number(t.activeEnergy ?? 0)) kcal", fraction: (t.activeEnergy ?? 0) / 600)
                }
                ForEach(t.workouts) { w in
                    RowDivider()
                    MetricRow(title: w.name, subtitle: "\(Format.clock(w.start)) · \(Format.duration(w.duration))",
                              value: w.energy.map { "\(Format.number($0)) kcal" })
                }
            }
        }
    }

    private func miniStat(_ title: String, value: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            ProgressLine(fraction: fraction).padding(.top, 6)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekSection: some View {
        let weekStart = Calendar.forma.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let week = sessions.filter { $0.start >= weekStart }
        let recoveries = (max(0, hub.days.count - 7)..<hub.days.count).map { hub.scores(for: $0).recovery }
        let avg = recoveries.isEmpty ? 0 : recoveries.reduce(0, +) / recoveries.count
        return FormaSection(title: "Diese Woche") {
            Plate {
                MetricRow(title: "Trainings", subtitle: week.isEmpty ? "noch keins" : week.map(\.title).joined(separator: ", "), value: "\(week.count)")
                RowDivider()
                MetricRow(title: "Volumen", value: Format.number(week.reduce(0) { $0 + $1.volume }), unit: "kg")
                RowDivider()
                MetricRow(title: "Erholung im Mittel", subtitle: "letzte 7 Tage", value: "\(avg)")
            }
        }
    }

    private var insightSection: some View {
        FormaSection(title: "Einblick") {
            Plate {
                Button { app.openCoach(with: Insights.text(hub.days)) } label: {
                    MetricRow(title: Insights.title(hub.days), subtitle: Insights.text(hub.days), showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func start(_ routine: Routine) {
        routine.lastUsed = .now
        app.liveWorkout = LiveWorkout.from(routine, history: sessions, adjustment: TrainingAdjustment.today)
    }
}

/// Einfache, ehrliche Auswertung aus den vorhandenen Tagen.
enum Insights {
    static func split(_ days: [DayMetrics]) -> (active: Double, calm: Double, n: Int)? {
        let pairs = zip(days, days.dropFirst()).compactMap { prev, next -> (Bool, Double)? in
            guard let steps = prev.steps, let sleep = next.sleep?.asleep else { return nil }
            return (steps >= 8000, sleep)
        }
        let active = pairs.filter(\.0).map(\.1), calm = pairs.filter { !$0.0 }.map(\.1)
        guard active.count >= 3, calm.count >= 3 else { return nil }
        return (active.reduce(0, +) / Double(active.count), calm.reduce(0, +) / Double(calm.count), pairs.count)
    }

    static func title(_ days: [DayMetrics]) -> String {
        guard let s = split(days) else { return "Noch zu wenig Daten" }
        let diff = Int(((s.active - s.calm) / 60).rounded())
        return diff >= 0 ? "Nach aktiven Tagen schläfst du \(diff) min länger" : "Nach aktiven Tagen schläfst du \(-diff) min kürzer"
    }

    static func text(_ days: [DayMetrics]) -> String {
        guard let s = split(days) else { return "Nach etwa zwei Wochen zeige ich dir hier Zusammenhänge." }
        return "Verglichen: Tage mit mindestens 8.000 Schritten und die Nacht danach, aus \(s.n) Nächten."
    }
}
