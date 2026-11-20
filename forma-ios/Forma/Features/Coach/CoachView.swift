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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ausdrückliche Zustimmung, bevor Gesundheitswerte an Anthropic gehen (Codex R-01-07, App-Review 5.1.2).
    @AppStorage(CoachProviders.consentKey) private var externalConsent = false
    /// Eigene Zustimmung für Fotos: Wer nur Text freigegeben hat, wird vor dem ersten Foto noch einmal gefragt.
    @AppStorage(CoachProviders.photoConsentKey) private var photoConsent = false
    @State private var photosLoading = false
    @State private var pendingConsentText: String?
    @State private var showMealPlan = false
    @State private var claudeTask: Task<Void, Never>?
    /// Fotos für die nächste Nachricht und die Fotos der bisherigen Nachrichten (nur Vorschau, nur im Speicher).
    @State private var attachments: [CoachPhoto] = []
    @State private var messagePhotos: [UUID: [CoachPhoto]] = [:]
    /// Schlüssel einmal beim Öffnen prüfen (Schlüsselbund-Zugriff nicht bei jedem Neuzeichnen).
    @State private var keyConfigured = false
    private var hasKey: Bool { !hub.isSample && keyConfigured }
    private var online: Bool { hasKey && externalConsent }

    private var context: CoachEngine.Context {
        let planned = routines.min { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        return CoachEngine.Context(
            scores: hub.scores, today: hub.today,
            hrvDelta: hub.today.hrv.flatMap { v in hub.baseline(\.hrv).map { v - $0.mean } },
            rhrDelta: hub.today.restingHR.flatMap { v in hub.baseline(\.restingHR).map { v - $0.mean } },
            plannedRoutine: planned?.name,
            trainedToday: sessions.contains { Calendar.forma.isDateInToday($0.start) },
            isSample: hub.isSample, hour: Calendar.forma.component(.hour, from: .now),
            recoveryAvailable: hub.availability.recovery, strainAvailable: hub.availability.strain,
            history: hub.history)
    }

    /// Jede Frage hat eine lokale Antwort in `CoachEngine.localAnswer`; „Wann soll ich …“ bleibt für den UI-Rundgang.
    private let suggestions = ["Wie war mein Schlaf?", "Soll ich heute trainieren?", "Wann soll ich ins Bett?", "Wie viel Belastung ist heute gut?"]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        HStack(spacing: Space.s2) {
                            if hub.isSample { SampleDataBadge() }
                            if online {
                                Menu {
                                    Button("Datenfreigabe widerrufen", systemImage: "hand.raised", role: .destructive) { CoachProviders.revokeChatConsent() }
                                } label: {
                                    sourceChip("Online-Coach", systemImage: "cloud")
                                }
                                .accessibilityLabel("Antworten kommen vom Online-Coach über das Internet. Tippen, um die Freigabe zu widerrufen.")
                            } else {
                                sourceChip("Lokaler Coach", systemImage: "iphone")
                                    .accessibilityLabel("Antworten werden auf dem iPhone berechnet")
                            }
                        }
                        .padding(.top, Space.s1)
                        dayCard
                        suggestionChips
                        suggestionCard
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                        if thinking { ThinkingBubble() }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.bottom, Space.s5)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await hub.syncAndNotify(background: false) }
                .onChange(of: messages.count) { _, _ in
                    withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("end", anchor: .bottom) }
                }
                .onChange(of: thinking) { _, _ in
                    withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .sheet(isPresented: $showMealPlan) { FoodPlanView(planTomorrow: true) }
            .formaScreen()
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .onAppear {
                keyConfigured = CoachProviders.hasConfiguredKey
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
            .onChange(of: externalConsent) { _, allowed in
                if !allowed { photoConsent = false; endOnlineSession() }
            }
            // Trennen von Google oder Wechsel zu Beispieldaten beendet die laufende Online-Anfrage
            // und sperrt den bisherigen Verlauf für weitere Anfragen (K-03-13).
            .onChange(of: hub.isSample) { _, _ in endOnlineSession() }
            .onChange(of: hub.google) { _, new in
                if case .connected = new { return }
                endOnlineSession()
            }
            .confirmationDialog("Frage an den Online-Coach senden?", isPresented: Binding(get: { pendingConsentText != nil }, set: { if !$0 { pendingConsentText = nil } }), titleVisibility: .visible) {
                Button("Senden und merken") {
                    externalConsent = true
                    if !attachments.isEmpty { photoConsent = true }
                    if let t = pendingConsentText { pendingConsentText = nil; send(t) }
                }
                Button("Nur lokal antworten") {
                    if let t = pendingConsentText {
                        pendingConsentText = nil
                        answerLocally(t)
                    }
                }
                Button("Abbrechen", role: .cancel) { pendingConsentText = nil }
            } message: {
                Text(consentMessage(for: pendingConsentText ?? ""))
            }
            .onChange(of: app.coachPrompt) { _, _ in consumePrompt() }
        }
    }

    // MARK: Tageskarte

    private var dayCard: some View {
        let c = context
        return Plate {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s2) {
                    dayValue("Recovery", c.recoveryAvailable ? "\(c.scores.recovery)" : nil,
                             tint: c.recoveryAvailable ? Theme.recovery(c.scores.recovery) : Theme.textSecondary,
                             spoken: c.recoveryAvailable ? "\(c.scores.recovery) Prozent" : nil)
                    dayValue("Strain-Ziel", c.recoveryAvailable ? "\(c.scores.target.lowerBound)–\(c.scores.target.upperBound)" : nil,
                             tint: Theme.strain,
                             spoken: c.recoveryAvailable ? "\(c.scores.target.lowerBound) bis \(c.scores.target.upperBound)" : nil)
                    dayValue("Schlafbedarf", c.sleepNeed.map(Format.duration), tint: Theme.sleep,
                             spoken: c.sleepNeed.map(Format.duration))
                }
                Text(CoachEngine.dailyLine(c))
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s4)
        }
        .padding(.top, Space.s1)
    }

    private func dayValue(_ title: String, _ value: String?, tint: Color, spoken: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.formaMicro).tracking(Tracking.micro).textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value ?? "–")
                .font(.formaNumber)
                .foregroundStyle(value == nil ? Theme.textTertiary : tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(spoken ?? "keine Messung")")
    }

    // MARK: Vorschlags-Chips

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(suggestions, id: \.self) { s in
                    Button { send(s) } label: {
                        Text(s)
                            .font(.formaCaptionStrong)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, Space.s4)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(Theme.card))
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.75))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(thinking)
                }
                Button { showMealPlan = true } label: {
                    Text("Essensplan für morgen")
                        .font(.formaCaptionStrong)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Space.s4)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.card))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.75))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.mealplan")
            }
            .padding(.horizontal, Space.page)
        }
        // Bis zum Rand scrollen, obwohl der Inhalt links eingerückt ist.
        .padding(.horizontal, -Space.page)
    }

    private func sourceChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.formaMicro)
            .tracking(Tracking.micro)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10).frame(height: 26)
            .background(Capsule().fill(Theme.cardRaised))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
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
        let isUser = m.role == .user
        return HStack(alignment: .bottom, spacing: Space.s2) {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if let photos = messagePhotos[m.id], !photos.isEmpty { CoachBubblePhotos(photos: photos) }
                Text(Self.markdown(m.text))
                    .font(.formaBody.monospacedDigit())
                    .foregroundStyle(isUser ? Theme.onSelection : Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background {
                        let shape = UnevenRoundedRectangle(
                            topLeadingRadius: Radius.plate, bottomLeadingRadius: isUser ? Radius.plate : 6,
                            bottomTrailingRadius: isUser ? 6 : Radius.plate, topTrailingRadius: Radius.plate, style: .continuous)
                        shape.fill(isUser ? Theme.selection : Theme.card)
                            .overlay { if !isUser { shape.strokeBorder(Theme.hairline, lineWidth: 0.75) } }
                    }
                    .textSelection(.enabled)
                    .accessibilityLabel((isUser ? "Du: " : "Coach: ") + m.text.replacingOccurrences(of: "**", with: ""))
            }
            if !isUser { Spacer(minLength: 48) }
        }
    }

    /// Fettdruck aus Markdown (`**Wort**`), Zeilenumbrüche bleiben erhalten.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private var canSend: Bool {
        !(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty) && !thinking && !photosLoading
    }

    private var composer: some View {
        VStack(spacing: Space.s2) {
            CoachPhotoStrip(photos: $attachments)
            HStack(alignment: .bottom, spacing: Space.s1) {
                CoachPhotoButton(photos: $attachments, isLoading: $photosLoading)
                    .frame(minWidth: 44, minHeight: 44)
                TextField("Frag deinen Coach", text: $input, axis: .vertical)
                    .font(.formaBody)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("coach.input")
                Button { send(input) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.onSelection)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.selection))
                        .opacity(canSend ? 1 : 0.35)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Senden")
            }
            .padding(.horizontal, Space.s1)
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
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

    /// Nur lokal antworten: Frage und Antwort bleiben auf dem iPhone. Fotos kann der lokale Coach nicht ansehen.
    /// Bricht eine laufende Online-Anfrage ab. Alle bisherigen Nachrichten bleiben auf dem iPhone
    /// und gehen in keiner späteren Anfrage mehr mit.
    private func endOnlineSession() {
        claudeTask?.cancel()
        claudeTask = nil
        thinking = false
        for index in messages.indices { messages[index].localOnly = true }
    }

    /// Wie viele frühere Online-Nachrichten der nächste Versand mitnimmt (Obergrenze steht in `CoachProviders`).
    private var historyCountForNextRequest: Int {
        let current = CoachProviders.conversationID
        return min(11, messages.filter {
            $0.conversationID == current && !$0.localOnly && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count)
    }

    private func answerLocally(_ text: String) {
        let photos = attachments
        let question = ChatMessage(role: .user, text: text, localOnly: true)
        messages.append(question)
        var answer = CoachEngine.localAnswer(to: text, context)
        if !photos.isEmpty {
            messagePhotos[question.id] = photos.map(\.forChat)
            attachments = []
            answer = "Fotos sehe ich nur im Online-Coach. Hier kann ich nur zu deinen Werten antworten.\n\n" + answer
        }
        messages.append(ChatMessage(role: .coach, text: answer, localOnly: true))
    }

    /// Dialogtext: wer bekommt was, wann OpenAI übernimmt (Gegenprüfung 01, Punkt 4).
    private func consentMessage(for question: String) -> String {
        let fields = CoachEngine.transmittedFields(for: question, context)
        let values = fields.isEmpty
            ? "Für diese Frage gehen keine Tageswerte mit."
            : "Dazu diese Tageswerte: \(fields.joined(separator: ", "))."
        let photos = attachments.isEmpty
            ? ""
            : " Außerdem \(attachments.count == 1 ? "dein Foto" : "deine \(attachments.count) Fotos")."
        let earlier = historyCountForNextRequest
        let history = earlier == 0
            ? "Es gibt noch keinen früheren Online-Chat."
            : "Mitgeschickt \(earlier == 1 ? "wird deine letzte Nachricht" : "werden die letzten \(earlier) Nachrichten") aus dem Online-Chat, auch mit darin genannten Werten."
        return """
        Gesendet wird deine Frage. \(history) \(values)\(photos)

        Empfänger ist Anthropic. Antwortet Anthropic nicht rechtzeitig oder unbrauchbar, bekommt OpenAI dieselben Daten und antwortet stattdessen. Ist nur ein OpenAI-Schlüssel hinterlegt, geht alles direkt an OpenAI. Frühere Fotos bleiben in deinem Chat.

        Widerrufen kannst du das oben im Coach über „Online-Coach“.
        """
    }

    private func send(_ raw: String) {
        let typed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        let photos = attachments
        guard !typed.isEmpty || !photos.isEmpty, !thinking, !photosLoading else { return }
        let text = typed.isEmpty ? "Schau dir das bitte an." : typed
        if hasKey && (!externalConsent || (!photos.isEmpty && !photoConsent)) {
            input = ""
            pendingConsentText = text
            return
        }
        input = ""
        let ctx = context
        let external = online
        let question = ChatMessage(role: .user, text: text, localOnly: !external)
        messages.append(question)
        if !photos.isEmpty {
            messagePhotos[question.id] = photos.map(\.forChat)
            attachments = []
        }
        if external {
            thinking = true
            let history = messages
            // Nur die Tageswerte, die zur Frage gehören – genau die, die der Dialog genannt hat.
            let summary = CoachEngine.contextSummary(ctx, for: text)
            claudeTask = Task {
                do {
                    let reply = try await CoachProviders.reply(context: summary, history: history, images: photos.map(\.jpeg))
                    guard !Task.isCancelled, externalConsent else {
                        messages.markLocalOnly(question.id)
                        thinking = false
                        return
                    }
                    messages.append(ChatMessage(role: .coach, text: reply))
                } catch is CancellationError {
                    // Abgebrochene Frage nie später im Verlauf mitsenden (Gegenprüfung 01, Punkt 5).
                    messages.markLocalOnly(question.id)
                    messages.append(ChatMessage(role: .coach, text: "Abgebrochen. Nichts weiter wurde gesendet.", localOnly: true))
                } catch CoachProviders.ReplyError.invalidImage {
                    messages.markLocalOnly(question.id)
                    messages.append(ChatMessage(role: .coach, text: "Dieses Foto konnte ich nicht lesen. Probier ein anderes. Es wurde nichts gesendet.", localOnly: true))
                } catch {
                    messages.markLocalOnly(question.id)
                    messages.append(ChatMessage(role: .coach, text: CoachEngine.localAnswer(to: text, ctx) + "\n\n(Der Online-Coach ist gerade nicht erreichbar, das war die lokale Antwort.)", localOnly: true))
                }
                thinking = false
            }
        } else {
            var answer = CoachEngine.localAnswer(to: text, ctx)
            if !photos.isEmpty { answer = "Fotos sehe ich nur im Online-Coach. Hier kann ich nur zu deinen Werten antworten.\n\n" + answer }
            messages.append(ChatMessage(role: .coach, text: answer, localOnly: true))
        }
    }
}

/// „Denkt nach“: drei pulsierende Punkte in einer Coach-Blase. Mit „Bewegung reduzieren“ stehen sie still.
private struct ThinkingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Radius.plate, bottomLeadingRadius: 6,
            bottomTrailingRadius: Radius.plate, topTrailingRadius: Radius.plate, style: .continuous)
        HStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        let wave = reduceMotion ? 0.5 : max(0, sin(t * 4 - Double(i) * 0.8))
                        Circle().fill(Theme.textSecondary)
                            .frame(width: 7, height: 7)
                            .opacity(0.3 + 0.7 * wave)
                            .offset(y: reduceMotion ? 0 : -2 * wave)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(shape.fill(Theme.card))
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.75))
            Spacer(minLength: 48)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach denkt nach")
    }
}

extension Array where Element == ChatMessage {
    /// Markiert eine Nachricht als nur lokal, damit sie in keiner späteren Online-Anfrage auftaucht.
    mutating func markLocalOnly(_ id: ChatMessage.ID) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].localOnly = true
    }
}
