import Darwin
import Foundation

/// Gemeinsamer Stand für Widget und App, mit noch nicht in SwiftData übernommenen Aktionen.
struct FastingWidgetStore: Sendable {
    static let widgetKind = "com.ma29xii.forma.fasting"
    static let defaultPlanHours = 16.0

    enum Event: Codable, Equatable, Sendable {
        case start(FastingAttributes)
        case end(start: Date, at: Date)

        var startDate: Date {
            switch self {
            case .start(let session): session.start
            case .end(let start, _): start
            }
        }
    }

    enum Presentation: Equatable, Sendable {
        case idle(planHours: Double)
        case countdown(FastingAttributes)
        case elapsed(FastingAttributes)
    }

    struct State: Codable, Equatable, Sendable {
        var planHours = FastingWidgetStore.defaultPlanHours
        var active: FastingAttributes?
        var pending: [Event] = []

        func presentation(at date: Date) -> Presentation {
            guard let active else { return .idle(planHours: planHours) }
            return active.progress(at: date, state: .init(end: nil)).reached
                ? .elapsed(active) : .countdown(active)
        }
    }

    let directory: URL?

    static var shared: Self {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.groupID)
        return Self(directory: root?.appendingPathComponent("forma-fasting-v1", isDirectory: true))
    }

    func state() throws -> State {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        return try load(from: directory.appendingPathComponent("state.json")) ?? State()
    }

    func toggle(at date: Date = .now, expectedActive: Bool? = nil) throws {
        try update { state in
            // Ein Widget kann einen älteren Stand anzeigen, während die App das Fasten schon geändert hat.
            if let expectedActive, expectedActive != (state.active != nil) { return }
            if let active = state.active {
                state.pending.append(.end(start: active.start, at: max(active.start, date)))
                state.active = nil
            } else {
                let session = FastingAttributes(start: date, targetHours: state.planHours)
                state.pending.append(.start(session))
                state.active = session
            }
        }
    }

    /// Schützt den gesamten Schreibvorgang prozessübergreifend. Leser sehen immer eine vollständige Datei.
    @discardableResult
    func update(_ change: (inout State) throws -> Void) throws -> Bool {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Die Sperrdatei bleibt liegen, da state.json beim atomaren Schreiben ersetzt wird.
        let lockFile = directory.appendingPathComponent("write.lock")
        let descriptor = lockFile.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let file = directory.appendingPathComponent("state.json")
        let previous = try load(from: file)
        var state = previous ?? State()
        try change(&state)
        guard state != previous else { return false }
        try JSONEncoder().encode(state).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }

    private func load(from file: URL) throws -> State? {
        do {
            return try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
