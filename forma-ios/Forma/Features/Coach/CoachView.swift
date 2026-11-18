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
    /// Ausdrückliche Zustimmung, bevor Gesundheitswerte an Anthropic gehen (Codex R-01-07, App-Review 5.1.2).
    @AppStorage("forma.claudeConsent") private var claudeConsent = false
    @State private var pendingConsentText: String?
    @State private var claudeTask: Task<Void, Never>?
    private var hasKey: Bool { !hub.isSample && !(Keychain.get("anthropic.key") ?? "").isEmpty }

    private var context: CoachEngine.Context {
        let planned = routines.min { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        return CoachEngine.Context(
            scores: hub.scores, today: hub.today,
            hrvDelta: hub.today.hrv.flatMap { v in hub.baseline(\.hrv).map { v - $0.mean } },
            rhrDelta: hub.today.restingHR.flatMap { v in hub.baseline(\.restingHR).map { v - $0.mean } },
            plannedRoutine: planned?.name,
            trainedToday: sessions.contains { Calendar.forma.isDateInToday($0.start) },
            isSample: hub.isSample, hour: Calendar.forma.component(.hour, from: .now),
            recoveryAvailable: hub.availability.recovery, strainAvailable: hub.availability.strain)
    }

    private let suggestions = ["Warum ist meine Erholung so?", "Was soll ich heute trainieren?", "Wann soll ich ins Bett?", "Wie viel Belastung ist heute gut?"]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        HStack(spacing: Space.s2) {
                            if hub.isSample { SampleDataBadge() }
                            Label(hasKey && claudeConsent ? "Claude (extern)" : "Lokaler Coach", systemImage: hasKey && claudeConsent ? "cloud" : "iphone")
                                .font(.formaMicro)
                                .tracking(Tracking.micro)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(Capsule().fill(Theme.cardRaised))
                                .accessibilityLabel(hasKey && claudeConsent ? "Antworten kommen von Claude über das Internet" : "Antworten werden auf dem iPhone berechnet")
                        }
                        .padding(.top, Space.s1)
                        Text("Heute")
                            .formaLabelStyle()
                            .padding(.top, Space.s4)
                        Text(CoachEngine.dailyLine(context))
                            .font(.system(.title3, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, Space.s2)
                        suggestionCard
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                        if thinking {
                            CoachThinkingLine().padding(.leading, Space.s2)
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
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .onAppear {
                if hub.isSample && messages.isEmpty {
                    let example = "Wann soll ich ins Bett?"
                    messages = [
                        ChatMessage(role: .user, text: example, localOnly: true),
                        ChatMessage(role: .coach, text: CoachEngine.localAnswer(to: example, context), localOnly: true)
                    ]
                }
                consumePrompt()
            }
            // Widerruf bricht eine laufende Anfrage sofort ab (Codex R-02-15).
            .onChange(of: claudeConsent) { _, allowed in
                if !allowed { claudeTask?.cancel(); claudeTask = nil; thinking = false }
            }
            .confirmationDialog("Frage an Claude senden?", isPresented: Binding(get: { pendingConsentText != nil }, set: { if !$0 { pendingConsentText = nil } }), titleVisibility: .visible) {
                Button("Senden und merken") {
                    claudeConsent = true
                    if let t = pendingConsentText { pendingConsentText = nil; send(t) }
                }
                Button("Nur lokal antworten") {
                    if let t = pendingConsentText {
                        pendingConsentText = nil
                        messages.append(ChatMessage(role: .user, text: t, localOnly: true))
                        messages.append(ChatMessage(role: .coach, text: CoachEngine.localAnswer(to: t, context), localOnly: true))
                    }
                }
                Button("Abbrechen", role: .cancel) { pendingConsentText = nil }
            } message: {
                Text("Dann gehen deine Frage, der bisherige Chat und eine Zusammenfassung deiner Tageswerte (Erholung, Schlaf, Belastung, HRV, Ruhepuls, geplantes Training) an Anthropic. Widerrufen kannst du das im Profil.")
            }
            .onChange(of: app.coachPrompt) { _, _ in consumePrompt() }
        }
    }

    // MARK: Vorschlag (nur mit Bestätigung)

    @ViewBuilder private var suggestionCard: some View {
        if !hub.isSample, let suggested = CoachEngine.suggestion(context), !dismissed {
            Plate {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Label("Vorschlag für heute", systemImage: "sparkles")
                        .formaLabelStyle()
                    Text(suggested.title).font(.system(.headline))
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
                            Button {
                                TrainingAdjustment.today = suggested
                                adjustment = suggested
                            } label: {
                                Text("Übernehmen").fontWeight(.semibold).foregroundStyle(Theme.onSelection)
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
                .background {
                    let shape = UnevenRoundedRectangle(
                        topLeadingRadius: Radius.plate, bottomLeadingRadius: m.role == .user ? Radius.plate : 6,
                        bottomTrailingRadius: m.role == .user ? 6 : Radius.plate, topTrailingRadius: Radius.plate, style: .continuous)
                    shape.fill(m.role == .user ? Theme.selection : Theme.card)
                        .overlay { if m.role == .coach { shape.strokeBorder(Theme.hairline, lineWidth: 0.75) } }
                }
                .textSelection(.enabled)
            if m.role == .coach { Spacer(minLength: 48) }
        }
    }

    private var composer: some View {
        VStack(spacing: Space.s2) {
            if messages.isEmpty {
                // Vollständig lesbare Einstiegsfragen statt abgeschnittener Chips (Codex R-01-33).
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element) { index, s in
                        if index > 0 { RowDivider() }
                        Button { send(s) } label: {
                            HStack(spacing: Space.s3) {
                                Text(s).font(.formaBody).frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textQuaternary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, Space.s4).frame(minHeight: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Radius.plate, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.plate, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75))
                .padding(.horizontal, Space.page)
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
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.onSelection).frame(width: 36, height: 36)
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
        messages.append(ChatMessage(role: .coach, text: prompt, localOnly: true))
        messages.append(ChatMessage(role: .coach, text: CoachEngine.localAnswer(to: app.coachTopic, context), localOnly: true))
    }

    private func send(_ raw: String) {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !text.isEmpty, !thinking else { return }
        if hasKey && !claudeConsent {
            input = ""
            pendingConsentText = text
            return
        }
        input = ""
        let ctx = context
        let external = claudeConsent && hasKey
        messages.append(ChatMessage(role: .user, text: text, localOnly: !external))
        if external, let key = Keychain.get("anthropic.key") {
            thinking = true
            let history = messages
            let summary = CoachEngine.contextSummary(ctx)
            claudeTask = Task {
                do {
                    let reply = try await ClaudeClient.reply(apiKey: key, context: summary, history: history)
                    guard !Task.isCancelled, claudeConsent else { thinking = false; return }
                    messages.append(ChatMessage(role: .coach, text: reply))
                } catch is CancellationError {
                    messages.append(ChatMessage(role: .coach, text: "Abgebrochen. Nichts weiter wurde gesendet.", localOnly: true))
                } catch {
                    messages.append(ChatMessage(role: .coach, text: CoachEngine.localAnswer(to: text, ctx) + "\n\n(Claude ist gerade nicht erreichbar, das war die lokale Antwort.)", localOnly: true))
                }
                thinking = false
            }
        } else {
            messages.append(ChatMessage(role: .coach, text: CoachEngine.localAnswer(to: text, ctx), localOnly: true))
        }
    }
}

private struct CoachThinkingLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("Denkt nach …")
            .font(.formaCaptionStrong)
            .foregroundStyle(Theme.textSecondary)
            .overlay {
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let position = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.2) / 3.2
                        GeometryReader { geometry in
                            LinearGradient(colors: [.clear, Color.white.opacity(0.68), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: geometry.size.width / 2)
                                .offset(x: geometry.size.width * (position * 1.5 - 0.5))
                        }
                        .mask { Text("Denkt nach …").font(.formaCaptionStrong) }
                    }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
    }
}
