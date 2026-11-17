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

    /// Inhaltskarte aus Liquid Glass.
    func card(padding: CGFloat = 16, radius: CGFloat = 28) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: radius, style: .continuous))
    }

    /// Leuchtender Hintergrund hinter den Glaskarten.
    func ambientBackground(_ tint: HabitColor? = nil) -> some View {
        background { AmbientBackground(tint: tint) }
    }
}

/// Weicher, farbiger Schein hinter dem Glas – auf Schwarz im Dunkelmodus,
/// auf hellem Grau im Hellmodus. Statisch, damit nichts unruhig wirkt.
struct AmbientBackground: View {
    var tint: HabitColor?

    @AppStorage(SettingsKey.accent, store: AppGroup.defaults) private var accentID = Palette.defaultID
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let main = tint ?? Palette.entry(accentID)
        let companion = Palette.companion(of: main)
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Circle()
                    .fill(main.color)
                    .frame(width: w * 1.15, height: w * 1.15)
                    .position(x: w * 0.05, y: h * 0.04)
                Circle()
                    .fill(main.endColor)
                    .frame(width: w * 0.95, height: w * 0.95)
                    .position(x: w * 1.02, y: h * 0.4)
                Circle()
                    .fill(companion.color)
                    .frame(width: w * 1.05, height: w * 1.05)
                    .position(x: w * 0.15, y: h * 0.96)
            }
            .blur(radius: 90)
            .opacity(scheme == .dark ? 0.36 : 0.22)
        }
        .background(scheme == .dark ? Color.black : Color(hex: 0xF3F3F7))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Der Haken zum Abhaken – eine Glasperle, die sich beim Erledigen mit dem
/// Farbverlauf füllt. Zähler zeigen ihren Fortschritt als Ring.
struct CompleteButton: View {
    let habit: Habit
    let snapshot: HabitSnapshot
    let day: Day
    var size: CGFloat = 40

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.haptics) private var haptics = true

    var body: some View {
        let tint = Palette.entry(habit.colorID)
        let done = snapshot.isDone(day)
        let amount = snapshot.amount(day)
        let slipped = snapshot.isSlip(day)
        let showsNumber = amount > 0 && ((habit.isCounter && !done) || (habit.kind == .quit && habit.dailyTarget > 0))
        let partial = habit.isCounter && !done ? snapshot.fraction(day) : 0

        Button {
            withAnimation(.snappy(duration: 0.3)) {
                habit.advance(on: day, in: context)
            }
        } label: {
            ZStack {
                if done || slipped {
                    Circle().fill(tint.gradient)
                } else {
                    Circle().fill(tint.color.opacity(0.12))
                }
                if partial > 0 {
                    Circle()
                        .trim(from: 0, to: partial)
                        .stroke(tint.gradient, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(size * 0.06)
                }
                if showsNumber {
                    Text(Format.number(amount))
                        .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .foregroundStyle(done || slipped ? tint.onColor : tint.color)
                        .contentTransition(.numericText())
                } else {
                    Image(systemName: slipped ? "xmark" : "checkmark")
                        .font(.system(size: size * 0.38, weight: .bold))
                        .foregroundStyle(done || slipped ? tint.onColor : tint.color.opacity(0.75))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: size, height: size)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(day > snapshot.today)
        .sensoryFeedback(trigger: done) { _, isDone in
            guard haptics else { return nil }
            return isDone ? .success : .impact(weight: .light)
        }
        .accessibilityLabel(done ? "\(habit.name): erledigt" : "\(habit.name) abhaken")
        .accessibilityRemoveTraits(done ? [] : .isSelected)
        .accessibilityAddTraits(done ? .isSelected : [])
        .accessibilityIdentifier("complete-\(habit.name)")
    }
}

/// Eine Zeile mit wenigen, großen Kennzahlen – ruhiger als viele Einzelkacheln.
struct MetricsRow: View {
    struct Item: Identifiable {
        let value: String
        let label: String
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: 34)
                }
                VStack(spacing: 3) {
                    Text(item.value)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
    }
}

/// Die letzten sieben Tage als antippbare Punkte.
struct WeekStrip: View {
    let habit: Habit
    let snapshot: HabitSnapshot

    @Environment(\.modelContext) private var context

    var body: some View {
        let tint = Palette.entry(habit.colorID)
        HStack(spacing: 0) {
            ForEach((0..<7).reversed(), id: \.self) { offset in
                let day = snapshot.today.adding(-offset)
                let cell = snapshot.cell(day)
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        habit.advance(on: day, in: context)
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(day.weekdayShort)
                            .font(.caption2)
                            .foregroundStyle(offset == 0 ? .primary : .secondary)
                        ZStack {
                            if cell.level > 0 {
                                Circle()
                                    .fill(tint.gradient)
                                    .opacity(0.3 + 0.7 * cell.level)
                            } else {
                                Circle().fill(Color.primary.opacity(0.08))
                            }
                            if cell.skipped {
                                Circle().strokeBorder(tint.color.opacity(0.6), lineWidth: 1.5)
                            }
                            Text("\(day.dayOfMonth)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(cell.level > 0.6 ? tint.onColor : Color.primary.opacity(0.75))
                        }
                        .frame(width: 32, height: 32)
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
    let tint: HabitColor

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
                        .background {
                            if isOn {
                                Capsule().fill(tint.gradient)
                            } else {
                                Capsule().fill(Color(.tertiarySystemFill))
                            }
                        }
                        .foregroundStyle(isOn ? tint.onColor : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Day.weekdaySymbolsLong[index])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Die Farbauswahl: jedes Duo als Verlaufskreis.
struct ColorGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 7), spacing: 12) {
            ForEach(Palette.all) { item in
                let isSelected = Palette.entry(selection).id == item.id
                Button {
                    withAnimation(.snappy) { selection = item.id }
                } label: {
                    Circle()
                        .fill(item.gradient)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(item.onColor)
                            }
                        }
                        .padding(isSelected ? 0 : 3)
                        .overlay {
                            if isSelected {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 2)
                                    .padding(-4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
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
