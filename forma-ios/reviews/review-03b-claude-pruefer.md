# Review 03b – unabhängiger Claude-Prüfer (Ersatz, bis Codex Runde 03 läuft) – 18.11.2026
Geprüfter Commit: `36bb341`

Prüfbasis: Code unter `forma-ios/Forma/**`, `FormaTests/**`, `FormaUITests/ScreenTour.swift`, Workflow `.github/workflows/forma-ios.yml`, die letzten acht Commits (`git show`), CI-Lauf 44396675307 für `36bb341` (Logs über `gh run view`) und alle 25 Bilder in `docs/forma-screens/`.

**Wichtig vorab:** Laut `HERKUNFT.txt` stammen alle Bilder aus Build `23c51a0`. Das ist der Stand **vor** dem Umbau `37668d4` (Journal, alte Ringdetails, alte Profilseite). Für `36bb341` hat die CI **keine** Bilder veröffentlicht: Der UI-Rundgang ist dort fehlgeschlagen. Der Workflow ist trotzdem grün (siehe C-03-06). Jede Aussage zu Bildern betrifft deshalb einen veralteten Stand. Was ich nur aus Code ableite, steht als „laut Code“ da. Am Gerät habe ich nichts geprüft.

## Gesamturteil

Die Synchronisierung aus Runde 02 ist im Kern solide gebaut. Dazu gehören Merge pro Messreihe, gebündelte Abrufe, `generation` und `draftID`. Danach hat der Umbau `37668d4` aber mehrere ✅-Punkte aus `review-02-antwort.md` stillschweigend wieder zurückgedreht: die Coach-Schalter, die Weckzeit, das Entfernen des Claude-Schlüssels, die Erklärungen zur Berechnung und die Kennzeichnung als Schätzung. Der Commit sagt selbst „noch ungeprüft vom Compiler“, und sein CI-Lauf ist rot.

Noten (Bilder aus `23c51a0`, Code aus `36bb341`):

| Bildschirm | Note | Kurz |
|---|---:|---|
| Heute · 01/02 | 6 | 02 ist ein exaktes Duplikat von 01: Der Rundgang scrollt nicht |
| Heute unten / anpassen · 03/03b | 6 | Demo zeigt „Trainings 0“, das Körperalter aber 137 min Kraft pro Woche |
| Erholung · 04/05 | 5 | „Schlafs-core“ und umbrechende Beitragsspalte. Im Code (HEAD) ist „Was beiträgt“ entfernt |
| Schlaf · 06/07 | 6 | Gut lesbar. In HEAD zwei verschiedene „Bedarf“-Werte auf einer Seite, Bettzeit ohne Hinweis auf den angenommenen Wecker |
| Belastung · 08 | 6 | In HEAD „Keine Recovery“ (Englisch) |
| Training · 09/09b | 7 | Ruhig, klare Hauptaktion |
| Live / Pause / Satz · 10–12 | 6 | Spaltenkopf „RIR“ neben „Reserve“ im Dock: zwei Begriffe für eine Sache |
| Zusammenfassung · 13 | 6 | Speichert eine Einheit mit 1 von 19 Sätzen ohne Rückfrage. „Training löschen“ nicht als destruktiv gestaltet |
| Gesundheit · 14/14e | 5 | Bereiche brechen um („13,7–⏎14,9 /min“). In HEAD heißt der Tab „Health Age“ |
| Körperalter · 14b–14d | 6 → HEAD 4 | Bild: gute Methode und Quellen. HEAD: Methode, fehlende Faktoren und Datenabdeckung entfernt, neues Diagramm übertreibt |
| HRV · 15 | 7 | Klar |
| Coach · 16/17 | 5 | Antwort „Die Weckzeit stellst du im Profil ein“: In HEAD gibt es diese Einstellung nicht mehr |
| Journal · 18 | – | In HEAD entfernt. Die gespeicherten Antworten bleiben unsichtbar in SwiftData liegen |
| Profil · 19 | 4 (HEAD) | Coach-Schalter, Weckzeit und Schlüssel-Verwaltung entfernt |

**Die 5 wichtigsten Punkte**
1. **Regression durch `37668d4`:** Morgenbericht und Bettzeit sind standardmäßig an und lassen sich in der App nicht mehr ausschalten. „Werte in Mitteilungen zeigen“ und die Weckzeit sind weg. Der Coach verweist auf eine Einstellung, die es nicht mehr gibt (C-03-01).
2. **Ein Claude-Schlüssel aus einer früheren Version kann nicht mehr entfernt werden.** Der externe Pfad bleibt damit aktiv. Die Health-Freigabe behauptet „Die Daten bleiben auf deinem iPhone“ (C-03-02, C-03-09).
3. **Zeitzonenwechsel nach Westen verschiebt den ganzen Cache um einen Kalendertag.** Bei Teilimporten wird diese Verschiebung dauerhaft gespeichert (C-03-03).
4. **Transparenz rückgebaut:** Ringberechnung, Beiträge, Körperalter-Methode, fehlende Faktoren und „Schätzung, nicht validiert“ an der Hauptkachel sind entfernt. Das neue 30-Tage-Diagramm bläst Differenzen unter einem Jahr auf volle Höhe auf (C-03-07, C-03-08).
5. **CI meldet grün, obwohl der UI-Rundgang auf HEAD fehlschlägt.** Plus-Tab aktiv, Sleep/Strain-Detail nicht gefunden. Die Bilder sind veraltet. R-02-23 ist damit widerlegt (C-03-06).

## Befunde

### C-03-01 · P0 · Profil, Coach, Sperrbildschirm · 17-Coach-Antwort.jpg, 19-Profil.jpg
Beobachtung: `37668d4` hat in `ProfileView` die Toggles „Morgenbericht“, „Erinnerung zur Schlafenszeit“ und „Werte in Mitteilungen zeigen“ entfernt, ebenso den DatePicker „Weckzeit“ (siehe `git show 37668d4 -- …/ProfileView.swift`). Heute stehen in `ProfileView.swift:100-114` nur noch „Mitteilungen erlauben“ und „iOS-Einstellungen öffnen“. `CoachNotifier.swift:18-19` setzt beide Funktionen standardmäßig auf an. `CoachNotifier.swift:20` liest `showValues` weiterhin. Wer den Schalter früher eingeschaltet hat, bekommt „Erholung 78 · Schlaf 93“ als Titel auf den Sperrbildschirm (`:64`) und kann das in der App nicht mehr abstellen. `CoachEngine.swift:112` antwortet weiter „Die Weckzeit stellst du im Profil ein.“ Dieselbe Weckzeit (`wakeMinutes`, Standard 6:55) speist `RingDetailView.swift:190` „Empfohlene Bettzeit“, ohne den alten Hinweis „Beispiel: Wecker um 6:55“. Der erklärende Fußtext („iOS bestimmt …“, „kann auf dem Sperrbildschirm erscheinen“) ist ebenfalls entfernt.
Warum falsch: Die Antwort auf R-02-07/08 ist damit sachlich falsch. Die einzige Möglichkeit abzuschalten wären die iOS-Mitteilungen insgesamt, und die nehmen auch den Pausentimer mit. Die App gibt eine falsche Bedienanweisung. Außerdem erscheint ein Standardwecker als persönliche Empfehlung.
Lösung: Abschnitt „Coach im Hintergrund“ in `ProfileView` wiederherstellen: `Toggle` für `CoachNotifier.morningKey`, `bedtimeKey` und `detailsKey` sowie `DatePicker(.hourAndMinute)` auf `wakeKey`. Dazu `.onChange` → `CoachNotifier.scheduleBedtimeReminder(hub)`, beim Ausschalten `removePendingNotificationRequests(withIdentifiers: ["forma.bedtime"])`. Standard für Morgenbericht und Bettzeit: **aus**, bis die Funktion bewusst eingeschaltet wird (siehe C-03-12). Ohne gesetzte Weckzeit in `RingDetailView` den Untertitel „Annahme: Wecker 6:55 – im Profil ändern“ zeigen. Test: `testCoachSettingsAreReachable` (UI) sowie Unit-Test `XCTAssertFalse(CoachNotifier.morningEnabled)` bei leeren UserDefaults.

### C-03-02 · P0 · Coach, Datenschutz · 16-Coach.jpg, 19-Profil.jpg
Beobachtung: `37668d4` hat das `SecureField` für den Anthropic-Schlüssel samt „Speichern“ und „Schlüssel entfernt“ aus `ProfileView` gelöscht. Im Code steht kein `Keychain.set(nil, for: "anthropic.key")` mehr. `CoachView.swift:19` und `:228-230` nutzen einen vorhandenen Schlüssel weiterhin. Ist `forma.claudeConsent` noch `true`, gehen Frage, Verlauf und `contextSummary` (HRV, Ruhepuls, Erholung …) an Anthropic. Löschen kann der Nutzer nur die Zustimmung (`ProfileView.swift:117-119`), nicht den Schlüssel. Schlüsselbund-Einträge überleben unter iOS in der Regel auch das Löschen der App (gerätespezifisch, nicht geprüft). Zusätzlich enthält der Systemprompt `CoachEngine.swift:171-172` den App-Namen „Forma“ und den Vornamen „Maxi“. Das sind personenbezogene Daten, die der Zustimmungstext (`CoachView.swift:106`) nicht nennt.
Warum falsch: Ein Geheimnis ohne Lösch- oder Ansichtspfad ist ein Datenschutzbefund (App Review 5.1.1/5.1.2). Der Zustimmungsdialog nennt nicht alles, was übertragen wird.
Lösung: Entweder den externen Coach vollständig entfernen und einmalig migrieren (`Keychain.set(nil, for: "anthropic.key")` plus `claudeConsent = false` in `FormaApp.init`), oder in `ProfileView` einen Abschnitt „Coach (extern)“ mit Status, „Schlüssel entfernen“ (destruktiv, Bestätigung) und Zustimmung anbieten. Im Systemprompt den Namen durch „die Person“ ersetzen. Test: `testLegacyKeyIsRemovedOrManageable`. Schlüssel setzen, App-Migration ausführen, dann `XCTAssertNil(Keychain.get("anthropic.key"))` oder UI-Element `profile.claude.removeKey` vorhanden.

### C-03-03 · P1 · Synchronisierung, Kalender · 01-Heute.jpg
Beobachtung: Der Cache speichert Tage als absolute `Date` (Mitternacht der damaligen Zeitzone). `SyncStore.normalized` (`SyncStore.swift:54-58`) bildet `d.date.startOfDay` in der **aktuellen** Zeitzone (`Calendar.forma`, `Metrics.swift:186-191`, `timeZone = .current`). Ein Beispiel für eine Reise nach Westen: Berlin 18.11. 00:00 entspricht New York 17.11. 18:00, `startOfDay` ergibt also den 17.11. **Jeder** gespeicherte Tag rutscht einen Tag zurück, heute bleibt leer. `DataHub.init` (`DataHub.swift:156`) zeigt das sofort an. Bei `.partial` (`SyncStore.merge`, `:101-113`) werden die Werte der fehlgeschlagenen Reihen aus dem verschobenen Altbestand übernommen und mit `SyncStore.save` (`DataHub.swift:427`) **dauerhaft** unter falschem Datum gespeichert. Nach Osten passiert nichts, weil die Mitternacht dort in denselben Kalendertag fällt. Ob `TimeZone.current` ohne Neustart der App auf einen Zonenwechsel reagiert, kann ich nicht sicher belegen. Die App reagiert auch nicht auf `NSSystemTimeZoneDidChange` oder `significantTimeChangeNotification`.
Warum falsch: Schlaf und HRV erscheinen am Vortag, „heute“ hat keine Nacht, Morgenbericht und Erholung fallen aus. Maxis Ziel „Synchronisierung extrem zuverlässig“ scheitert an einer einfachen Reise.
Lösung: Tagesschlüssel als Kalendertag speichern (`DateComponents(year:month:day:)` oder `"yyyy-MM-dd"`, wie `FitbitService.dayString`) und beim Laden in die aktuelle Zone abbilden. `normalized`/`merge` bekommen einen Parameter `calendar: Calendar`. Auf `.NSSystemTimeZoneDidChange` mit `TimeZone.resetSystemTimeZone()` reagieren, dann `syncAndNotify` aufrufen und die Bettzeit neu planen. Snapshot-Version anheben und alte Snapshots einmalig migrieren.

### C-03-04 · P1 · Synchronisierung und Coach, Abschlussweg · codebasiert
Beobachtung: Laut Antwort zu R-02-06/07 laufen „alle Abrufe über einen Weg“. Tatsächlich rufen `FormaApp.swift:104` (Start), `:115` (Vordergrund) und `TodayView.swift:59` sowie `HealthView.swift:56` (Ziehen zum Aktualisieren) nur `hub.refresh()` auf, ohne `CoachNotifier.afterSync`. Die Bettzeit-Erinnerung wird dann beim normalen Öffnen nicht neu geplant. Umgekehrt: Hängen sich zwei `syncAndNotify`-Aufrufer an denselben `inFlight` (`DataHub.swift:334-337`), bekommen beide `.updated` und starten **zwei** `afterSync`-Tasks. `sendMorningReportIfDue` liest `sentKey` vor dem `await add` (`CoachNotifier.swift:52-74`), also können zwei Berichte (gleiche ID, aber zwei Banner und Töne) entstehen. Ob iOS bei gleicher ID zweimal anzeigt, habe ich nicht am Gerät belegt. Außerdem gilt `.partial` als `isFresh` (`:185`). Dabei werden `lastUpdate` („Letzter erfolgreicher Import“) und `lastBackgroundSync` gesetzt, auch wenn nur eine Reihe gelesen wurde, die leer war (`DataHub.swift:426-433`). HealthKit-Beobachter melden immer `background: true` (`:195`), auch bei offener App. Das verfälscht „Letzter Abruf im Hintergrund“.
Warum falsch: Zeitstempel und Coach-Auslösung sagen nicht die Wahrheit über den Zustand. Doppelte Mitteilungen wirken fehlerhaft.
Lösung: `RootView` und `.refreshable` rufen `syncAndNotify(background: false)` auf. In `CoachNotifier` einen `@MainActor static var morningInFlight: Bool` oder ein Set mit Tageskennung **vor** dem `await` setzen. `afterSync` mit einem `generation`/`resultID` entprellen. `RefreshResult.partial` nur dann `isFresh`, wenn mindestens eine *erfolgreiche* Reihe für heute einen Wert lieferte. `lastUpdate` nur bei `.updated`, für Teilimporte ein eigenes Feld. `background` aus `UIApplication.shared.applicationState` ableiten.

### C-03-05 · P1 · Heute, Demo · 01-Heute.jpg
Beobachtung: `TodayView.swift:92-98` zeigt „Beispieldaten anzeigen“, sobald `todayDataNotice != nil` ist. Das ist auch bei „Lade deine Daten …“, „Warte auf Entsperren“ oder einem Teilimport der Fall. Ein Tipp setzt `preferredSource = .sample`. Das wird gespeichert (`DataHub.swift:125`) und gilt nach jedem Neustart. Ab dann gilt: `expectsRealData == false` (`:152`), keine Beobachter, `afterSync` bricht ab (`CoachNotifier.swift:38`), `BackgroundRefresh.schedule` wird übersprungen (`FormaApp.swift:114`). Zurück geht es nur über Profil → Quelle. Zusätzlich ersetzt `FormaApp.swift:18-23` die gesamte `RootView` durch eine Demo-Hierarchie mit In-Memory-Speicher. Ein offenes Profil-Blatt verschwindet dabei.
Warum falsch: Ein beiläufiger Tipp neben einem Ladehinweis schaltet stillschweigend Synchronisierung und Coach ab. Das widerspricht Maxis Hauptziel.
Lösung: Demo nur sitzungsweise (`@State var demoPreview` in `AppState`, nicht in `forma.source`) oder nur zeigen, wenn `askedForHealthAccess == false`. In der Demo oben ein festes Banner „Beispieldaten · Zurück zu deinen Daten“ (44 pt). Test: Nach `hub.preferredSource = .sample` und neuem `DataHub()` gilt `XCTAssertNotEqual(hub.preferredSource, .sample)`, oder bei Sitzungsdemo: `UserDefaults["forma.source"]` bleibt unverändert.

### C-03-06 · P1 · CI und Bildherkunft · alle Bilder
Beobachtung: Lauf 44396675307 für `36bb341` ist „success“. Im Log stehen aber `** TEST FAILED **`, `ScreenTour.swift:139: Die Ring-Detailseite Sleep fehlt`, `… Strain fehlt`, `ScreenTour.swift:99: XCTAssertFalse failed` (der Plus-Tab ist laut Test **aktiv**) und „Pflichtbilder fehlen: 06-Sleep 08-Strain“. Der UI-Schritt endet mit `exit 0` (`forma-ios.yml:136`), der Veröffentlichungsschritt hat `continue-on-error: true` (`:140`). Die Bilder im Repo stammen weiterhin aus `23c51a0` und zeigen z. B. das entfernte Journal (18) und die alte Profilseite (19). Die Rundgänge 01 und 02 sind byte-gleiche Ansichten, der Scroll fehlt also. `37668d4` lief rot (Build-Fehler) und wurde ohne Korrektur-Commit mit „noch ungeprüft vom Compiler“ gepusht. Die Commit-Nachricht nennt einen Modellnamen (Regel in AGENTS.md verletzt). Laut Commit hat Codex gebaut, was der Rollenverteilung widerspricht.
Warum falsch: R-02-23 („nur bei vollständigem Pflichtsatz“) ist formal erfüllt, praktisch aber wertlos, weil grün trotzdem grün bleibt. Review-Runden prüfen alte Bilder.
Lösung: Am Ende des UI-Schritts `exit $status`. Den Veröffentlichungsschritt ohne `continue-on-error`, bei fehlenden Pflichtbildern den Job rot. In `HERKUNFT.txt` zusätzlich „UI-Rundgang: bestanden/fehlgeschlagen“. In `ScreenTour` vor `shot("02 …")` per `XCTAssertNotEqual` auf Bildinhalt oder Scroll-Offset prüfen. Plus-Tab siehe C-03-10.

### C-03-07 · P1 · Health Age · 14b-Körperalter.jpg, 14c, 14d, 14e
Beobachtung (HEAD): `BodyAgeDetailView.resultView` (`BodyAgeView.swift:145-177`) zeigt nur Hero, Vergleich, Faktorzeilen und „Tage mit Daten“. `factor.explanation`, `result.missing` (z. B. „Krafttraining nicht aufgezeichnet“, „Geschlecht im Profil …“, `BodyAge.swift:183`), `confidence` und der Abschnitt „So wird gerechnet“ werden nirgends mehr angezeigt (`grep` findet keinen Aufruf). `HealthAgeHero` im Zustand `.ready` (`:43-46`) trägt keine Kennzeichnung „Schätzung, nicht validiert“. Die steht nur im Detail (`:149`). Die Hauptseite heißt „Health Age“ (`HealthView.swift:58`), darunter „Biomarker“ (`:45`). Der Satz „Health ersetzt keine ärztliche Beratung“ wurde aus dem Profil entfernt. Ebenso entfernt sind „Was beiträgt“ und „So wird gerechnet“ für alle drei Ringe (`git show 37668d4 -- RingDetailView.swift`).
Warum falsch: AGENTS.md behauptet „Körperalter mit offengelegter Methode“, R-02-10 behauptet „Schätzung an der Kachel“. Beides gilt in HEAD nicht mehr. „Biomarker“ für Schritte und Energie ist medizinisch überhöht. Ohne Beitragszeilen sind die Ringwerte nicht nachvollziehbar.
Lösung: In `HealthAgeHero` unter der Zahl `Text("Schätzung, nicht validiert")` (formaCaption, textSecondary). In `resultView` wieder Abschnitte „Was fehlt“ (`result.missing`), „So wird gerechnet“ (DisclosureGroup mit `factor.explanation`) und „Datenabdeckung“ (`confidence`). In `RingDetailView` `ContributionRow` und die Berechnungstexte zurückholen. „Biomarker“ → „Messwerte“, Navigationstitel → „Gesundheit“.

### C-03-08 · P1 · Health Age, 30-Tage-Vergleich · (kein Bild für HEAD)
Beobachtung: `AgeWindowChart` (`BodyAgeView.swift:270-296`) verbindet zwei Kategorien („30 Tage davor“, „Letzte 30 Tage“) mit einer `LineMark` und skaliert die y-Achse auf `min-1 … max+1` (`:288`). Ein Unterschied von 0,3 Jahren nimmt damit etwa 13 % der Höhe ein. Bei 27,1 gegenüber 27,4 und Alter 27 reicht die Achse von 26 bis 28,4, die Linie steigt sichtbar. Gleichzeitig sagt `signedYears` „unter ½ Jahr“, früher „Kein deutlicher Unterschied“. Die gestrichelte Regel liegt beim ungerundeten Alter (z. B. 30,8), die Beschriftung `:297` sagt aber „30 Jahre“. Der AX-Label `:296` ist englisch („Health Age …“) und nennt keine Werte. Die Farbe der Linie richtet sich nach `recent - age`, nicht nach der Veränderung.
Warum falsch: Das Diagramm suggeriert einen Trend, wo das Modell selbst „kein deutlicher Unterschied“ sagt. Das ist irreführend, ähnlich wie R-02-11.
Lösung: Mindestspanne der y-Achse ±3 Jahre um `age`. Bei `abs(recent - previous) < 0.5` keine Linie, nur zwei Punkte und den Text „Kein deutlicher Unterschied“. Barmark statt Linie. `accessibilityLabel("Geschätztes Alter: davor \(…), zuletzt \(…), dein Alter \(…)")`. Die Regel beim angezeigten Alter beschriften („dein Alter 30,8“ oder Regel bei `rounded(.down)`). Test: `ageChartDomain(previous: 27.1, recent: 27.4, age: 27).upperBound - lowerBound >= 6`.

### C-03-09 · P1 · App-Name und Freigabetexte · 19-Profil.jpg, Onboarding
Beobachtung: `Info.plist:8` heißt die App „Health“, also genauso wie Apples App. Die Mitteilung lautet „Dein Tagesbericht ist bereit … Öffne Health“ (`CoachNotifier.swift:67-68`). Der Profil-Fußtext sagt „Apple Health unter Profilbild → Apps → Health“ (`ProfileView.swift:69`). `NSHealthShareUsageDescription` (`Info.plist:51`) verschweigt Herzfrequenz (`HKQuantityType(.heartRate)`, `HealthService.swift:19`), Geburtsdatum und Geschlecht (`:22-23`). Außerdem behauptet sie „Die Daten bleiben auf deinem iPhone“, obwohl der externe Coach (C-03-02) Werte senden kann. Tabs und Ringe heißen „Today“, „Health“, „Plus“ (`FormaApp.swift:59-75`) bzw. „Strain/Recovery/Sleep“ (`Rings.swift:9-11`), dazu „Keine Recovery“ (`RingDetailView.swift:107`). Das ist exakt Whoops Wortwahl.
Warum falsch: Eine Mitteilung „Health“ wirkt wie eine von Apple Health. Das täuscht, und der Name dürfte im App Review scheitern (das kann ich nicht bestätigen, Risiko hoch). Ein unvollständiger Freigabetext ist ein Datenschutzproblem. AGENTS.md: deutsch, keine Whoop-Kopie.
Lösung: Eigener Name (z. B. wieder „Forma“) in `CFBundleDisplayName`. Freigabetext vollständig: „… Herzfrequenz, Geburtsdatum, biologisches Geschlecht … Ohne deine Zustimmung verlässt nichts das iPhone.“ Deutsche Tab-Titel „Heute, Training, Gesundheit, Coach“ und Ringe „Belastung, Erholung, Schlaf“, wie auf den Bildern 01–08.

### C-03-10 · P1 · Tab-Leiste „Plus“ · (kein Bild für HEAD)
Beobachtung: `FormaApp.swift:71-75` legt einen fünften Tab „Plus“ mit `Color.clear` und `.disabled(true)` an. Der UI-Test `ScreenTour.swift:99` meldet ihn als **aktiv**. Ein Tipp führt laut Code auf einen leeren schwarzen Bildschirm. Am Bild belegen kann ich das nicht.
Warum falsch: HIG: Tabs sind Ziele, keine Platzhalter. Ein deaktivierter oder leerer Tab kostet Breite (5 statt 4 Tippziele in der Daumenzone), VoiceOver sagt „Plus, Tab, 5 von 5“ ohne Funktion.
Lösung: Tab entfernen. Eine Plus-Aktion als `ToolbarItem` oder `.tabViewBottomAccessory` mit echter Aktion (z. B. „Training starten“) erst einbauen, wenn es sie gibt.

### C-03-11 · P1 · Synchronisierung, Leerlauf und Löschung · codebasiert
Beobachtung: (a) Eine einzeln entzogene Lesefreigabe (z. B. nur Schlaf) liefert in HealthKit „erfolgreich, leer“ (`failed` leer). `merge` setzt die Reihe dann für **alle 180 Tage** auf `nil` und speichert das (`SyncStore.swift:102-114`, Absicht laut Kommentar „in Apple Health gelöscht“). Ein vollständiger Entzug wird dagegen als `.rejectedEmpty` behandelt und der alte Stand behalten (`:90`). Beides ist für den Nutzer nicht unterscheidbar und nicht erklärt. (b) Hat der zusammengeführte Stand in den letzten 30 Tagen keine Daten, setzt `performRefresh` `longDays = merged` (`DataHub.swift:419`), speichert aber nicht und gibt `.unchanged` zurück (`:421-425`). Die Anzeige zeigt dann den gelöschten Zustand, nach einem Neustart erscheint der alte Cache wieder. (c) `SyncStore.save` meldet `false`, wenn nur `setResourceValues` scheitert, obwohl die Datei geschrieben wurde (`:33-41`). Die UI sagt dann „konnte nicht gespeichert werden“.
Warum falsch: Inkonsistente Wahrheit zwischen Anzeige, Speicher und Neustart.
Lösung: (a) Pro Reihe den letzten Stand behalten, wenn die Reihe vorher Werte hatte und jetzt in **allen** 180 Tagen leer ist, und den Hinweis „Schlaf: keine Daten mehr lesbar – Freigabe prüfen?“ zeigen. (b) `longDays` erst nach erfolgreicher Prüfung setzen. (c) Schreib- und Backup-Ausschluss getrennt melden.

### C-03-12 · P1 · Mitteilungen, Einwilligungsumfang · 11-Pause.jpg
Beobachtung: „Bei Pausenende benachrichtigen“ (`LiveWorkoutView.swift:206-213`) ruft `CoachNotifier.requestPermission()` auf. Mit dieser einen Freigabe sind laut C-03-01 automatisch Morgenbericht und Bettzeit aktiv (Standard an, kein Schalter). Wer nur den Pausentimer wollte, bekommt täglich zwei Coach-Mitteilungen.
Warum falsch: Zweckbindung der Einwilligung. Das stört und verletzt das Vertrauen.
Lösung: Morgenbericht und Bettzeit nur nach eigenem Opt-in im Profil oder Coach („Coach darf mich morgens informieren“). `CoachNotifier.afterSync` prüft zusätzlich `UserDefaults.object(forKey: morningKey) != nil`.

### C-03-13 · P2 · Live-Training, Abschluss und Einheiten · 10–13
Beobachtung: (a) „Speichern und beenden“ ohne erledigten Satz: `save` gibt `nil` zurück, `finish()` setzt trotzdem `app.liveWorkout = nil` (`LiveWorkoutView.swift:328-343`). Der Entwurf samt bearbeiteter Gewichte ist ohne Hinweis weg. (b) In 13 wird eine Einheit mit 1 von 19 Sätzen ohne Rückfrage gespeichert. (c) lb: Schritt `5 / 2.20462` kg (`:238`) wird in `changeWeight` auf 0,25 kg gerundet (`AppState.swift:309`), also 2,25 kg = 4,96 lb. Nach vier Tipps zeigt die App 19,8 statt 20 lb. „vorher 72,5 × 8“ hängt bei lb keine Einheit an und zeigt kg-Werte (`LiveWorkoutView.swift:132`). (d) Spaltenkopf „RIR“ (`:101`) neben „Reserve“ im Dock. (e) Wiederherstellung übernimmt `exerciseIndex/setIndex` aus dem Snapshot, auch wenn dieser Satz erledigt ist (`AppState.swift:240-243`). Der Dock zeigt dann „Satz n abschließen“, und `completeCurrentSet(id:)` lehnt ab. Das ist ein toter Knopf (nur mit manipulierten oder alten Daten).
Lösung: (a/b) Bei 0 Sätzen Dialog „Nichts zu speichern – Training verwerfen?“, bei unvollständigem Training „x von y Sätzen erledigt – trotzdem speichern?“. (c) Gewicht intern in der Eingabeeinheit führen oder bei lb auf 0,5 lb runden. „vorher“ über `Format.weight(_:unit:)`. (d) Kopf „Res.“ mit `accessibilityLabel("Reserve")`. (e) Nach `restore` den ausgewählten Satz prüfen, sonst `selectFirstOpen`.

### C-03-14 · P2 · Claude-Aufruf · 17-Coach-Antwort.jpg
Beobachtung: (a) Ein Widerruf bricht `URLSession.data` ab, das wirft `URLError(.cancelled)`, keine `CancellationError`. `CoachView.swift:241-243` hängt dann „Claude ist gerade nicht erreichbar, das war die lokale Antwort“ an statt „Abgebrochen“. (b) `max_tokens: 400` ohne `thinking`-Angabe (`CoachEngine.swift:180`). Das eingetragene Modell denkt laut aktueller API-Dokumentation standardmäßig adaptiv. Kurze Limits können zu abgeschnittenen oder leeren Antworten führen (`stop_reason` `max_tokens`/`refusal` wird nicht ausgewertet, leere Antworten führen zu Fehler 204 und dem lokalen Rückfall). Am Gerät nicht geprüft. (c) Der Zustimmungstext nennt „der bisherige Chat“, gesendet werden aber nur nicht-lokale Nachrichten. Das ist zu viel versprochen, im Zweifel unkritisch, aber ungenau.
Lösung: In `ClaudeClient.reply` `URLError.cancelled` auf `CancellationError` abbilden. `stop_reason` dekodieren, bei `refusal` oder `max_tokens` einen klaren Hinweis zeigen. Effort oder Länge ausdrücklich festlegen, `max_tokens` großzügiger wählen. Zustimmungstext: „deine Frage, frühere an Claude gesendete Nachrichten …“.

### C-03-15 · P2 · Schlaf- und Belastungsdetail · 06/07/08
Beobachtung (HEAD): Auf derselben Seite stehen „Geschätzter Bedarf“ (letzte Nacht, `RingDetailView.swift:167`) und „Schlafbedarf“ (heute Nacht, `:192`) mit unterschiedlichen Werten ohne Erklärung. Der Status unter der Schlafzahl heißt immer „Schlafqualität“ (`:60`), das sagt nichts aus. „Empfohlene Bettzeit“ wird auch ohne jede Schlafhistorie berechnet (Grundbedarf 7,75 h), hat also keine Datengrundlage. `formaHero` hat feste 64 pt (`Theme.swift:89`) und skaliert nicht mit Dynamic Type. Die neue Kopfkarte stützt sich darauf.
Lösung: Beschriftungen „Bedarf letzte Nacht“ und „Bedarf heute Nacht“. Status nach Wert („Gut geschlafen“/„Zu kurz“). Bettzeit nur mit `availability.sleep` oder mindestens 3 Nächten, sonst „–“ und „Mehr Nächte nötig“. `formaHero` über `@ScaledMetric` oder `Font.system(.largeTitle).…` mit `minimumScaleFactor` nur bei AX-Größen.

### C-03-16 · P2 · Journal-Daten verwaist · 18-Journal.jpg
Beobachtung: Das Journal ist entfernt, `JournalAnswer` bleibt im Schema (`FormaApp.swift:9,29`). Vorhandene Antworten (Alkohol, krank, Stress …) liegen weiter auf dem Gerät, sind nicht sichtbar und nicht löschbar.
Lösung: Einmalige Migration, die `JournalAnswer` löscht (oder Export plus Löschen im Profil). Danach das Modell im Schema per `VersionedSchema` und Migrationsplan sauber entfernen.

### C-03-17 · P2 · Tests belegen weniger als behauptet · codebasiert
Beobachtung: `testOverlappingDeepAndRemCountOnce` (`FormaTests.swift:700-710`) prüft nur `0 < score ≤ 100`. Das bestünde auch mit doppelter Zählung. Zu A-07 gibt es nur einen Test mit Closure für `restore`. `save` zweimal gegen einen echten In-Memory-`ModelContainer` ist ungetestet. Für `DataHub.refresh`/`inFlight`/`generation`, `CoachNotifier` (Tageskennung, Annahmefehler), Zeitzonen und Sommerzeit gibt es keine Tests, weil `HealthService`, `UNUserNotificationCenter` und `Calendar` nicht injizierbar sind.
Lösung: Siehe Angriffstest-Tabelle. Protokolle `HealthReading` und `NotificationScheduling`, `Calendar` als Parameter.

### C-03-18 · P3 · Kleinkram aus den Bildern (Stand `23c51a0`)
- 04: „Schlafs-core 93 · +6 Pkt“ trennt falsch, „+0,3 /min · −2 Pkt“ bricht vor dem Punkt um. In HEAD ist die Zeile entfernt (siehe C-03-07). Beim Wiederherstellen Score und Messwert untereinander setzen.
- 14: „Dein Bereich 13,7–⏎14,9 /min“, „7:02–⏎7:37 h“: geschütztes Leerzeichen bzw. `Text(verbatim:)` mit `.lineLimit(1)` und `ViewThatFits`. Zeitformat „7:02–7:37 h“ ist uneinheitlich zu „7 h 20 min“.
- 13: „Training löschen“ als neutrale Glaskapsel. Besser `role: .destructive` mit Bestätigung, 44 pt.
- 14c/14e: VO₂max 46,5 (Mittel, ohne „im Mittel“) neben 47,0 (letzter Wert). Die Quelle des Werts gehört in die Zeile.
- 14d: Der Methodentext spricht in der Ich-Form („nehme ich“), der Rest der App nicht.
- `CoachNotifier.swift:46,74`: Sendebestätigung pro Tag `forma.coach.morningSent.YYYY-MM-DD` wächst unbegrenzt in UserDefaults. Ältere Schlüssel als 7 Tage löschen.
- Profil: „Erneut verbinden“ (`ProfileView.swift:56`) steht auch da, wenn noch nie verbunden wurde.

## Nachprüfung Runde 02

| ID | Ergebnis | Beleg |
|---|---|---|
| R-02-01 Import | teilweise bestätigt | `ImportResult`, `merge(failed:)` und Testfälle A-01/A-02 vorhanden. Teilimport gilt als „erfolgreich“ (C-03-04), Zeitzonenverschiebung (C-03-03), Leerlauf-Inkonsistenz (C-03-11). Messdatum pro Wert weiterhin offen |
| R-02-02 Cache | bestätigt, mit Einschränkung | `SyncStore.swift:35-37` `isExcludedFromBackup`, Löschen mit Bestätigung `ProfileView.swift:120-126`. Der erklärende Fußtext zur Backup-Ausnahme wurde in `37668d4` entfernt. Die Kopie entsteht beim nächsten Abruf sofort neu |
| R-02-03 Fehlende Daten | teilweise | Ringe nutzen `availability`. Bettzeit und Coach-Satz rechnen ohne Datengrundlage weiter (`RingDetailView.swift:190`, `CoachEngine.bedtime`) |
| R-02-04 Satzabschluss | bestätigt | `AppState.swift:342-346`, `LiveWorkoutView.swift:290-293`, Test `testDoubleTapCompletesOnce` |
| R-02-05 Speichern | bestätigt, mit Einschränkung | `draftID`-Abfrage `AppState.swift:419` per `try?` (Fehler → Duplikat möglich), kein `@Attribute(.unique)`, kein Test mit echtem Container |
| R-02-06 Hintergrund | teilweise | `inFlight` und Nachlauf korrekt. Vordergrundwege umgehen `syncAndNotify`, doppeltes `afterSync`, Beobachter immer „Hintergrund“ (C-03-04) |
| R-02-07 Mitteilungen | **widerlegt** | Schalter „Werte in Mitteilungen zeigen“, Morgenbericht und Bettzeit in `37668d4` entfernt (C-03-01) |
| R-02-08 Bettzeit | **widerlegt** | Gemeinsame `bedtimePlan` ja, „Weckzeit im Profil“ entfernt. Keine Neuplanung bei Zeitzonenwechsel |
| R-02-09 Schlaf | teilweise | Vereinigung in `ScoreEngine.swift:26` korrekt, Test ohne Aussagekraft (C-03-17) |
| R-02-10 Körperalter | teilweise / widerlegt | Altersbereich und Krafttraining-Regel per Test belegt. „Schätzung, nicht validiert an der Kachel“ und Hinweis auf fehlendes Krafttraining in HEAD nicht mehr sichtbar (C-03-07) |
| R-02-12 Fortschritt | bestätigt | `AppState.swift:259, 278`, Knopf „Übernehmen“ |
| R-02-13 Entwurf | bestätigt, mit Einschränkung | Grenzen in `restore`. Index kann auf einen erledigten Satz zeigen (C-03-13e) |
| R-02-14 Quellen | bestätigt | `generation` in `performRefresh`. Neuer Demo-Knopf schaltet die Synchronisierung dauerhaft ab (C-03-05) |
| R-02-15 Claude | teilweise | `localOnly`-Filter `CoachEngine.swift:177`, Abbruch `CoachView.swift:89-91`. Schlüssel nicht mehr entfernbar (C-03-02), falsche Abbruchmeldung (C-03-14) |
| R-02-17 Dynamic Type | teilweise | Dock korrekt. Neue Heldenzahlen mit fester Größe von 64 pt (C-03-15). Kein AX5-Bild vorhanden |
| R-02-20 Diagramm | im Code bestätigt | `HealthView.swift:146` „keine Messung“. Kein aktuelles Bild |
| R-02-22 Journal | hinfällig | Journal entfernt, Daten verwaist (C-03-16) |
| R-02-23 CI | **widerlegt** | Grün trotz `TEST FAILED`, Bilder veraltet (C-03-06) |
| R-02-24 Kalender | teilweise | `normalized` beim Start vorhanden, Verschiebung bei Reisen nach Westen (C-03-03) |
| R-02-26 Mitteilungsabfrage | bestätigt, mit Einschränkung | Abfrage nur auf Knopfdruck. Die Freigabe schaltet aber auch den Coach frei (C-03-12) |

Zur Priorisierung der ⏭-Punkte: P1 sind „Messdatum pro Wert“ (R-02-01) und „Ergebnis von `BGTaskScheduler.submit` anzeigen“ (R-02-06), weil beide über Maxis Sync-Ziel entscheiden. P2 sind lb im Editor (R-02-21), `Keychain.set` mit Status (R-02-15, wird mit C-03-02 wichtiger) und Reduce Motion im Dock (R-02-18). Der Rest ist P3.

## Angriffstest

| Angriff | Ergebnis laut Code | Risiko | Testfall (XCTest-Vorschlag) |
|---|---|---|---|
| T-01 · Reise Berlin → New York, offline starten | Alle Cache-Tage einen Tag früher, Teilimport speichert die Verschiebung | P1 | `normalized(_:today:keepDays:calendar:)` einführen. `let berlin = cal("Europe/Berlin"), ny = cal("America/New_York"); let d = berlin.date(from: .init(year:2026,month:11,day:17))!; var m = DayMetrics(date: d); m.hrv = 50; let n = SyncStore.normalized([m], today: ny.date(from: .init(year:2026,month:11,day:18))!, keepDays: 3, calendar: ny); XCTAssertEqual(ny.component(.day, from: n.first { $0.hrv == 50 }!.date), 17)` |
| T-02 · Zwei Abrufe gleichzeitig, beide frisch | Zwei `afterSync`-Tasks, Tagesmarke erst nach `await add` gesetzt | P2 | Mit `NotificationScheduling`-Spy: `async let a = hub.syncAndNotify(background: true); async let b = hub.syncAndNotify(background: false); _ = await (a, b); await spy.idle(); XCTAssertEqual(spy.added.filter { $0.hasPrefix("forma.morning.") }.count, 1)` |
| T-03 · App öffnen am Abend | Nur `refresh()`, Bettzeit wird nicht neu geplant | P1 | `RootView`-Logik in `AppLifecycle.onActive(hub:)` auslagern. Test: Spy registriert `forma.bedtime` nach `onActive` |
| T-04 · Teilimport, nur leere SpO₂-Reihe gelesen | `.partial` → `isFresh`, `lastUpdate = now` | P2 | `HealthReading`-Stub: `failed = alle außer .spo2`, SpO₂ leer → `XCTAssertEqual(result, .unchanged)` und `XCTAssertNil(hub.lastUpdate)` (bzw. eigenes `lastPartialUpdate`) |
| T-05 · Nur Schlaf-Freigabe entzogen | 180 Tage Schlaf im Cache gelöscht, Körperalter springt | P1 | `merge(old: 180 Tage mit Schlaf, new: 180 Tage ohne Schlaf, failed: [])` → erwartet: Schlaf bleibt erhalten und es gibt einen Hinweis `.seriesVanished([.sleep])` |
| T-06 · „Beispieldaten anzeigen“ antippen, App neu starten | Demo dauerhaft, keine Beobachter, kein Coach | P1 | `hub.preferredSource = .sample; let fresh = DataHub(); XCTAssertNotEqual(fresh.preferredSource, .sample)` (nach Umbau auf Sitzungsdemo) |
| T-07 · Alter Claude-Schlüssel, Zustimmung erteilt, neue Version | Externe Übertragung aktiv, Schlüssel nicht löschbar | P0 | `Keychain.set("dummy", for: "anthropic.key"); UserDefaults.standard.set(true, forKey: "forma.claudeConsent"); LegacyMigration.run(); XCTAssertNil(Keychain.get("anthropic.key"))` oder UI-Test findet `profile.claude.removeKey` |
| T-08 · Widerruf während der Anfrage | `URLError.cancelled` → „nicht erreichbar“-Rückfall | P3 | `URLProtocol`-Stub ohne Antwort. `let t = Task { try await ClaudeClient.reply(...) }; t.cancel(); do { _ = try await t.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }` |
| T-09 · „Speichern und beenden“ ohne Satz | Entwurf wird ohne Hinweis verworfen | P2 | In-Memory-Container: `XCTAssertNil(try w.save(into: ctx))` und neues `XCTAssertFalse(w.canSave)`. View-Test: Entwurf bleibt erhalten (`LiveWorkout.restore() != nil`) |
| T-10 · Zweimal speichern | Dank `draftID` eine Einheit | — | `let c = try ModelContainer(for: WorkoutSession.self, SetRecord.self, configurations: .init(isStoredInMemoryOnly: true)); let w = …; w.completeCurrentSet(id: w.currentSet!.id); let a = try w.save(into: c.mainContext); let b = try w.save(into: c.mainContext); XCTAssertEqual(a?.persistentModelID, b?.persistentModelID); XCTAssertEqual(try c.mainContext.fetchCount(FetchDescriptor<WorkoutSession>()), 1)` |
| T-11 · Manipulierter Entwurf mit Index auf erledigten Satz | Toter „Satz abschließen“-Knopf | P3 | `let w = workout(); w.completeCurrentSet(id: w.currentSet!.id); w.setIndex = 0; w.persist(); let r = LiveWorkout.restore()!; XCTAssertFalse(r.currentSet!.done)` |
| T-12 · Einheitenwechsel auf lb, 4× „+“ | 4 × 2,25 kg = 9 kg, angezeigt 19,8 lb statt 20 lb | P2 | `app.weightUnit = .lb; w.changeWeight(by: 5/2.20462)` ×4 von 0 → `XCTAssertEqual(w.currentSet!.weight * 2.20462, 20, accuracy: 0.05)` |
| T-13 · Tief und REM überlappen | Score korrekt, Test schwach | P2 | `XCTAssertEqual(ScoreEngine.sleepScore(night([core 0–480, deep 60–180, rem 60–180]), need: 8*3600), ScoreEngine.sleepScore(night([core 0–480, deep 60–180]), need: 8*3600))` |
| T-14 · Pausentimer erlaubt, Coach nie eingeschaltet | Morgenbericht und Bettzeit kommen trotzdem | P1 | Leere UserDefaults → `XCTAssertFalse(CoachNotifier.morningEnabled); XCTAssertFalse(CoachNotifier.bedtimeEnabled)` |
| T-15 · Bettzeit ohne jede Schlafhistorie | „Ins Bett 22:45“ ohne Grundlage | P2 | `let s = ScoreEngine.scores(today: DayMetrics(date: today), history: [])`, neue Funktion `CoachEngine.bedtime(s, available: false) == "–"` |
| T-16 · 30-Tage-Vergleich mit 0,3 Jahren Unterschied | Achse 26–28,4, sichtbarer „Anstieg“ | P1 | `XCTAssertGreaterThanOrEqual(AgeWindowChart.domain(previous: 27.1, recent: 27.4, age: 27).count, 6)` (Domain als statische Funktion herausziehen) |
| T-17 · Plus-Tab antippen | Laut UI-Test aktiv, leerer Bildschirm | P1 | `ScreenTour`: `XCTAssertFalse(app.tabBars.buttons["tab.add"].exists)` nach Entfernen |
| T-18 · UI-Rundgang schlägt fehl | Workflow grün | P1 | Workflow-Test: absichtlich `XCTFail` in `ScreenTour` → Job `screens` muss rot sein |
| T-19 · BG-Task läuft ab mitten im Import | `inFlight`-Task reagiert nicht auf Abbruch. Ob iOS dann beendet oder nur suspendiert, kann ich nicht belegen. `SyncStore.save` schreibt atomar, Datenverlust ist unwahrscheinlich | P3 | Gerätetest mit `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.ma29xii.forma.refresh"]`, danach Cache unversehrt und `lastBackgroundAttempt` gesetzt |
| T-20 · Gesperrt, Beobachter feuert | `.locked`, `waitingForUnlock`, Nachholen nach Entsperren | — | Gerätetest (Simulator gibt keinen Schutzklassen-Zustand): sperren, Schlaf in Health eintragen, entsperren → genau ein Abruf, ein Bericht |

## Was bleiben soll
- `SyncStore.merge(failed:)` mit pro Reihe getrenntem Ergebnis und `.rejectedEmpty` für den vollständigen Fehlschlag. Das Konzept stimmt, nur die Schlüssel müssen Kalendertage werden.
- `refresh()` mit einem gemeinsamen `inFlight`-Task, Nachlauf über `refreshPending` und Verwerfen über `generation`. Sauber und testbar, sobald `HealthService` injizierbar ist.
- `completeCurrentSet(id:)`, `draftID` und die Grenzen beim `restore`. Die Haptik kommt nur bei angenommenem Abschluss.
- Mitteilungen ohne Gesundheitswerte als Standard, datierte Kennung und „erst nach `add` als gesendet merken“.
- `isProtectedDataAvailable`-Prüfung mit `protectedDataDidBecomeAvailable`-Nachholen.
- Der ruhige Trainingsbildschirm (09/09b), der Dock mit genau einer Glasebene und 44-pt-Reserveknöpfen (12) und das HRV-Detail (15).
- Quellenliste zum Körperalter mit direkten Studienlinks und der Altersbereich 18–90 mit VO₂max nur für 20–79.
- `seedWorkouts` nur in einen reinen In-Memory-Container (`SampleData.swift`, Prüfung `isStoredInMemoryOnly`). Das ist ein guter Schutz der echten Trainingsdaten.
