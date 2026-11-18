# Review 01 – unabhängiger Claude-Prüfer (Ersatz für Codex) – 18.11.2026
Geprüfter Commit: 370cc2d

Ergänzt Codex' `review-01.md` (unabhängig davon entstanden, Befund-IDs mit Präfix „C“). Grundlage: alle 22 Screenshots in `docs/forma-screens/` (Simulator iPhone 17 Pro, 402 × 874 pt, Bildbreite 460 px, also etwa 1,14 px pro pt) und der Code in `forma-ios/Forma/**`. Maße sind aus den Bildern geschätzt (±2 pt). Kontrastwerte sind berechnet (sRGB, WCAG 2.x) für Text auf `#030303` bzw. auf der Plate (etwa `#141414` oben, `#0C0C0C` unten).

## Gesamturteil

| Bildschirm | Note | Kurz |
|---|---|---|
| Heute (01–03) | 6/10 | Starker Kopf, darunter ein Dashboard ohne Hauptsache: 8 Kacheln, 3 davon doppelt. |
| Heute anpassen (03b) | 6/10 | Funktioniert, aber grau statt Glas, „Standard“ ohne Rückfrage. |
| Erholung (04–05) | 6/10 | Schöner Ring, aber die Erklärung widerspricht dem Code, und die Beitragszeile ist ein Einheitenmix. |
| Schlaf (06–07) | 6,5/10 | Bester Detailbildschirm. Das Hypnogramm ist blau statt lavendel, die 7-Nächte-Balken sagen nichts. |
| Belastung (08) | 5/10 | Für Kraftsportler fachlich blind: Forma-Training zählt nicht, „Summe 270“ hat keine Bedeutung. |
| Training (09/09b) | 5,5/10 | Solide, aber leere Zustände sind Nullreihen, „ab RIR 3“ ist falsch herum. |
| Live-Training (10–12) | 6/10 | Gute Daumenzone. Es fehlt die Spalte „Vorher“, der Kreis ist kein Knopf, Glas liegt auf Glas, das Pausenende ist stumm. |
| Zusammenfassung (13) | 5/10 | Kein Höhepunkt, kg fest verdrahtet, 1RM ignoriert die Reserve. |
| Gesundheit (14, 14e) | 5,5/10 | Fast eine Kopie von „Heute“. Der „Normal“-Bereich ist medizinisch irreführend. |
| Körperalter (14b–d) | 5/10 | Methode und Quellen sind vorbildlich offengelegt, aber die Hauptzahl beruht auf einem *angenommenen* Alter. |
| HRV-Detail (15) | 6/10 | Ordentlich. Die Kurve erfindet Spitzen (Catmull-Rom), die Achse ist abgeschnitten. |
| Coach (16) | 3,5/10 | Sagt etwas Falsches über die Belastung, die Hälfte des Bildschirms ist leer, eine Vorschlags-Frage wird falsch beantwortet. |

**Die 5 wichtigsten Punkte**
1. **Inhalte widersprechen sich oder sind falsch** (C-01-01 bis C-01-06): Der Coach sagt „16 Punkte bis zum Zielbereich“, während die Belastung im Zielbereich liegt. Die Erholungsformel im Text weicht vom Code ab. Das Journal verspricht eine Auswertung, die es nicht gibt. Bei SpO₂ widersprechen sich „Normal 93–100 %“ und „95–100 % gelten als normal“.
2. **Das Körperalter rechnet mit einem erfundenen Alter** und nennt das Ergebnis trotzdem „Verlässlichkeit: Hoch“ (C-01-01, C-01-15, C-01-16).
3. **Barrierefreiheit fehlt fast ganz:** keine einzige Schrift skaliert mit Dynamic Type. Tertiärtext liegt bei etwa 3,3:1 Kontrast, mehrere Tippziele sind unter 44 pt (C-01-07, C-01-08, C-01-26).
4. **Für Kraftsportler fehlt der Kern:** Forma-Training fließt nicht in die Belastung ein. Im Live-Training gibt es keine „Vorher“-Werte, das Pausenende im Vordergrund ist stumm, und die Begriffe RIR/Reserve sind inkonsistent (C-01-10, C-01-11, C-01-12, C-01-13, C-01-23).
5. **Eigenständigkeit:** Ampel-Schwellen 67/34, Stress 0–3, Belastung asymptotisch bis 100, Schlafbedarf mit „zu X % gedeckt“: Das ist in Summe das Whoop-Konzept, nur umgefärbt (C-01-20). Das widerspricht dem Auftrag „ruhig, modern und eigenständig“.

---

## Befunde

### C-01-01 · P0 · Körperalter · 14b-Körperalter.jpg, 03-Heute-unten.jpg, 14-Gesundheit.jpg
**Beobachtung:** Die Hauptzahl „27,0“ (76 pt, mint, mit Schein) und die Schlagzeile „3,0 Jahre jünger als du bist“ beruhen laut gelbem Chip auf „Annahme: 30 Jahre, männlich“. `BodyAge.evaluate` liefert auch bei `PersonInfo.origin == .assumed` ein volles `.ready(Result)`. Auf „Heute“ und „Gesundheit“ fehlt der Hinweis auf die Annahme ganz: Dort steht nur „27,0 Jahre · 3,0 Jahre jünger als du bist“.
**Warum falsch:** Eine Zahl, die wie ein persönliches Messergebnis aussieht, ist zur Hälfte erfunden. „als du bist“ behauptet, die App kenne dein Alter. Das ist irreführend und verletzt Prinzip 10 („Ehrlichkeit“) aus DESIGN.md.
**Lösung:** `BodyAge.evaluate`: `guard person.origin != .assumed else { return .needsProfile }`. Wenn du eine Vorschau willst, zeig nur die Verschiebung: neuer `Outcome.preview(shift: Double)`. `BodyAgeSummaryCard` zeigt dann „etwa 3 Jahre jünger als dein Alter“ ohne absolute Zahl und mit Knopf „Geburtsjahr eintragen“ (≥ 44 pt, `.buttonStyle(.glass)`). Die Verlässlichkeit ist bei Annahme immer `.low`.

### C-01-02 · P0 · Coach · 16-Coach.jpg (gegen 08-Belastung.jpg)
**Beobachtung:** Der Coach schreibt „Gut trainiert. Bis zum Zielbereich fehlen noch 16 Punkte – ein lockerer Spaziergang reicht.“ Gleichzeitig zeigt „Belastung“ 39 und „Im Zielbereich“ (35–55). Ursache ist `CoachEngine.dailyLine`: `remaining = s.target.upperBound - s.strain`. Gerechnet wird also gegen die *Obergrenze*. „Gut trainiert“ kommt außerdem schon nach einem Ein-Minuten-Training (13-Zusammenfassung: „Dauer 1 min“), das die Belastung gar nicht verändert (siehe C-01-13).
**Warum falsch:** Der Coach ist die Stimme der App. Wenn er den Ringen widerspricht, glaubst du keiner Zahl mehr.
**Lösung:** In `dailyLine` nach dem Training drei Fälle unterscheiden: `strain < lower` → „Noch \(lower - strain) Punkte bis zum Zielbereich“. `lower...upper` → „Du bist im Zielbereich. Jetzt zählt die Erholung: ins Bett gegen …“. `> upper` → „Über dem Ziel – plan genug Schlaf ein“. „Gut trainiert“ erst ab `session.duration >= 20 * 60`. Dazu ein Unit-Test pro Fall, gleiche Texte wie in `StrainDetail.status`, am besten aus einer gemeinsamen Funktion `StrainStatus(s)`.

### C-01-03 · P0 · Erholung · 05-Erholung-unten.jpg (aufgeklappte Berechnung)
**Beobachtung:** `RecoveryDetail` schreibt „Startwert 55. …“. In `ScoreEngine.recovery` steht aber `var score = 58.0`. Der Text nennt auch keine Gewichte (HRV ×10, Ruhepuls ×7, Atmung ×4, Schlaf ×0,25 je Punkt über 70).
**Warum falsch:** „So wird gerechnet“ ist ein Transparenzversprechen. Ein falscher Startwert macht es zur Behauptung.
**Lösung:** Konstanten in `ScoreEngine` als `static let recoveryBase = 58.0, hrvWeight = 10.0 …` herausziehen und den Erklärtext daraus bauen (`"Startwert \(Int(ScoreEngine.recoveryBase))…"`). Ein Test prüft, dass der Text die Konstanten enthält.

### C-01-04 · P0 · Journal · (kein Screenshot) `Features/Journal/JournalView.swift`
**Beobachtung:** Der Fußtext verspricht: „Nach etwa zwei Wochen zeigt dir der Coach, wie diese Gewohnheiten deine Erholung beeinflussen.“ `JournalAnswer` wird außer in `JournalView` und im Model-Container nirgends gelesen (geprüft per Suche). `Insights` wertet nur Schritte und Schlaf aus.
**Warum falsch:** Die App verspricht eine Funktion, die es nicht gibt. Nach zwei Wochen Ausfüllen kommt nichts. Das ist P0 (irreführend).
**Lösung:** Sofort den Satz ersetzen durch „Deine Antworten bleiben auf dem iPhone. Die Auswertung kommt in einer späteren Version.“ Danach umsetzen: `Insights.habit(_ question:)` vergleicht die Erholung am Folgetag mit und ohne Gewohnheit, erst ab 5 Ja- **und** 5 Nein-Tagen und mit der Formulierung „Zusammenhang, keine Ursache“.

### C-01-05 · P0 · Heute/Gesundheit · 02-Heute-gescrollt.jpg, 14-Gesundheit.jpg
**Beobachtung:** Die Zeile „Sauerstoffsättigung · Normal 93–100 %“. Die Detailerklärung in `MetricKind.spo2.explanation` sagt dagegen: „Werte zwischen 95 und 100 % gelten als normal.“ „Normal“ ist hier dein Mittel ± 1 Standardabweichung (`MetricSummaryRow`). Die Obergrenze kann rechnerisch über 100 % liegen (96,5 + 3,9 = 100,4) und wird nur durch Rundung zu „100“.
**Warum falsch:** „Normal“ klingt medizinisch. 93 % als „normal“ zu bezeichnen widerspricht dem eigenen Erklärtext und der üblichen klinischen Lesart. Wer bei SpO₂ krank ist, wird beruhigt.
**Lösung:** In `MetricSummaryRow` „Normal“ durch „Bei dir üblich“ ersetzen. Für `.spo2` die obere Grenze auf `min(100, high)` setzen und eine untere Warnschwelle fest bei 95 % (`valueColor: Theme.warning`, wenn `< 95`), unabhängig vom persönlichen Bereich. Der Fußtext in `HealthView` erklärt den persönlichen Bereich, er gehört aber an die Zeile (siehe C-01-22).

### C-01-06 · P0 · Coach · 16-Coach.jpg
**Beobachtung:** Der vierte Vorschlags-Chip „Wie viel Belastung ist heute gut?“ wird in `CoachEngine.localAnswer` vom Trainings-Zweig abgefangen, weil `q.contains("heute")` vor `q.contains("belast")` geprüft wird. Antwort: „Push wie geplant …“ statt einer Belastungsantwort. Zusätzlich hängt `consumePrompt()` an *jeden* über eine Kachel geöffneten Text eine Erholungsantwort an (`localAnswer(to: "erholung")`), auch beim „Einblick“ zum Schlaf.
**Warum falsch:** Ein vorgeschlagener Knopf liefert eine falsche Antwort. Das ist kaputt.
**Lösung:** Die Absicht als `enum CoachIntent { recovery, sleep, training, strain, stress }` explizit mitgeben. Jeder Chip ist `(label, intent)`, `send(_:intent:)` umgeht die Stichwortsuche. Bei Freitext werden spezifische Stichwörter (`belast`, `ziel`, `schlaf`) **vor** generischen (`heute`) geprüft. `app.openCoach(with:intent:)` übergibt die Absicht der Kachel.

### C-01-07 · P1 · alle Bildschirme · `Design/Theme.swift`
**Beobachtung:** Alle Schriften sind `Font.system(size:)` mit festen pt-Werten (34, 28, 22, 20, 17, 16, 15, 13, 11). Dazu kommen feste Größen in Komponenten (`size: 12.5`, `size: 22`, `size: 76`). Kein `@ScaledMetric`, kein `dynamicTypeSize`.
**Warum falsch:** Dynamic Type ist für Apple-Level Pflicht. Wer im Studio ohne Brille liest, kann nicht vergrößern. App-Store-Prüfer und Bedienungshilfen-Nutzer bemerken das sofort.
**Lösung:** Die Tokens auf Textstile umstellen: `formaLargeTitle = .largeTitle.bold()`, `formaTitle = .title.bold()`, `formaHeadline = .title2.weight(.semibold)`, `formaSection = .title3.weight(.semibold)`, `formaBodyLarge = .body`, `formaRowTitle = .callout.weight(.medium)`, `formaBody = .subheadline`, `formaCaption = .footnote`, `formaMicro = .caption2.weight(.semibold)`. Zahlen: `.system(.largeTitle, design: .rounded, weight: .semibold)`. Ringgrößen und Zahlengrößen in `RingTrio`/`DetailHero` per `@ScaledMetric(relativeTo: .largeTitle) var ring = 120`. Zweispaltige Raster (Energie/Stress, Tag, Schlaf-Kennzahlen, Zusammenfassung) mit `ViewThatFits { HStack … ; VStack … }`. Test mit AX3 und AX5 im Simulator, als eigener Schritt im UI-Rundgang.

### C-01-08 · P1 · alle · Kontrast `Theme.textTertiary`/`textQuaternary`
**Beobachtung:** `textTertiary = white.opacity(0.40)` ergibt auf Schwarz etwa `#686868`, also **≈ 3,7:1** auf `#030303` und **≈ 3,3:1** auf der Plate. Verwendet wird es für 11–13-pt-Text: „Antippen zum Fragen“, „letzte 180 Tage“, „dein Alter“, „geschätzt“, Tabellenköpfe „Satz/kg/Wdh/RIR“, Wochentage unter den Balken, Phasennamen im Hypnogramm und den Quellen-Fußtext. `textQuaternary = 0.22` ergibt etwa `#3B3B3B`, also **≈ 1,8:1 / 1,6:1**. Damit gezeichnet sind die Chevrons und der offene Abhak-Kreis im Live-Training. `textSecondary #9A9AA0` liegt bei ≈ 6,6:1 und ist in Ordnung.
**Warum falsch:** WCAG AA verlangt 4,5:1 für Text unter 18 pt und 3:1 für bedeutungstragende Grafik (1.4.11). Der offene Kreis *ist* der Status „nicht erledigt“.
**Lösung:** `textTertiary = Color.white.opacity(0.56)` (≈ `#8E8E8E`, ≈ 5,5:1 auf der Plate). `textQuaternary = Color.white.opacity(0.40)` (≈ 3,3:1) und nur für Grafik, nie für Text. Chevrons im Live-Kreis: `strokeBorder(Theme.textTertiary, lineWidth: 2)`.

### C-01-09 · P1 · Live-Training (Pause) · 11-Pause.jpg
**Beobachtung:** Das Dock ist `.glassEffect(.regular, in: .rect(cornerRadius: 30))`. Darin liegt ein `GlassEffectContainer` mit `.buttonStyle(.glass)` („+15 s“) und `.glassProminent` („Weiter“). Das ist Glas auf Glas, sichtbar als zwei verschieden helle Glasebenen (dunkelgraue Kapsel, 44 pt, in grauem Dock).
**Warum falsch:** Das widerspricht DESIGN.md, Prinzip 1 („kein Glas auf Glas“), und Apples Liquid-Glass-Richtlinien: Glas bricht Glas schlecht, der Kontrast der Beschriftung sinkt. „+15 s“ hat auf dem Dockglas etwa 1,3:1 Flächenkontrast.
**Lösung:** Entweder ist das Dock **kein** Glas, sondern ein `GlassEffectContainer` ohne eigene Fläche, und die Knöpfe sind die einzigen Glaselemente (`.glassEffect(.regular.interactive())` auf jedem, mit `.glassEffectID` für das Morphing). Oder das Dock bleibt Glas, und die inneren Knöpfe nutzen `PrimaryButtonStyle` bzw. eine sekundäre Fläche `Capsule().fill(.white.opacity(0.10))`. Ich empfehle die erste Variante, sie ergibt auch die schöne Morph-Animation (siehe Animations-Vorschlag A6).

### C-01-10 · P1 · Live-Training (Pause) · 11-Pause.jpg, `App/AppState.swift`
**Beobachtung:** Das Pausenende ist im Vordergrund stumm. `RestNotifier` plant eine lokale Mitteilung, aber es gibt keinen `UNUserNotificationCenterDelegate.willPresent`. Mitteilungen werden bei offener App also nicht angezeigt. `LiveWorkoutView` hat nur `.sensoryFeedback(.success, trigger: completedCount)`, nichts bei 0:00. Außerdem gibt es kein „−15 s“.
**Warum falsch:** Das iPhone liegt auf der Bank, der Bildschirm ist an. Genau dann ist das Pausenende der wichtigste Moment, und es passiert nichts.
**Lösung:** `@State var restFinished = 0` hochzählen, wenn `remaining` von 1 auf 0 fällt (in `dock`, z. B. `.onChange(of: remaining <= 0)`). Dann `.sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: restFinished)` plus kurzer Ton (`AudioServicesPlaySystemSound(1005)`, Stummschalter respektieren). In `FormaApp` ein `NotificationDelegate` mit `willPresent` → `[.banner, .sound]`, gesetzt in `init()`. Im Pausen-Dock „−15 s | +15 s | Überspringen“ (drei Ziele, je ≥ 44 pt).

### C-01-11 · P1 · Live-Training · 10-Live-Training.jpg
**Beobachtung:** Der Kreis rechts in jeder Satzzeile (28 × 28 pt, Rand 1,5 pt in 22 % Weiß) sieht aus wie Hevys Abhak-Knopf. Antippen wählt aber nur die Zeile aus (`workout.select`). Abschließen geht nur über das Dock.
**Warum falsch:** Die Form verspricht eine Handlung, die nicht passiert (falsche Affordance). Wer von Hevy kommt, tippt den Kreis an und wundert sich. Das kostet im Training echte Sekunden.
**Lösung:** In `setRow` den Kreis als eigenen `Button` mit `frame(width: 44, height: 44)` und `contentShape(Circle())`. Antippen ruft `workout.complete(exercise:set:)` mit den Werten der Zeile auf (startet die Pause wie das Dock). Bei erledigten Sätzen macht Antippen den Satz wieder offen (mit `.sensoryFeedback(.selection)`). Die Zeile selbst bleibt „auswählen“.

### C-01-12 · P1 · Training/Live/Zusammenfassung · 09-Training.jpg, 10–13
**Beobachtung:** Vier Begriffe für dieselbe Sache: Tabellenkopf „RIR“, Dock „Reserve“, Zusammenfassung „RIR 2“, Kachel „ab RIR 3“. „ab RIR 3“ ist zudem **falsch herum**: Der Code zählt `rir <= 3`, also „höchstens 3 Wdh. Reserve“. „ab“ heißt im Deutschen „3 oder mehr“. Der Aufwärmsatz heißt „A“ und wird nirgends erklärt.
**Warum falsch:** Fachbegriff ohne Erklärung, inkonsistente Benennung und eine sachlich falsche Beschriftung.
**Lösung:** Einheitlich „Reserve“ (Wdh. übrig). Tabellenkopf „Res.“ mit `accessibilityLabel("Wiederholungen in Reserve")`. Kachel-Accessory: „bis 3 Wdh. Reserve“. Zusammenfassung: „2 Wdh. Reserve“. Beim ersten Live-Training einmal ein `TipKit`-Tipp („Reserve = wie viele Wiederholungen du noch geschafft hättest. 0 = Muskelversagen.“). TipKit läuft ohne Extension. Aufwärmsatz: „W“ in `textTertiary` und VoiceOver-Label „Aufwärmsatz“, oder ein kleines `flame`-Symbol.

### C-01-13 · P1 · Belastung · 08-Belastung.jpg, `Data/ScoreEngine.swift`
**Beobachtung:** `ScoreEngine.strain` = aktive kcal + 4 × Trainingsminuten aus `DayMetrics.workouts`, also nur aus Health/Fitbit. Forma-Trainings (SwiftData) fließen nicht ein und werden nicht als `HKWorkout` geschrieben. Ein 75-Minuten-Beintraining mit niedriger Herzfrequenz ergibt also fast keine Belastung. Unter den 7-Tage-Balken steht „Summe 270“: Eine Summe aus asymptotischen 0–100-Werten hat keine Einheit und keine Bedeutung.
**Warum falsch:** Für die Kernzielgruppe (Kraftsport) misst der Belastungsring das Falsche. Die Empfehlung „Zielbereich 35–55“ ist dann wertlos.
**Lösung:** In `ScoreEngine.strain(_:sessions:)` Forma-Sitzungen des Tages addieren: `load += minutes * intensityFactor`, mit `intensityFactor` aus der mittleren Reserve (Reserve 0 → 8, 1 → 7, 2 → 6, ≥ 3 → 4.5 „Punkte pro Minute“). Das entspricht dem Prinzip der Session-RPE (Foster): Dauer × Anstrengung. Doppelte Zählung gegen ein gleichzeitiges Health-Krafttraining vermeiden (wie in `BodyAge.strengthMinutes` über `max`). „Summe“ durch „Mittel \(Int(avg))“ ersetzen. In „So wird gerechnet“ Krafttraining erwähnen.

### C-01-14 · P1 · Körperalter vs. Training · 14b-Körperalter.jpg, 09b-Training-unten.jpg, 03-Heute-unten.jpg
**Beobachtung:** Das Körperalter zählt „Krafttraining 137 min pro Woche · −1,2 Jahre“. Gleichzeitig sagt „Verlauf“ „Noch kein Training“, und „Diese Woche“ zeigt „Trainings 0 · noch keins · Volumen 0 kg“. Die 137 min kommen aus Health-Beispieldaten (`SampleData`, jeden zweiten Tag „Push/Pull/Beine“).
**Warum falsch:** Drei Bildschirme, zwei Wahrheiten. Ohne Quelle an der Zahl wirkt die App fehlerhaft.
**Lösung:** `Factor.valueText` mit Quelle: „137 min pro Woche · aus Apple Health und Forma“. In `weekTile` Health-Krafttrainings mitzählen und getrennt ausweisen („2 in Forma · 1 aus Health“). Oder den Titel ehrlich „Forma-Trainings“ nennen.

### C-01-15 · P1 · Körperalter · 14b-Körperalter.jpg, 03-Heute-unten.jpg
**Beobachtung:** „27,0 Jahre“, „3,0 Jahre jünger“, „Dein Alter: 30,0 Jahre“, „Richtung … 27,0 Jahre“. Überall steht eine Nachkommastelle.
**Warum falsch:** Das Modell hat eine eigene Dämpfung von 70 % (frei gewählt), Referenzwerte, die „eine Annahme“ sind (65 bpm, 7.000 Schritte), und Uhrwerte statt Laborwerten. Die echte Unsicherheit liegt nach meiner Einschätzung bei mehreren Jahren. „,0“ täuscht Präzision vor. „Dein Alter: 30,0 Jahre“ liest sich zudem seltsam.
**Lösung:** `BodyAgeText.years(_:decimals: 0)` überall. Den Unterschied auf ganze Jahre runden („etwa 3 Jahre jünger“). Dazu eine Spanne aus einer einfachen Sensitivitätsrechnung: Dämpfung 0,5 und 0,9 ergeben z. B. „26–28“, als `Text` unter der Hauptzahl in `textSecondary`. Das eigene Alter als ganze Zahl.

### C-01-16 · P1 · Körperalter · 14c-Körperalter-Faktoren.jpg
**Beobachtung:** „Wie sicher ist das? · Verlässlichkeit · Hoch · 180 von 180 Tagen mit Daten · 5 Faktoren“. `Confidence` hängt nur an Tagen und Faktorzahl, nicht an der Modellunsicherheit oder an angenommenem Alter und Geschlecht.
**Warum falsch:** „Verlässlichkeit hoch“ heißt für Laien „Ergebnis stimmt“. Gemessen wird aber nur die Datenmenge.
**Lösung:** Umbenennen in „Datenlage“ mit den Werten „Lückenhaft / Ausreichend / Vollständig“. Eine zweite Zeile, fest: „Genauigkeit des Modells: grob (± mehrere Jahre)“. Bei `origin == .assumed` oder `sex == .unknown` immer „Lückenhaft“.

### C-01-17 · P1 · Körperalter (Inhalt) · `Data/BodyAge.swift`
**Beobachtung:** Ich habe die Rechnung nachgerechnet. Sie stimmt mit dem Code überein: Kraft 0,7 × 8/ln 2 × ln 0,86 = −1,22 · Ruhepuls (53 − 65)/10 × ln 1,09 × 11,54 × 0,7 = −0,84 · VO₂max (46,8 − 45,2)/3,5 × ln 0,87 × 11,54 × 0,7 = −0,51 · Schritte −0,42 · Summe −2,99 → „3,0 jünger“. Auch die Effektgrößen passen nach meiner Kenntnis zu den Abstracts: Kodama 13 % je MET, Zhang 9 % je 10 bpm, Paluch HR 0,60/0,55/0,47, Cappuccio 1,12/1,30, Momma 10–17 % bei 30–60 min. Drei Probleme gibt es trotzdem:
1. **Ruhepuls:** Die Studien in Zhang 2016 messen überwiegend in Ruhe im Sitzen/Liegen bei der Untersuchung. Fitbit und Apple ermitteln den Ruhepuls aus Schlaf- bzw. Ruhephasen, und das liegt typischerweise niedriger. Der Vergleich mit 65 bpm verschiebt also systematisch Richtung „jünger“. Die genaue Größe kann ich nicht bestätigen.
2. **Schlaf:** Cappuccio stützt sich überwiegend auf *selbst berichtete* Schlafdauer. Die Uhr misst *tatsächlich geschlafene* Zeit, die meist kürzer ist als die selbst berichtete. „Unter 7 h“ gemessen ist also nicht dasselbe wie „unter 7 h“ berichtet. Das verschiebt Richtung „älter“.
3. **Langer Schlaf:** Bei 9 h gemessenem Schlaf rechnet die App +2,1 Jahre (ln 1,30 × 11,54 × 0,7). Der eigene Erklärtext sagt aber, die Ursache sei „oft eine Krankheit, nicht der Schlaf selbst“. Für einen Sportler in einer harten Trainingsphase ist diese Strafe falsch.
**Warum falsch:** Die Rechnung ist offen, aber sie vergleicht Äpfel (Uhr) mit Birnen (Studie) und bestraft einen Effekt, den sie selbst für nicht ursächlich hält.
**Lösung:** In `factors`: für langen Schlaf `logHazard = 0` bis 9,5 h, darüber nur ein Hinweis statt Jahren. Für Uhr-Schlafdauer die Schwelle auf 6,5 h senken und das als Annahme in `referenceText` nennen („Uhr misst kürzer als Selbstauskunft“). Für den Ruhepuls `referenceText` ergänzen: „Uhr misst meist niedriger als beim Arzt – Vorteil eher überschätzt“. Die Referenz auf 60 bpm senken oder den Faktor halbieren. Jede dieser Annahmen in „So wird gerechnet“ aufzählen.

### C-01-18 · P1 · Körperalter (Inhalt) · 14b-Körperalter.jpg
**Beobachtung:** „Krafttraining 137 min pro Woche · −1,2 Jahre“ gibt den vollen Bonus (gedeckelt ab 30 min). Der Text sagt: „Ob deutlich mehr noch mehr bringt, ist nicht geklärt.“ Momma et al. (2022) beschreiben aber eine **J-förmige** Kurve mit dem größten Vorteil bei etwa 30–60 min/Woche. Nach meiner Kenntnis wird der Zusammenhang bei deutlich höheren Umfängen schwächer. Die genaue Schwelle bitte im Original (Abb. 2) prüfen, ich kann sie nicht sicher bestätigen.
**Warum falsch:** Der Text verschweigt die J-Form. Gerade Kraftsportler (Zielgruppe) liegen fast alle weit über 60 min.
**Lösung:** Erklärtext ehrlich: „Am stärksten ist der Zusammenhang bei 30–60 min pro Woche. Bei viel mehr Training wird er in den Studien schwächer – das heißt nicht, dass mehr schadet, aber auch nicht, dass es mehr bringt.“ Rechnerisch weiter deckeln, den Wert aber in `referenceText` als „voller Bonus ab 30 min“ zeigen.

### C-01-19 · P1 · Körperalter (Faktoren) · 14c-Körperalter-Faktoren.jpg
**Beobachtung:** „Schlafdauer ±0 Jahre“ zeigt im `DivergingBar` einen orangen Strich (3 pt breit, `Theme.older`), weil `value < 0 ? younger : older` den Wert 0 als „älter“ einfärbt. Außerdem färbt `FactorRow` mit `BodyAgeText.color(factor.years)` (ungedämpft, Schwelle 0,5), zeigt aber den gedämpften Wert. „−0,4 Jahre“ bei Schritten ist grün, ein „−0,3“ wäre weiß.
**Warum falsch:** Ein neutraler Faktor sieht aus wie ein Nachteil. Farbe und Zahl folgen verschiedenen Regeln.
**Lösung:** `DivergingBar`: `if abs(value) < 0.05 { /* nur Mittellinie */ }`. In `FactorRow` beide Male `let shown = factor.years * BodyAge.overlapDamping` und `color(shown)` mit Schwelle 0,25.

### C-01-20 · P1 · Heute/Erholung/Schlaf · 01-Heute.jpg, `Theme.recovery`, `ScoreEngine`
**Beobachtung:** Erholung als Ampel mit Grenzen **67/34** und den Farben Neongrün/Gelb/Rot, Belastung 0–100 mit asymptotischer Sättigung, Stress „von 3“, Schlafbedarf aus Grundbedarf + Belastung + Schuld und „Bedarf zu 88 % gedeckt“. Jedes Einzelteil ist für sich vertretbar. Zusammen ist es das Bedienkonzept von Whoop: Ampel, Schwellen, Strain-Asymptote, Stress-Skala 0–3, Sleep Performance in %. Die genauen Whoop-Farbwerte kann ich nicht bestätigen, die Schwellen 67/34 und die Skala 0–3 sind dort aber typisch.
**Warum falsch:** AGENTS.md verlangt ausdrücklich „keine Kopie von Whoop … eigenständig“. Ein Kenner sieht es in zwei Sekunden.
**Lösung:** Eigene Sprache. Erholung als stufenlose Skala in **einer** Farbfamilie (z. B. von `#FF8A5B` über `#F5F5F7` nach `#3DDC97`, wie beim Körperalter), mit Worten „Zurückhalten / Normal trainieren / Bereit für mehr“ statt Ampel. Stress auf 0–100 oder ganz streichen (C-01-42). Schlaf zeigt „7 h 20 von 8 h 16“ statt Prozent. Die Bereiche aus der eigenen Verteilung ableiten (Perzentile deiner letzten 60 Tage) statt aus festen 67/34. Das ist auch fachlich besser.

### C-01-21 · P1 · HRV-Detail · 15-HRV.jpg
**Beobachtung:** `LineMark(...).interpolationMethod(.catmullRom)` schwingt über und unter die echten Messpunkte hinaus (sichtbar an den runden Bergen bei ~62 und ~50). Die letzte x-Beschriftung ist abgeschnitten („1?“ am rechten Rand, bei etwa x = 395 pt). Die x-Achse hat keine Gitterlinien, die y-Achse vier Werte (50–65) rechts in 11 pt `textTertiary` (≈ 3,3:1).
**Warum falsch:** Ein Gesundheitsdiagramm darf keine Werte zeigen, die nie gemessen wurden. Abgeschnittene Beschriftung wirkt unfertig.
**Lösung:** `.interpolationMethod(.monotone)` (überschwingt nicht) oder `.linear` plus `PointMark` je Tag in 4 pt. `.chartXScale(range: .plotDimension(padding: 12))`, `AxisMarks(values: .stride(by: .day, count: 7)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated), anchor: .top) }` mit `collisionResolution: .greedy`. Dazu `.chartXSelection(value: $selected)` mit `RuleMark` und Wertanzeige (siehe A8).

### C-01-22 · P1 · Heute/Gesundheit · 02, 14, 14e
**Beobachtung:** „Normal 53–59 ms“ ist dein Mittel ± 1 SD (`ScoreEngine.baseline`, Populations-SD, Untergrenze 4 % des Mittels). Bei einer Normalverteilung liegt also etwa ein Drittel *deiner normalen* Tage außerhalb von „Normal“. Dazu kommt Scheingenauigkeit: „Normal 6.754–9.573“ (Schritte), „431–605 kcal“, „7:02–7:37 h“. Die Erklärung steht nur ganz unten in 13 pt Tertiärtext (14e).
**Warum falsch:** Ein Wort mit medizinischem Klang, eine statistisch zu enge Spanne und Ziffern, die nach Laborwert aussehen.
**Lösung:** Beschriftung „Bei dir üblich“. Spanne = 25.–75. Perzentil der letzten 30 Tage, oder ± 1,0 SD beibehalten und dann „meist“ sagen. Runden: Schritte auf 100, kcal auf 10, Schlaf auf 5 min, im Format „7 h 00–7 h 35“ wie überall sonst (`Format.duration`). Die Erklärung als `accessibilityHint` und als Satz im Detail („Was der Wert bedeutet“).

### C-01-23 · P1 · Live-Training · 10-Live-Training.jpg
**Beobachtung:** Unter dem Übungsnamen steht entweder die Muskelgruppe oder `lastTime` als ein einziger Text. Pro Satz fehlt der Wert vom letzten Mal (Hevy: Spalte „Vorher“ „72,5 kg × 8“). Spalten: Satz 40 pt, kg flexibel, Wdh flexibel, RIR 36 pt. Zwischen „72,5“ (x ≈ 80 pt) und „8“ (x ≈ 195 pt) liegen über 100 pt Leerraum.
**Warum falsch:** Für progressive Überlastung ist der Satz-für-Satz-Vergleich *die* wichtigste Information im Studio. Die Tabelle verschenkt dafür Platz.
**Lösung:** In `exerciseBlock` eine Spalte „Vorher“ (`.frame(width: 84)`, `formaCaption`, `textSecondary`) aus `LiveSet.previous: (weight, reps, rir)?`. Antippen übernimmt die Werte in die Zeile (`.sensoryFeedback(.selection)`). kg und Wdh. bekommen feste Breiten (64 / 44 pt) statt `.infinity`. Spaltenköpfe „Satz · Vorher · kg · Wdh · Res.“.

### C-01-24 · P1 · Schlaf/Heute · 07-Schlaf-unten.jpg, 01-Heute.jpg
**Beobachtung:** „Ins Bett 22:28 · für einen Wecker um 6:55“. Die Weckzeit ist fest im Code (`CoachEngine.bedtime(wake: 6:55)`, Text in `SleepDetail`), im Profil gibt es dafür keine Einstellung. Dazu kommen 10 min Einschlafpuffer ohne Erklärung (6:55 − 8 h 16 − 10 min = 22:29).
**Warum falsch:** Eine persönliche Empfehlung mit einer fremden Weckzeit ist falsch für jeden, der nicht um 6:55 aufsteht.
**Lösung:** `@AppStorage("forma.wake") var wake: Double = 6.9 * 3600` mit `DatePicker("Aufstehen um", selection:, displayedComponents: .hourAndMinute)` im Profil und direkt in der Zeile „Ins Bett“ (Antippen → kleines Sheet mit `.presentationDetents([.height(280)])`). Untertitel: „Wecker 6:55 · inkl. 10 min zum Einschlafen“. Optional: Weckzeit aus HealthKit-Schlafplan, falls verfügbar.

### C-01-25 · P1 · Heute/Schlaf (Inhalt) · 01-Heute.jpg, `ScoreEngine.sleepDebt`
**Beobachtung:** Der Chip zeigt „Schlafschuld 1 h 19 min“. Gerechnet wird Summe(max(0, 7 h 45 − Schlaf)) der letzten 7 Nächte **÷ 3**. Das echte Defizit wäre also etwa 4 h, die Division durch 3 wird nirgends erklärt. Der Grundbedarf 7 h 45 gilt fest für alle. Der Schlafbedarf rechnet nur 25 % der Schuld ein.
**Warum falsch:** Eine Zahl, die als Fakt im Chip steht, ist eine erfundene Gewichtung.
**Lösung:** In „Heute Nacht“ eine Zeile „So entsteht der Bedarf“ mit allen drei Teilen: „Grundbedarf 7 h 45 + Belastung 12 min + Abbau Schlafschuld 20 min“. Den Grundbedarf im Profil einstellbar machen (7–9 h). Die Division durch 3 entweder streichen (dann ehrlich „4 h Defizit in 7 Nächten“) oder als „wir rechnen nur ein Drittel an, weil sich Schlaf nicht 1:1 nachholen lässt“ erklären und „geschätzt“ an den Chip schreiben.

### C-01-26 · P1 · mehrere · Tippziele
**Beobachtung (geschätzt bzw. aus Code):** `SampleDataBadge` als Button auf „Heute“: **26 pt** hoch. „Start“-Pille (`SmallPillButtonStyle`): **32 pt**. Reserve-Knöpfe: **40 × 36 pt**. `YesNoSwitch`: **34 pt**. Mini-Ringe im angehefteten Streifen: ≈ **22 × 30 pt** je Ring. Minus/Plus im Anpassen-Sheet: Symbol 22 pt ohne Rahmen. „… anpassen“-Knopf: ≈ **32 pt**.
**Warum falsch:** HIG: mindestens 44 × 44 pt. Im Studio sind die Hände nass oder in Handschuhen.
**Lösung:** `SmallPillButtonStyle`: `.frame(height: 32)` beibehalten, aber `.contentShape(Rectangle().inset(by: -6))` und `.frame(minHeight: 44)` außen. Reserve: `.frame(width: 52, height: 44)`, 5 Knöpfe × 52 + 4 × 6 = 284 pt passen. `YesNoSwitch` 44 hoch. `SampleDataBadge` als Button: `.frame(minHeight: 44)` mit `.contentShape`. `TileEditor`-Knöpfe: `.frame(width: 44, height: 44)`. Kompakt-Ringe: `.frame(minHeight: 44)` am Button.

### C-01-27 · P1 · Körperalter-Skala · 03-Heute-unten.jpg, 14-Gesundheit.jpg
**Beobachtung:** `AgeScale` über die volle Kartenbreite (≈ 338 pt), Spur 6 pt mit Verlauf mint → grau → orange, „Daumen“ 14 pt mit Schein und schwarzem Rand. Das sieht exakt aus wie ein iOS-`Slider`. Auf „Heute“ liegt er in einer antippbaren Karte.
**Warum falsch:** Falsche Affordance: Man versucht zu ziehen.
**Lösung:** Spur auf 4 pt, ohne Verlauf (nur `white.opacity(0.08)`). Den Punkt durch eine 2-pt-Marke von 14 pt Höhe in Ergebnisfarbe ersetzen, kein Schein. Unter der Skala links „jünger“ und rechts „älter“ in `formaMicro` statt nur „dein Alter“ in der Mitte. Auf „Heute“ weglassen und nur „27 · etwa 3 Jahre jünger“ zeigen (Kachel wird kürzer, siehe C-01-34).

### C-01-28 · P1 · Heute (Einblick) · 03-Heute-unten.jpg
**Beobachtung:** „Nach aktiven Tagen schläfst du 20 / min länger“: Zahl und Einheit sind auf zwei Zeilen getrennt. Die Aussage beruht auf 29 Nachtpaaren, ohne Gruppengrößen, ohne Streuung, mit `diff == 0` als „0 min länger“. Antippen öffnet den Coach, der dann über Erholung redet (C-01-06).
**Warum falsch:** Typografischer Fehler und eine Kausal-Formulierung („Nach … schläfst du“) bei einem kleinen, unkontrollierten Vergleich.
**Lösung:** In `Format.duration` geschützte Leerzeichen: `"\(m)\u{00A0}min"`, `"\(h)\u{00A0}h"`. `Insights.title` erst bei `abs(diff) >= 10` und je Gruppe ≥ 7 Nächten. Sonst „Kein klarer Unterschied“. Text: „An Tagen mit 8.000+ Schritten (12 Nächte) hast du im Mittel 20 min länger geschlafen als an ruhigeren (17 Nächte). Ein Zusammenhang, keine Ursache.“

### C-01-29 · P1 · Coach · 16-Coach.jpg
**Beobachtung:** Zwischen dem einzigen Satz (y ≈ 230–260 pt) und den Chips (y ≈ 710 pt) liegen **etwa 450 pt Leere**. Der Tagessatz ist nackter Text ohne Karte, Absender oder Zeit, also weder Chat noch Kachel. Die Chips laufen rechts hart ab („Was soll ich he…“), ohne Verlauf. Unten liegen drei Glasschichten übereinander: Chips, Eingabefeld, Tab-Leiste. Tippen auf die Coach-Kachel erzeugt zwei Coach-Blasen ohne eine Frage von dir.
**Warum falsch:** Der Bildschirm hat keine Hauptsache. Ein Chat, in dem der Coach mit sich selbst redet, wirkt kaputt.
**Lösung:** Oben eine Kontextkarte (`Plate`, 3 Mini-Ringe + „Heute: Push · Ziel 35–55“). Darunter den Tagessatz als erste Coach-Blase. Im leeren Zustand die 4 Vorschläge **vertikal** als Liste (je 44 pt, links ausgerichtet, `.buttonStyle(.plain)` mit Plate-Hintergrund) statt horizontal scrollender Glas-Chips. `consumePrompt` legt den Kachel-Text als **Nutzer**-Blase an („Erklär mir: …“) und antwortet passend zur Absicht (C-01-06). Die horizontalen Chips erst nach der ersten Nachricht, dann mit `.scrollClipDisabled()` und `.mask(LinearGradient)` am rechten Rand.

### C-01-30 · P1 · Heute · 01-Heute.jpg
**Beobachtung:** „Ziel 35–55“ und „Schlafschuld 1 h 19 min“ sind `InfoChip` aus `.glassEffect(.regular)`, 30 pt hoch, aber **nicht antippbar**. Daneben ist das ebenso gläserne `SampleDataBadge` antippbar.
**Warum falsch:** Liquid Glass bedeutet in iOS 26 „Bedienelement“. Zwei gleich aussehende Glas-Kapseln verhalten sich unterschiedlich.
**Lösung:** Entweder beide Chips zu Buttons machen (Ziel → `path.append(.ring(.strain))`, Schlafschuld → `.ring(.sleep)`, `.buttonStyle(.glass)`, `minHeight: 44`), oder Glas entfernen und als ruhige Zeile mit Symbolen in `textSecondary` setzen. Ich empfehle Buttons: Sie sind nützlich und liegen in der Daumenzone der Heute-Seite nach dem Scrollen.

### C-01-31 · P1 · Zusammenfassung · 13-Zusammenfassung.jpg, `WorkoutSummaryView`, `Progression`
**Beobachtung:** „Volumen 580 kg“, 1RM „91,8 kg“, Vergleich „… kg“ und der Steigerungshinweis „+2,5 kg: …“ sind fest mit kg verdrahtet, obwohl `app.weightUnit` lb erlaubt. Die Satzliste nutzt dagegen `Format.weight(…, unit:)`.
**Warum falsch:** Wer lb einstellt, sieht gemischte Einheiten. Das ist ein echter Fehler.
**Lösung:** Überall `Format.weight(value, unit: app.weightUnit)` plus `app.weightUnit.rawValue`. In `Progression.plan` den Hinweis ohne Einheit bilden oder die Einheit übergeben. Schrittweite in lb 5 lb (ist schon so), Text „+5 lb“.

### C-01-32 · P1 · Zusammenfassung (Inhalt) · 13-Zusammenfassung.jpg
**Beobachtung:** „Geschätztes Maximum (1RM) · Bankdrücken · 91,8 kg“ aus Epley (72,5 × (1 + 8/30)), obwohl der Satz mit „RIR 2“ erfasst wurde. Mit Reserve wären es 72,5 × (1 + 10/30) ≈ 96,7 kg. Die Nachkommastelle täuscht Genauigkeit vor. „1RM“ wird nicht erklärt. Ein neuer Bestwert wird in `Theme.recoveryHigh` (Erholungsgrün) gefärbt.
**Warum falsch:** Die erfasste Reserve ist die wertvollste Zusatzinformation und wird verworfen. Die Erholungsfarbe für „Bestwert“ verletzt Prinzip 3 („Farbe bedeutet etwas“).
**Lösung:** `OneRepMax.estimate(weight:reps:rir:)` = `epley(weight, reps + max(0, rir))`, nur bei `reps + rir <= 12`, sonst „–“. Auf 0,5 kg runden. Titel „Geschätztes Maximum“ mit Untertitel „für 1 Wiederholung“. Bestwert neutral hervorheben: `Image(systemName: "trophy.fill")` in `textPrimary` plus Animation (A5), keine Datenfarbe.

### C-01-33 · P1 · Zusammenfassung · 13-Zusammenfassung.jpg
**Beobachtung:** „Training löschen“ ist ein neutraler Glas-Knopf mit weißem Text (≈ 150 × 36 pt), mittig im Inhalt. `role: .destructive` wirkt mit `.buttonStyle(.glass)` hier nicht sichtbar. Die Rückfrage hat keinen Titel (`confirmationDialog` ohne `titleVisibility`).
**Warum falsch:** Eine zerstörerische Aktion sieht aus wie jede andere. Ein Fehltipp kostet ein Training.
**Lösung:** In die Toolbar als `Menu { Button("Training löschen", role: .destructive) … } label: { Image(systemName: "ellipsis") }`. Dialog mit `titleVisibility: .visible` und Text „Das lässt sich nicht rückgängig machen.“. Im Verlauf zusätzlich `.swipeActions` zum Löschen.

### C-01-34 · P2 · Heute · 01–03
**Beobachtung:** 8 Kacheln über ≈ 2,6 Bildschirmhöhen. „Körper“ ist identisch mit „Herz und Atmung“ auf „Gesundheit“, „Körperalter“ steht auf beiden Seiten, „Tag“ wiederholt „Aktivitäten heute“ der Belastung. Unterhalb der Ringe gibt es keine Hauptsache.
**Warum falsch:** Prinzip 2 „Eine Hauptsache pro Bildschirm“. „Heute“ soll eine Entscheidung erleichtern („Was mache ich heute?“), nicht alles zeigen.
**Lösung:** `TodayTile.defaultHidden = [.body, .bodyAge, .energy]`. Standardreihenfolge: Coach, Als Nächstes, Diese Woche, Einblick, Tag. Die ausgeblendeten Kacheln bleiben über „Heute anpassen“ erreichbar.

### C-01-35 · P2 · Heute · 01-Heute.jpg
**Beobachtung:** Die kleinen Ringe (88 pt) liegen mit ihrem Außenrand bei ≈ 14 pt vom Bildschirmrand, die Karten bei 16 pt. Der Schein (`shadow radius 8 pt`) läuft über den Rand. Der gestrichelte Zielbogen ist 1,5 pt breit, `white 0.6`, Strich 2,5/3,5. Auf dem Bild ist er kaum zu erkennen, obwohl er laut DESIGN.md eine feste Bedeutung hat.
**Warum falsch:** Unsauberes Raster am auffälligsten Element. Eine wichtige Markierung ist unter der Wahrnehmungsschwelle.
**Lösung:** `RingTrio` mit `.padding(.horizontal, 4)` innerhalb der 16-pt-Seitenkante, sodass der Ringrand bei 20 pt liegt. Zielbogen: `lineWidth: 2.5`, `opacity 0.85`, `dash: [3, 4]`, Abstand `lineWidth/2 + 6`. Alternativ den Zielbereich als hellere Spur *im* Ring (Track-Segment in `white 0.22`), ruhiger und eindeutiger.

### C-01-36 · P2 · alle · Typografie-Hierarchie
**Beobachtung:** Heldenzahlen sind uneinheitlich: Ring-Detail 64 pt Rounded, Körperalter 76 pt Rounded mit Schein, Metrik-Detail 48 pt **SF Pro** (nicht Rounded, 15-HRV), Zusammenfassungs-Werte 22 pt SF Pro, Heute „Tag“ 22 pt Rounded, Energie 40 pt Rounded. Im HRV-Detail steht „HRV“ als 13-pt-Label direkt unter dem Navigationstitel „HRV“. Der Übungstitel „Schrägbankdrücken Kurzhantel“ bricht in 28 pt bold auf zwei Zeilen um.
**Warum falsch:** DESIGN.md: „große Zahlen SF Pro Rounded“. Doppelte Titel kosten Platz und Ruhe.
**Lösung:** Drei Zahlentokens: `formaHero` (Detail-Held), `formaWidgetNumber` (Kachel), `formaStat` (22 pt Rounded, neu) und sonst keine. In `MetricDetailView` `.font(.formaHero)` und das Label entfernen (oder durch „Heute, 6:50“ ersetzen). Übungstitel `formaHeadline` (22 pt) mit `.lineLimit(2)` und `.minimumScaleFactor(0.85)`.

### C-01-37 · P2 · Erholung · 04-Erholung.jpg
**Beobachtung:** „Was beiträgt“ mischt in einer Spalte: „+4 ms“, „-1 bpm“ (Bindestrich statt Minuszeichen), „93“ (ein Punktwert, kein Unterschied) und „0,3“ (ohne Vorzeichen und ohne Einheit, obwohl der Balken nach links zeigt). Die Balken nutzen die Erholungsfarben Grün/Gelb für „hilft/bremst“.
**Warum falsch:** Man kann die Zeilen nicht vergleichen. Gelb heißt anderswo „mittlere Erholung“.
**Lösung:** In `contributions` einheitlich Unterschied zum Normalwert mit Vorzeichen und typografischem Minus: „+4 ms“, „−1 S/min“, „+0,3 /min“, „Schlaf 93 / 100“ als eigener Untertitel. Helfer `Format.signed(_:unit:)`. Balkenfarbe: hilft = `textPrimary`, bremst = `Theme.warning`. Das ist neutral und mit Bedeutung.

### C-01-38 · P2 · alle · Einheiten und Sprache
**Beobachtung:** „bpm“ (Englisch), „/min“ für Atemzüge (mehrdeutig), „Wdh“ ohne Punkt, „VO₂max“ ohne Erklärung auf Heute/Gesundheit, „HRV“ auf Heute ohne Erklärung, „Mittel erholt“ (holprig), „Trainings“ (umgangssprachlich).
**Warum falsch:** Der Auftrag lautet „Deutsch, keine Fachsprache ohne Erklärung“.
**Lösung:** `MetricKind.unit`: Ruhepuls „S/min“ (VoiceOver „Schläge pro Minute“ per `accessibilityLabel`), Atemfrequenz „Atemzüge/min“ in der Detailansicht und „/min“ nur in engen Zeilen. Untertitel erklären Kürzel einmal: „HRV · Herzschlag-Variabilität“. `recoveryWord`: „Gut erholt / Normal erholt / Wenig erholt“. „Trainings“ → „Einheiten“.

### C-01-39 · P2 · Schlaf · 06-Schlaf.jpg
**Beobachtung:** Das Hypnogramm nutzt `#3B66B8`, `#6E9BD8`, `#B9C8FF`, also Blau. Der Ring ist Lavendel `#8E8CFF`. Iteration 6 hat Schlaf gerade von Blau auf Lavendel umgestellt, *weil* es mit Belastung `#0093E7` verwechselt wurde.
**Warum falsch:** Die Entscheidung aus DESIGN.md wird im Detail unterlaufen.
**Lösung:** `Hypnogram.color`: Tief `#5A55D6`, Kern `#8E8CFF`, REM `#C9C7FF`, Wach `white 0.55`. Kontrast der Stufen untereinander prüfen, mindestens 1,4:1 zwischen Nachbarn.

### C-01-40 · P2 · Schlaf · 07-Schlaf-unten.jpg, 06-Schlaf.jpg
**Beobachtung:** „Letzte 7 Nächte“: Alle Balken sind fast gleich hoch (Skala 0–9,5 h, Werte 7,0–7,4 h). Die Farbkappe ist 3 pt, die x-Labels liegen in 11 pt Tertiär. Oben steht „Bedarf zu 88 % gedeckt“ neben dem Ring „93“. Zwei Prozentzahlen, die verschieden sind, ohne Erklärung.
**Warum falsch:** Das Diagramm trägt keine Information. Zwei Werte für „wie gut war mein Schlaf“ verwirren.
**Lösung:** Mit Swift Charts: `BarMark` je Nacht plus `RuleMark(y: need)` gestrichelt „Bedarf“. `chartYScale(domain: 5...9.5)` mit sichtbarer Achse „5 h / 7 h / 9 h“. Im Helden die Zeile „7 h 20 von 8 h 16 Bedarf“ statt %. Den Ring „Schlafqualität“ nennen und erklären, woraus er besteht (Dauer 60 %, Effizienz 20 %, Tief+REM 20 %).

### C-01-41 · P2 · Schlaf (Inhalt) · `ScoreEngine.sleepScore`
**Beobachtung:** Effizienz gibt die vollen 20 Punkte ab 95 %, Tief+REM die vollen 20 Punkte ab 45 % Anteil. Eine Nacht mit 88 % des Bedarfs ergibt so 93. Fast jede Nacht mit gutem Tracker liegt über 85.
**Warum falsch:** Ein Wert, der fast immer hoch ist, verliert seine Aussage (Deckeneffekt).
**Lösung:** Dauer quadratisch gewichten unter 90 % (`pow(ratio, 1.5) * 60`). Effizienz-Spanne 80–97 %, Tief+REM-Spanne 30–50 %. Dann an den letzten 30 Beispielnächten prüfen, dass die Werte von etwa 55 bis 95 streuen.

### C-01-42 · P2 · Heute (Energie und Stress) · 02-Heute-gescrollt.jpg
**Beobachtung:** „Energie 65“ mit 10 Segmenten, „Stress 1,1 von 3 · geschätzt“. Die Energie sinkt laut Code einfach mit der Uhrzeit (`dayFatigue = (Stunde − 8) × 1,4`), Stress steigt mit der Belastung (Sport zählt als Stress). Die Kachel ist nicht antippbar und hat kein „So wird gerechnet“. Die Segmentleiste rundet ab (65 → 6 Segmente).
**Warum falsch:** Zwei erfundene Größen ohne Erklärung. Das widerspricht Prinzip 4 („Jede Zahl mit Bezug“) und 10 („Ehrlichkeit“).
**Lösung:** Standardmäßig ausblenden (C-01-34). Wenn sie bleibt: Antippen → Sheet mit Formel und Hinweis „Uhrzeit-Abzug: je Stunde nach 8 Uhr −1,4“. Stress ohne Belastungsanteil (nur HRV/Ruhepuls-Abweichung). Segmente mit `Int((Double(energy)/10).rounded())`.

### C-01-43 · P2 · Training · 09-Training.jpg
**Beobachtung:** „Harte Sätze diese Woche“: fünf Zeilen mit „0“ und Strichen (leerer Zustand ohne Text), ≈ 245 pt Höhe. Der Richtwert „10 Sätze pro Woche“ hat keine Quelle und steckt fest bei `n / 20`. Muskelgruppen sind fest (keine Waden, kein Bauch). „Arme“ fasst Bizeps und Trizeps zusammen.
**Warum falsch:** Leere Nullreihen sind Rauschen. Ein Richtwert ohne Quelle widerspricht der eigenen Ehrlichkeitsregel.
**Lösung:** Leerer Zustand: eine Zeile „Diese Woche noch keine harten Sätze. Ab dem ersten Training siehst du hier, welche Muskeln genug bekommen.“ Quelle als Fußnote: „Richtwert ≥ 10 Sätze: Schoenfeld et al., J Sports Sci 2017“. Bitte vor dem Einbau prüfen, das kann ich nicht wörtlich bestätigen. Bereich statt Strich: 10–20 als helleres Band. Gruppen aus `Exercise.muscle` dynamisch ableiten.

### C-01-44 · P2 · Training · 09b-Training-unten.jpg
**Beobachtung:** „Freies Training“ steckt als zweite Zeile in der Kachel „Bibliothek“, ganz unten (y ≈ 650 pt nach dem Scrollen). „Übungsbibliothek“ wiederholt den Kachel-Titel „Bibliothek“.
**Warum falsch:** Ein Hauptweg in das Kernfeature ist versteckt. Doppelte Beschriftung.
**Lösung:** In `nextCard` unter „Training starten“ einen zweiten Knopf `Button("Ohne Routine starten") {…}.buttonStyle(.glass).controlSize(.large)`. In der Bibliothek-Kachel nur noch eine Zeile „Übungen“.

### C-01-45 · P2 · Live-Training · 10-Live-Training.jpg, 12-Nächster-Satz.jpg
**Beobachtung:** Das Dock hat 8 pt Seitenabstand (`.padding(.horizontal, Space.s2)`), die Inhalte 16 pt: Die Kanten fluchten nicht. Unter dem Dock (y ≈ 860–874 pt) ist gescrollter Inhalt sichtbar („3 · 26 · 10“). Das Dock verdeckt mit ≈ 200 pt (mit Reserve-Zeile) den Titel der nächsten Übung. Der Abstandhalter `Color.clear.frame(height: 300)` ist geraten.
**Warum falsch:** Unsaubere Kanten. Inhalt, der unter einem schwebenden Element „durchschaut“, wirkt unfertig.
**Lösung:** `.padding(.horizontal, Space.page)` am Dock. `.scrollEdgeEffectStyle(.hard, for: .bottom)` (iOS 26) am `ScrollView`. Statt fester 300 pt `.contentMargins(.bottom, dockHeight + 16, for: .scrollContent)` mit per `onGeometryChange` gemessener Dockhöhe. Beim Scrollen zum aktiven Satz `anchor: UnitPoint(x: 0, y: 0.25)` statt `.top`.

### C-01-46 · P2 · Live-Training · 12-Nächster-Satz.jpg
**Beobachtung:** Die Gewichtsschritte sind fest ±2,5 kg für alle Übungen, auch für Kurzhanteln und Kabel. Der Scheibenrechner `plateText` steht im Code, ist im Screenshot bei „Bankdrücken 72,5“ aber nicht zu sehen. Das hängt an `equipment == "Langhantel"` per Namensvergleich. Ich kann nicht bestätigen, ob die Seed-Daten hier „Langhantel“ setzen.
**Warum falsch:** Kurzhanteln gibt es oft in 2-kg- oder 1-kg-Schritten. Ein Feature, das nicht erscheint, ist keins.
**Lösung:** `Exercise.increment: Double` (Langhantel 2,5, Kurzhantel 2, Kabel/Maschine 5, eigenes Feld im Editor). Langes Drücken auf ± öffnet einen Zahlenblock (`.sheet` mit `TextField(.decimalPad)`). Scheibenrechner per Exercise-ID statt Namen, und im UI-Rundgang prüfen, dass „Pro Seite: 20 + 5 + 1,25“ erscheint.

### C-01-47 · P2 · Heute anpassen · 03b-Heute-anpassen.jpg
**Beobachtung:** „Standard“ steht links an der Stelle von „Abbrechen“ und setzt **ohne Rückfrage** alles zurück. Das Sheet hat `.presentationBackground(.thinMaterial)` und wirkt dadurch flach-grau statt wie ein iOS-26-Glas-Sheet. Die Fußzeile „Ziehen zum Sortieren. Tipp: …“ ist Bedienungsanleitung.
**Warum falsch:** Eine zerstörerische Aktion sitzt an der Stelle, die man reflexhaft zum Schließen drückt.
**Lösung:** Links nichts (bzw. nur „Fertig“ rechts). Am Listenende `Section { Button("Standard wiederherstellen", role: .destructive) { confirm = true } }` mit `confirmationDialog`. `.presentationBackground` entfernen (Systemglas). Fußzeile kürzen: „Lange drücken auf einer Kachel geht auch.“

### C-01-48 · P2 · Heute (Coach-Kachel) · 01-Heute.jpg
**Beobachtung:** Das Accessory „Antippen zum Fragen“ (13 pt Tertiär, ≈ 3,3:1) ist Bedienungsanleitung im Inhalt.
**Warum falsch:** Gute Oberflächen erklären sich durch Form, nicht durch Text.
**Lösung:** Accessory entfernen, stattdessen rechts in der Kopfzeile `Image(systemName: "bubble.left")` oder ein Chevron. `accessibilityHint` bleibt.

### C-01-49 · P2 · Heute · 01-Heute.jpg, `TodayView.toolbar`
**Beobachtung:** Datum und Badge stehen als eigene `HStack` unter dem Large Title, mit ≈ 52 pt Luft zwischen Title-Grundlinie und Ringen. Die Toolbar enthält einen unsichtbaren `Text("Heute").opacity(0)` als Platzhalter.
**Warum falsch:** Ein Hack statt Systemverhalten. iOS 26 bietet dafür `navigationSubtitle`.
**Lösung:** `.navigationSubtitle(Format.dayTitle(.now))`, Badge als `ToolbarItem(placement: .topBarLeading)` oder in die Subtitle-Zeile. Den `principal`-Platzhalter entfernen: `if showCompactRings { compactRings }` reicht.

### C-01-50 · P2 · Coach · `CoachView.send`
**Beobachtung:** Der Fehlertext lautet „(Claude war nicht erreichbar: Claude antwortet mit Fehler 400.)“, also technisch, in Klammern und an eine lokale Antwort angehängt. Ein Ladezustand ist nur ein `ProgressView()` ohne Text.
**Warum falsch:** Statuscodes sind keine Nutzersprache.
**Lösung:** Fehler abbilden: 401/403 → „Dein API-Schlüssel passt nicht. Prüf ihn im Profil.“, kein Netz → „Keine Verbindung. Ich antworte erst mal mit den Daten auf dem iPhone.“, 429/5xx → „Claude ist gerade ausgelastet.“. Ladezustand als Coach-Blase mit drei animierten Punkten (`.symbolEffect(.variableColor.iterative)` auf `ellipsis`).

### C-01-51 · P2 · alle · VoiceOver und Bewegung
**Beobachtung:** `DayBars`, `Sparkline`, `RangeBar`, `DivergingBar`, `AgeScale` sind `accessibilityHidden(true)`, ohne Ersatztext. Die 7-Tage-Werte sind für VoiceOver also nicht vorhanden. Der Swift-Charts-Verlauf hat keinen `accessibilityChartDescriptor`. Es gibt nirgends `accessibilityReduceMotion`: Ringe federn 1,1 s, der Lichtschein blendet 0,8 s.
**Warum falsch:** Die Daten sind der Kern der App und für Blinde unsichtbar. „Bewegung reduzieren“ wird ignoriert.
**Lösung:** An jeder Kachel mit Grafik `.accessibilityElement(children: .combine)` plus `accessibilityValue("Montag 54, Dienstag 61, … heute 78")`. In `MetricDetailView` `.accessibilityChartDescriptor(self)` (`AXChartDescriptorRepresentable`). `@Environment(\.accessibilityReduceMotion)` in `RingTrio`/`DetailHero`/`ScreenBackground`: Animation dann `.none` bzw. `.easeOut(0.2)` als reine Überblendung.

### C-01-52 · P2 · Körperalter (Quellen) · 14d-Körperalter-Methode.jpg
**Beobachtung:** Der Kaminsky-Link führt auf eine **PubMed-Suche**, nicht auf die Arbeit. „Gompertz-Gesetz“ verlinkt die englische Wikipedia. Im Text spricht die App von sich in der Ich-Form („vergleiche ich“), anderswo neutral. Die „Richtung“-Karte heißt „Nur die letzten 30 Tage“, das liest sich wie ein Filter, nicht wie ein Trend.
**Warum falsch:** Eine Quellenliste, die auf eine Suche zeigt, ist keine Quelle. Uneinheitliche Stimme.
**Lösung:** Kaminsky et al., Mayo Clin Proc 2015, mit direkter DOI oder PubMed-ID verlinken (bitte nachschlagen, ich gebe hier keine ID aus dem Gedächtnis an). Für Gompertz eine Übersichtsarbeit oder die deutsche Wikipedia. Ich-Form nur im Coach. Hier „Forma vergleicht …“. „Richtung“ → Titel „Letzte 30 Tage“, Wert „27 (gleich)“ bzw. „26 (↓ 1)“.

### C-01-53 · P3 · Heute · 01-Heute.jpg
**Beobachtung:** Reihenfolge der Ringe: Belastung – Erholung – Schlaf.
**Warum (Geschmack):** Die Ursachenkette eines Morgens ist Schlaf → Erholung → Belastung. Diese Reihenfolge erzählt die Geschichte von links nach rechts.
**Lösung:** `RingKind.allCases` als `[.sleep, .recovery, .strain]`. Achtung: Die Reihenfolge des kompakten Streifens und die VoiceOver-Reihenfolge ändern sich mit.

### C-01-54 · P3 · Heute/Detail · `ScreenBackground`
**Beobachtung:** Grüner Schein mit `opacity 0.20` über 520 pt Höhe. Auf dem Bild wirkt das obere Drittel neongrün (01, 02, 03). Zusammen mit `#16EC06` wirkt es eher „Gaming“ als „ruhig“.
**Lösung:** `strength` auf 0,12 (Gelb 0,08). Die Schein-Farbe um 20 % in Richtung Grau mischen (`tint.mix(with: .gray, by: 0.2)`, iOS 18+). Den Schein beim Scrollen mit `.visualEffect { $0.opacity(1 - scrollOffset/300) }` ausblenden.

### C-01-55 · P3 · Tab-Leiste · alle
**Beobachtung:** „Heute“ nutzt `circle.circle`, ein generisches Symbol ohne Bezug. Der Coach nutzt das schwere `bubble.left.and.text.bubble.right`.
**Lösung:** „Heute“ → `sun.horizon` oder ein eigenes Symbol mit drei Ringen (SF-Symbols-Vorlage). Coach → `bubble.left.and.text.bubble.right` durch `text.bubble` ersetzen. Zusätzlich `Tab(role: .search)` nicht nötig. Bei Gelegenheit `tabViewBottomAccessory` für ein laufendes Training nutzen (siehe Feature F8).

---

## Feature-Vorschläge
Alle ohne App-Extensions (kein WidgetKit, keine Live Activity), rein in der App-Target, in SwiftUI/SwiftData. Bei HealthKit-Funktionen gilt der offene Punkt aus AGENTS.md: Mit kostenloser Apple-ID per Sideloadly ist HealthKit nicht bestätigt.

| # | Feature | Nutzen für Kraftsportler | Aufwand |
|---|---|---|---|
| F1 | **„Vorher“-Spalte + Doppel-Progression je Satz.** Pro Satz letzter Wert („72,5 × 8 · 2 Res.“), Antippen übernimmt ihn. Regel: Wdh.-Ziel als Bereich (z. B. 6–10). Wenn alle Sätze am oberen Ende mit ≥ 1 Reserve liegen → Gewicht + Schritt, Wdh. zurück auf unteres Ende. Ersetzt die heutige Pauschalregel (+2,5 kg). | Der wichtigste Studio-Moment: „Was muss ich heute schlagen?“ Ohne Kopfrechnen. | M (2–3 Tage): `LiveSet.previous`, `RoutineItem.repRange`, Logik in `Progression`. |
| F2 | **Kraft-Verlauf je Übung.** Swift-Charts-Linie des geschätzten Maximums (mit Reserve, C-01-32), Bestwerte je Wdh.-Zahl (1–12 „Rep-PRs“), Volumen pro Woche, Scrubbing per `chartXSelection`. | Fortschritt sichtbar machen ist der stärkste Motivator. Stagnation früh erkennen. | M: `ExerciseDetailView` erweitern, Daten liegen schon in `SetRecord`. |
| F3 | **Muskel-Wochenbilanz mit Bereichen.** Harte Sätze je Muskel mit persönlichem Zielband (z. B. 10–20), Ampel nur am Rand, Vorschau „mit heutigem Push: Brust 12“. | Plant die Woche, verhindert vergessene Muskelgruppen. | S–M: Kachel aus C-01-43 ausbauen. |
| F4 | **Krafttraining zählt in die Belastung (Session-RPE).** Dauer × Anstrengung aus der Reserve, kombiniert mit Herzfrequenz aus Health im Trainingsfenster (falls vorhanden). Wochenlast mit Verhältnis „diese Woche zu den letzten 4“. | Belastungsring und Zielbereich werden für Kraftsport überhaupt erst sinnvoll (C-01-13). Warnung bei plötzlichem Lastsprung. | M: `ScoreEngine.strain` + Fenster-Abfrage `HKQuantityType(.heartRate)`. |
| F5 | **Deload- und Ermüdungshinweis.** Wenn das geschätzte Maximum in 2–3 Kernübungen zweimal in Folge fällt **und** der Ruhepuls-Trend 5 Tage über dem Normalwert liegt (oder die Erholung im 7-Tage-Mittel < 40) → Vorschlag „leichte Woche: −1 Satz, −10 %“. Wie die heutige Anpassung nur mit Bestätigung. | Nutzt genau die Kombination, die Forma als einzige App hat: Kraftdaten **und** Erholungsdaten. Echte Differenzierung zu Hevy. | M: Regel in `CoachEngine`, Anzeige als Vorschlagskarte. |
| F6 | **Aufwärm-Rechner + Scheibenrechner für alle Hanteltypen.** Aus dem ersten Arbeitssatz automatisch 2–4 Aufwärmsätze (z. B. Stange × 10, 50 % × 5, 70 % × 3, 85 % × 1), Scheiben je Seite im Dock, eigene Scheiben-Ausstattung im Profil. | Spart Kopfrechnen bei jedem Training. Gestaltung wie Apple: unaufdringlich im Dock. | S: `PlateMath` erweitern, „Aufwärmsätze einfügen“-Knopf im Übungsblock. |
| F7 | **Pausen, die man hört und fühlt.** Haptik + Ton bei 0:00 im Vordergrund, Mitteilung im Hintergrund (C-01-10), Pausendauer je Übungsart (Grundübung 3 min, Isolation 90 s) und automatisch länger bei Reserve 0. | Der häufigste Ärger in Trainings-Apps. Klein, aber täglich spürbar. | S. |
| F8 | **Laufendes Training im Hintergrund + Schnellstart.** Statt `fullScreenCover` ein minimierbares Training: `tabViewBottomAccessory` (iOS 26) mit „Push · 23:14 · Pause 1:12“, Antippen öffnet wieder. Dazu **Home-Bildschirm-Schnellaktionen** (`UIApplicationShortcutItem`, kein Extension-Target nötig) „Nächstes Training starten“ und **App Shortcuts** (App Intents im App-Target) „Hey Siri, starte Push in Forma“. Ob App Intents beim Sideloading mit kostenloser Apple-ID funktionieren, kann ich nicht bestätigen. | Zwischen den Sätzen Journal/Erholung ansehen, ohne das Training zu verlieren. Start mit einer Geste. | M: Architektur von `app.liveWorkout` auf minimierbaren Zustand umbauen. Schnellaktionen S. |

Bewusst nicht vorgeschlagen: Apple-Watch-App (wäre ein eigenes Target), Widgets/Live Activities (Extensions), Ernährung (nicht Kern).

---

## Animations-Vorschläge
Grundregel: Bewegung erklärt einen Zustandswechsel oder eine Herkunft. Alles hinter `@Environment(\.accessibilityReduceMotion)`. Kein Konfetti, kein Dauerpulsieren.

| # | Ort | Was | SwiftUI-API |
|---|---|---|---|
| A1 | Ring antippen → Ring-Detail | Der Ring wächst in den großen Detail-Ring (Herkunft sichtbar). | `@Namespace var ns`. In `RingTrio`: `.matchedTransitionSource(id: kind, in: ns)` am `RingView`. In `navigationDestination`: `RingDetailView(kind:).navigationTransition(.zoom(sourceID: kind, in: ns))`. Gleiches für Körperalter-Kachel → Detail und Metrik-Zeile → Metrik-Detail. |
| A2 | „Training starten“ → Live-Training | Der Knopf zoomt in den Vollbildmodus, beim Beenden zurück. | `.matchedTransitionSource(id: "start", in: ns)` am Knopf, `.navigationTransition(.zoom(sourceID: "start", in: ns))` am Inhalt von `fullScreenCover`. |
| A3 | Abhaken eines Satzes | Der Haken zeichnet sich, der Kreis füllt sich, die Zeile dimmt, die nächste Zeile bekommt die Markierung. | `Image(systemName: "checkmark").transition(.symbolEffect(.drawOn))` (iOS 26), Kreis `.contentTransition(.symbolEffect(.replace))` von `circle` zu `checkmark.circle.fill`. Aktiv-Markierung per `matchedGeometryEffect(id: "active", in: ns)`. Dazu `.sensoryFeedback(.success, trigger:)` (vorhanden). |
| A4 | Stepper kg/Wdh. | Zahl rollt in Richtung der Änderung, fühlbarer Raster-Klick. | `.contentTransition(.numericText(value: weight))` (vorhanden) + `.sensoryFeedback(.increase, trigger: weight)` bzw. `.decrease`, mit `.buttonRepeatBehavior(.enabled)` (vorhanden) gedrosselt auf ≤ 10 Hz. |
| A5 | Neuer Bestwert (Zusammenfassung) | Pokal springt einmal, Zeile hebt sich kurz an. | `Image(systemName: "trophy.fill").symbolEffect(.bounce, value: isPR)` + `keyframeAnimator` (scale 1 → 1.04 → 1, 0,5 s) + `.sensoryFeedback(.success, trigger: isPR)`. |
| A6 | Trainings-Dock: Satz ↔ Pause | Die Knöpfe morphen statt hart zu wechseln: „Satz abschließen“ wird zu „Überspringen“, die Stepper verschwinden weich. | Dock als `GlassEffectContainer(spacing: 8)`, Knöpfe mit `.glassEffect(.regular.interactive())` und `.glassEffectID("primary", in: ns)`. Zustandswechsel mit `withAnimation(.smooth(duration: 0.35))`, Inhalte `.transition(.blurReplace)`. |
| A7 | Pausenring | Flüssig statt Sekundensprüngen. Bei 0:00 ein kurzes Aufleuchten. | `TimelineView(.animation)` für die Ringfraktion. Ende: `.phaseAnimator([1, 1.06, 1], trigger: restFinished)` + `.sensoryFeedback(.impact(weight: .heavy), trigger: restFinished)`. |
| A8 | Verlaufsdiagramme (HRV, VO₂max, Kraft) | Finger über das Diagramm ziehen zeigt Tag und Wert, mit fühlbaren Stufen pro Tag. | `.chartXSelection(value: $selectedDate)` + `RuleMark` + Annotation. `.sensoryFeedback(.selection, trigger: selectedDate)`. Bereichswechsel 7/14/30 Tage mit `.animation(.smooth, value: range)`. |
| A9 | Kacheln beim Scrollen | Sehr dezentes Einblenden am unteren Rand, nicht oben (sonst unruhig). | `.scrollTransition(.animated(.smooth), axis: .vertical) { c, phase in c.opacity(phase == .bottomTrailing ? 0.6 : 1).scaleEffect(phase == .bottomTrailing ? 0.98 : 1) }`. |
| A10 | Großer Ringstreifen → angehefteter Mini-Streifen | Die großen Ringe schrumpfen beim Scrollen kontinuierlich, statt bei 250 pt plötzlich zu springen. | `.visualEffect { content, proxy in let y = proxy.frame(in: .scrollView).minY; return content.scaleEffect(max(0.6, 1 + y/600), anchor: .top).opacity(…) }` auf `rings`. Erst wenn sie fast weg sind, Mini-Streifen mit `.transition(.scale.combined(with: .opacity))`. |
| A11 | Synchronisierung / Warte auf Fitbit | Das Sync-Symbol dreht sich nur, solange wirklich geladen wird. | `Image(systemName: "arrow.triangle.2.circlepath").symbolEffect(.rotate, isActive: hub.isRefreshing)`. Neue Werte in Kacheln: `.contentTransition(.numericText(value:))` auf allen Zahlen (`MetricRow.value`). |
| A12 | Hypnogramm | Die Nacht zeichnet sich einmal von links nach rechts (0,6 s), nur beim ersten Öffnen. | `.mask(alignment: .leading) { Rectangle().frame(width: progress * w) }` mit `withAnimation(.easeOut(duration: 0.6))` in `.onAppear`. Bei Reduce Motion direkt voll. |
| A13 | Kachel ziehen/ablegen | Fühlbares Andocken. | `.sensoryFeedback(.impact(flexibility: .soft), trigger: dropTarget)` in `TileStack`. Die Rahmen-Hervorhebung mit `.animation(.snappy, value: dropTarget)`. |

Wo **keine** Animation hin soll: Lichtschein beim Scrollen (kein Parallax), Zahlen ohne Datenänderung, Tab-Wechsel (Systemverhalten lassen), Coach-Text (kein Tippmaschinen-Effekt bei lokalen Antworten).

---

## Was bleiben soll
- **Transparenz beim Körperalter:** Methode, Gompertz-Umrechnung, offen benannte 70-%-Dämpfung, der Satz „HRV fließt nicht ein: Apple misst SDNN, Fitbit RMSSD“ und die Quellenliste. Das ist besser als bei jeder mir bekannten Konkurrenz. Die nachgerechneten Effektgrößen passen (C-01-17). Nur die Eingaben (Alter, Uhr- vs. Studienwerte) und die Präzision müssen ehrlicher werden.
- **Name „Körperalter“** statt „biologisches Alter“: bescheiden und richtig.
- **Daumenzone im Live-Training:** Stepper mit 44-pt-Plus/Minus, 52-pt-Primärknopf, Satz-Nummer im Knopf („Satz 1 abschließen“), Wiederholen bei gedrückter Taste (`buttonRepeatBehavior`). Und dass ein unterbrochenes Training wiederhergestellt wird (`LiveWorkout.restore`).
- **Coach-Vorschläge nur mit Bestätigung** und der Satz „Deine gespeicherte Routine bleibt unverändert.“: genau die richtige Haltung.
- **Beispieldaten-Kennzeichnung** auf jedem Hauptbildschirm.
- **Neutrales Schwarz `#030303`** und die matte Plate mit Lichtkante (7,5 → 3,5 %, Rand 0,75 pt). Ruhig, hochwertig, kein Glas auf Inhalt in den Karten.
- **Schlafdetail:** Hypnogramm plus Phasenleiste plus Legende mit Dauer ist eine sehr gute Informationsarchitektur (nur die Farben anpassen, C-01-39). Die Zahlen sind stimmig: 1 h 40 + 1 h 38 + 4 h 2 = 7 h 20, plus 18 min wach = 7 h 38 im Bett, also 96 % Effizienz.
- **Ringe mit gestaffelter Animation nur bei neuen Werten** (`forma.lastRings`) und `contentTransition(.numericText)` in den Ringen.
- **Kacheln mit drei Wegen zum Anordnen** (Ziehen, Kontextmenü, Liste) und das Anhängen neuer Kacheln aus Updates. Technisch sauber gelöst.
- **Minimierende Tab-Leiste** (`tabBarMinimizeBehavior(.onScrollDown)`): richtiges iOS-26-Verhalten.
- **„Ins Bett um …“ in „Als Nächstes“:** eine handlungsleitende Zeile statt einer weiteren Zahl. Mehr davon.
