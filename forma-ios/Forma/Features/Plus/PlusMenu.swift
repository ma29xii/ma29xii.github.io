import SwiftUI
import SwiftData

/// Einträge des Plus-Menüs.
enum PlusAction: String, CaseIterable, Identifiable, Sendable {
    /// Sichtbare Kacheln.
    case track, plan, training, water, fasting, weight
    /// Neu in F6: Erfassen (Stimmung, Koffein) und Jetzt (Atmen, Schlafplan, Coach).
    case mood, caffeine, breathe, sleepPlan, askCoach
    /// Nur intern (Siri, Steuerelement): Scanner direkt öffnen und Training sofort starten.
    case scan, quickTraining

    var id: String { rawValue }
    var accessibilityID: String { "plus." + rawValue }

    /// Gruppen im Menü, je im Raster mit drei Spalten.
    static let capture: [PlusAction] = [.track, .water, .weight, .mood, .caffeine]
    static let now: [PlusAction] = [.training, .fasting, .plan, .breathe, .sleepPlan, .askCoach]
    static let tiles: [PlusAction] = capture + now

    var title: String {
        switch self {
        case .track: "Nährwerte tracken"
        case .plan: "Essen planen"
        case .training: "Fitness"
        case .water: "Wasser"
        case .fasting: "Fasten"
        case .weight: "Gewicht"
        case .mood: "Stimmung"
        case .caffeine: "Koffein"
        case .breathe: "Atmen"
        case .sleepPlan: "Schlafplan"
        case .askCoach: "Coach fragen"
        case .scan: "Essen scannen"
        case .quickTraining: "Training starten"
        }
    }

    var systemImage: String {
        switch self {
        case .track: "fork.knife"
        case .plan: "calendar"
        case .training, .quickTraining: "dumbbell"
        case .water: "drop"
        case .fasting: "timer"
        case .weight: "scalemass"
        case .mood: "face.smiling"
        case .caffeine: "cup.and.saucer"
        case .breathe: "wind"
        case .sleepPlan: "bed.double"
        case .askCoach: "bubble.left"
        case .scan: "barcode.viewfinder"
        }
    }

    /// Kennfarbe der Kachel: etwas Farbe, ohne bunt zu werden.
    var tint: Color {
        switch self {
        case .track, .scan: Theme.younger
        case .plan: Theme.sleep
        case .training, .quickTraining: Theme.recoveryHigh
        case .water: Theme.strain
        case .fasting: Theme.warning
        case .weight: Theme.older
        case .mood: Theme.recoveryMid
        case .caffeine: Theme.warning
        case .breathe: Theme.strain
        case .sleepPlan: Theme.sleep
        case .askCoach: Theme.accent
        }
    }
}

enum PlusLogic {
    /// Welche Routine als Nächstes dran ist: nie benutzte zuerst, sonst die am längsten nicht benutzte.
    /// Bei Gleichstand die frühere in der Liste. Ohne Routinen `nil`.
    static func nextRoutineIndex(lastUsed: [Date?]) -> Int? {
        lastUsed.indices.min { (lastUsed[$0] ?? .distantPast) < (lastUsed[$1] ?? .distantPast) }
    }
}

// MARK: - Menü

/// Kleine Kacheln in einer Glasfläche, in zwei Gruppen: „Erfassen“ und „Jetzt“.
/// Sie wächst aus der Ecke des Plus-Knopfs nach oben; die Kacheln springen gestaffelt auf.
struct PlusMenuPanel: View {
    let onSelect: (PlusAction) -> Void
    @State private var visible = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            group("Erfassen", PlusAction.capture, first: 0)
            group("Jetzt", PlusAction.now, first: PlusAction.capture.count)
        }
        .padding(Space.s3)
        .frame(maxWidth: 330)
        .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
        .foregroundStyle(Theme.textPrimary)
        .onAppear { visible = true }
    }

    /// `first` ist die Position der ersten Kachel der Gruppe im ganzen Menü (für die Staffelung).
    private func group(_ title: String, _ actions: [PlusAction], first: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .formaLabelStyle()
                .padding(.horizontal, Space.s1)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: Space.s2) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    Button { onSelect(action) } label: { tile(action) }
                        .buttonStyle(FormaPressStyle(scale: 0.94))
                        .formaPop(index: first + index, visible: visible)
                        .accessibilityIdentifier(action.accessibilityID)
                }
            }
        }
    }

    private func tile(_ action: PlusAction) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: action.systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(action.tint)
                .frame(height: 26)
                .accessibilityHidden(true)
            Text(action.title)
                .font(.formaCaptionStrong)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .padding(.horizontal, Space.s1)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.plate))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.plateEdge, lineWidth: 0.75))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Eine Feder lässt das Menü aus der unteren rechten Ecke aufspringen
/// (dort sitzt der Plus-Knopf); bei „Bewegung reduzieren“ blendet es nur ein.
private struct PlusMenuOverlay: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onSelect: (PlusAction) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                if app.showPlus {
                    let tabBarClearance = proxy.safeAreaInsets.bottom + 76
                    Button {
                        app.showPlus = false
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                    .padding(.bottom, tabBarClearance)
                    PlusMenuPanel(onSelect: onSelect)
                        .padding(.trailing, Space.page)
                        // Knapp über der schwebenden Tab-Leiste (Sicherheitsrand unten plus Leiste).
                        .padding(.bottom, tabBarClearance)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.12, anchor: .bottomTrailing).combined(with: .opacity))
                        .accessibilityAction(.escape) { app.showPlus = false }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .animation(reduceMotion ? FormaMotion.calm : FormaMotion.pop, value: app.showPlus)
        .sensoryFeedback(.impact(weight: .light), trigger: app.showPlus)
        .allowsHitTesting(app.showPlus)
    }
}

// MARK: - Ablauf

/// Zeigt das Plus-Menü und öffnet das gewählte Ziel. Das Menü ist kein Sheet und kann deshalb sofort
/// einem Sheet Platz machen.
private struct PlusFlow: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var destination: PlusAction?
    /// Seit wann ein Scan-Auftrag auf das Ende des Trainings wartet; nach 15 Minuten ist er veraltet.
    @State private var scanHeldSince: Date?

    private var nextRoutine: Routine? {
        PlusLogic.nextRoutineIndex(lastUsed: routines.map(\.lastUsed)).map { routines[$0] }
    }

    func body(content: Content) -> some View {
        content
            .overlay { PlusMenuOverlay { choose($0) } }
            // Kurzbefehle und Steuerelemente: erst nach dem Start, nie über ein anderes offenes Fenster.
            .onChange(of: HealthIntentRouter.shared.pending) { _, _ in routeIntent() }
            .onChange(of: app.launchReady) { _, _ in routeIntent() }
            .onChange(of: app.showProfile) { _, _ in routeIntent() }
            .onChange(of: app.finishedSession?.id) { _, _ in routeIntent() }
            .onChange(of: app.isWorkoutSummaryActive) { _, _ in routeIntent() }
            .onChange(of: app.liveWorkout?.draftID) { _, _ in routeIntent() }
            .onChange(of: destination) { _, new in
                if new == .training { app.trainingHomeOpen = true }
                routeIntent()
            }
            // Erst nach dem Schließen darf die Wurzel ein laufendes Training wieder zeigen.
            .sheet(item: $destination, onDismiss: { app.trainingHomeOpen = false }) { action in
                switch action {
                case .track: PlusFood.track()
                case .scan: PlusFood.scan()
                case .plan: PlusFood.plan()
                case .training: PlusFood.training()
                case .water: PlusFood.water()
                case .fasting: PlusFood.fasting()
                case .weight: PlusFood.weight()
                case .mood: PlusMoodSheet()
                case .caffeine: PlusCaffeineSheet()
                case .breathe: BreathingSession()
                case .sleepPlan: PlusSleepPlanSheet()
                case .askCoach: EmptyView()
                case .quickTraining: EmptyView()
                }
            }
    }

    private func choose(_ action: PlusAction) {
        app.showPlus = false
        switch action {
        case .quickTraining: startTraining()
        case .askCoach: app.selectTab(.coach)
        default: destination = action
        }
    }

    /// Übernimmt eine wartende Anfrage von Siri, Kurzbefehl oder Steuerelement.
    private func routeIntent() {
        // Erst ansehen, dann verbrauchen: Was jetzt nicht gezeigt werden kann, bleibt in der Warteschlange
        // und läuft weiter, sobald das Hindernis weg ist (Profil zu, Training beendet, Sheet geschlossen).
        guard app.launchReady, !app.showProfile, !trainingEndBlocksWindows, destination == nil,
              let request = HealthIntentRouter.shared.pending else { return }
        // Ein laufendes Training liegt als Vollbild darüber; der Scanner wartet, bis es beendet ist.
        if request == .scanFood, app.liveWorkout != nil {
            if scanHeldSince == nil { scanHeldSince = .now }
            return
        }
        let held = scanHeldSince
        scanHeldSince = nil
        guard HealthIntentRouter.shared.consume() != nil else { return }
        if request == .scanFood, let held, Date.now.timeIntervalSince(held) > 15 * 60 { return }
        app.showPlus = false
        switch request {
        case .startTraining: startTraining(freeIfNoRoutine: true)
        case .scanFood: destination = .scan
        }
    }

    /// Zwischen „Training beenden“ und geschlossener Zusammenfassung (inklusive der 450 ms davor)
    /// darf kein weiteres Fenster aufgehen.
    private var trainingEndBlocksWindows: Bool {
        app.isWorkoutSummaryActive
    }

    private func startTraining(freeIfNoRoutine: Bool = false) {
        // Läuft schon ein Training, liegt es als Vollbild da. Nichts doppelt starten.
        guard app.liveWorkout == nil else { return }
        guard let routine = nextRoutine else {
            if freeIfNoRoutine { app.liveWorkout = LiveWorkout.empty() }
            return
        }
        routine.lastUsed = .now
        try? context.save()
        app.liveWorkout = LiveWorkout.from(routine, history: sessions, adjustment: app.workoutAdjustment)
    }
}

extension View {
    /// Hängt das Plus-Menü samt Zielen an die Wurzel der App.
    func plusFlow() -> some View { modifier(PlusFlow()) }
}
