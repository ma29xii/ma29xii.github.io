import SwiftData
import SwiftUI

extension Day: Identifiable {
    var id: Int { ordinal }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension View {
    /// Begrenzt Inhalte auf dem iPad auf eine angenehme Lesebreite.
    func readableWidth() -> some View {
        self
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }

    /// Ruhige Inhaltskarte. Liquid Glass bleibt den Bedienelementen vorbehalten.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// Der Haken zum Abhaken – zeigt je nach Gewohnheit Haken, Zählerstand oder Rückfall.
struct CompleteButton: View {
    let habit: Habit
    let snapshot: HabitSnapshot
    let day: Day
    var size: CGFloat = 40

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.haptics) private var haptics = true

    var body: some View {
        let color = Palette.color(habit.colorID)
        let done = snapshot.isDone(day)
        let amount = snapshot.amount(day)
        let slipped = snapshot.isSlip(day)
        let showsNumber = amount > 0 && ((habit.isCounter && !done) || (habit.kind == .quit && habit.dailyTarget > 0))
        let fill: Double = done ? 1 : (habit.isCounter ? 0.16 + 0.5 * snapshot.fraction(day) : 0.16)

        Button {
            withAnimation(.snappy(duration: 0.25)) {
                habit.advance(on: day, in: context)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(color.opacity(fill))
                if showsNumber {
                    Text(Format.number(amount))
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 3)
                        .foregroundStyle(done ? Color.white : color)
                        .contentTransition(.numericText())
                } else {
                    Image(systemName: slipped ? "xmark" : "checkmark")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(done ? Color.white : color.opacity(0.6))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: size, height: size)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(day > snapshot.today)
        .sensoryFeedback(trigger: done) { _, isDone in
            guard haptics else { return nil }
            return isDone ? .success : .impact(weight: .light)
        }
        .accessibilityLabel(done ? "\(habit.name): erledigt" : "\(habit.name) abhaken")
        .accessibilityIdentifier("complete-\(habit.name)")
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Die letzten sieben Tage als antippbare Punkte.
struct WeekStrip: View {
    let habit: Habit
    let snapshot: HabitSnapshot

    @Environment(\.modelContext) private var context

    var body: some View {
        let color = Palette.color(habit.colorID)
        HStack(spacing: 0) {
            ForEach((0..<7).reversed(), id: \.self) { offset in
                let day = snapshot.today.adding(-offset)
                let cell = snapshot.cell(day)
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        habit.advance(on: day, in: context)
                    }
                } label: {
                    VStack(spacing: 5) {
                        Text(day.weekdayShort)
                            .font(.caption2)
                            .foregroundStyle(offset == 0 ? .primary : .secondary)
                        ZStack {
                            Circle().fill(color.opacity(0.14 + 0.86 * cell.level))
                            if cell.skipped {
                                Circle().strokeBorder(color.opacity(0.6), lineWidth: 1.5)
                            }
                            Text("\(day.dayOfMonth)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(cell.level > 0.6 ? Color.white : Color.primary.opacity(0.75))
                        }
                        .frame(width: 30, height: 30)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Auswahl der Wochentage als runde Schalter.
struct WeekdayPicker: View {
    @Binding var mask: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                let isOn = mask & (1 << index) != 0
                Button {
                    mask ^= (1 << index)
                } label: {
                    Text(Day.weekdaySymbolsShort[index])
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(isOn ? color : Color(.tertiarySystemFill), in: .capsule)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Day.weekdaySymbolsLong[index])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

struct ColorGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8), spacing: 10) {
            ForEach(Palette.all) { item in
                Button {
                    selection = item.id
                } label: {
                    Circle()
                        .fill(item.color)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if selection == item.id {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(selection == item.id ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// Überschrift innerhalb einer Karte.
struct CardTitle: View {
    let title: String
    var subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
