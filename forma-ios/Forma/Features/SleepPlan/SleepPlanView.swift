import SwiftUI

struct SleepPlanView: View {
    @AppStorage private var savedPlan: Data
    let fallback: SleepPlanner
    @Environment(DataHub.self) private var hub
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing: WakeSelection? = nil
    @State private var pendingReminder: Task<Void, Never>?

    init(store: UserDefaults) {
        _savedPlan = AppStorage(wrappedValue: Data(), SleepPlanner.storageKey, store: store)
        fallback = SleepPlanner.fallback(in: store)
    }

    private var sleepNeed: TimeInterval? { hub.measuredSleepNeed }

    private var plan: SleepPlanner {
        get { SleepPlanner.restore(savedPlan, fallback: fallback) }
        nonmutating set {
            if let data = newValue.encoded() { savedPlan = data }
        }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let calendar = Calendar.forma
            let plan = self.plan
            let next = plan.nextWindow(after: context.date, sleepNeed: sleepNeed, calendar: calendar)
            let wake = next?.wake ?? plan.nextWake(after: context.date, calendar: calendar)
            let dates = SleepPlanner.week(containing: wake ?? context.date, calendar: calendar)

            InsightPage(title: "Schlafplan") {
                SleepPlanSummary(title: "Nächste Nacht", window: next, calendar: calendar, wake: wake)
                VStack(alignment: .leading, spacing: Space.s2) {
                    DashboardHeading(title: "Woche")
                    DashboardCard {
                        if !typeSize.isAccessibilitySize {
                            timelineAxis
                        }
                        ForEach(dates, id: \.self) { date in
                            if let day = SleepPlanner.Weekday(rawValue: calendar.component(.weekday, from: date)) {
                                let isNext = wake.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                                dayRow(WakeSelection(day: day, date: date), plan: plan, isNext: isNext, calendar: calendar)
                                if date != dates.last { RowDivider() }
                            }
                        }
                    }
                }
                workdayPicker(workdays: plan.workdays)
            }
            .accessibilityIdentifier("sleepplan.view")
        }
        .sheet(item: $editing) { selection in
            SleepPlanWakeEditor(selection: selection, savedPlan: $savedPlan, fallback: fallback, sleepNeed: sleepNeed)
        }
        .onChange(of: plan) { _, _ in
            guard !hub.isSample else { return }
            pendingReminder?.cancel()
            pendingReminder = Task {
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
                guard !hub.isSample else { return }
                await CoachNotifier.scheduleBedtimeReminder(hub)
            }
        }
    }

    private var timelineAxis: some View {
        Text("06:00")
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) { Text("18:00") }
            .overlay(alignment: .trailing) { Text("18:00") }
            .font(.formaCaption.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .accessibilityHidden(true)
    }

    private func dayRow(_ selection: WakeSelection, plan: SleepPlanner, isNext: Bool, calendar: Calendar) -> some View {
        let window = plan.window(wakingOn: selection.date, sleepNeed: sleepNeed, calendar: calendar)
        let wake = window?.wake ?? plan.wakeDate(wakingOn: selection.date, calendar: calendar)
        let group = plan.workdays.contains(selection.day) ? "Arbeitstag" : "Freier Tag"
        let status = isNext ? "Nächste Nacht, \(group)" : group
        return Button {
            editing = selection
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                if typeSize.isAccessibilitySize {
                    dayLabel(selection.day.title, isNext: isNext)
                    SleepPlanTimes(window: window, wake: wake)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        dayLabel(selection.day.title, isNext: isNext)
                        Spacer(minLength: Space.s1)
                        SleepPlanTimes(window: window, wake: wake)
                    }
                }
                SleepPlanBar(window: window, calendar: calendar)
            }
            .font(.formaValue)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isNext ? Theme.sleep.opacity(0.09) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selection.day.title)
        .accessibilityValue("\(status), \(SleepPlanTimes.spoken(window, wake: wake))")
        .accessibilityHint("Weckzeit bearbeiten")
    }

    private func dayLabel(_ title: String, isNext: Bool) -> some View {
        Text(title)
            .font(isNext ? .formaCaptionStrong : .formaCaption)
            .foregroundStyle(isNext ? Theme.sleep : Theme.textPrimary)
    }

    private func workdayPicker(workdays: Set<SleepPlanner.Weekday>) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            DashboardHeading(title: "Arbeitstage")
            DashboardCard {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        ForEach(SleepPlanner.Weekday.allCases) { day in
                            workdayButton(day, selected: workdays.contains(day), compact: true)
                        }
                    }
                    VStack(spacing: Space.s1) {
                        ForEach(SleepPlanner.Weekday.allCases) { day in
                            workdayButton(day, selected: workdays.contains(day), compact: false)
                        }
                    }
                }
                .padding(Space.s2)
            }
        }
    }

    private func workdayButton(_ day: SleepPlanner.Weekday, selected: Bool, compact: Bool) -> some View {
        Button {
            var updated = plan
            if updated.workdays.remove(day) == nil {
                updated.workdays.insert(day)
            }
            plan = updated
        } label: {
            HStack(spacing: Space.s2) {
                Text(compact ? day.shortTitle : day.title)
                if !compact, selected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .font(.formaCaptionStrong)
            .foregroundStyle(selected ? Theme.sleep : Theme.textSecondary)
            .fixedSize(horizontal: compact, vertical: false)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .background(selected ? Theme.sleep.opacity(0.14) : Color.clear, in: Capsule())
            .overlay {
                if selected {
                    Capsule().strokeBorder(Theme.sleep.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.title)
        .accessibilityValue(selected ? "Arbeitstag" : "Freier Tag")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct WakeSelection: Identifiable, Sendable {
    let day: SleepPlanner.Weekday
    let date: Date
    var id: Date { date }
}

private struct SleepPlanWakeEditor: View {
    let selection: WakeSelection
    @Binding var savedPlan: Data
    let fallback: SleepPlanner
    let sleepNeed: TimeInterval?
    @Environment(\.dismiss) private var dismiss

    // Das Rad bearbeitet eine Uhrzeit für die ganze Gruppe, auch wenn sie am konkreten Tag ausfällt.
    private static let pickerAnchor = Date(timeIntervalSinceReferenceDate: 0)
    private static let pickerCalendar: Calendar = {
        var calendar = Calendar.forma
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var plan: SleepPlanner { SleepPlanner.restore(savedPlan, fallback: fallback) }

    private var wakeTime: Binding<Date> {
        Binding {
            Self.pickerAnchor.addingTimeInterval(Double(plan.wakeMinutes(for: selection.day)) * 60)
        } set: { date in
            var updated = plan
            updated.setWakeMinutes(SleepPlanner.minuteOfDay(date, calendar: Self.pickerCalendar), for: selection.day)
            if let data = updated.encoded() { savedPlan = data }
        }
    }

    var body: some View {
        let calendar = Calendar.forma
        let window = plan.window(wakingOn: selection.date, sleepNeed: sleepNeed, calendar: calendar)
        let wake = window?.wake ?? plan.wakeDate(wakingOn: selection.date, calendar: calendar)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.gap) {
                    SleepPlanSummary(title: plan.workdays.contains(selection.day) ? "Arbeitstage" : "Freie Tage",
                                     window: window, calendar: calendar, wake: wake)
                    DatePicker("Weckzeit", selection: wakeTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .environment(\.locale, .german)
                        .environment(\.calendar, Self.pickerCalendar)
                        .environment(\.timeZone, Self.pickerCalendar.timeZone)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.s4)
            }
            .dashboardScreen()
            .navigationTitle(selection.day.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

struct SleepPlanSummary: View {
    let title: String
    let window: SleepPlanner.Window?
    let calendar: Calendar
    let wake: Date?

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                DashboardHeading(title: title)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Space.s4) {
                        bedtime.fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        wakeTime.fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: Space.s3) {
                        bedtime
                        wakeTime
                    }
                }
                SleepPlanBar(window: window, calendar: calendar, height: 6)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(SleepPlanTimes.spoken(window, wake: wake))
    }

    private var bedtime: some View { time("Bettzeit", icon: "moon.fill", date: window?.bed) }
    private var wakeTime: some View { time("Weckzeit", icon: "alarm", date: wake) }

    private func time(_ label: String, icon: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Label(label, systemImage: icon)
                .font(.formaCaption)
                .foregroundStyle(Theme.textSecondary)
            Text(date.map(SleepPlanTimes.clock) ?? "–")
                .font(.formaBigNumber)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

struct SleepPlanTimes: View {
    let window: SleepPlanner.Window?
    let wake: Date?

    var body: some View {
        if let window {
            Text("\(Self.clock(window.bed)) · \(Self.clock(window.wake))")
                .monospacedDigit()
        } else if let wake {
            Text(Self.clock(wake)).monospacedDigit()
        } else {
            Text("–")
        }
    }

    nonisolated static func spoken(_ window: SleepPlanner.Window?, wake: Date?) -> String {
        guard let window else {
            return wake.map { "Weckzeit \(clock($0)), keine Bettzeit berechnet" } ?? "Keine Bettzeit berechnet"
        }
        return "Bettzeit \(clock(window.bed)), Weckzeit \(clock(window.wake))"
    }

    nonisolated static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(.german))
    }
}

private struct SleepPlanBar: View {
    let window: SleepPlanner.Window?
    let calendar: Calendar
    var height: CGFloat = 4

    var body: some View {
        let segments = window?.timelineSegments(calendar: calendar) ?? []
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                ForEach(segments, id: \.self) { segment in
                    Capsule()
                        .fill(Theme.sleep)
                        .frame(width: geometry.size.width * CGFloat(segment.upperBound - segment.lowerBound))
                        .offset(x: geometry.size.width * CGFloat(segment.lowerBound))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
