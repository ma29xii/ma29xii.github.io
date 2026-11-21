import SwiftUI

struct MorningBriefing: Identifiable {
    static let shownDayKey = "forma.morningBriefing.shownDay"

    let day: Date
    var id: Date { day }

    static func dayKey(at date: Date, calendar: Calendar = .forma) -> String {
        GoogleHealthTime.day(date, calendar: calendar)
    }

    static func shouldOpen(at date: Date, shownDay: String, calendar: Calendar = .forma) -> Bool {
        (5..<11).contains(calendar.component(.hour, from: date)) && shownDay != dayKey(at: date, calendar: calendar)
    }
}

struct MorningBriefingTile: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            DashboardCard {
                HStack(spacing: Space.s3) {
                    Image(systemName: TodayTile.morningBriefing.systemImage)
                        .font(.title2)
                        .foregroundStyle(Theme.warning)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    DashboardHeading(title: TodayTile.morningBriefing.title)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(Space.card)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.formaCard)
        .accessibilityIdentifier("today.morningBriefing.open")
    }
}

struct MorningBriefingStory: View {
    let day: Date
    @Environment(DataHub.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page: Page = .recovery

    private enum Page: Int, CaseIterable {
        case recovery, sleep, target
    }

    var body: some View {
        let recent = hub.days
        let measured = recent.last { $0.date == day } ?? DayMetrics(date: day)
        let snapshot = DashboardDay(day: measured, history: recent)
        let tint: Color = switch page {
        case .recovery: snapshot.recovery.map(Theme.recovery) ?? Theme.accent
        case .sleep: Theme.sleep
        case .target: Theme.strain
        }

        VStack(spacing: Space.s4) {
            RecapStoryHeader(title: TodayTile.morningBriefing.title, identifier: "morningBriefing",
                             page: page.rawValue, count: Page.allCases.count, progress: 1, close: { dismiss() })
            if hub.isSample {
                SampleDataBadge().frame(maxWidth: .infinity, alignment: .leading)
            }
            if reduceMotion {
                storyPage(page, snapshot: snapshot)
            } else {
                TabView(selection: $page) {
                    ForEach(Page.allCases, id: \.self) { page in
                        storyPage(page, snapshot: snapshot)
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            controls
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.s4)
        .background { RecapStoryBackdrop(tint: tint) }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func storyPage(_ page: Page, snapshot: DashboardDay) -> some View {
        GeometryReader { proxy in
            ScrollView {
                pageContent(page, snapshot: snapshot)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s4)
                    .frame(minHeight: proxy.size.height)
            }
        }
    }

    @ViewBuilder private func pageContent(_ page: Page, snapshot: DashboardDay) -> some View {
        switch page {
        case .recovery:
            let recovery = snapshot.recovery
            panel("Recovery", icon: "heart.fill", tint: recovery.map(Theme.recovery) ?? Theme.accent,
                  value: recovery.map { "\($0) %" }, detail: recovery.map(Theme.recoveryWord))
        case .sleep:
            let seconds = snapshot.day.sleep?.asleep
            let duration: String? = seconds.flatMap { $0.isFinite && $0 > 0 ? Format.duration($0) : nil }
            panel("Letzte Nacht", icon: "moon.stars.fill", tint: Theme.sleep, value: duration,
                  detail: snapshot.sleepScore.map { "Sleep \($0) %" })
        case .target:
            let illness = IllnessSignal.evaluate(day: snapshot.day, history: snapshot.history)?.level
            if let advice = ReadinessAdvice.make(recovery: snapshot.recovery, illness: illness) {
                panel("Bereit für", icon: "figure.run", tint: Theme.strain, value: advice.kind.title,
                      detail: "Strain \(advice.rangeText)")
            } else {
                let goal = day == hub.today.date ? hub.stepGoalToday : nil
                panel("Tagesziel", icon: "figure.walk", tint: Theme.strain,
                      value: goal.map { Format.number(Double($0)) }, detail: goal == nil ? nil : "Schritte")
            }
        }
    }

    private func panel(_ title: String, icon: String, tint: Color, value: String?, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Label(title, systemImage: icon)
                .font(.formaHeadline)
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            Text(value ?? "Keine Messung")
                .font(value == nil ? .formaHeadline : .formaBigNumber)
                .foregroundStyle(Theme.textPrimary)
            if let detail {
                Text(detail).font(.formaBody).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Space.s2)) : AnyLayout(HStackLayout(spacing: Space.s3))
        let next = Page(rawValue: page.rawValue + 1)
        return layout {
            if let previous = Page(rawValue: page.rawValue - 1) {
                Button { go(to: previous) } label: {
                    Text("Zurück").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
            }
            Button {
                if let next { go(to: next) } else { dismiss() }
            } label: {
                Text(next == nil ? "Fertig" : "Weiter")
                    .font(.formaRowTitle)
                    .foregroundStyle(Theme.onSelection)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.selection, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func go(to target: Page) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { page = target }
    }
}
