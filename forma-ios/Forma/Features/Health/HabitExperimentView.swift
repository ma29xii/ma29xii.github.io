import SwiftUI

private let experimentTint = Theme.sleep

/// Einstieg im Health-Tab: zeigt Stand des laufenden Experiments oder lädt zu einem neuen ein.
struct ExperimentTile: View {
    @Environment(DataHub.self) private var hub
    @State private var store = ExperimentStore()

    var body: some View {
        NavigationLink {
            ExperimentDetailView(store: $store, isSample: hub.isSample)
        } label: {
            DashboardCard {
                HStack(spacing: Space.s4) {
                    ExperimentRing(fraction: fraction, lineWidth: 5) {
                        Image(systemName: store.current?.habit.icon ?? "flask")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gewohnheit").formaLabelStyle()
                        Text(status)
                            .font(.formaRowTitle)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Space.s4)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("health.experiment")
        .onAppear { store = ExperimentStore.load(isSample: hub.isSample) }
        .onChange(of: hub.isSample) { _, sample in store = ExperimentStore.load(isSample: sample) }
    }

    private var fraction: Double {
        guard let current = store.current else { return 0 }
        return Double(current.answeredCount) / Double(HabitExperiment.length)
    }

    private var status: String {
        guard let current = store.current else { return "Starten" }
        if current.isComplete() { return "Ergebnis bereit" }
        return "Tag \(current.elapsedDays()) von \(HabitExperiment.length)"
    }
}

/// Fortschrittsring über 14 Tage.
struct ExperimentRing<Center: View>: View {
    let fraction: Double
    var lineWidth: CGFloat = 12
    @ViewBuilder var center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let value = min(1, max(0, fraction))
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(value))
                .stroke(experimentTint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(lineWidth / 2)
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: value)
    }
}

/// Auswahl, Protokoll und Ergebnis eines Experiments.
struct ExperimentDetailView: View {
    @Binding var store: ExperimentStore
    let isSample: Bool
    @Environment(DataHub.self) private var hub
    @State private var confirmEnd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                if isSample { SampleDataBadge() }
                if let current = store.current {
                    running(current)
                } else {
                    picker
                }
                if !store.past.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        DashboardHeading(title: "Frühere Gewohnheiten")
                        DashboardCard {
                            ForEach(Array(store.past.enumerated()), id: \.element.id) { index, experiment in
                                if index > 0 { RowDivider() }
                                NavigationLink {
                                    ScrollView {
                                        ExperimentResults(experiment: experiment, days: hub.longDays)
                                            .padding(.horizontal, Space.page)
                                            .padding(.vertical, Space.s4)
                                    }
                                    .dashboardScreen()
                                    .navigationTitle(experiment.habit.title)
                                    .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    HStack(spacing: Space.s3) {
                                        Image(systemName: experiment.habit.icon)
                                            .foregroundStyle(Theme.textSecondary)
                                            .frame(width: 24)
                                            .accessibilityHidden(true)
                                        Text(experiment.habit.title).font(.formaRowTitle)
                                        Spacer()
                                        Text(Format.shortDate(experiment.start))
                                            .font(.formaCaption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .padding(.horizontal, Space.s4)
                                    .frame(minHeight: 52)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.s4)
        }
        .dashboardScreen()
        .navigationTitle("Gewohnheit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.current != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Beenden") { confirmEnd = true }
                }
            }
        }
        .confirmationDialog("Gewohnheit beenden?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Beenden und auswerten") { update { $0.finishCurrent() } }
            Button("Verwerfen", role: .destructive) { update { $0.current = nil } }
        }
        .onChange(of: store) { _, value in value.save(isSample: isSample) }
    }

    // MARK: Auswahl

    private var picker: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Welche Gewohnheit testest du?")
                .font(.formaHeadline)
                .padding(.top, Space.s2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s3), GridItem(.flexible(), spacing: Space.s3)],
                      spacing: Space.s3) {
                ForEach(ExperimentHabit.allCases) { habit in
                    Button {
                        update { $0.current = HabitExperiment(habit: habit, start: .now) }
                    } label: {
                        VStack(alignment: .leading, spacing: Space.s3) {
                            Image(systemName: habit.icon)
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(experimentTint)
                            Text(habit.title)
                                .font(.formaRowTitle)
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Space.s4)
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                        .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Startet diese Gewohnheit für 14 Tage")
                }
            }
        }
    }

    // MARK: Laufend

    @ViewBuilder
    private func running(_ experiment: HabitExperiment) -> some View {
        let today = experiment.dayIndex(of: .now)
        let complete = experiment.isComplete()

        VStack(spacing: Space.s2) {
            ExperimentRing(fraction: Double(experiment.answeredCount) / Double(HabitExperiment.length)) {
                VStack(spacing: 2) {
                    Text(complete ? "14" : "\(experiment.elapsedDays())")
                        .font(.formaDisplay)
                        .formaNumberTransition(Double(experiment.elapsedDays()))
                    Text("von 14 Tagen")
                        .font(.formaCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 188, height: 188)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fortschritt")
            .accessibilityValue("Tag \(experiment.elapsedDays()) von 14, \(experiment.answeredCount) Antworten")
            Label(experiment.habit.title, systemImage: experiment.habit.icon)
                .font(.formaRowTitle)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s2)

        if let today, !complete {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(experiment.habit.question)
                    .font(.formaHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s3) {
                    answerButton("Ja", value: true, day: today, experiment: experiment)
                    answerButton("Nein", value: false, day: today, experiment: experiment)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
        }

        ExperimentDays(experiment: experiment) { index in
            update { store in
                guard var current = store.current else { return }
                // Offen → mit → ohne → offen. Zukünftige Tage sind nicht antippbar.
                switch current.answers[index] {
                case nil: current.answers[index] = true
                case true?: current.answers[index] = false
                case false?: current.answers[index] = nil
                }
                store.current = current
            }
        }

        if complete {
            ExperimentResults(experiment: experiment, days: hub.longDays)
            Button {
                update { $0.finishCurrent() }
            } label: {
                Text("Abschließen")
                    .font(.formaRowTitle)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
        }
    }

    private func answerButton(_ title: String, value: Bool, day: Int, experiment: HabitExperiment) -> some View {
        let selected = experiment.answers[day] == value
        return Button {
            update { store in store.current?.answers[day] = value }
        } label: {
            Text(title)
                .font(.formaRowTitle)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(selected ? Theme.onSelection : Theme.textPrimary)
                .background(selected ? Theme.selection : Theme.cardRaised,
                            in: .rect(cornerRadius: Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func update(_ change: (inout ExperimentStore) -> Void) {
        var copy = store
        change(&copy)
        store = copy
    }
}

/// 14 Tage als zwei Reihen: gefüllt = mit, Ring = ohne, blass = offen.
private struct ExperimentDays: View {
    let experiment: HabitExperiment
    let onTap: (Int) -> Void

    var body: some View {
        let elapsed = experiment.elapsedDays()
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Deine 14 Tage")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: Space.s2) {
                ForEach(0..<HabitExperiment.length, id: \.self) { index in
                    let answer = experiment.answers[index]
                    let reachable = index < elapsed
                    let state: String = answer == true ? "mit" : (answer == false ? "ohne" : "offen")
                    let hint: String = reachable ? "Wechselt zwischen mit, ohne und offen" : ""
                    Button { onTap(index) } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .stroke(answer == false ? experimentTint : Theme.track, lineWidth: 2)
                                if answer == true {
                                    Circle().fill(experimentTint)
                                }
                            }
                            .frame(width: 22, height: 22)
                            Text(experiment.date(ofDay: index).formatted(.dateTime.day()))
                                .font(.formaMicro)
                                .monospacedDigit()
                                .foregroundStyle(reachable ? Theme.textSecondary : Theme.textQuaternary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!reachable)
                    .opacity(reachable ? 1 : 0.45)
                    .accessibilityLabel(Format.shortDate(experiment.date(ofDay: index)))
                    .accessibilityValue(state)
                    .accessibilityHint(hint)
                }
            }
            .padding(Space.s3)
            .background(Theme.card, in: .rect(cornerRadius: Radius.plate))
            HStack(spacing: Space.s4) {
                legend(filled: true, "mit")
                legend(filled: false, "ohne")
            }
            .font(.formaCaption)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)
        }
    }

    private func legend(filled: Bool, _ title: String) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(experimentTint, lineWidth: 2)
                if filled { Circle().fill(experimentTint) }
            }
            .frame(width: 10, height: 10)
            Text(title)
        }
    }
}

/// Mit/ohne je Kennzahl mit Stichprobengröße und einer ehrlichen Zeile.
struct ExperimentResults: View {
    let experiment: HabitExperiment
    let days: [DayMetrics]

    var body: some View {
        let answers = experiment.answersByDate()
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Ergebnis")
            DashboardCard {
                ForEach(Array(ExperimentComparison.Metric.allCases.enumerated()), id: \.element) { index, metric in
                    if index > 0 { RowDivider() }
                    row(metric, ExperimentComparison.compare(
                        answers: answers,
                        values: ExperimentComparison.values(for: metric, dates: Array(answers.keys), days: days)))
                }
            }
            Text("Beobachtet an deinen Tagen, kein Beweis.")
                .font(.formaCaption)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityIdentifier("health.experiment.honesty")
        }
    }

    private func row(_ metric: ExperimentComparison.Metric, _ result: ExperimentComparison.Result) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title).font(.formaRowTitle)
                Spacer()
                if let difference = result.difference {
                    Text(metric.formatDifference(difference))
                        .font(.formaNumber)
                        .monospacedDigit()
                        .formaNumberTransition(difference)
                }
            }
            if result.isConclusive, let with = result.withMean, let without = result.withoutMean {
                HStack(spacing: Space.s4) {
                    column("mit", metric.format(with), count: result.withCount)
                    column("ohne", metric.format(without), count: result.withoutCount)
                }
            } else {
                Text("Zu wenige Tage: \(result.withCount) mit, \(result.withoutCount) ohne – je Gruppe braucht es \(ExperimentComparison.minimumPerGroup).")
                    .font(.formaCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
    }

    private func column(_ title: String, _ value: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.formaValue).monospacedDigit()
            Text("\(title) · \(count) \(count == 1 ? "Tag" : "Tage")")
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
