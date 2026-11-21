import SwiftData
import SwiftUI

struct FoodRepeatSuggestions {
    let yesterday: [FoodEntry]
    let frequent: [FoodEntry]

    static func historyStart(for day: Date) -> Date { day.adding(days: -14) }

    init(entries: [FoodEntry], day: Date) {
        let start = Self.historyStart(for: day)
        let yesterdayStart = day.adding(days: -1)
        let history = entries.filter { $0.date >= start && $0.date < day }
        yesterday = history.filter { $0.date >= yesterdayStart }.sorted { $0.date < $1.date }
        frequent = FoodTracking.frequent(history, limit: 5, minimumCount: 1)
    }
}

struct FoodRepeatChips: View {
    let day: Date
    let log: (FoodEntry) -> Void
    @Query private var entries: [FoodEntry]
    @Environment(\.dynamicTypeSize) private var typeSize

    init(day: Date, log: @escaping (FoodEntry) -> Void) {
        self.day = day
        self.log = log
        let start = FoodRepeatSuggestions.historyStart(for: day)
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= start && $0.date < day })
    }

    var body: some View {
        let suggestions = FoodRepeatSuggestions(entries: entries, day: day)
        if !suggestions.yesterday.isEmpty || !suggestions.frequent.isEmpty {
            VStack(alignment: .leading, spacing: Space.s4) {
                group("Wie gestern", entries: suggestions.yesterday)
                group("Häufig", entries: suggestions.frequent)
            }
            .padding(.bottom, Space.s4)
        }
    }

    @ViewBuilder private func group(_ title: String, entries: [FoodEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                DashboardHeading(title: title)
                    .accessibilityAddTraits(.isHeader)
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Space.s2) { chips(entries) }
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: Space.s2) { chips(entries) }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func chips(_ entries: [FoodEntry]) -> some View {
        ForEach(entries, id: \.persistentModelID) { entry in
            let amount = "\(FoodText.number(entry.amount, digits: 1)) \(entry.unit)"
            let details = [entry.brand, amount].compactMap { $0 }.joined(separator: " · ")
            Button { log(entry) } label: {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(entry.name).font(.formaCaptionStrong).foregroundStyle(Theme.textPrimary)
                    Text(details).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 240, alignment: .leading)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .frame(minHeight: 44)
                .background(Theme.plate, in: RoundedRectangle(cornerRadius: Radius.plate))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.name)
            .accessibilityValue([entry.brand, amount, entry.meal.title].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint("Erneut eintragen")
        }
    }
}
