import SwiftUI

/// Trainingskalender: Serie in Wochen, Monat mit einem Punkt je Trainingstag. Tippen auf einen Trainingstag filtert die Liste.
struct TrainingCalendarCard: View {
    let dates: [Date]
    @Binding var selectedDay: Date?
    @State private var month = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let calendar = Calendar.forma
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let trained = TrainingCalendar.days(dates, calendar: calendar)
        let streak = TrainingCalendar.weekStreak(dates, calendar: calendar)
        let inMonth = trained.filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }.count
        let isCurrentMonth = calendar.isDate(month, equalTo: .now, toGranularity: .month)

        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .firstTextBaseline) {
                stat("\(streak)", streak == 1 ? "Woche in Folge" : "Wochen in Folge")
                Spacer()
                stat("\(inMonth)", inMonth == 1 ? "Trainingstag" : "Trainingstage", trailing: true)
            }

            HStack {
                Text(month.formatted(Date.FormatStyle(locale: .german).month(.wide).year()))
                    .font(.formaRowTitle)
                    .contentTransition(.opacity)
                Spacer()
                monthButton("chevron.left", label: "Vorheriger Monat", by: -1)
                monthButton("chevron.right", label: "Nächster Monat", by: 1).disabled(isCurrentMonth)
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.formaMicro).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(Array(TrainingCalendar.grid(for: month, calendar: calendar).enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day, trained: trained.contains(day)) } else { Color.clear.frame(height: 44) }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: month)
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func stat(_ value: String, _ label: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(value).font(.formaDisplay).contentTransition(.numericText())
            Text(label).font(.formaCaption).foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func monthButton(_ symbol: String, label: String, by offset: Int) -> some View {
        Button {
            withAnimation(.smooth) {
                month = calendar.date(byAdding: .month, value: offset, to: month) ?? month
                selectedDay = nil
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityLabel(label)
    }

    @ViewBuilder private func dayCell(_ day: Date, trained: Bool) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isFuture = day > .now
        let cell = VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(.footnote, design: .rounded, weight: isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isFuture ? Theme.textQuaternary : (trained || isToday ? Theme.textPrimary : Theme.textTertiary))
            Circle()
                .fill(trained ? Theme.strain : Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Circle().fill(isSelected ? Theme.cardRaised : Color.clear).frame(width: 40, height: 40))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(Date.FormatStyle(locale: .german).day().month(.wide)) + (trained ? ", Training" : ""))

        if trained {
            Button {
                withAnimation(.smooth(duration: 0.25)) { selectedDay = isSelected ? nil : day }
            } label: { cell }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .sensoryFeedback(.selection, trigger: isSelected)
        } else {
            cell
        }
    }
}
