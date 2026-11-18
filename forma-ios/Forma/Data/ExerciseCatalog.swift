import Foundation

/// Die 16 Muskelgruppen der Muskelkarte.
enum Muscle: String, CaseIterable, Identifiable, Sendable {
    case chest, frontDelts, sideDelts, rearDelts, biceps, triceps, forearms, abs, obliques
    case traps, lats, lowerBack, glutes, quads, hamstrings, calves

    var id: String { rawValue }

    var name: String {
        switch self {
        case .chest: "Brust"
        case .frontDelts: "Vordere Schulter"
        case .sideDelts: "Seitliche Schulter"
        case .rearDelts: "Hintere Schulter"
        case .biceps: "Bizeps"
        case .triceps: "Trizeps"
        case .forearms: "Unterarme"
        case .abs: "Bauch"
        case .obliques: "Seitlicher Bauch"
        case .traps: "Oberer Rücken"
        case .lats: "Latissimus"
        case .lowerBack: "Unterer Rücken"
        case .glutes: "Gesäß"
        case .quads: "Quadrizeps"
        case .hamstrings: "Beinbeuger"
        case .calves: "Waden"
        }
    }

    /// Grobe Gruppe der Bibliothek.
    var group: String {
        switch self {
        case .chest: "Brust"
        case .frontDelts, .sideDelts, .rearDelts: "Schultern"
        case .biceps, .triceps, .forearms: "Arme"
        case .abs, .obliques: "Rumpf"
        case .traps, .lats, .lowerBack: "Rücken"
        case .glutes, .quads, .hamstrings, .calves: "Beine"
        }
    }

    /// Ob die Karte den Muskel vorne und/oder hinten zeigt.
    var onFront: Bool {
        switch self {
        case .chest, .frontDelts, .sideDelts, .biceps, .forearms, .abs, .obliques, .traps, .quads, .calves: true
        default: false
        }
    }
    var onBack: Bool {
        switch self {
        case .sideDelts, .rearDelts, .triceps, .forearms, .traps, .lats, .lowerBack, .glutes, .hamstrings, .calves: true
        default: false
        }
    }
}

/// Bewegungen mit eigener Animation (die wichtigsten Grundübungen).
enum ExerciseMotion: String, CaseIterable, Sendable {
    case squat, deadlift, romanianDeadlift, benchPress, overheadPress, pullUp, latPulldown
    case barbellRow, cableRow, curl, pushdown, lateralRaise, splitSquat, hipThrust, pushUp
}

/// Alles, was die App zu einer Übung weiß: Muskeln, Ausrüstung und richtige Ausführung.
struct ExerciseInfo: Identifiable, Sendable {
    let name: String
    let group: String
    let equipment: String
    let primary: [Muscle]
    let secondary: [Muscle]
    let steps: [String]
    let mistakes: [String]
    let breathing: String
    let tempo: String
    let motion: ExerciseMotion?

    var id: String { name }

    /// Leuchtstärke je Muskel: primär voll, sekundär gedämpft.
    var intensity: [Muscle: Double] { ExerciseCatalog.intensity(primary: primary, secondary: secondary) }
}

enum ExerciseCatalog {
    static let secondaryLevel = 0.42

    static func info(for name: String) -> ExerciseInfo? { byName[name] }

    /// Muskeln einer Übung. Eigene Übungen ohne Katalogeintrag bekommen die Hauptmuskeln ihrer Gruppe.
    static func muscles(for name: String, group: String?) -> (primary: [Muscle], secondary: [Muscle]) {
        if let info = byName[name] { return (info.primary, info.secondary) }
        return (fallback[group ?? ""] ?? [], [])
    }

    static func intensity(primary: [Muscle], secondary: [Muscle]) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for m in secondary { result[m] = secondaryLevel }
        for m in primary { result[m] = 1 }
        return result
    }

    /// Katalogübungen, die den Muskel direkt (primär) oder mit (sekundär) trainieren.
    static func exercises(for muscle: Muscle) -> (primary: [ExerciseInfo], secondary: [ExerciseInfo]) {
        (all.filter { $0.primary.contains(muscle) }, all.filter { $0.secondary.contains(muscle) && !$0.primary.contains(muscle) })
    }

    private static let fallback: [String: [Muscle]] = [
        "Brust": [.chest], "Rücken": [.lats, .traps], "Schultern": [.sideDelts, .frontDelts],
        "Beine": [.quads, .glutes], "Arme": [.biceps, .triceps], "Rumpf": [.abs]
    ]

    private static let byName: [String: ExerciseInfo] = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

    // MARK: - Ausführungsmuster (Standard für Atmung und Tempo)

    private enum Pattern {
        case press, pull, legs, isolation, core, hold

        var breathing: String {
            switch self {
            case .press: "Oben einatmen, Bauch fest. Beim Drücken ausatmen."
            case .pull: "Vor dem Zug einatmen, beim Ziehen ausatmen, beim Zurückführen wieder einatmen."
            case .legs: "Oben tief in den Bauch einatmen und die Luft halten, bis du die schwerste Stelle geschafft hast. Oben ausatmen."
            case .isolation: "Beim Anspannen ausatmen, beim Zurückführen einatmen."
            case .core: "Beim Einrollen ausatmen, beim Zurückgehen einatmen."
            case .hold: "Ruhig und gleichmäßig weiteratmen, den Bauch dabei fest halten."
            }
        }

        var tempo: String {
            switch self {
            case .press, .pull, .legs: "2 s ablassen, kurz halten, kontrolliert zurück."
            case .isolation, .core: "1 s anspannen, kurz halten, 2–3 s zurück."
            case .hold: "20–60 s halten. Lieber kürzer und sauber."
            }
        }
    }

    private static func e(_ name: String, _ group: String, _ equipment: String, _ primary: [Muscle], _ secondary: [Muscle],
                          _ pattern: Pattern, motion: ExerciseMotion? = nil, steps: [String], mistakes: [String]) -> ExerciseInfo {
        ExerciseInfo(name: name, group: group, equipment: equipment, primary: primary, secondary: secondary, steps: steps,
                     mistakes: mistakes, breathing: pattern.breathing, tempo: pattern.tempo, motion: motion)
    }

    // MARK: - Übungen

    static let all: [ExerciseInfo] = [
        // Brust
        e("Bankdrücken", "Brust", "Langhantel", [.chest], [.frontDelts, .triceps], .press, motion: .benchPress,
          steps: ["Leg dich so hin, dass die Augen unter der Stange sind. Füße fest am Boden.",
                  "Schulterblätter zusammen und nach unten ziehen, leichte Brücke im Rücken.",
                  "Etwas breiter als schulterbreit greifen und die Stange über die Schultern heben.",
                  "Kontrolliert zur unteren Brust ablassen, Ellbogen etwa 45° vom Körper.",
                  "Gerade nach oben drücken, bis die Arme gestreckt sind."],
          mistakes: ["Ellbogen weit zur Seite abgespreizt – das belastet die Schulter.",
                     "Stange auf der Brust abfedern lassen.",
                     "Po hebt von der Bank ab."]),
        e("Schrägbankdrücken Kurzhantel", "Brust", "Kurzhantel", [.chest], [.frontDelts, .triceps], .press,
          steps: ["Bank auf 30–45° stellen, Hanteln auf den Oberschenkeln mit nach oben nehmen.",
                  "Schulterblätter zurück und unten, Hanteln neben der oberen Brust.",
                  "Schräg nach oben drücken, bis sie sich über der Brust fast berühren.",
                  "Langsam bis zur Dehnung neben der Brust absenken."],
          mistakes: ["Bank zu steil – dann arbeitet vor allem die Schulter.", "Hanteln oben zusammenschlagen."]),
        e("Dips", "Brust", "Körpergewicht", [.chest, .triceps], [.frontDelts], .press,
          steps: ["Auf den Holmen stützen, Arme gestreckt, Schultern tief.",
                  "Oberkörper leicht nach vorn neigen.",
                  "Absenken, bis die Oberarme etwa waagerecht sind.",
                  "Kraftvoll hochdrücken, ohne die Ellbogen zu überstrecken."],
          mistakes: ["Schultern rutschen zu den Ohren hoch.", "Zu tief absenken, obwohl die Schulter zwickt."]),
        e("Fliegende am Kabel", "Brust", "Kabel", [.chest], [.frontDelts], .isolation,
          steps: ["Kabelzüge auf Schulterhöhe, einen Schritt nach vorn in Schrittstellung.",
                  "Arme leicht gebeugt öffnen, bis du eine Dehnung in der Brust spürst.",
                  "In einem Bogen vor der Brust zusammenführen und kurz drücken.",
                  "Langsam in den Bogen zurück."],
          mistakes: ["Ellbogen beugen und strecken – dann wird es Drücken.", "Zu schweres Gewicht zieht die Schultern nach vorn."]),
        e("Liegestütz", "Brust", "Körpergewicht", [.chest], [.triceps, .frontDelts, .abs], .press, motion: .pushUp,
          steps: ["Hände etwas breiter als schulterbreit, Körper von Kopf bis Ferse gerade.",
                  "Bauch und Po anspannen.",
                  "Brust bis knapp über den Boden absenken, Ellbogen schräg nach hinten.",
                  "Hochdrücken, bis die Arme gestreckt sind."],
          mistakes: ["Hüfte hängt durch.", "Kopf nach vorn strecken statt in Verlängerung der Wirbelsäule halten."]),

        // Schultern
        e("Schulterdrücken", "Schultern", "Langhantel", [.frontDelts], [.sideDelts, .triceps, .traps], .press, motion: .overheadPress,
          steps: ["Stange auf Schulterhöhe, Griff knapp schulterbreit, Unterarme senkrecht.",
                  "Po und Bauch fest, Kinn leicht zurück.",
                  "Stange gerade nach oben drücken und den Kopf danach durch die Arme schieben.",
                  "Oben ganz strecken, dann kontrolliert zurück zur Schulter."],
          mistakes: ["Starkes Hohlkreuz statt festem Rumpf.", "Stange in einem Bogen um den Kopf führen."]),
        e("Seitheben", "Schultern", "Kurzhantel", [.sideDelts], [.traps], .isolation, motion: .lateralRaise,
          steps: ["Aufrecht stehen, Hanteln seitlich, Ellbogen leicht gebeugt.",
                  "Arme seitlich bis auf Schulterhöhe anheben, die Ellbogen führen.",
                  "Oben kurz halten.",
                  "Langsam absenken, ohne Schwung."],
          mistakes: ["Schwung aus dem Oberkörper.", "Schultern zu den Ohren ziehen."]),
        e("Face Pulls", "Schultern", "Kabel", [.rearDelts], [.traps, .sideDelts], .pull,
          steps: ["Seil auf Augenhöhe einhängen, Daumen zeigen zu dir.",
                  "Zum Gesicht ziehen, Ellbogen hoch und weit auseinander.",
                  "Am Ende die Hände nach außen drehen, Schulterblätter zusammen.",
                  "Kontrolliert nach vorn zurück."],
          mistakes: ["Zu tief ziehen – dann wird es Rudern.", "Mit dem Oberkörper nach hinten lehnen."]),
        e("Arnold Press", "Schultern", "Kurzhantel", [.frontDelts], [.sideDelts, .triceps], .press,
          steps: ["Sitzend, Hanteln vor dem Gesicht, Handflächen zu dir.",
                  "Beim Hochdrücken die Hände nach außen drehen.",
                  "Oben zeigen die Handflächen nach vorn, Arme fast gestreckt.",
                  "Auf demselben Weg zurückdrehen und absenken."],
          mistakes: ["Hohlkreuz beim Drücken.", "Drehung zu schnell und ohne Kontrolle."]),
        e("Reverse Flys", "Schultern", "Kurzhantel", [.rearDelts], [.traps], .isolation,
          steps: ["Vorgebeugt stehen, Rücken gerade, Hanteln hängen unter der Brust.",
                  "Arme leicht gebeugt seitlich anheben.",
                  "Bis auf Schulterhöhe, Schulterblätter dabei zusammen.",
                  "Langsam absenken."],
          mistakes: ["Oberkörper richtet sich beim Heben auf.", "Zu schweres Gewicht, dann zieht der obere Rücken."]),

        // Rücken
        e("Klimmzüge", "Rücken", "Körpergewicht", [.lats], [.biceps, .rearDelts, .traps, .forearms], .pull, motion: .pullUp,
          steps: ["Stange etwas breiter als schulterbreit greifen und ganz hängen.",
                  "Zuerst die Schultern nach unten ziehen.",
                  "Brust zur Stange ziehen, bis das Kinn darüber ist.",
                  "Langsam bis in den gestreckten Hang ablassen."],
          mistakes: ["Schwung mit den Beinen.", "Nur halbe Wiederholungen."]),
        e("Langhantelrudern", "Rücken", "Langhantel", [.lats, .traps], [.rearDelts, .biceps, .lowerBack], .pull, motion: .barbellRow,
          steps: ["Hüftbreit stehen, Knie leicht gebeugt, Oberkörper etwa 45° vorgebeugt.",
                  "Rücken gerade, die Stange hängt unter den Schultern.",
                  "Stange zum Bauchnabel ziehen, Ellbogen nah am Körper.",
                  "Oben Schulterblätter zusammen, dann kontrolliert ablassen."],
          mistakes: ["Runder Rücken.", "Mit dem Oberkörper hochschwingen."]),
        e("Latzug", "Rücken", "Kabel", [.lats], [.biceps, .rearDelts], .pull, motion: .latPulldown,
          steps: ["Oberschenkel unter das Polster, Stange breit greifen.",
                  "Leicht zurücklehnen, Brust raus.",
                  "Stange zur oberen Brust ziehen, Ellbogen nach unten.",
                  "Langsam nach oben führen, bis die Arme gestreckt sind."],
          mistakes: ["Stange in den Nacken ziehen.", "Mit dem ganzen Körper nach hinten fallen."]),
        e("Rudern am Kabel", "Rücken", "Kabel", [.lats, .traps], [.rearDelts, .biceps], .pull, motion: .cableRow,
          steps: ["Aufrecht sitzen, Füße an der Platte, Knie leicht gebeugt.",
                  "Griff mit gestreckten Armen halten, Schultern tief.",
                  "Griff zum Bauch ziehen, die Brust bleibt oben.",
                  "Schulterblätter zusammen, dann langsam nach vorn strecken."],
          mistakes: ["Mit dem Oberkörper weit vor und zurück schaukeln.", "Schultern hochziehen."]),
        e("Kurzhantelrudern einarmig", "Rücken", "Kurzhantel", [.lats], [.traps, .rearDelts, .biceps], .pull,
          steps: ["Knie und Hand auf der Bank, Rücken waagerecht.",
                  "Die Hantel hängt unter der Schulter.",
                  "Hantel Richtung Hüfte ziehen, Ellbogen nah am Körper.",
                  "Unten den Arm ganz strecken."],
          mistakes: ["Oberkörper aufdrehen.", "Zur Brust statt zur Hüfte ziehen."]),
        e("Kreuzheben", "Rücken", "Langhantel", [.glutes, .hamstrings, .lowerBack], [.quads, .traps, .forearms, .lats], .legs, motion: .deadlift,
          steps: ["Füße hüftbreit, Stange über der Fußmitte.",
                  "Schulterbreit greifen, Schienbeine an die Stange.",
                  "Rücken gerade, Brust raus, Spannung aufbauen.",
                  "Mit den Beinen vom Boden wegdrücken, Stange am Körper hochführen.",
                  "Oben die Hüfte strecken, auf demselben Weg zurück."],
          mistakes: ["Runder Rücken beim Anheben.", "Stange entfernt sich vom Körper.", "Oben nach hinten überstrecken."]),
        e("Shrugs", "Rücken", "Kurzhantel", [.traps], [.forearms], .isolation,
          steps: ["Aufrecht stehen, Hanteln seitlich.",
                  "Schultern gerade nach oben zu den Ohren ziehen.",
                  "Oben 1 s halten.",
                  "Langsam absenken."],
          mistakes: ["Schultern kreisen.", "Kopf nach vorn schieben."]),
        e("Hyperextensions", "Rücken", "Gerät", [.lowerBack], [.glutes, .hamstrings], .isolation,
          steps: ["Hüfte knapp über dem Polster, Fersen fixiert.",
                  "Oberkörper mit geradem Rücken absenken.",
                  "Hochkommen, bis Oberkörper und Beine eine Linie bilden.",
                  "Nicht darüber hinaus ins Hohlkreuz."],
          mistakes: ["Mit Schwung hochreißen.", "Oben weit überstrecken."]),

        // Beine
        e("Kniebeuge", "Beine", "Langhantel", [.quads, .glutes], [.hamstrings, .lowerBack, .abs], .legs, motion: .squat,
          steps: ["Stange auf dem oberen Rücken, Füße etwa schulterbreit, Zehen leicht nach außen.",
                  "Tief einatmen, Bauch fest.",
                  "Hüfte nach hinten und unten, Knie folgen den Zehen.",
                  "Mindestens bis die Oberschenkel waagerecht sind, Fersen bleiben unten.",
                  "Aus der Fußmitte kraftvoll hochdrücken."],
          mistakes: ["Knie fallen nach innen.", "Fersen heben ab.", "Rücken rundet sich unten ein."]),
        e("Rumänisches Kreuzheben", "Beine", "Langhantel", [.hamstrings, .glutes], [.lowerBack, .forearms], .legs, motion: .romanianDeadlift,
          steps: ["Aufrecht mit der Stange vor den Oberschenkeln, Knie leicht gebeugt.",
                  "Hüfte nach hinten schieben, die Stange gleitet an den Beinen entlang.",
                  "Absenken, bis du hinten am Oberschenkel eine starke Dehnung spürst.",
                  "Hüfte nach vorn bringen und aufrichten."],
          mistakes: ["Knie zu stark beugen – dann wird es normales Kreuzheben.", "Rücken rundet sich."]),
        e("Beinpresse", "Beine", "Maschine", [.quads, .glutes], [.hamstrings], .legs,
          steps: ["Rücken fest ans Polster, Füße schulterbreit auf der Platte.",
                  "Sicherung lösen, Platte kontrolliert absenken.",
                  "Tief gehen, solange der untere Rücken am Polster bleibt.",
                  "Hochdrücken, die Knie oben nicht ganz durchstrecken."],
          mistakes: ["Becken rollt unten vom Polster.", "Knie fallen nach innen."]),
        e("Ausfallschritte", "Beine", "Kurzhantel", [.quads, .glutes], [.hamstrings, .calves], .legs, motion: .splitSquat,
          steps: ["Aufrecht stehen, Hanteln seitlich.",
                  "Einen großen Schritt machen.",
                  "Hinteres Knie Richtung Boden senken, vorderes Knie bleibt über dem Fuß.",
                  "Über die vordere Ferse zurück in den Stand drücken."],
          mistakes: ["Vorderes Knie knickt nach innen.", "Zu kurzer Schritt, die vordere Ferse hebt ab."]),
        e("Beinstrecker", "Beine", "Maschine", [.quads], [], .isolation,
          steps: ["Lehne so einstellen, dass das Knie an der Drehachse liegt.",
                  "Polster vorn am Schienbein über dem Fuß.",
                  "Beine strecken, oben kurz anspannen.",
                  "Langsam zurück, ohne das Gewicht abzulegen."],
          mistakes: ["Mit Schwung hochtreten.", "Po hebt vom Sitz ab."]),
        e("Beinbeuger", "Beine", "Maschine", [.hamstrings], [.calves], .isolation,
          steps: ["Knie an der Drehachse, Polster über der Ferse.",
                  "Hüfte fest auf dem Polster halten.",
                  "Fersen zum Po ziehen, kurz halten.",
                  "Langsam strecken."],
          mistakes: ["Hüfte hebt ab.", "Gewicht zurückfallen lassen."]),
        e("Wadenheben", "Beine", "Maschine", [.calves], [], .isolation,
          steps: ["Fußballen auf der Kante, Fersen frei.",
                  "Fersen tief absenken bis zur Dehnung.",
                  "So hoch wie möglich auf die Zehenspitzen drücken.",
                  "Oben 1 s halten, dann langsam ab."],
          mistakes: ["Wippen ohne volle Bewegung.", "Knie beugen und mitschieben."]),
        e("Hip Thrust", "Beine", "Langhantel", [.glutes], [.hamstrings, .quads], .legs, motion: .hipThrust,
          steps: ["Schulterblätter an die Bankkante, Stange gepolstert über der Hüfte.",
                  "Füße hüftbreit, Schienbeine oben senkrecht.",
                  "Hüfte hochdrücken, bis Oberkörper und Oberschenkel eine Linie bilden.",
                  "Oben den Po fest anspannen, dann kontrolliert absenken."],
          mistakes: ["Oben ins Hohlkreuz gehen.", "Füße zu weit weg – dann arbeitet vor allem der Beinbeuger."]),
        e("Bulgarian Split Squat", "Beine", "Kurzhantel", [.quads, .glutes], [.hamstrings], .legs, motion: .splitSquat,
          steps: ["Hinteren Fuß auf eine Bank legen, vorderer Fuß gut einen Schritt davor.",
                  "Aufrecht bleiben, Hanteln seitlich.",
                  "Senkrecht nach unten gehen, bis das hintere Knie fast den Boden berührt.",
                  "Über die vordere Ferse hochdrücken."],
          mistakes: ["Vorderer Fuß zu nah an der Bank.", "Oberkörper fällt weit nach vorn."]),

        // Arme
        e("Bizepscurls", "Arme", "Kurzhantel", [.biceps], [.forearms], .isolation, motion: .curl,
          steps: ["Aufrecht stehen, Hanteln seitlich, Handflächen nach vorn.",
                  "Ellbogen bleiben am Körper.",
                  "Hanteln zur Schulter beugen, oben kurz anspannen.",
                  "Langsam ganz strecken."],
          mistakes: ["Schwung aus dem Rücken.", "Ellbogen wandern nach vorn."]),
        e("Hammercurls", "Arme", "Kurzhantel", [.biceps, .forearms], [], .isolation, motion: .curl,
          steps: ["Hanteln seitlich, Daumen zeigen nach vorn.",
                  "Ellbogen am Körper fixieren.",
                  "Hanteln im Hammergriff hochbeugen.",
                  "Kontrolliert absenken."],
          mistakes: ["Schwung aus dem Rücken.", "Handgelenke abknicken."]),
        e("Langhantelcurls", "Arme", "Langhantel", [.biceps], [.forearms], .isolation, motion: .curl,
          steps: ["Schulterbreit im Untergriff greifen, Stange vor den Oberschenkeln.",
                  "Ellbogen bleiben seitlich am Körper.",
                  "Stange zur Brust beugen.",
                  "Langsam bis zur vollen Streckung ablassen."],
          mistakes: ["Hüfte schiebt nach vorn.", "Unten nicht ganz strecken."]),
        e("Trizepsdrücken am Kabel", "Arme", "Kabel", [.triceps], [], .isolation, motion: .pushdown,
          steps: ["Vor dem Kabel stehen, Griff oder Seil auf Brusthöhe.",
                  "Ellbogen seitlich am Körper fixieren.",
                  "Nach unten strecken, bis die Arme gerade sind.",
                  "Langsam zurück, bis die Unterarme etwa waagerecht sind."],
          mistakes: ["Ellbogen wandern nach vorn.", "Der Oberkörper drückt mit."]),
        e("Überkopf-Trizepsstrecken", "Arme", "Kabel", [.triceps], [], .isolation,
          steps: ["Rücken zum Kabel, Seil hinter dem Kopf.",
                  "Ellbogen zeigen nach vorn oben und bleiben dort.",
                  "Arme nach vorn oben strecken.",
                  "Langsam bis zur Dehnung zurück."],
          mistakes: ["Ellbogen gehen weit auseinander.", "Hohlkreuz statt fester Rumpf."]),
        e("French Press", "Arme", "SZ-Stange", [.triceps], [], .isolation,
          steps: ["Auf der Bank liegen, SZ-Stange über der Brust.",
                  "Oberarme leicht nach hinten geneigt fixieren.",
                  "Stange Richtung Stirn absenken, nur der Ellbogen beugt.",
                  "Wieder strecken."],
          mistakes: ["Ellbogen gehen weit auseinander.", "Oberarme bewegen sich mit."]),
        e("Unterarmcurls", "Arme", "Langhantel", [.forearms], [], .isolation,
          steps: ["Unterarme auf der Bank, Handgelenke über der Kante.",
                  "Stange im Untergriff halten.",
                  "Handgelenke nach oben beugen.",
                  "Langsam absenken."],
          mistakes: ["Unterarme heben von der Bank ab.", "Zu kleine Bewegung."]),

        // Rumpf
        e("Plank", "Rumpf", "Körpergewicht", [.abs], [.obliques, .lowerBack], .hold,
          steps: ["Unterarme unter den Schultern, Körper gerade.",
                  "Po und Bauch anspannen, Becken leicht einrollen.",
                  "Kopf in Verlängerung der Wirbelsäule.",
                  "Halten, solange die Linie sauber bleibt."],
          mistakes: ["Hüfte hängt durch oder geht hoch.", "Luft anhalten."]),
        e("Seitstütz", "Rumpf", "Körpergewicht", [.obliques], [.abs], .hold,
          steps: ["Seitlich auf den Unterarm, Ellbogen unter der Schulter.",
                  "Füße übereinander, Hüfte hoch.",
                  "Der Körper bildet eine gerade Linie.",
                  "Halten, dann die Seite wechseln."],
          mistakes: ["Hüfte sinkt ab.", "Oberkörper kippt nach vorn."]),
        e("Hängendes Beinheben", "Rumpf", "Körpergewicht", [.abs], [.obliques, .forearms], .core,
          steps: ["An der Stange hängen, Schultern aktiv.",
                  "Becken einrollen und die Beine nach oben heben.",
                  "Oben kurz halten.",
                  "Langsam ablassen, ohne zu schwingen."],
          mistakes: ["Schwung statt Bauchkraft.", "Nur die Beine heben, das Becken bleibt starr."]),
        e("Cable Crunch", "Rumpf", "Kabel", [.abs], [.obliques], .core,
          steps: ["Vor dem Kabel knien, Seil neben dem Kopf.",
                  "Die Hüfte bleibt still.",
                  "Brustkorb Richtung Becken einrollen.",
                  "Langsam wieder aufrollen."],
          mistakes: ["Mit der Hüfte nach hinten setzen statt einzurollen.", "Mit den Armen ziehen."]),
        e("Ab Wheel", "Rumpf", "Gerät", [.abs], [.lats, .obliques], .core,
          steps: ["Auf den Knien, Rad unter den Schultern.",
                  "Bauch fest, Becken eingerollt.",
                  "Langsam nach vorn rollen, nur so weit der Rücken gerade bleibt.",
                  "Mit dem Bauch zurückziehen."],
          mistakes: ["Hohlkreuz am Umkehrpunkt.", "Zu weit rollen."])
    ]
}

/// Sätze je Muskel über die letzten 7 Tage (heute eingeschlossen).
enum MuscleVolume {
    /// Primärer Muskel zählt einen Satz, sekundärer einen halben.
    static func lastSevenDays(_ sets: [(exercise: String, date: Date)], groups: [String: String] = [:],
                              now: Date = .now, calendar: Calendar = .forma) -> [Muscle: Double] {
        guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else { return [:] }
        var result: [Muscle: Double] = [:]
        for set in sets where set.date >= start && set.date <= now {
            let muscles = ExerciseCatalog.muscles(for: set.exercise, group: groups[set.exercise])
            for m in muscles.primary { result[m, default: 0] += 1 }
            for m in muscles.secondary where !muscles.primary.contains(m) { result[m, default: 0] += 0.5 }
        }
        return result
    }

    /// Leuchtstärke für die Karte: ab 10 Sätzen voll, jeder trainierte Muskel sichtbar.
    static func level(_ sets: Double) -> Double {
        sets <= 0 ? 0 : min(1, 0.25 + 0.075 * sets)
    }

    /// „12“ oder „4,5“.
    static func text(_ sets: Double) -> String {
        sets.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE")))
    }
}
