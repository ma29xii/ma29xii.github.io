# Codex-Review 02 – 18.11.2026

Geprüfter Commit: `b0b01b94698d8948a77bf382e79e37df848759b9`

## Gesamturteil

Runde 01 hat den Trainings-Dock verständlicher gemacht, den lokalen Coach gekennzeichnet und der Körperalter-Schätzung ihre scheinbare Nachkommagenauigkeit genommen. Die neue Hintergrund-Synchronisierung muss als Nächstes drei Fragen belastbar beantworten: Welche Daten wurden wirklich neu gelesen? Welche Werte fehlen? Was darf auf dem Sperrbildschirm erscheinen?

1. **Import und Cache** brauchen Ergebnisse pro Messreihe. Teilerfolge können gestrige Werte verlieren und historische Werte nach Löschung weiter anzeigen.
2. **Coach, Ringe und Wochenmittel** müssen dieselbe Datenbasis verwenden. Ein leerer Tag liefert intern weiterhin plausible Zahlen, die der Coach und einige Detailansichten übernehmen.
3. **Das lokale Gesundheitsarchiv** braucht eine ausdrückliche Löschmöglichkeit, einen Umgang mit entzogenen Berechtigungen und Schutz vor regulärer App-Datensicherung.
4. **Trainingssätze und Speichern** brauchen eindeutige IDs pro Aktion. Sonst kann dieselbe Bestätigung einen weiteren Satz oder bei einem Neustart eine doppelte Einheit erzeugen.
5. **Hintergrund- und Bildschirmabnahme** gehören getrennt geprüft. Ein grüner Simulatorlauf bestätigt keine HealthKit-Zustellung auf Maxis gesperrtem iPhone.

### Prüfbasis und Bildschirmnoten

**Prüfbasis:** Alle 25 JPGs in `docs/forma-screens/`, Bild-Commit `676f58f` für den App-Commit `32d24a2`. Simulator mit Standard-Schriftgröße und Beispieldaten, Größen aus SwiftUI oder am 16-pt-Seitenrand geschätzt. Code einschließlich der neueren kleinen Änderungen bis `b0b01b9` und Claudes Antwort geprüft. Zwischen Bild- und Prüf-Commit kamen der UI-Test-Schalter für Berechtigungsdialoge, eine ausgerichtete X-Achse, ein einzeiliger Kartenkopf und die serielle CI-Reihenfolge hinzu. Ihre visuelle Wirkung am neuesten Stand bleibt offen. In Lauf 12 waren Unit-Tests und Bild-Job erfolgreich, der IPA-Job wurde abgebrochen. Echte HealthKit-Zustellung, externer Coach, AX5 und Bedienung am iPhone sind offen. [CI-Lauf 12](https://github.com/ma29xii/ma29xii.github.io/actions/runs/44333145537) · [CI-Lauf 14 für den neuen Stand](https://github.com/ma29xii/ma29xii.github.io/actions/runs/44336272790)

| Bildschirm | Note | Wichtigste Beobachtung |
|---|---:|---|
| Heute, Einstieg · 01 | 7/10 | Klare Ringhierarchie; nur die Kopfzeile markiert den ganzen Bildschirm als Demo |
| Heute, gescrollt · 02 | 6/10 | Feste Tabs helfen, Teildaten und Aktualität bleiben mehrdeutig |
| Heute, unten · 03 | 6/10 | Einblick vorsichtiger formuliert, Wochenmittel kann Ersatzwerte enthalten |
| Heute anpassen · 03b | 7/10 | Eindeutige Liste; Reset-Wort und Ende des Drag-Bereichs bleiben offen |
| Erholung · 04 | 6/10 | Verständliche Statuszeile, enge Beitrags-Spalte mit „Schlafs-core“ |
| Erholung, unten · 05 | 6/10 | Lesbare Wochenbalken, undatierte Mini-Verläufe |
| Schlaf · 06 | 6/10 | Score klarer benannt, keine stabile Bewertung derselben Nacht |
| Schlaf, unten · 07 | 5/10 | Fester Wecker und Nullnächte im Mittel |
| Belastung · 08 | 5/10 | Mittel verständlicher, Schritte allein können einen Nullwert als Messung freigeben |
| Training · 09 | 7/10 | „Push starten“ und freie Einheit sichtbar; Satzdefinition doppelt |
| Training, unten · 09b | 7/10 | Lesbare Routinen, alte gespeicherte Kachelanordnung kann neue Hierarchie verdecken |
| Live-Training · 10 | 5/10 | Mitteilungsdialog unterbricht den ersten Satz; Folgecommit blendet ihn in Tests aus |
| Pause · 11 | 7/10 | Klare Aktion unten, Zeile überspringt die Pause ohne Ansage |
| Nächster Satz · 12 | 6/10 | Große Reserve-Ziele, weiterhin unbeabsichtigte Vorbelegung und wenig Platz bei großer Schrift |
| Zusammenfassung · 13 | 6/10 | Beschriftung klarer, Wiederherstellung nach Abschluss noch nicht eindeutig |
| Gesundheit · 14 | 7/10 | Messwerte weiter vorgerückt, sichtbarer Vergleichszeitraum variabel |
| Körperalter · 14b | 6/10 | „Geschätzt“ und ganze Jahre, Alters- und Datenabdeckung zu großzügig |
| Körperalter-Faktoren · 14c | 6/10 | Abdeckung lesbar, fehlendes Krafttraining wird als Null behandelt |
| Körperalter-Methode · 14d | 7/10 | Quellen und Annahmen besser, Fenster und Gesamtbegrenzung unvollständig erklärt |
| Gesundheit, unten · 14e | 6/10 | Alter Messwert datiert, Herkunft und Frische bleiben schwer vergleichbar |
| HRV · 15 | 6/10 | Messpunkte klarer, letztes Datum abgeschnitten; Folgecommit richtet die Achse neu aus |
| Coach · 16 | 6/10 | Vier klare Einstiegsfragen und lokaler Modus, Unsicherheit fehlt im Rat |
| Coach-Antwort · 17 | 6/10 | Frage und Antwort unterscheidbar, Uhrzeit und Bedarf als Versprechen formuliert |
| Journal · 18 | 7/10 | Aufgeräumte binäre Felder, einige Labels mehrdeutig |
| Profil · 19 | 6/10 | Datenquelle und Importabschnitt klar; „180 von 180“ zählt Demo, obwohl kein Import stattfand |
| Onboarding, Routineneditor, Übungsdetail, externe Zustimmung | — | Code geprüft, keine passende Bildschirmaufnahme |

## Befunde

### R-02-01 · P0 · Apple-Health-Import · 01-Heute.jpg, 14-Gesundheit.jpg

**Beobachtung:** `HealthService.dailyValues`, `sleepNights` und `workouts` reduzieren Fehler auf leere Ergebnisse. `SyncStore.merge` ersetzt heute und gestern vollständig, sobald irgendwo in der neuen 180-Tage-Reihe ein Wert vorliegt. Scheitert beispielsweise nur der Schlafabruf, während Schritte eintreffen, kann eine schon angezeigte Nacht verschwinden. Für ältere Tage wird dagegen ein fehlender Wert aus dem Cache übernommen, auch wenn er absichtlich in Health gelöscht wurde. `DataHub.refresh` setzt `lastUpdate` anhand der zusammengeführten 30 Tage, daher auch mit ausschließlich alten Werten plus einem neuen Signal außerhalb dieser 30 Tage. Ein Schreibfehler im Cache bleibt durch `try?` unsichtbar.

**Warum falsch:** Leere Abfragen, vorübergehende Lesefehler und bestätigte Löschungen haben unterschiedliche Bedeutung. Der grüne „Stand“-Hinweis kann Aktualität vortäuschen. Schlaf, Erholung und Coach können gleichzeitig springen.

**Lösung:** `HealthService` soll je Messreihe Erfolg, leeres Ergebnis oder Fehler transportieren. In `SyncStore` nur fehlgeschlagene Messreihen als letzten Stand behalten. Bestätigte Löschungen aus einem HealthKit-Änderungsstrom berücksichtigen. `DataHub` braucht einen Zeitpunkt des letzten erfolgreichen Abrufs je Quelle und je Reihe sowie Messdatum am Wert. Speichern und Abrufen können getrennt scheitern. In `TodayView` „Schlaf von heute · Puls zuletzt gestern“ bzw. „Letzter Stand“ klar ausweisen. Prüffälle A-01/A-02.

### R-02-02 · P0 · Lokaler Gesundheits-Cache und Datenschutz · Profil, codebasiert

**Beobachtung:** `SyncStore.save` legt bis zu 180 Tage mit Schlaf, Herz, Aktivität und Trainings in `Application Support/forma-sync.json` ab. Dateischutz ist gesetzt, ein Backup-Ausschluss fehlt. `SyncStore.clear` wird aus der Oberfläche nicht aufgerufen. Ein leerer Abruf nach früheren Daten führt zu `.rejectedEmpty` und kann den alten Bestand auf unbestimmte Zeit sichtbar lassen. `ProfileView` verspricht bei lokalem Coach eine Verarbeitung auf dem iPhone.

**Warum falsch:** Ein rekonstruierbarer Gesundheits-Cache in Application Support fällt grundsätzlich in den regulären Backup-Bereich. Dateischutz allein regelt keinen Backup-Ausschluss. Eine tatsächliche Sicherung auf Maxis Gerät wurde hier nicht geprüft. Bei entzogenen Health-Berechtigungen kann die App die Lage nicht zuverlässig allein aus einem leeren Abruf erkennen.

**Lösung:** Cache in ein für Backups ausgeschlossenes Verzeichnis schreiben oder als rekonstruierbaren Cache führen. Bereits angelegte Datei beim Upgrade migrieren oder bereinigen. Im Profil „Apple-Health-Kopie in Forma löschen“ mit Bestätigung anbieten, Cache und Importstatus gemeinsam zurücksetzen. Bei leeren Abrufen Alter und Herkunft klar zeigen und künftige Verwendung zeitlich begrenzen. Keine Vermutung über Berechtigungen als Tatsache darstellen. Prüffall A-03. [Apple – Ordner und Backups](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively) · [Apple – HealthKit-Lesezugriff](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) · [Apple – App Review 5.1.3](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research)

### R-02-03 · P0 · Fehlende Daten und Coach · 01-Heute.jpg, 04-Erholung.jpg, 05-Erholung-unten.jpg, 08-Belastung.jpg, 16-Coach.jpg

**Beobachtung:** `DataHub.availability` prüft für Erholung HRV **oder** Ruhepuls, auch ohne die vier für die Baseline nötigen Vergleichswerte. Für Belastung reicht ein Schrittwert, der in `ScoreEngine.strain` gar nicht eingeht. Ohne Messwerte liefert `ScoreEngine` unverändert Erholung 41, Schlaf 0, Belastung 0 und Stress 1,2. Der Ring kann „–“ anzeigen, während `CoachView` die ungesicherten Scores für Tagesansage, lokale Antwort und ggf. externen Kontext verwendet. Erholungsmittel werden über Kalendertage statt verfügbare Bewertungen gebildet.

**Warum falsch:** „Keine Grundlage“ kann wie ein ruhiger, mäßig erholter Tag wirken. Wer nur Schritte hat, kann „Belastung 0“ als Messung lesen. Der externe Coach kennt den Unterschied nach der Übergabe ebenfalls nicht.

**Lösung:** Verfügbarkeit in `ScoreEngine` als Teil des Ergebnisses ableiten und durch `DataHub`, `RingDetailView`, `TodayView`, Wochenmittel und beide Coach-Wege tragen. Erholung nur aus klar benannten gemessenen Beiträgen. Keine Ziel-, Gewicht- oder Bettzeit-Anweisung aus unbelegten Scores. „Heute fehlen Messwerte“ mit verständlichem Weg zum Profil. Demo darf Vorschläge erläutern, aber keine echte Trainingsänderung speichern. Prüffälle A-04/A-05.

### R-02-04 · P0 · Satzabschluss aus zwei Eingaben · 10-Live-Training.jpg, 11-Pause.jpg, 12-Nächster-Satz.jpg

**Beobachtung:** `LiveWorkout.completeCurrentSet` prüft nur, ob ein aktueller Satz vorhanden ist. Nach dem Abschluss zieht `selectFirstOpen` sofort zum nächsten Satz. Eine bereits ausgelöste zweite Aktion hat keinen Bezug zur ursprünglichen Satz-ID und prüft auch keinen laufenden Timer. Ein Tippen auf eine offene Tabellenzeile beendet die Pause über `select` direkt. Schnelles Doppeltippen wurde nicht auf einem Gerät beobachtet. Der Modellpfad erlaubt zwei Abschlüsse aus zwei Aufrufen.

**Warum falsch:** Ein zusätzlicher, gar nicht absolvierter Satz landet im Training, Fortschritt und Wochenvolumen. Zeilenauswahl nimmt dem Nutzer die klar beschriftete Pausenentscheidung ab.

**Lösung:** Die vom Button angezeigte `LiveSet.id` an die Modellaktion binden. Nur genau diesen offenen Satz einmal abschließen. Während einer Pause explizit „Pause beenden“ verwenden. Haptik erst nach tatsächlich akzeptiertem Abschluss. Prüffall A-06.

### R-02-05 · P0 · Speichern und Wiederherstellung · 13-Zusammenfassung.jpg

**Beobachtung:** `LiveWorkout.save(into:)` speichert die Session erfolgreich in SwiftData. Erst danach löscht `LiveWorkoutView.finish` über `app.liveWorkout = nil` den Entwurf. `LiveWorkout.id` wird beim Restore neu erzeugt. `WorkoutSession` hat keine feste Abschlusskennung aus dem Entwurf, anhand derer die Wiederherstellung dieselbe bereits gespeicherte Session erkennen könnte. `context.rollback()` betrifft den gesamten übergebenen Kontext.

**Warum falsch:** Ein Abbruch zwischen erfolgreichem Commit und Bereinigung kann einen abgeschlossenen Entwurf erneut anbieten. Erneutes Speichern kann eine Einheit doppelt erfassen. Bei Einzel-Schreibfehlern können ausstehende, fachfremde Änderungen im gemeinsamen Kontext zurückgesetzt werden.

**Lösung:** Im Snapshot eine langlebige Abschluss-ID mitführen und die Session anhand dieser ID genau einmal speichern. Beim Start vorhandene Sessions prüfen und gespeicherte Entwürfe gezielt abschließen. In einem auf den Abschluss beschränkten Kontext oder mit gezielter Rücknahme arbeiten. Prüffall A-07.

### R-02-06 · P1 · Hintergrund-Import · Profil und Heute, codebasiert

**Beobachtung:** `DataHub.refresh` beendet einen parallel eingehenden Aufruf sofort und setzt nur `refreshPending`. `backgroundRefresh` und `scheduleRefresh` melden anschließend einen Hintergrundabruf und starten den Coach auch bei gesperrtem HealthKit, bei `.rejectedEmpty` oder bevor der nachgereichte Import fertig ist. `startObserving` fängt Registrierungsfehler ab, setzt `observersStarted` vor erfolgreichen Registrierungen. `BackgroundRefresh.schedule` ignoriert planungsbezogene Fehler. In der UI steht, der Coach meldet sich sobald die Nacht in Apple Health ankommt.

**Warum falsch:** Der Zustand „erfolgreich aktualisiert“ und die Coach-Auslösung fallen auseinander. iOS garantiert ab `earliestBeginDate` keinen Zeitpunkt. Apple rät dazu, HealthKit-Beobachter vor der Zustellung beim Start zu registrieren. Die tatsächliche Zustellung braucht ein Gerät.

**Lösung:** Einen geteilten Refresh-Task pro Quelle mit getyptem Ergebnis verwenden, wartende Aufrufer an dessen Abschluss hängen. Separat „letzter Versuch“, „letzter erfolgreicher Import“ und „wartet auf Entsperren“ anzeigen. Nur aus einem passenden, aktuellen Importergebnis den Bericht planen. Observer-Registrierung und `BGTaskScheduler`-Ergebnis ohne Messwerte protokollieren, fehlgeschlagene Typen erneut registrieren. `UIApplication.protectedDataDidBecomeAvailableNotification` für den Fortschritt nach Entsperren prüfen. „iOS bestimmt den Zeitpunkt“ im Profil. Prüffälle A-08/A-09. [Apple – Observer Queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries) · [Apple – BGTaskRequest](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate)

### R-02-07 · P1 · Coach im Hintergrund und Sperrbildschirm · 19-Profil.jpg, codebasiert

**Beobachtung:** Morgenbericht und Bettzeit stehen standardmäßig auf an. `requestHealthAccess` stößt die Systemabfrage für Benachrichtigungen an, bevor Nutzer den Coach-Bereich gesehen haben. `CoachNotifier` legt Schlafwert und Erholung in den Titel, HRV-Abweichungen können im Text stehen. Der Morgenstempel wird vor der Annahme der Mitteilung gesetzt. `sendMorningReportIfDue` prüft Schlaf, aber kein Datum von `hub.today` gegen den aktuellen Tag. Bei normalem manuellen `hub.refresh()` findet kein einheitlicher `afterSync`-Aufruf statt.

**Warum falsch:** Gesundheitswerte können abhängig von der iOS-Vorschau auf dem Sperrbildschirm stehen. Ein zugelassener Tagesbericht kann bei einer Ablehnung, einem Fehler oder einem veralteten Snapshot den Tag fälschlich als bedient behandeln.

**Lösung:** Separates Opt-in für den Bericht, standardmäßig „Dein Forma-Tagesbericht ist bereit“, Messwerte im Bericht innerhalb der App. Bei direkter Detailvorschau Optionen und Auswirkung erklären. Datum, Quellenstatus und `UNNotificationSettings` vor der Planung prüfen. Tagesstempel mit einem datierten Notification-Identifier erst nach erfolgreicher Annahme speichern und Fehlschläge erneut versuchen. Alle inhaltlich gleichwertigen Importwege durch denselben Abschluss führen. Prüffall A-10.

### R-02-08 · P1 · Bettzeit, Nacht und Zeitzone · 07-Schlaf-unten.jpg, 16-Coach.jpg

**Beobachtung:** `CoachEngine.bedtime` und `CoachNotifier.bedtimeDate` berechnen unabhängig mit 06:55. Der Notifier prüft für Bettzeit keinen aktuellen Datensatz und kann beim Einschalten im Profil auch aus Demo-Zahlen erinnern. Die bestehende Erinnerung wird vor neuer Validierung entfernt. Nach Mitternacht wird anhand des nächsten Kalendertags auf den folgenden Abend gezielt. Die Kalenderkomponenten der Mitteilung enthalten keine ausdrücklich festgelegte Zeitzone.

**Warum falsch:** Die angezeigte Uhrzeit kann vom Zeitpunkt der Mitteilung abweichen. Wer seine Schlafenszeit nach Mitternacht plant oder reist, kann den falschen Kalendertag erwischen. Eine Demo-Erinnerung wirkt persönlich.

**Lösung:** Eine gemeinsame Funktion für nächste Weckzeit, Bettzeit und Erinnerungsdatum mit injizierbarer Uhr und Kalender. Weckzeit im Profil. Erinnerungen nur nach bewusstem Opt-in und gegen aktuell gültige Grundlage, bestehende Planung gezielt ersetzen. Nach Zeit-/Zeitzonenwechsel neu planen. Maxis Gerät mit gesperrtem Telefon, Zeitzonenwechsel und Sommerzeit prüfen. Prüffall A-11.

### R-02-09 · P1 · Schlaf-Import und Nachtbewertung · 06-Schlaf.jpg, 07-Schlaf-unten.jpg

**Beobachtung:** `SleepNight.asleep` bildet die Vereinigung der Schlafintervalle. `total(.deep) + total(.rem)` summiert aber zwei getrennte Vereinigungen, sodass gegensätzliche Phasen mit Überlappung mehrfach in den Score gehen. `DayMetrics.sanitized` prüft Länge und Reihenfolge, schneidet Phasen nicht auf die Nachtgrenzen. `mainNights` kann ein Nickerchen bei einer Lücke unter 90 min anschließen. Die Wahl nahe am 15-min-Grenzwert hängt bei identisch eingestuften Quellen von der Iterationsreihenfolge ab. `ScoreEngine.scores` bewertet dieselbe Nacht mit dem aus heutiger Belastung berechneten Bedarf. Im 7-Nächte-Mittel zählen fehlende Nächte als null.

**Warum falsch:** Werte können sich ohne neu gemessenen Schlaf ändern. Ein Prozentwert und die Phasenlegende können dann unterschiedliche Grundlagen abbilden.

**Lösung:** `SleepNight` disjunkte, auf Nachtgrenzen zugeschnittene Phasen mit nachvollziehbarer Quellpriorität liefern lassen. Nickerchen als eigenen Eintrag erhalten, exakte Fremdphasen als „unbekannt“ führen. `ScoreEngine` den Referenzbedarf der betreffenden Nacht getrennt vom heutigen Bedarf geben. Im Wochenmittel nur gemessene Nächte mit `n/7` und Lücke zeichnen. Hypnogramm um eine zugängliche Phasenzusammenfassung ergänzen. Prüffälle A-12/A-13.

### R-02-10 · P1 · Körperalter, Datenabdeckung und Rundung · 03-Heute-unten.jpg, 14b-Körperalter.jpg, 14c-Körperalter-Faktoren.jpg, 14d-Körperalter-Methode.jpg

**Beobachtung:** `BodyAge.evaluate` kann ab 21 reinen Schritttagen ein Alter berechnen. Krafttraining wird auch ohne belegte Aufzeichnung als Faktor mit null Minuten gezählt. Für „Gut“ können 120 Tage mit irgendeinem Signal, je sieben Ruhepuls-/Schlafdaten und drei VO₂max-Tage reichen. Die Grenzwerte für Geburtsjahr werden in `ProfileView`, aber nicht in `DataHub.person` oder `PersonInfo.age` geprüft. Alterswerte außerhalb der FRIEND-Kohorte 20–79 werden an den Tabellenenden geklemmt. Bei einem Alter von 30,8 und einer modellierten Differenz von 0 kann die UI „31 Jahre“ und „Etwa 1 Jahr älter“ anzeigen. Der Text verspricht eine exakte Summe sichtbarer Zeilen trotz Halbjahres-Rundung und Gesamtbegrenzung.

**Warum falsch:** Die Datengrundlage wirkt vollständiger als sie ist. Ein vermeintlicher Jahresunterschied kann aus der Anzeige allein entstehen. Die Quellen stützen die Vergleiche auf Gruppenebene und decken das extrapolierte Alter nicht ab.

**Lösung:** Altersbereich und benötigte Messdichte pro Faktor im Modell prüfen. Fehlende Kraftaufzeichnungen separat anzeigen. Altersabweichung aus `bodyAge - age` vor dem Runden ableiten. Bereich und Text gemeinsam mit der ±15-Grenze führen und bei Begrenzung benennen, warum sich Anzeige und sichtbare Beiträge unterscheiden. „Geschätzt“ und Hinweis auf fehlende Validierung bereits an der Kachel. Den Nutzerwunsch zur Anzeige beibehalten. Prüffälle A-14/A-15. [FRIEND 2015, Tabelle 2](https://www.mayoclinicproceedings.org/article/S0025619615006424/pdf) · [Gurven et al. zu Verdopplungszeiten](https://pmc.ncbi.nlm.nih.gov/articles/PMC6121812/)

### R-02-11 · P1 · Körperalter, Vergleich und Kraftminuten · 14b-Körperalter.jpg, 14c-Körperalter-Faktoren.jpg

**Beobachtung:** Der neue 30/30-Vergleich ist zeitlich getrennt und verlangt gleiche Faktor-IDs. Gleiche IDs erlauben weiterhin ungleiche Dichte, etwa sieben gegenüber 30 Schlafnächten oder unterschiedlich alte VO₂max-Messungen. `BodyAge.strengthMinutes` verwendet je Tag das Maximum der Summe aus Forma und Health. Zwei unabhängige Einheiten am gleichen Tag gehen so nur teilweise ein. Der Steps-Faktor verwirft auch echte Tage mit höchstens 500 Schritten. `AgeScale` klemmt sichtbare Punkte schon bei ±12 Jahren, während `BodyAge` bis ±15 erlaubt.

**Warum falsch:** Ein scheinbar günstigerer Trend kann durch Stichprobenlücken entstehen. Der Skalenrand kann einen moderaten und einen maximalen Unterschied gleich anzeigen.

**Lösung:** Im Vergleich Mindestabdeckung pro Faktor und vergleichbare Messverteilung fordern und die beiden Zeiträume je mit Anzahl anzeigen. Kraftsessions per Zeit/Quelle gezielt deduplizieren, getrennte Sessions addieren. Schrittwerte bei belegter Messung einbeziehen und Nichttragezeiten gesondert markieren. Skala auf ±15 abstimmen, Enden beschriften. Prüffälle A-15/A-16.

### R-02-12 · P1 · Fortschritt und Gewichtsplanung · 09-Training.jpg, 10-Live-Training.jpg, 12-Nächster-Satz.jpg

**Beobachtung:** `Progression.plan` bezieht nur Sätze beim höchsten bisherigen Gewicht ein, filtert fehlende Reserve heraus und rechnet mit den übrigen Werten. Schon ein absolvierter Satz kann das Gewicht für alle geplanten Arbeitssätze um 2,5 kg anheben. `LiveWorkout.from` übernimmt dieses Ergebnis automatisch und verdeckt damit im Training den im Routineeditor gewählten Planwert. Reserve 2 ist im Dock weiterhin voreingestellt und bleibt satzübergreifend. Der letzte Session-Treffer kann nur Aufwärmsätze enthalten und frühere Arbeitssätze aus dem Vergleich verdrängen.

**Warum falsch:** Ein als Vorschlag betitelter Wert ist bereits wirksam. Reserve ohne Eingabe erscheint als Trainingsergebnis und kann in der nächsten Einheit dieselbe Steigerungsregel auslösen.

**Lösung:** Stärkebewertung an vollständige vergleichbare Arbeitssätze und erfasste Reserve binden. `Progression` liefert einen separaten Vorschlag. Dock zeigt bisherigen Plan und Änderung mit bewusster Übernahme. Reserve als optionalen Satzwert modellieren und leere Reserve neutral anzeigen. Für Verlauf den letzten relevanten Arbeitssatz suchen. Prüffälle A-17/A-18.

### R-02-13 · P1 · Persistierter Trainingszustand · 10-Live-Training.jpg bis 13-Zusammenfassung.jpg

**Beobachtung:** `LiveWorkout.restore` prüft Alter des Entwurfs, Index und globale Reserve, lässt aber leere Satzreihen, große Listen, unplausible Satzwerte und Timer aus einem decodierbaren alten Format weitgehend unverändert. `allDone` kann bei einer Übung ohne Sätze wahr sein. Nach dem letzten Satz eines Ein-Übungs-Trainings lässt `addSet` bei einem noch vorhandenen erledigten `currentSet` den Auswahlzeiger auf dem alten Satz. `persist` verschweigt Schreibprobleme. Ein Entwurf ab acht Stunden wird ohne Rückfrage entfernt.

**Warum falsch:** „Training beenden“ kann erscheinen, obwohl keine Einheit speicherbar ist. Ein hinzugefügter Satz ist möglicherweise offen, während der Dock weiter den erledigten Satz bedient. Ein später wieder geöffneter Entwurf kann ohne Hinweis fehlen.

**Lösung:** Versioniertes Snapshot-Schema und gemeinsame Grenzen für Serien, Gewicht, Wiederholungen, Datum und Timer. Leeren/abgelaufenen Entwurf sichtbar behandeln. Vor Restore und Mutation einen offenen Satz konsistent auswählen. Bei fehlgeschlagenem Entwurfsspeichern einen ehrlichen Status anzeigen. Prüffälle A-19/A-20.

### R-02-14 · P1 · Profil und Quellenwechsel · 19-Profil.jpg, 01-Heute.jpg, 14-Gesundheit.jpg

**Beobachtung:** 19 zeigt „Beispieldaten“ zweimal, zweimal „noch keiner“, „Jetzt synchronisieren“ und dazu „180 von 180“. Der Picker schreibt `preferredSource`. Ein unmittelbarer Reload ist im Picker nicht verdrahtet. Der neue „Jetzt synchronisieren“-Knopf ist während eines Abrufs gesperrt. Ein bereits begonnener Health-Import kann nach der Wahl „Beispieldaten“ noch alte Ergebnisse veröffentlichen. Ohne Health-Aufforderung liefert „Automatisch“ direkt `SampleData`. „Tage mit Daten“ zählt eine engere Menge an Messreihen als `SyncStore.hasData`.

**Warum falsch:** „Quelle“ und „Gerade aktiv“ bleiben ohne erkennbaren Übergang unterschiedlich. Die Antwort auf R-01-35 behauptet eine ausdrückliche Demowahl, der Automatikpfad zeigt weiterhin eine gekennzeichnete Fallback-Demo.

**Lösung:** `DataHub`-Aktion für Quellenwechsel mit Aktualisierungszustand und Versionsnummer des Auftrags. Ergebnisse eines überholten Imports verwerfen. Bei ausstehender Freigabe „Keine Gesundheitsdaten verbunden“ und einen separaten Einstieg „Demo ansehen“. Abdeckungszahl, Quelle und Kalenderzeitraum aus dem gleichen Statusmodell lesen. Im Demo-Modus „180 Beispieltage“ und „Mit Apple Health verbinden“ zeigen. Prüffall A-21.

### R-02-15 · P1 · Externer Coach, Zustimmung und Fehleranzeige · 16-Coach.jpg, 17-Coach-Antwort.jpg, 19-Profil.jpg

**Beobachtung:** `CoachView.send` prüft Zustimmung und Schlüssel vor dem Senden. Danach übernimmt der Task einen globalen Zustimmungsstand und kann nach 429, 5xx oder Zeitüberschreitung erneut senden. Widerruf und Schlüsselwechsel sind mit dem laufenden Task nicht gekoppelt. Der bisherige Verlauf kann auch Nachrichten enthalten, die über „Nur lokal antworten“ entstanden. Ein bis zu 12 Nachrichten langer Verlauf hat keine Obergrenze je Nachricht. Leere Antworten und lange Ausgabe werden bereits behandelt. Die zwei Versuche mit je 30 s Inaktivitäts-Timeout und 2 s Pause haben kein gemeinsames Deadline-Budget.

**Warum falsch:** Das Versprechen „nur lokal“ braucht eine Nachrichtengrenze oder eine spätere gezielte Freigabe. Nutzer erwarten, dass Widerruf auch ausstehende weitere Aufrufe stoppt. Der Ladeindikator nennt im Wartemoment keine Abbruchmöglichkeit.

**Lösung:** Bei Umschalten oder Widerruf ausstehende Arbeit abbrechen und erneute Versuche an die aktuelle Zustimmung binden. Lokale Nachrichten standardmäßig vom externen Verlauf ausschließen. Eindeutiges Zeitbudget, Größenlimit vor Serialisierung und übersetzte Rückfallmeldung. `Keychain.set` soll Status zurückgeben und vorhandene Einträge aktualisieren, da Löschen plus ignoriertes Ergebnis von `SecItemAdd` einen Speichererfolg vortäuschen kann. Prüffälle A-22/A-23. [Apple – Datenschutz, App Review 5.1.2](https://developer.apple.com/app-store/review/guidelines/#privacy)

### R-02-16 · P2 · Fitbit-Altcode und Google-Übergang · Profil, codebasiert

**Beobachtung:** Fitbit ist aus der normalen Einrichtung entfernt. `Forma/Resources/Info.plist` registriert weiter ein URL-Schema, `ProfileView.connectFitbit` hat keine sichtbare Schaltfläche und im Einstieg ist kein `onOpenURL` für Fitbit verbunden. `FitbitService.handleCallback` vergleicht den gespeicherten State, bindet den Callback dort nicht an Schema/Host und verbraucht den Zustand erst nach erfolgreichem asynchronem Austausch. `retryAfter` versteht positive Sekunden und begrenzt sie, aber keine HTTP-Datumsangabe. `FitbitTime.parse` lässt Kalender-Normalisierung zu. Die Google Health API ist noch nicht implementiert.

**Warum falsch:** In diesem Stand habe ich keinen erreichbaren Fitbit-Login und keine externe Ausnutzbarkeit festgestellt. Für einen neuen Importer dürfen alte Parser, Zeitannahmen und Callback-Lebensdauer nicht als fertig gelten.

**Lösung:** Nicht benötigten Alt-Login aus der ausgelieferten Oberfläche und URL-Konfiguration nehmen, Migration vorhandener lokaler Zugangsdaten klar festlegen. Für Google Google-OAuth, exakte Redirect-Identität, einzeln verbrauchbaren Autorisierungszustand, klare Quellen-/Zeitführung und Retry-Semantik verwenden. Die Endpunkte in R-01-37 bleiben der Entwurf. Abnahme mit Stubs ohne echte Kontodaten. Prüffälle A-24/A-25. [Google – Autorisierung und Umstieg](https://developers.google.com/health/migration/data-access) · [RFC 9110 – Retry-After](https://www.rfc-editor.org/rfc/rfc9110.html#name-retry-after)

### R-02-17 · P1 · Dynamic Type und Daumenzone · 01-Heute.jpg, 03b-Heute-anpassen.jpg, 12-Nächster-Satz.jpg, 14c-Körperalter-Faktoren.jpg, 16-Coach.jpg

**Beobachtung:** Semantische Fonts in `Theme.swift`, flexible `MetricRow` und größere Ja/Nein-Ziele sind echte Fortschritte. Der Trainings-Dock reserviert für fünf Reserve-Schaltflächen 220 pt plus rund 30 pt Zwischenraum, zusätzlich Beschriftung und Seitenpolster. Zwei Steppers teilen die verfügbare Breite horizontal. `LiveWorkoutView` hält Überschriften mit `.lineLimit(1)` und 0,8er-Verkleinerung fest. Einige Statuschips sind 26–30 pt hoch. `a811d51` begrenzt jetzt auch die Titel aller `WidgetCard`-Köpfe auf eine Zeile. Lange Labels wie „Letzte 30 Tage gegenüber den 30 Tagen davor“ brauchen bei großer Schrift weiterhin Platz.

**Warum falsch:** Die nächste Aktion muss auch mit größerer Schrift ohne Präzisionseingabe sichtbar bleiben. Schrumpfen innerer Beschriftungen untergräbt die Textvergrößerung. Ein winziges dekoratives Symbol ist unkritisch, eine aktive Schaltfläche braucht das geforderte Trefferziel.

**Lösung:** Reserve in ein umbruchfähiges Raster unter eigenem Label, Stepper bei großer Schrift vertikal und langen Übungsnamen zwei Zeilen geben. In `WidgetCard` bei großer Schrift Titel über Zusatzinformation stellen. In `InfoChip` bei Buttons ein separates 44-pt-Ziel mit `contentShape` sicherstellen. Achsen und feste Zahlen in `AgeScale`, Charts und Hero mit zugänglichen Textalternativen. Prüffall A-26. [Apple – Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

### R-02-18 · P2 · Glas, Kontrast und Bewegung · 02-Heute-gescrollt.jpg, 03b-Heute-anpassen.jpg, 11-Pause.jpg, 15-HRV.jpg

**Beobachtung:** Vier Tabs sind wieder dauerhaft erreichbar, der Schein in `ScreenBackground` ist kürzer, der Pause-Dock nutzt eine Glasebene. `textTertiary` wurde auf 56 %, `textQuaternary` auf 36 % Weiß angehoben. Im sRGB-Modell ergeben sich über `#202020` rund 6,01:1 und 3,29:1. Über einem helleren `#505050` wären es 3,80:1 und 2,49:1. Das sind Vergleichsrechnungen, keine Messung des simulierten Glases. `LiveWorkoutView` behält erzwungene Timer-, Zahlen-, Scroll- und Satzanimationen. `TileStack` animiert Drop-Highlight und `TileEditor` Reset/Einblenden teilweise unabhängig von „Bewegung reduzieren“.

**Warum falsch:** Verbesserte Grundkontraste garantieren keinen Kontrast über getöntem Glas. Wiederholte Bewegung beim Pausentimer berührt einen häufig verwendeten Ablauf. Der Nutzer hat mehr Glas gewünscht, deshalb ist funktionales Glas an klaren Aktionen passend.

**Lösung:** Finale Text- und Symbolkontraste auf der gerenderten Oberfläche prüfen (4,5:1 für kleinen Text, 3:1 für interaktive Konturen). In `LiveWorkoutView` und `TileEditor` die bereits in `Theme` verwendete Reduce-Motion-Abfrage durchreichen. Tab- und Dock-Glas belassen, feste Masken oder ruhige Unterlage an den Inhaltsgrenzen testen. Prüffall A-26. [Apple – Materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [WCAG 2.2](https://www.w3.org/TR/WCAG22/#contrast-minimum)

### R-02-19 · P2 · Kacheln, Speicherung und Drag-and-drop · 03b-Heute-anpassen.jpg, 09b-Training-unten.jpg, 14e-Gesundheit-unten.jpg

**Beobachtung:** Dubletten und unbekannte Reihenfolge-IDs werden verworfen, der Reset fragt nach und der Editor hat 44-pt-Rahmen. Drop bedeutet weiter ausschließlich „vor das Ziel“. Die rohe Zeichenkette gilt bereits als Drop-Payload, ein aus anderen Quellen stammender Text mit passendem Kachelnamen wird nicht vom eigenen Drag unterschieden. VoiceOver-Aktionen „Nach oben/unten“ bleiben an den Rändern auch bei wirkungsloser Änderung vorhanden. Ein älteres gespeichertes Layout behält seine alte Reihenfolge, auch wenn „Gesundheit“ für neue Nutzer jetzt die Messwerte zuerst zeigt.

**Warum falsch:** Die sichtbare Rückmeldung verspricht mehr als die Aktion leisten kann. Der Benutzer soll individuelle Layouts behalten können und zugleich eindeutig erkennen, was aktiv ist.

**Lösung:** Drop-Ziel am Listenende, typisierten Drag-Kontext verwenden und ungültige Ziele ablehnen. Unmögliche VoiceOver-Aktionen ausblenden und die Position ansagen. Layouts bestehender Nutzer erhalten, optional einen bewusst gewählten Reset für die neue Anordnung anbieten. Prüffall A-27.

### R-02-20 · P2 · Gesundheit und Chart-Zeitraum · 14-Gesundheit.jpg, 14e-Gesundheit-unten.jpg, 15-HRV.jpg

**Beobachtung:** In 15 stehen 30 Messpunkte und gut unterscheidbare Linien. Das letzte Datum endet trotz 6-pt-Rand im ersten oder zweiten Zeichen. Der Endpunkt liegt rund 6 pt links vom 60er-Achsenwert. `a811d51` ergänzt dafür `AxisMarks(preset: .aligned)`; die Wirkung ist im älteren Bild ungetestet. `selectedPoint` springt bei einer Lücke zur nächstliegenden Messung statt „Keine Messung“ anzuzeigen. Der große Wert im Detail berücksichtigt das Alter der letzten Messung nicht, obwohl die Übersichtszeile „zuletzt am …“ zeigt. Das persönliche Band verwendet weiterhin ein festes Referenzfenster mit mindestens vier Werten. Leere Reihe zeigt zunächst „0 Messungen · Finger …“, darunter den Leerzustand.

**Warum falsch:** Ein Finger auf einem leeren Tag kann einen weiter entfernten Tag erscheinen lassen. Eine Zahl von vor Wochen wirkt auf der Detailseite aktueller als in der Übersicht. Bei 7/14/30 Tagen sind Stichprobe und Referenzfenster beide nötig.

**Lösung:** Auf den gewählten Kalendertag abbilden, in Lücken „An diesem Tag keine Messung“. `selection` bei Fensterwechsel zurücksetzen. Datum und Anzahl der für den Vergleich verwendeten Werte deutlich anzeigen. Touch-Anleitung nur bei Daten. Rechts verankertes letztes Label oder bewusst weniger Achsenmarken einsetzen. ca. 12–16 pt Reserve mit unterschiedlichen Datumsformaten prüfen. Prüffall A-28.

### R-02-21 · P2 · Trainingseinheiten, Scheiben und Zusammenfassung · 09-Training.jpg, 10-Live-Training.jpg, 13-Zusammenfassung.jpg

**Beobachtung:** Live-Gewicht wird in 0,25-kg-Schritten gerundet, auch wenn die Oberfläche 5 lb pro Tap meint. Der Routineeditor ändert in lb weiterhin um 2,5 kg. Die Anzeige „Letztes Mal“ und Teile der Zusammenfassung bleiben in kg, „vorher …“ hängt gar keine Einheit an. Der Scheibenrechner verwendet starr eine 20-kg-Stange. `PlateMath` rundet Zwischenlasten und eine Greedy-Auswahl kann mit eigener Scheibenliste eine machbare Kombination übersehen. Das 1RM-Modell wird von Aufwärmsätzen im Übungsdetail nicht durchgehend getrennt.

**Warum falsch:** Im Krafttraining sind Einheit, Stange und Zahl gemeinsam die Anweisung. Eine korrekt wirkende Scheibenliste kann an einer anderen Stange zu falscher Last führen.

**Lösung:** In `WeightUnit` Eingabeschritt und Formatierung für Plan, Satz, Rückblick und Volumen zentral führen. Scheibenanzeige als „20-kg-Stange angenommen“ beschriften und von der tatsächlichen Zielmasse ableiten. Bei benutzerdefinierten Platten entweder notwendige Kombination prüfen oder die Schnittstelle auf die Standardliste verengen. Nur Arbeitssätze für Vergleiche verwenden. Prüffälle A-29/A-30.

### R-02-22 · P2 · Heute und Journal, Inhalte und Routinen · 01-Heute.jpg, 02-Heute-gescrollt.jpg, 03-Heute-unten.jpg, 18-Journal.jpg

**Beobachtung:** Die Chip-Knöpfe haben nun eine Aktion, der Einblick nennt Gruppen und Zusammenhang. „Als Nächstes“ und Coach können dennoch die rechnerische Bettzeit als Empfehlung zeigen, wenn die Basis fehlt. Die Energiekachel benennt Schätzung, aber `ScoreEngine` nutzt auch Tageszeit und Belastung. Fortschrittsbalken bei Schritten und Energie brauchen die Bezugsgröße am Wert. In 18 stehen „0 von 11“ und elf gleichartige Zeilen mit Ja/Nein. „Spät gegessen“ hat keine Referenz und „Dehnen / Mobility“ mischt Sprachen. „Wie am Vortag ausfüllen“ kann ohne Vorwerte weiterhin wirkungslos bleiben, das Speichern fängt Fehler still ab.

**Warum falsch:** Die Haupthandlung ist nützlich, wenn der Kontext stimmt. Beim Journal kann der Nutzer eine stattgefundene Übernahme annehmen und das Blatt verlassen.

**Lösung:** Datenabhängige Empfehlungen über R-02-03 stützen. Fortschritt nur mit explizitem Ziel anbieten. Im Journal „0 von 11 beantwortet“ und einfache, gleichartige Labels wie „Dehnen oder beweglich bleiben“ verwenden. Übernommene Anzahl und Fehler anzeigen, bei fehlenden Vorgaben die Schaltfläche deaktivieren. In „Als Nächstes“ „Training starten“ samt Routinennamen im 44-pt-Tippziel belassen. Prüffall A-31.

### R-02-23 · P1 · CI, Tests und Bildschirmherkunft · UI-Rundgang

**Beobachtung:** `FormaTests` sind im Workflow ein eigener blockierender Schritt. `b0b01b9` reiht die Jobs hintereinander, bei abgebrochenem IPA-Job wird der Bild- und Testjob übersprungen. Der UI-Schritt endet unabhängig vom Ergebnis mit `exit 0`, der Export toleriert Fehler. `ScreenTour` verwendet weiterhin optionale Schritte und feste Wartezeiten. Der Export ersetzt den Bildordner ohne Prüfung eines Mindest-Satzes und versucht, seine Bilder auf einen inzwischen weitergelaufenen Branch zu rebasen. Die Commit-Nachricht enthält den Build-SHA.

**Warum falsch:** Ein grüner Workflow kann fehlende oder einem älteren App-Code zugeordnete Screenshots hinterlassen. Die Hintergrundfunktionen sind auf dem Simulator grundsätzlich kein Nachweis.

**Lösung:** Stabile IDs für die Pflichtnavigation. Je Pflichtbild einen erwarteten Screen prüfen und erst nach vollständiger, valider Dateiliste veröffentlichen. Zu jedem Bildsatz Build-SHA und Run-ID speichern und am Review damit prüfen. Ergänzend Simulatorfälle für Teilimport, App-Restore und großen Text. Background Delivery, Benachrichtigungen und Sideloadly explizit am iPhone abnehmen. Prüffall A-32. [Apple – HKObserverQuery und Simulator](https://developer.apple.com/documentation/healthkit/hkobserverquery)

### R-02-24 · P1 · Kalender, Cache und veraltete Werte · 01-Heute.jpg, Profil, codebasiert

**Beobachtung:** `DataHub.init` setzt `longDays` direkt aus dem decodierten Snapshot. `today` greift auf `.last` zu und prüft den Kalendertag nicht. `SyncStore.merge` vergleicht absolute Tagesbeginn-Zeitpunkte. Dieselben Kalendertage können nach einem Wechsel der Zeitzone andere Schlüssel haben. `today` und `days` lesen während des gesperrten oder abgelehnten Imports den alten Bestand weiter. HealthKit-Abfragen haben ein Startdatum, aber keinen expliziten Endzeitpunkt für die aktuelle Messgrenze.

**Warum falsch:** Ein frischer Tag kann mit alten Scores starten. Dabei kann auch der Morgenbericht Arbeit aus dem falschen Datensatz ableiten, R-02-07. Der Datumstext „Heute“ wird unabhängig von der Quelle gerendert.

**Lösung:** `DataHub` soll aus Persistenz und Abfragen eine validierte, nach Datum normalisierte Reihe erstellen. Das Cache-Schema muss festhalten, wie ein Messzeitpunkt einem Tag zugeordnet wurde. Auf Mitternacht, Kalender-/Zeitzonenwechsel und längere Offline-Intervalle reagieren. Die heutigen Dienste liefern `nil` für nicht belegte heutige Werte, den letzten Stand mit Tagesdatum separat. Beim Decodieren Quelldaten, Reihenfolge und Fenster prüfen. Prüffall A-09.

### R-02-25 · P2 · Aktivitätszuordnung · 02-Heute-gescrollt.jpg, 08-Belastung.jpg, 13-Zusammenfassung.jpg

**Beobachtung:** `DataHub.days` fügt Forma-Einheiten bei jeder Auswertung zum Health-Array hinzu. Schon eine beliebige Überschneidung gilt als Duplikat. Ein in Health vorhandener Spaziergang und ein Forma-Krafttraining können sich zeitlich überschneiden. Der SwiftData-Trigger in `RootView` beobachtet nur die Anzahl, nicht veränderte Sessions mit gleicher Anzahl. Die Belastungsformel behandelt aktive Energie und Trainingsminuten weiterhin als additive Eingänge.

**Warum falsch:** Beim Vorliegen verschiedener Quellen zählt ein sichtbarer Eintrag je nach Überschneidung unterschiedlich. Änderung und Entfernung müssen denselben sichtbaren Verlauf aktualisieren.

**Lösung:** Einmal pro Import bzw. SwiftData-Änderung eine zusammengeführte Reihe aufbauen. Trainings-ID, Aktivitätsart und weitgehend gleichen Zeitraum als Duplikatbedingungen verwenden. Energie und Trainingszeit als Modellannahme am Belastungsscore erklären. Prüffall A-16 zusätzlich mit überschneidenden, aber unterschiedlichen Sportarten prüfen.

### R-02-26 · P1 · Erstes Training und Mitteilungsabfrage · 10-Live-Training.jpg, 11-Pause.jpg, 19-Profil.jpg

**Beobachtung:** In Bild 10 verdeckt die Systemabfrage die Satzliste und dimmt den gerade eingeblendeten Dock. `AppState.liveWorkout.didSet` fordert beim ersten Start und beim Wiederherstellen eines Entwurfs die Berechtigung an, unmittelbar mit dem Wechsel in das Training. `a811d51` deaktiviert die Anfrage für `-uitest`; der normale Einstieg ist gleich geblieben. Die Systemoberfläche war im Simulator Englisch. Daraus folgt keine fehlende deutsche App-Übersetzung.

**Warum falsch:** Für einen Satzabschluss braucht es keine Systemberechtigung. Die Abfrage erscheint in einem Moment ohne Kontext und blockiert den unmittelbar gewünschten Ablauf.

**Lösung:** „Pausenende als Mitteilung“ als verständliche, freiwillige Aktion in der Pausenansicht oder im Profil. Erst daraufhin die Systemberechtigung anfordern. Zustand Ablehnung mit weiter bedienbarem Timer behandeln. Wiederherstellung soll den laufenden Ablauf zeigen. Im UI-Test den Berechtigungszustand vor „Live-Training“ festlegen und die erste Aktion als erreichbar prüfen. Prüffall A-33.

### R-02-27 · P2 · Layout, Beschriftungen und Glas-Kanten · 01-Heute.jpg, 03b-Heute-anpassen.jpg, 04-Erholung.jpg, 06-Schlaf.jpg, 08-Belastung.jpg, 09-Training.jpg, 12-Nächster-Satz.jpg, 13-Zusammenfassung.jpg, 14-Gesundheit.jpg, 14b-Körperalter.jpg, 14e-Gesundheit-unten.jpg, 17-Coach-Antwort.jpg

**Beobachtung:** Auf 01 konkurrieren oben zwei runde Icons mit Datum/Badge, der Startknopf bleibt als klare Aktion erkennbar. In 03b liegen „Standard“, Titel und „Fertig“ auf einer Zeile, bei der unteren Kachel ist nur der Anschnitt zu sehen. In 04 muss die feste 60-pt-Ergebnis-Spalte „Schlafscore“ und „+6 Pkt“ auf drei Zeilen umbrechen. In 06 wird 93 im Ring und direkt darunter im Satz wiederholt. Auf 08 leuchtet die Wochenreihe durch die Tab-Leiste, und der Mittelwert ist beim Bildanschnitt kaum zu lesen. In 09 steht das Kriterium für harte Sätze im Kopf und nochmals im Leertext. Auf 12 steht am Rechner „Pro Seite: 25 + 1,25“ ohne Einheit direkt an der Ergebniszeile. 13 nutzt eine lange 1RM-Überschrift und Satzzeilen ohne Einheit. 14/14e brechen Atemfrequenz, Schlaf- und Kalorienbereiche an der Bereichsmarke um. Auf 14b heißt ein Zeitvergleich rechts „kaum Einfluss“, dieselbe Formulierung bezeichnet unten den Einfluss eines Faktors. Auf 17 verspricht die Antwort, man bekomme die errechnete Schlafdauer.

**Warum falsch:** Werte und Erklärungen müssen im richtigen Bezug lesbar bleiben. Sichtbare Kanten dürfen Platz für Glanz schaffen, ohne das nächste Label zu überdecken. Dasselbe Wort für zwei unterschiedliche Auswertungen verwischt die Bedeutung.

**Lösung:** `ContributionRow` als primäre Score-Punkte plus Messwert in einer zweiten Zeile mit natürlicher Breite; `MetricSummaryRow` kurze Bereiche mit geschützten Zahl/Einheit-Zusammenhängen und bei enger Breite umbruchfähigem Layout. Im `TileEditor` Reset als klare Aktion einer größeren Liste, im `StrainDetail` den Wochenwert über die Balken oder mit geprüftem Bottom-Inset setzen. Doppelten Satz-Hinweis in `TrainingView` zusammenziehen. „Pro Seite: 25 kg + 1,25 kg“ und kürzeres „Geschätztes Maximum für 1 Wiederholung“ in der Zusammenfassung testen. Auf 14b „Kein deutlicher Unterschied“ allein oder „unter ½ Jahr“. Coach-Text „Geschätzter Bedarf 8 h 16 min. Bei Wecker 6:55 Uhr: gegen 22:28 Uhr ins Bett“. Prüffälle A-26/A-28/A-29.

### Nachprüfung aller Befunde aus Runde 01

„Bestätigt“ bezeichnet beobachtbaren Code oder einen im Bild eindeutig erkennbaren Zustand. Bedienwirkung auf dem Gerät bleibt separat zu prüfen.

| Runde 01 | Ergebnis Runde 02 |
|---|---|
| R-01-01 | Teilweise. Schätzung, ganze Jahre und Datenabdeckung sind umgesetzt. Rundung und Mindestgrundlage bleiben offen, R-02-10. |
| R-01-02 | Alte Einrichtung aus Picker und Onboarding entfernt. Altcode behandelt 410 beim Daten-GET. Neue Google-Verbindung offen, R-02-16. |
| R-01-03 | Teilweise. Ringe und Ladehinweis verbessert. Engine, Coach und aktive Quelle sind noch widersprüchlich, R-02-01/03/14. |
| R-01-04 | Fehler kommt in der UI an, Entwurf wird gehalten. Dauerhafte Abschluss-ID und isolierte Rücknahme fehlen, R-02-05/13. |
| R-01-05 | Grenzen 34/35/39/55/56 und fehlende HRV im Tagessatz sind adressiert. Übrige Coach-Pfade bleiben offen, R-02-03. |
| R-01-06 | Quelltrennung und neutrale Phasengewichtung bestätigt. Überlappende Stufen, Zeitgrenze und Schlafvalidierung bleiben, R-02-09. |
| R-01-07 | Erstsende-Dialog, Modus und Widerruf bestätigt. Lokale Nachrichten und ausstehende Wiederholung offen, R-02-15. |
| R-01-08 | Direkte Studienlinks und einzelne Annahmen bestätigt. Die sichtbare Summenerklärung und Referenzgrenzen bleiben, R-02-10. |
| R-01-09 | 30/30 ohne Überlappung und ohne fortgeschriebene VO₂max-Werte bestätigt. Messdichte und Altersgrenzen offen, R-02-10/11. |
| R-01-10 | Semantische Fonts und flexiblere Zeilen in `539c0ff` bestätigt. Feste Dock-Geometrie bleibt, R-02-17. |
| R-01-11 | Höhere Opazität und hellere Achsen bestätigt. Gerichteter Kontrasttest für Glas und Farbakzente offen, R-02-18. |
| R-01-12 | Feste Tabs, reduzierter Schein und aktive Glas-Chips bestätigt. Transparenz und Trefferflächen am Gerät messen, R-02-17/18. |
| R-01-13 | Zusätzlicher Einstieg, 44 pt, Reset und Aktionen bestätigt. End-Drop weiterhin offen, R-02-19. |
| R-01-14 | Hauptanimationen teils abgesichert. Dock, Editor und neuer Import-Indikator prüfen, R-02-18. |
| R-01-15 | Routinenschaltfläche und beschriftete Ziele bestätigt. „Von 100“ ist in den Ring-Accessibility-Labels vorhanden. Sichtbare Einführung und Chip-Trefferflächen bleiben, R-02-17/22. |
| R-01-16 | Gruppengrößen, Zusammenhang und passende Coach-Abzweigung bestätigt. Mindestgröße bleibt kleiner Eigenwert und sollte im Einblick sichtbar bleiben. |
| R-01-17 | Wochenzeitraum, kg/lb und Schätzung verbessert. Fortschrittsbezug und getrennte Verfügbarkeit offen, R-02-03/22. |
| R-01-18 | Beitragspunkte und klare Vorzeichen bestätigt. `TrendRow` nimmt weiter den letzten Messwert ohne Datumslabel. Fehlender Schlaf bleibt numerisch wirksam, R-02-03/09/20. |
| R-01-19 | Zugänglicher Text zu Wochenbalken in `539c0ff` vorhanden. Unbekannte Tage und Mini-Charts sind weiterhin offen, R-02-03/09/20. |
| R-01-20 | „Schlafscore“, geschätzter Bedarf und Beispielwecker bestätigt. Festen Bedarf für die vergangene Nacht und eigene Weckzeit weiter priorisieren, R-02-08/09. |
| R-01-21 | „Schlafeffizienz“ und Zeitlabel bestätigt. Gesprochene Phasenzusammenfassung und eindeutige Zählung offen, R-02-09. |
| R-01-22 | Tagesmittel und Forma-Trainings in Belastung bestätigt. Die Überlappungsprüfung kann eine Forma-Einheit unterdrücken, auch bei unterschiedlicher Aktivität. Schritte bleiben ein falsches Verfügbarkeitssignal, R-02-03/25. |
| R-01-23 | „Höchstens 3“ und Ausschluss unbekannter Reserve bestätigt. Vorbelegte Reserve kann echte Einträge verfälschen, R-02-12. |
| R-01-24 | Freies Training beim Einstieg ergänzt. Position hängt bei älteren Installationen von gespeicherter Anordnung ab, R-02-19. |
| R-01-25 | Dock-Kopfzeile, kleinerer Leerraum und Statuslabel bestätigt. Erledigte Zeilen sind deaktiviert. Identität der Aktion offen, R-02-04/13. |
| R-01-26 | 44-pt-Reserve und Schutz bearbeiteter Folgelast bestätigt. Optionale Reserve, exakte Gewichtsschritte und direkte Eingabe offen, R-02-12/17/21. |
| R-01-27 | Nächster Satz und „Pause beenden“ vorhanden. Fokus am Ablaufende, Sprung durch Zeilentap und Bewegungsreduktion bleiben. Erstaufruf unterbricht den Ablauf mit Mitteilungsabfrage, R-02-04/18/26. |
| R-01-28 | Kurze Dauer und 1RM-Beschriftung verbessert. Satz-/Vergleichseinheiten und Arbeitssatzfilter bleiben, R-02-21. |
| R-01-29 | Weiter offen. Routineeditor, lb-Schritte und implizites Speichern bleiben Teil der Anschlussprüfung, R-02-21. |
| R-01-30 | Messwerte für Standardanordnung zuerst, persönliche Bereiche und Datum in Zeile bestätigt. Alte Layouts und Detailkontext offen, R-02-19/20. |
| R-01-31 | Lineare Segmente, Punkte, Leerzustand und Accessibility-Zusammenfassung vorhanden. Auswahl in Lücken und Datum im Kopf offen, R-02-20. |
| R-01-32 | Einheit, neutraler Faktor und gegliederte Methode bestätigt. Skala und konsistente Rundung offen, R-02-10/11. |
| R-01-33 | Lesbare Einstiegsfragen und Thema-Übergabe bestätigt. Externes Warten, lokaler Rückfall und Datenverfügbarkeit offen, R-02-03/15. |
| R-01-34 | Versprechen entfernt, größere Ja/Nein-Ziele und Frage als VoiceOver-Kontext in `539c0ff`. Übernahme und Persistenz offen, R-02-22. |
| R-01-35 | Importdatum, Hintergrundversuch und Abdeckung ergänzt. Fallback, Quelle im Übergang und Cache-Löschung offen, R-02-01/02/14. |
| R-01-36 | Mehr IDs und eigener Unit-Test-Schritt. Verbindliche Screenshot-Vollständigkeit und Gerätetest fehlen, R-02-23. |
| R-01-37 | Alte API zur Migration dokumentiert. Google-API-Importer, Projektzugang und echte Verbindung offen, R-02-16. |

### Bildschirmübergreifende Abnahme

1. Auf „Heute“ muss jeder Ring einen Wert mit Herkunft oder einen fehlenden Wert erklären. In der nächsten Karte und beim Coach gilt derselbe Zustand. Für Beispiele ist das Label direkt beim betroffenen Wert sichtbar.
2. Beim Training muss eine Hand Gewicht, Wiederholungen und den Satzabschluss erreichen. Bei großer Schrift und langen Namen müssen die aktive Übung und alle Eingaben lesbar bleiben. Kein interaktives Symbol verdeckt den Inhalt hinter dem Dock.
3. Gesundheit zeigt Messdatum und Fenster direkt am Wert. Apple Fitness macht seinen Bezugszeitraum explizit. Bevel und Oura erklären Datenfrische bzw. Kalibrierung am Modell. Forma kann diese klaren Bezüge für seine Schätzung und eigenen Karten übernehmen. [Apple Fitness – Trends](https://support.apple.com/en-ae/guide/iphone/iph4c34a8a95/27/ios/27) · [Bevel – Biological Age](https://help.bevel.health/en/articles/11586369) · [Oura – Cardiovascular Age](https://support.ouraring.com/hc/en-us/articles/28451491040019-Cardiovascular-Age)

## Angriffstest

Defensive Prüfung auf Basis des Quellcodes. Die folgenden XCTest-Vorschläge arbeiten mit in-memory SwiftData, temporär isolierten Test-Daten, injizierter Zeit und Stubs. Hintergrundzustellung, Gerätesperre und VoiceOver benötigen zusätzlich ein echtes iPhone. In diesem Review wurden weder echte Gesundheitswerte noch externe Konten oder Schlüssel verwendet.

| Angriff | Ergebnis laut Code | Risiko | Testfall |
|---|---|---|---|
| A-01 · Teilweiser Import | `SyncStore.merge` ersetzt die jüngsten zwei Tage als Ganzes. | P0 · Schlaf kann bei erfolgreichem Schrittimport verschwinden. | Gespeicherte Nacht, Health-Stub meldet Schlaf-Fehler und Schritte erfolgreich → Nacht als letzter Stand, Schritte frisch. Erzwungener Cache-Schreibfehler → beim Neustart kein fälschlich bestätigter Cache-Stand. |
| A-02 · Reguläre Health-Löschung oder alter Teilerfolg | Ältere `nil`-Felder fallen auf Cache zurück, `lastUpdate` folgt dem gemischten Bestand. | P0 · Entfernte Werte sichtbar, alte Werte wirken aktuell. | Löschung für früheren Tag im Stub → Messung entfernt. Erfolgreicher Abruf außerhalb der letzten 30 Tage → heutiger Status bleibt alt. |
| A-03 · Cache in Backup und Berechtigungsänderung | `Application Support`, kein Ausschluss, keine Nutzerlöschung. | P0 · Lokale Gesundheitskopie hat keinen vollständigen Lösch- oder Backuppfad. | Temporärer Speicher nach Migration → Cache-Verzeichnis vom Backup ausgeschlossen. Produktaktion „Kopie löschen“ → Dateien und Status entfernt, Neustart zeigt keine Kopie. |
| A-04 · Kein Tag, ein Tag, nur Schritte | Basiswerte bleiben numerisch, Verfügbarkeit und Berechnung laufen auseinander. | P0 · Unbelegte Empfehlung. | Leerer Tag und nur Schrittzahl → für Erholung und Belastung fehlende Grundlage, Coach liest dieselbe Darstellung. Echte aktive Energie von 0 → Messung vorhanden und 0. |
| A-05 · Demo und fehlende Baseline | Vorschlag prüft Schlaf und HRV, aber keinen Demo-Status und keine Baseline; Bestätigungen betreffen den echten Trainingsplan. | P0 · Beispieldaten können das Training ändern. | Vollständiges Demo-Profil, echter Trainingsplan → keine wirksame Planänderung. Ein HRV-Messwert ohne Referenz → keine persönliche Abweichung. |
| A-06 · Zwei Bestätigungen desselben Satzes | `completeCurrentSet` greift jeweils auf neuen Auswahlzustand zu. | P0 · Falscher Arbeitssatz in Historie. | Dieselbe modellierte Bestätigung zweimal, Stoppuhr aktiv → genau ein Satz geschlossen und Restzeit bleibt erhalten. |
| A-07 · Neustart direkt nach erfolgreichem Speichern | SwiftData und Entwurf sind getrennt und ohne gemeinsame Abschlusskennung. | P0 · Doppelte Session. | In-Memory-Speicher: erfolgreich abschließen, Entwurf noch vorhanden simulieren, zweimal wiederherstellen → exakt eine Session, kein offener Entwurf. Fehler beim Speichern → Entwurf bleibt. |
| A-08 · Gesperrt, parallel und abgebrochen | Hintergrundpfad setzt Versuchsstempel und ruft Coach nach vorzeitigem Refresh-Rücksprung. | P1 · Alter Gesundheitsstand kann Auslöser sein. | Stub pausiert Vordergrundabruf, zweiter Abruf und „Gerät gesperrt“ → kein Erfolgszeitpunkt und kein Bericht aus altem Stand. Entsperren → ein konsolidierter Nachlauf. |
| A-09 · Mitternacht, Reisen, langer Zeitraum | Cache sortiert nach absoluten `Date`-Schlüsseln, `today` liest `.last`, Tagesraster entsteht beim nächsten erfolgreichen Merge. | P1 · Gestern kann unter Heute stehen; alte Werte können bei Zonenwechsel aus der Tageszuordnung fallen. | Offline-Wiederstart am nächsten Tag und Zeitzonenwechsel → alter Wert als gestern, kein Heute-Score. Fenstertests 0, 1, 180 und sehr lange Historie → eindeutig datierte, auf das erlaubte Fenster begrenzte Tage. |
| A-10 · Bericht abgelehnt, zweimal gestartet, alter Snapshot | Stempel wird vor der Annahme gesetzt, Tag von `hub.today` wird nicht geprüft. | P1 · Bericht wird zu früh oder gar nicht als erneut versendbar markiert. | Fake-`UNUserNotificationCenter`: Annahme scheitert, danach Erfolg → genau ein akzeptierter Bericht. Snapshot von gestern → heute kein Bericht. |
| A-11 · Wecker, Reisetag und Sommerzeit | Fixe 6:55 und zwei Berechnungen; Zeitkomponenten ohne ausdrückliche Zone. | P1 · Falscher Tag oder Uhrzeit. | Kalender in `Europe/Berlin`, Abende vor beiden Umstellungen sowie regulärer Zugriff nach 00:00 → eindeutige nächste Weckzeit, identische UI- und Erinnerungszeit. Demo → keine Erinnerung. |
| A-12 · Überlappende Schlafphasen und Nickerchen | Vereinigung nur innerhalb einer Phase oder über Schlaf gesamt; separate Phasen können sich überlagern. | P1 · Phasenwerte stimmen nicht mit Nacht überein. | Stub mit zwei Quellen, Nickerchen, überlappenden Kategorien und unvollständigen Phasen → stabile Hauptnacht, disjunkte Phasensummen, unbekannter Anteil ausdrücklich markiert. |
| A-13 · Fehlende und wechselnde Tageswerte | Schlafscore für vergangene Nacht hängt von Tagesbelastung ab, leere Nächte sind 0 im Mittel. | P1 · Vergleich springt ohne neue Nacht. | Dieselbe vergangene Nacht vor/nach Training → gleicher Nacht-Score. Sechs Nächte fehlen → Mittel der einen Nacht und „1 von 7“. |
| A-14 · Geburtsjahr außerhalb der Profilwerte | Obergrenze ist nur in der Picker-Liste vorhanden. | P1 · Unplausibles Körperalter. | Künftiges Geburtsdatum sowie Alter außerhalb FRIEND → verständlicher Profilhinweis oder fehlender VO₂max-Vergleich, keine extrapolierte persönliche Zahl. |
| A-15 · Lücken- und Rundungsgrenzen | Tage und Faktor-IDs sind grobe Gates. Alter wird für Abweichung zweimal unterschiedlich gerundet. | P1 · Scheindifferenz. | Identisches chronologisches und modelliertes Alter 30,8 → gleiche Abweichung wie bei 30,0. Fälle 20/21 Tage, 2/3 VO₂max-Messtage und unterschiedliche Dichte → Schwelle und UI konsistent. |
| A-16 · Krafttraining aus zwei Quellen | Tagesmaximum unterschlägt separate Sessions. | P1 · Falsche Kraftminuten. | Gleicher Health-/Forma-Termin → einmal zählen. Zwei zeitlich getrennte Sitzungen am selben Tag → beide zählen. |
| A-17 · Abgebrochene Einheit als Fortschrittsbasis | `Progression` nimmt höchste Gewichtsgruppe, ein Arbeitssatz kann reichen. | P1 · Verfrühte Erhöhung. | Routine mit mehreren geplanten Sätzen, zuvor nur teilweise absolviert → Vorschlag erst nach vollständigem, vergleichbarem Satzsatz. |
| A-18 · Reserve nicht ausgefüllt | Globaler Standard 2 wird für jeden Arbeitssatz gespeichert. | P1 · Falsches Trainingsprotokoll und künstliche Verbesserung. | Ohne Reserve-Eingabe abschließen → unbekannte Reserve, keine Progressionsfreigabe daraus. |
| A-19 · Leerer Entwurf, zusätzliche Sätze | Leere Satzlisten können als fertig gelten. Auswahlinvariante nach `addSet` unvollständig. | P1 · Falscher Dock-Zustand. | Freies Training ohne Satz → kein Speicherversprechen. Nach letztem Satz einen weiteren hinzufügen → neu hinzugefügter Satz ausgewählt. |
| A-20 · Alte Datenformate und Mengengrenzen | Decode, Alterscheck und Indexcheck vorhanden. Werte und Menge sind nur bei einzelnen Eingabeaktionen begrenzt. | P1 · Fehler beim Wiederherstellen großer oder inkonsistenter Einheiten. | Test-Fixtures mit altem Snapshot-Schema, leerem Satz, sehr großer Satzliste, Gewicht 0/1000, abgelaufenem Timer → klare Ablehnung oder konsistente Normalisierung ohne stillen Verlust gültiger Sätze. |
| A-21 · Quelle wechseln während eines Abrufs | Picker ändert Wunschquelle, in-flight-Ergebnis prüft die aktuelle Wahl nicht. | P1 · Falsch beschriftete Quelldaten. | Health-Stub wartet, Picker wechselt zu Demo → Ergebnis des alten Abrufs wird nicht in der Demo-Ansicht veröffentlicht. |
| A-22 · Lokaler Chat, Zustimmung und Widerruf | Externer Pfad prüft globale Zustimmung beim Start, Verlauf und erneuter Versuch folgen unverändert. | P1 · Lokale Nachricht oder späterer Versuch kann entgegen Erwartung gesendet werden. | Injektierter Transport: lokale Unterhaltung, anschließend externe Freigabe → lokale Beiträge bleiben getrennt. Widerruf zwischen Versuchen → kein zweiter ausgehender Aufruf. |
| A-23 · Externe Antwort leer, sehr lang oder Fehler | Leere Antwort und Kürzung nach Decode vorhanden; Zeit- und Eingabebudget fehlt. | P1 · Blockierte Eingabe oder unklarer Rückfall. | Netzwerkstub für 200 leer/lang, 401, 429, 5xx und Timeout → begrenzte Ausgabe, erwartete Anzahl Versuche, Abbruch und klarer lokaler Rückfall. |
| A-24 · Legacy-Login und Auth-Zustand | Alte Route ohne sichtbaren Einstieg und ohne `onOpenURL`; bestehende State-Prüfung im Service. | P2 · Altlast für die Migration. | Produkt- und Stub-Tests: kein Legacy-Start aus der UI. Neuer Auth-Koordinator akzeptiert nur den passenden einmaligen Callback und meldet fremde/abgelaufene Zustände als Fehler, ohne Transportaufruf. |
| A-25 · Fremdformat und Wartezeit | Parser filtert mehrere Zahlen, Rundlauf über Kalender fehlt. `Retry-After` ist Sekunden-only und auf drei Stunden begrenzt. | P2 · Falsche Tageszuordnung oder Retry-Zeit. | Parser-Funktionsfälle mit leerem JSON, unplausiblem Kalendertag, ISO-Offset, ungültiger Dauer, Sekunden- und HTTP-Datum → erwartete Annahme/Ablehnung und nachvollziehbarer Backoff. Kein Live-Endpunkt nötig. |
| A-26 · Große Schrift, Reduce Motion, Rotation/Sperren | Semantische Fonts teils vorhanden, harte Dock-Geometrie und eigene Animationen bleiben. | P1 · Bedienelemente oder nächste Übung können unlesbar sein. | UI-Test auf kleinem iPhone bei AX5, Bewegung reduzieren und während Pause Hintergrund/Vordergrund → alle 44-pt-Ziele erreichbar, Timer-Termin stabil, kein zusätzlicher Abschluss. |
| A-27 · Gespeicherte Kacheln fehlen oder sind doppelt | Parser verwirft Dubletten, hängt fehlende Fälle an; Reset und Drag-Grenzen haben getrennte Wege. | P2 · Falsche Position oder wirkungslose Aktion. | Alter gespeicherter Zustand, alle ausgeblendet, doppelter Eintrag, letzte Position → gültige eindeutige Darstellung und erreichbare Wiederherstellung. |
| A-28 · Auswahl in einer Datenlücke | Nächstgelegener Messwert gewinnt immer. | P2 · Falsches Datum unter Finger. | Messungen an Tag 1 und 6, Auswahl an Tag 3 → „keine Messung“ und zugängliche Schrittwahl über echte Punkte. |
| A-29 · Gewichtswechsel und Tellerkombination | kg gerundet auch bei lb, Standardstange vorausgesetzt. | P2 · Irreführende Gewichts-/Scheibenanzeige. | 5-lb-Schritte mehrfach hoch/runter, Einheit zurückwechseln → keine Drift. Stangenlast und nicht darstellbare Ziele → korrekt beschriftetes Ergebnis oder `nil`. |
| A-30 · Zahlen unplausibel oder fehlend | `sanitized` filtert viele Health-Werte. `ScoreEngine.baseline` prüft Endlichkeit der Eingaben, nicht der Zwischensumme. Lokale Trainingswerte umgehen den Health-Filter. | P1 · Zahlengrenzen fehlen in tieferen Schichten. | Einheiten- und Modelltests für nicht endliche und außerhalb des Fachbereichs liegende Messwerte, große Zahlen und zu wenig Werte → fehlende Grundlage, kein Überlauf, stabile 0–100-Grenzen für gültige Scores. |
| A-31 · „Wie am Vortag“ mit leerem Journal | Stiller No-op; `try? context.save()` blendet Schreibfehler aus. | P2 · Falscher Eindruck einer erfolgreichen Übernahme. | Keine Vorwerte → klarer Hinweis. Erzwungener Schreibfehler → Meldung und wiederholbare Aktion. |
| A-32 · Pflichtbild fehlt und CI meldet Erfolg | UI-Testschritt und Export lassen Fehlschläge durch. | P1 · Visuell ungeprüfte Änderungen erscheinen abgenommen. | Testtour mit bewusst übersprungener Pflichtseite → Pflichtprüfung schlägt fehl, vorheriger Bildsatz bleibt, Build-SHA ist sichtbar. |
| A-33 · Erstes Training ohne Mitteilungsfreigabe | Start oder Restore fordert die Systemberechtigung an. | P1 · Einstieg in die erste Einheit unterbrochen. | Frische Installation und wiederhergestellter Entwurf → Satzabschluss erreichbar; Systemabfrage nur nach bewusster Aktion. Bei Ablehnung bleibt der Timer bedienbar. |

## Was bleiben soll

- Vier feste Tabs, matte Karten und eigene Datenfarben. Glas am interaktiven Dock und an der Navigation erhält Forma einen ruhigen nativen Auftritt.
- Ringe am Anfang von „Heute“, eigener Erklärweg pro Ring und der gestrichelte Zielbogen. Die Anzeige „–“ als Einstieg in einen klaren Zustand für fehlende Daten.
- Dock-Kopfzeile mit aktivem Satz, 44-pt-Reserve und „Pause beenden“. Den schnellen Zugriff unten behalten, die Bedienlogik an den sichtbaren Satz binden.
- Stabile eigene Layouts, bewusster Reset und semantische Typografie. Die neue flexible Metrikzeile für weitere feste Layouts nutzen.
- Körperalter mit transparenten Quellen und klarer Kennzeichnung als Schätzung. Den getrennten 30/30-Vergleich und die sichtbare Herkunft pro Faktor ausbauen.
- Lokaler Coach mit getrenntem externem Modus. Den Offline-Abruf aus dem letzten gültigen Stand beibehalten und Datenfrische und Einwilligung durch die Anzeige tragen.
