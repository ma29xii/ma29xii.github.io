import SwiftUI
import SwiftData

/// Einträge des Plus-Menüs.
enum PlusAction: String, CaseIterable, Identifiable, Sendable {
    case scan, photo, search, food, plan, water, fasting, weight, training

    var id: String { rawValue }
    var accessibilityID: String { "plus." + rawValue }

    var title: String {
        switch self {
        case .scan: "Mahlzeit scannen"
        case .photo: "Essen fotografieren"
        case .search: "Essen suchen"
        case .food: "Ernährung heute"
        case .plan: "Essen planen"
        case .water: "Wasser"
        case .fasting: "Fasten"
        case .weight: "Gewicht"
        case .training: "Training starten"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: "barcode.viewfinder"
        case .photo: "camera.viewfinder"
        case .search: "magnifyingglass"
        case .food: "fork.knife"
        case .plan: "calendar"
        case .water: "drop"
        case .fasting: "timer"
        case .weight: "scalemass"
        case .training: "dumbbell"
        }
    }
}

struct PlusGroup: Identifiable, Sendable {
    let title: String
    let actions: [PlusAction]
    var id: String { title }
}

extension PlusAction {
    /// Gruppen im Menü: Essen, Heute erfassen, Training.
    static let groups = [
        PlusGroup(title: "Essen", actions: [.scan, .photo, .search, .food, .plan]),
        PlusGroup(title: "Heute erfassen", actions: [.water, .fasting, .weight]),
        // Ohne Überschrift: „Training“ über „Training starten“ wäre doppelt.
        PlusGroup(title: "", actions: [.training])
    ]
}

enum PlusLogic {
    /// Welche Routine als Nächstes dran ist: nie benutzte zuerst, sonst die am längsten nicht benutzte.
    /// Bei Gleichstand die frühere in der Liste. Ohne Routinen `nil`.
    static func nextRoutineIndex(lastUsed: [Date?]) -> Int? {
        lastUsed.indices.min { (lastUsed[$0] ?? .distantPast) < (lastUsed[$1] ?? .distantPast) }
    }
}

/// Das Menü hinter dem Plus-Knopf in der Tab-Leiste.
struct PlusMenuSheet: View {
    var trainingSubtitle: String? = nil
    let onSelect: (PlusAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(PlusAction.groups) { group in
                    if !group.title.isEmpty {
                        Text(group.title).formaLabelStyle()
                            .padding(.top, group.id == PlusAction.groups.first?.id ? 0 : Space.s3)
                    } else {
                        Color.clear.frame(height: Space.s1)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(group.actions.enumerated()), id: \.element.id) { index, action in
                            if index > 0 { RowDivider(inset: Space.s4 + 36 + Space.s3) }
                            Button { onSelect(action) } label: { row(action) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(action.accessibilityID)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Radius.plate, style: .continuous).fill(Theme.plate))
                    .overlay(RoundedRectangle(cornerRadius: Radius.plate, style: .continuous).strokeBorder(Theme.plateEdge, lineWidth: 0.75))
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s4)
        }
        .foregroundStyle(Theme.textPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ action: PlusAction) -> some View {
        HStack(spacing: Space.s3) {
            Glyph(systemName: action.systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(.formaRowTitle)
                // Nur das Training braucht eine Zeile dazu: welche Routine startet.
                if action == .training, let trainingSubtitle {
                    Text(trainingSubtitle).font(.formaCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textQuaternary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// Zeigt das Plus-Menü und danach das gewählte Ziel. Das Ziel erscheint erst, wenn das Menü
/// ganz weg ist (`onDismiss`), weil SwiftUI zwei Sheets nicht gleichzeitig sauber wechselt.
private struct PlusFlow: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var chosen: PlusAction?
    @State private var destination: PlusAction?
    /// Training kam von einem Kurzbefehl: ohne Routine ein freies Training starten.
    @State private var freeTrainingIfNone = false
    /// Seit wann ein Scan-Auftrag auf das Ende des Trainings wartet; nach 15 Minuten ist er veraltet.
    @State private var scanHeldSince: Date?

    private var nextRoutine: Routine? {
        PlusLogic.nextRoutineIndex(lastUsed: routines.map(\.lastUsed)).map { routines[$0] }
    }

    func body(content: Content) -> some View {
        @Bindable var app = app
        content
            .sheet(isPresented: $app.showPlus, onDismiss: menuClosed) {
                PlusMenuSheet(trainingSubtitle: nextRoutine?.name) { action in
                    chosen = action
                    app.showPlus = false
                }
            }
            // Kurzbefehle und Steuerelemente: erst nach dem Start, nie über ein anderes offenes Fenster.
            .onChange(of: HealthIntentRouter.shared.pending) { _, _ in routeIntent() }
            .onChange(of: app.launchReady) { _, _ in routeIntent() }
            .onChange(of: app.showProfile) { _, _ in routeIntent() }
            .onChange(of: app.finishedSession?.id) { _, _ in routeIntent() }
            .onChange(of: app.liveWorkout?.draftID) { _, _ in routeIntent() }
            .onChange(of: destination) { _, _ in routeIntent() }
            .sheet(item: $destination) { action in
                switch action {
                case .scan: PlusFood.scan()
                case .photo: PlusFood.photo()
                case .search: PlusFood.search()
                case .food: PlusFood.log()
                case .plan: PlusFood.plan()
                case .water: PlusFood.water()
                case .fasting: PlusFood.fasting()
                case .weight: PlusFood.weight()
                case .training: EmptyView()
                }
            }
    }

    private func menuClosed() {
        guard let action = chosen else { return }
        chosen = nil
        if action == .training { menuClosedStart() } else { destination = action }
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
        switch request {
        case .startTraining:
            freeTrainingIfNone = true
            if app.showPlus {
                // Menü ist offen: über dieselbe Kette schließen, dann starten.
                chosen = .training
                app.showPlus = false
            } else {
                menuClosedStart()
            }
        case .scanFood:
            if app.showPlus {
                chosen = .scan
                app.showPlus = false
            } else {
                destination = .scan
            }
        }
    }

    /// Zwischen Trainingsende und geschlossener Zusammenfassung darf kein weiteres Fenster aufgehen.
    /// Heute nur die Zusammenfassung selbst; die Lücke von 450 ms davor schließt der Zustand von training-muskeln,
    /// sobald er da ist. Hier ist die einzige Stelle, an der er ergänzt wird (plus `onChange` oben).
    private var trainingEndBlocksWindows: Bool {
        app.finishedSession != nil
    }

    private func menuClosedStart() {
        startTraining()
        freeTrainingIfNone = false
    }

    private func startTraining() {
        app.selectedTab = .training
        // Läuft schon ein Training, zeigt Training es wieder an. Nichts doppelt starten.
        guard app.liveWorkout == nil else { return }
        guard let routine = nextRoutine else {
            if freeTrainingIfNone { app.liveWorkout = LiveWorkout.empty() }
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
