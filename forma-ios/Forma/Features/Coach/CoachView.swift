import SwiftUI
import SwiftData

struct CoachView: View {
    @Environment(DataHub.self) private var hub
    @Environment(AppState.self) private var app
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var thinking = false
    @State private var adjustment: TrainingAdjustment? = TrainingAdjustment.today
    @State private var dismissed = TrainingAdjustment.dismissedToday
    @FocusState private var inputFocused: Bool

    private var context: CoachEngine.Context {
        let planned = routines.min { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        return CoachEngine.Context(
            scores: hub.scores, today: hub.today,
            hrvDelta: hub.today.hrv.flatMap { v in hub.baseline(\.hrv).map { v - $0.mean } },
            rhrDelta: hub.today.restingHR.flatMap { v in hub.baseline(\.restingHR).map { v - $0.mean } },
            plannedRoutine: planned?.name,
            trainedToday: sessions.contains { Calendar.forma.isDateInToday($0.start) },
            isSample: hub.isSample, hour: Calendar.forma.component(.hour, from: .now))
    }

    private let suggestions = ["Warum ist meine Erholung so?", "Was soll ich heute trainieren?", "Wann soll ich ins Bett?", "Wie viel Belastung ist heute gut?"]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        if hub.isSample { SampleDataBadge().padding(.top, Space.s1) }
                        Text(CoachEngine.dailyLine(context))
                            .font(.formaBodyLarge)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, Space.s3)
                        suggestionCard
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                        if thinking {
                            ProgressView().tint(Theme.textSecondary).padding(.leading, Space.s2)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.bottom, Space.s5)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .formaScreen()
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.showProfile = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Profil und Einstellungen")
                }
            }
            .onAppear(perform: consumePrompt)
            .onChange(of: app.coachPrompt) { _, _ in consumePrompt() }
        }
    }

    // MARK: Vorschlag (nur mit Bestätigung)

    @ViewBuilder private var suggestionCard: some View {
        if let suggested = CoachEngine.suggestion(context), !dismissed {
            Plate {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Label("Vorschlag für heute", systemImage: "sparkles")
                        .font(.formaCaptionStrong).foregroundStyle(Theme.textSecondary)
                    Text(suggested.title).font(.formaRowTitle)
                    Text(CoachEngine.suggestionReason(suggested, context)).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                    if adjustment == suggested {
                        Label("Übernommen für das nächste Training heute", systemImage: "checkmark")
                            .font(.formaCaptionStrong)
                        Button("Rückgängig") {
                            TrainingAdjustment.today = nil
                            adjustment = nil
                        }
                        .buttonStyle(.glass)
                    } else {
                        HStack(spacing: Space.s2) {
                            Button("Übernehmen") {
                                TrainingAdjustment.today = suggested
                                adjustment = suggested
                            }
                            .buttonStyle(.glassProminent)
                            Button("Nein, danke") {
                                TrainingAdjustment.dismissedToday = true
                                dismissed = true
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                .padding(Space.s4)
            }
        }
    }

    // MARK: Chat

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.role == .user { Spacer(minLength: 48) }
            Text(m.text)
                .font(.formaBody)
                .foregroundStyle(m.role == .user ? Theme.onSelection : Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20, bottomLeadingRadius: m.role == .user ? 20 : 6,
                        bottomTrailingRadius: m.role == .user ? 6 : 20, topTrailingRadius: 20, style: .continuous)
                    .fill(m.role == .user ? Theme.selection : Theme.plate)
                )
                .textSelection(.enabled)
            if m.role == .coach { Spacer(minLength: 48) }
        }
    }

    private var composer: some View {
        VStack(spacing: Space.s2) {
            if messages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { send(s) }.buttonStyle(.glass)
                        }
                    }
                    .padding(.horizontal, Space.page)
                }
            }
            HStack(spacing: Space.s2) {
                TextField("Frag deinen Coach", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
                    .submitLabel(.send)
                    .onSubmit { send(input) }
                Button { send(input) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking)
                .accessibilityLabel("Senden")
            }
            .padding(.horizontal, Space.page)
        }
        .padding(.vertical, Space.s2)
    }

    private func consumePrompt() {
        guard let prompt = app.coachPrompt else { return }
        app.coachPrompt = nil
        messages.append(ChatMessage(role: .coach, text: prompt))
        messages.append(ChatMessage(role: .coach, text: CoachEngine.localAnswer(to: "erholung", context)))
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        input = ""
        messages.append(ChatMessage(role: .user, text: text))
        let ctx = context
        if let key = Keychain.get("anthropic.key"), !key.isEmpty {
            thinking = true
            let history = messages
            let summary = CoachEngine.contextSummary(ctx)
            Task {
                do {
                    let reply = try await ClaudeClient.reply(apiKey: key, context: summary, history: history)
                    messages.append(ChatMessage(role: .coach, text: reply))
                } catch {
                    messages.append(ChatMessage(role: .coach, text: CoachEngine.localAnswer(to: text, ctx) + "\n\n(Claude war nicht erreichbar: \(error.localizedDescription))"))
                }
                thinking = false
            }
        } else {
            messages.append(ChatMessage(role: .coach, text: CoachEngine.localAnswer(to: text, ctx)))
        }
    }
}
