# Codex-Review 03 – 18.11.2026

Geprüfter Commit: `23c51a03fc98c53bbac863f9ae7e9ab63860ffa0` (App), `7006981` (Bildstand und Prüf-HEAD).

25 JPGs bei Standard-Schriftgröße im dunklen Simulator mit Beispieldaten geprüft. `docs/forma-screens/HERKUNFT.txt` weist denselben Build aus. GitHub meldet den Lauf als erfolgreich, einschließlich des Jobs mit verpflichtenden Unit-Tests. Der UI-Rundgang hat einen eigenen, nicht verpflichtenden Exitcode. Testanzahl und einzelne Testlogs konnte ich ohne GitHub-CLI-Anmeldung nicht einsehen. Windows bietet hier keinen iOS-Testlauf. Aussagen über Sperrbildschirm, HealthKit-Hintergrundzustellung, VoiceOver, Bedienungshilfen-Textgrößen und echten Claude-Abruf beruhen auf Code beziehungsweise auf vorgeschlagenen Gerätetests. Größen in pt stammen aus SwiftUI oder sind am Bild geschätzt. [CI-Lauf 44371941788](https://github.com/ma29xii/ma29xii.github.io/actions/runs/44371941788) · [Apple zu HealthKit-Beobachtern und Gerätetests](https://developer.apple.com/documentation/healthkit/executing-observer-queries)

## Gesamturteil

| Bildschirm | Note | Beobachtung |
|---|---:|---|
| Heute und Heute anpassen (01–03b) | 6/10 | Klare Ring-Hierarchie und ruhige Karten. Ein generischer Zeitstempel ersetzt das Messdatum, die Kachelköpfe sind klein. Bild 02 ist bytegleich mit 01. Das Ende in 03 zeigt tatsächlich die kompakte Ringleiste. |
| Erholung (04–05) | 5/10 | Messwerte und Punktbeiträge sind getrennt. „Schlafscore“ zerfällt im schmalen Feld. Detail und Wochenmittel können Ersatzwerte zeigen. |
| Schlaf (06–07) | 6/10 | Hypnogramm, Phasen und Wochenmittel sind gut gegliedert. Der Blick springt zwischen zwei Bedarfswerten und die Weckzeit-Zeile ist fest geschrieben. |
| Belastung (08) | 5/10 | Der Zielbogen und die Aufteilung in Aktivitäten und Kennzahlen funktionieren bei vollständigen Daten. Das leere Detail zeigt ein scheinbar persönliches Ziel. |
| Training und Bibliotheksübersicht (09/09b) | 7/10 | Eine auffällige primäre Aktion, ruhiger Verlauf. „Freies Training“ erscheint an zwei Stellen, die Bibliothekskachel mischt Nachschlagen und Starten. |
| Live-Training (10–12) | 7/10 | Abschluss und Pause in Daumenreichweite. Ein Übungstitel im Scrollinhalt wird hinter dem Dock angeschnitten. „RIR“ bleibt in der Tabelle unerklärt. |
| Zusammenfassung (13) | 7/10 | Satztyp und Volumen sind verständlich. Die 1RM-Überschrift braucht zwei Zeilen. Gewichtseinheiten sind über die Oberfläche hinweg inkonsistent. |
| Gesundheit (14/14e) und HRV (15) | 7/10 | Messwert, Einheit und persönlicher Bereich haben eine klare Ordnung. Der große letzte Wert hat kein Messdatum, mehrere Hilfstexte in kleinen Schriftgraden sind dicht. |
| Körperalter und Methode (14b–14d) | 6/10 | Schätzung und Quellen sind auffindbar. Grün, ganze Jahre und „Gut“ geben der Zahl mehr Gewissheit als die Datenabdeckung trägt. |
| Coach (16–17) | 6/10 | Herkunft der Antwort ist gut erkennbar. Eine kurze Antwort steht in einer hohen, weitgehend leeren Ansicht. Text und Logik beanspruchen in manchen Pfaden eine persönliche Empfehlung aus unvollständigen Daten. |
| Journal (18) | 7/10 | Lesbare Fragen und verständlicher Fortschritt. Der nach unten gewanderte Vortagsknopf ist im Bildausschnitt nicht belegt. |
| Profil (19) | 5/10 | Quelle und drei Sync-Zeitpunkte sind greifbar. „Health“, „Apple Health“, ein generisches „Tage mit Daten“ und die Berechtigungsführung bleiben verwechselbar. |

Die fünf wichtigsten Punkte:

1. **P0** – Beim ersten fehlgeschlagenen Apple-Health-Abruf können Beispieldaten als eigene Messungen erscheinen.
2. **P0** – Leere Abrufe und Löschungen sind weiterhin mehrdeutig. Ein Teilimport kann Erfolg melden, obwohl die Nacht aus dem alten Cache stammt.
3. **P0** – Leere Ringe öffnen Details mit Ersatzwerten und einem persönlichen Belastungsziel. Der Coach verwendet Teile desselben Fallbacks.
4. **P1** – Der Hintergrundabschluss wartet auf unterschiedliche Abrufstände. Der Zeitpunkt der Coach-Planung ist vom Abschluss des iOS-Hintergrundjobs entkoppelt.
5. **P1** – „Health“ ist auch Apples App-Name. Berechtigungsanleitung und Datenschutzhinweise brauchen eindeutige Rollen, gerade wenn Nutzer später Claude freischalten.

Apple Fitness führt vom Ring zum konkreten Tag. Bevel erklärt bei fehlender Erholung, welche Eingaben für die Berechnung fehlen. Oura beschreibt Beiträge mit ihren Vergleichszeiträumen und eine Einlernphase. Daraus leite ich für Health ein Ziel ab: Ring, Detail und Coach tragen dasselbe Datum, dieselbe Messbasis und denselben Leerzustand. Die eigene Ringanordnung passt dazu. [Apple Fitness](https://support.apple.com/de-de/guide/iphone/-iph4c34a8a95/ios) · [Bevel zu fehlender Erholung](https://help.bevel.health/en/articles/11258241) · [Oura zu Erholungsbeiträgen](https://support.ouraring.com/hc/en-us/articles/360057791533-Readiness-Contributors)

Unter den offenen Punkten aus Runde 02 haben Messdatum, Herkunft und abgesicherte Teilimporte höchste Priorität. P1 haben außerdem Diagnose des Hintergrundabrufs, Schlafphasen, Abdeckung im Körperalter-Vergleich, Duplikate und lb-Darstellung. Reine Kachelbedienung, die 1RM-Überschrift und der ausgeblendete Fitbit-Altpfad sind P2.

## Nachprüfung der Antwort auf Review 02

| Runde 02 | Code und Bildbeleg | Ergebnis |
|---|---|---|
| 01 Import | `HealthService.loadDays` kennzeichnet Fehler. `SyncStore.merge` erhält bekannte Fehlerreihen, der Löschtest behält eine weitere Reihe. 01/14 zeigen Demo, 19 nur Zeitstempel. | Teilweise. Leeres Ergebnis, letzte Löschung, Zeitstempel und Schreibfehler im Teilimport bleiben offen (R-03-01/02/03). |
| 02 Cache | `SyncStore.save` setzt den Backup-Ausschluss nach dem Schreiben, `ProfileView` bestätigt die Löschaktion. Die Aktion liegt unterhalb von Bild 19. | Teilweise. Die Löschung kann scheitern oder von einem laufenden Abruf überholt werden (R-03-03). |
| 03 Fehlende Daten | `DataHub.availability` verlangt Basisdaten. Auf 03 steht „7 von 7 Tagen mit Messwerten“. 04/05/08 zeigen den gut gefüllten Fall. `RingDetailView` und `CoachEngine` verwenden Fallbacks weiter. | Teilweise (R-03-04). |
| 04 Satzabschluss | `completeCurrentSet(id:)` prüft Satz-ID, Pause und Status. Haptik nach Annahme. `testDoubleTapCompletesOnce` und `testSelectKeepsRest` vorhanden. 10–12 zeigen die Zustände. | Modellpfad bestätigt. Doppeltipp und Bedienung im Hintergrund am Gerät offen. |
| 05 Speichern | `WorkoutSession.draftID`, Lookup beim Speichern und Restore-Abfrage vorhanden. 13 zeigt die Zusammenfassung. | Abschluss-ID bestätigt. Gemeinsamer Rollback und ignorierter Fetchfehler bleiben (R-03-12). |
| 06 Hintergrund | `inFlight`, `RefreshResult`, Entsperrbeobachter und Observer-Hinweise vorhanden. 19 belegt getrennte Anzeigen. | Teilweise. Abarbeitung, Tagesgrenze und Abbruch sind offen (R-03-05/06/09). |
| 07 Mitteilungen | `CoachNotifier` nutzt neutralen Standardtext, Datumsprüfung und write-after-add. 19 zeigt den Mitteilungsbereich nicht. | Teilweise. Kennung und Stempel allein serialisieren die Planung nicht. Verspätet gelesene Einstellungen und alte Anfragen bleiben relevant (R-03-07/08). |
| 08 Bettzeit | `bedtimePlan` wird von UI und Notifier verwendet. Mit Standardwecker nennen 07 und 17 dieselbe Bettzeit. `ProfileView` hat einen Weckzeit-Picker. | Teilweise. Fester Untertitel in 07, Mitternacht im Picker, Richtungswechsel der Uhr und veraltete Erinnerungen (R-03-08). |
| 09 Schlaf | `ScoreEngine` vereinigt Tief/REM und verwendet den Bedarf von gestern. 07 belegt Mittel und gemessene Nächte. Entsprechende Unit-Tests vorhanden. | Teilweise. Schlafdetail, Phasenlegende und leere Balken brauchen dieselbe Datengrundlage (R-03-10). |
| 10 Körperalter | Guard 18–90, VO₂max 20–79, kein reines Schritte-Modell, Kraftfaktor mit Aufzeichnung und ungerundete Differenz. 03/14b–d belegen Schätzungskennzeichnung, Faktoren und Quellen. | Genannte Guards bestätigt. „Gut“ und 30/30-Vergleich suggerieren weiter gleichmäßigere Abdeckung als berechnet (R-03-11). |
| 11 Vergleich | „jünger/älter“ auf 14b, Grenzen ±15 im Code. `BodyAge.strengthMinutes` vergleicht Kraft-Einheiten mit Forma-Zeiten. | Teilweise. Messdichte und Duplikate in der Quelle bleiben (R-03-11/17). |
| 12 Fortschritt | `Progression.plan` verlangt Zielwiederholungen, volle Satzzahl und bekannte Reserve. `LiveWorkoutView` bietet „Übernehmen“. 12 zeigt neutrale Reserve, die Fortschrittskarte ist im Rundgang unbesetzt. | Modell bestätigt. Einheiten in der Vorschlagszeile sind separat offen (R-03-14). |
| 13 Entwurf | `restore` begrenzt Daten und Laufzeit, `addSet` wählt den neuen Satz. Unit-Tests für Wiederherstellung, leeres Training und Satzauswahl vorhanden. | Teilweise. Versionswert wird geschrieben. Aktuelle Normalaktionen lassen mehr Zeilen zu als Restore übernimmt (R-03-12). |
| 14 Quellen | `preferredSource` erhöht `generation`. 19 zeigt Auswahl und aktive Quelle. | Teilweise. Bestehender Task läuft weiter, Demo kann umetikettiert werden, „180 Beispieltage“ fehlt (R-03-01/05/15). |
| 15 Claude | `CoachView` markiert lokal beantwortete Einträge, `ClaudeClient` filtert und deckelt Nachrichten. Widerruf cancelt, Prüfungen im Retrypfad vorhanden. 16/17 belegen lokalen Coach. | Kern bestätigt. Profil ignoriert Keychain-Status, externe Kontextwerte haben Lücken (R-03-04/15). |
| 16 Fitbit | Picker blendet Fitbit aus, Start migriert alte Präferenz. Profil zeigt aus Code „Wird umgestellt“ und bietet Entfernen der Altverbindung. | Altcode bleibt bis zum Importer offen, P2 im aktuellen Produktpfad (R-03-15). |
| 17 Dynamic Type | Stack-Wechsel bei Steppern, Reservebeschriftung und zweizeiliger Übungsname im Code. 10–12 zeigen Standardgröße. | Teilweise. Fünf Reservechips bleiben eine Zeile, feste Zahlenfonts und der Dock-Umfang bleiben zu prüfen (R-03-13). |
| 18 Glas und Bewegung | Dock, Tab-Leiste und Editor auf 03b/10–12 sichtbar. `Tiles` prüft Reduce Motion in Teilpfaden. | Teilweise. Animationen im Dock und Editor bleiben, Inhalt hinter Tab-Leiste ist auf 04/08/14c zu sehen (R-03-13). |
| 19 Kacheln | 03b zeigt Editor und Griffe. `Tiles` akzeptiert Strings und Ziele vor vorhandenen Kacheln. | Offen, P2. Editor und Kontextmenü bieten Verschieben ans Ende (R-03-18). |
| 20 Diagramm | `selectedPoint` prüft Kalendertag. Beim Zeitraumwechsel wird die Auswahl gelöscht, Leertext vorhanden. 15 zeigt Standardreihe und Picker. | Code bestätigt, Bild ohne Lücke. Messdatum und zugänglicher Tageswert offen (R-03-13/18). |
| 21 Einheiten | 10/12 belegen „kg“ und „20-kg-Stange“. Editor, Vorwerte und Vergleich nutzen gemischte Formatierung. | Teilweise, P1 (R-03-14). |
| 22 Journal | 18 zeigt „0 von 11“ und präzisere Fragen. Übernehmen und Fehlertext in `JournalView` vorhanden. | Text und Abfrage bestätigt. Speichern pro Zeile und Fehlerrückmeldung widersprechen sich beim Sammelvorgang (R-03-18). |
| 23 CI | `HERKUNFT.txt` und 12 Pflichtbilder im Workflow, alle 25 Dateien vorhanden. | Herkunft bestätigt. Gleiches Bild und maskierter UI-Exitcode lassen einen falschen Nachweis zu (R-03-16). |
| 24 Kalender | `normalized` füllt am Neustart den fehlenden Tag. `testNormalizedEndsToday` verwendet eine Zone. | Teilweise. Bereits laufende App und Reisen bleiben offen (R-03-09). |
| 25 Aktivitäten | 08 zeigt genau einen Demospaziergang. Code schließt Forma-Training anhand beliebiger Überlappung aus und dedupliziert Apple-Health-Einträge nicht. | Offen, P1 wegen Auswirkung auf die Belastung (R-03-17). |
| 26 Mitteilungsabfrage | 10/11 zeigen keinen Dialog beim Start und die freiwillige Aktion in der Pause. Code fragt auf Knopfdruck in Pause oder Profil. | Bestätigt im Ablauf und Code. Berechtigungswechsel am Gerät offen. |
| 27 Layout und Texte | 04 zeigt „Schlafs-core“ als sichtbaren Umbruch, 13 die zweizeilige 1RM-Überschrift, 14b „unter ½ Jahr“. `TileEditor` fragt vor Standard-Reset. | Zahlenformat und Bestätigung bestätigt. Übriges P2 (R-03-13/18). |

## Befunde

### R-03-01 · P0 · Falsche Datenquelle · 01-Heute.jpg, 14-Gesundheit.jpg, 19-Profil.jpg

**Beobachtung.** Nach einem Demo-Start kann der erste Apple-Health-Abruf komplett scheitern. `DataHub.performRefresh` setzt `activeSource = .health` vor dem Merge. Bei `.rejectedEmpty` ohne lokalen Health-Stand bleibt `longDays` unverändert. So verschwinden Badge und Demo-Schutz, obwohl dieselben Beispielwerte vorliegen. Beim Folgeabruf betrachtet `previous` diese Werte als Health-Stand und kann sie in fehlgeschlagenen Reihen übernehmen. Ein Neustart mit bereits gesetztem Freigabe-Flag, aber ohne Cache startet umgekehrt mit leeren Daten und `.sample` als aktiver Quelle. Die Bilder dokumentieren den korrekt gekennzeichneten Demo-Ausgangszustand.

**Warum falsch.** Erholung, Körperalter und Coach können erfundene Daten als persönliche Messungen verwenden. Bei einem nachfolgenden Teilimport können sie sogar im Health-Cache landen.

**Lösung.** In `DataHub.swift:112` und `:332–362` Daten, Quelle und Verfügbarkeit gemeinsam veröffentlichen. Der Health-Pfad darf als Altbestand nur einen nachweislich aus Apple Health stammenden Snapshot lesen. Beim Quellenwechsel ohne echten Stand leeres Health-Raster mit Lade- oder Fehlerhinweis zeigen. Prüffälle A-01/A-02.

### R-03-02 · P0 · Datenverlust, Löschungen und Frische · 01-Heute.jpg, 19-Profil.jpg

**Beobachtung.** `HealthService.ImportResult` kennt Fehler je Reihe. Ein erfolgreicher leerer Abruf wird dennoch implizit als Löschung geführt, sobald irgendwo anders Daten eintreffen. Bei vollständig leerem Abruf ohne Fehler bleiben sämtliche alten Werte, auch nach bestätigter Löschung des letzten Eintrags. Bei Teilfehlern prüft `DataHub` für `lastUpdate` nur, ob das *zusammengeführte* 30-Tage-Fenster Daten enthält. Einzig ein erhaltener Cachewert reicht. Bei Teilimport plus fehlgeschlagenem Cache-Schreiben wird der Schreibfehler vom Teilimporttext verdeckt. Der alte Status kann auf Heute als neuer „Stand“ erscheinen. Apples Lesefreigabe lässt sich aus einem leeren Resultat nicht ableiten.

**Warum falsch.** Gespeicherte Werte können bei unklarer Leselage aus dem Cache verschwinden oder nach erwiesener Löschung erhalten bleiben. Frische, Abruf und vorhandene Messung werden als dasselbe signalisiert.

**Lösung.** In `HealthService.swift:85–135`, `SyncStore.swift:75–119` und `DataHub.swift:334–362` Zustand und Zeitraum je Reihe erfassen. Bestätigte Löschungen über HealthKit-Änderungen und betroffene Tage nachführen. Bei leerer Sicht ohne Löschbeleg explizit den letzten Stand mit Datum zeigen. Fensterbegrenzungen der Lesefreigabe berücksichtigen und veraltete Werte nicht in automatische Empfehlungen übernehmen. Synchronisierungs-, Mess- und Schreibstatus getrennt in Heute und Profil ausgeben. A-03/A-04. [HealthKit-Lesefreigabe](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) · [HealthKit-Änderungsabfragen](https://developer.apple.com/documentation/healthkit/executing-anchored-object-queries)

### R-03-03 · P1 · Cache löschen und ohne Netz starten · 19-Profil.jpg, unterhalb des Bildes

**Beobachtung.** `SyncStore.clear` verschluckt Dateifehler und `deleteLocalHealthCopy` invalidiert keinen laufenden Import. Die Werte verschwinden aus dem Speicher, können aber nach dem Neustart oder einem Abschluss des alten Abrufs zurückkehren. `SyncStore.save` markiert den Backup-Ausschluss erst nach dem atomaren Ersetzen. Scheitert das Markieren, bleibt der neu geschriebene Snapshot liegen. Ein alter Cache wird beim Laden nicht nachmarkiert. Falls der letzte Messwert der jüngsten 30 Tage entfällt, setzt der Merge den Speicherzustand, der anschließende Guard überspringt jedoch den Datei-Commit. Der alte Wert kann dadurch beim nächsten Start kurz wieder auftauchen.

**Warum falsch.** Die UI vermittelt eine erledigte Datenschutzaktion und einen konsistenten Offline-Stand, die beide unter normalen Fehlerbedingungen auseinanderfallen können. Backup-Exposition auf dem Gerät ist ungeprüft.

**Lösung.** In `SyncStore.swift:17–47` ein dediziertes ausgeschlossenes Verzeichnis und die Migration des Altbestands absichern. Löschung quittieren, „Datei fehlt“ als erledigt behandeln, andere Fehler anzeigen. In `DataHub.swift:103–110` Generationswechsel beim Löschen und Publikationsgrenze für bereits gestartete Imports einsetzen. Eindeutig ermittelte leere Snapshots ebenfalls dauerhaft übernehmen. A-05/A-06. [Apple zum Backup-Ausschluss](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup)

### R-03-04 · P0 · Ersatzwerte in Details und Empfehlungen · 01-Heute.jpg, 04-Erholung.jpg, 05-Erholung-unten.jpg, 08-Belastung.jpg, 16-Coach.jpg

**Beobachtung.** `TodayView` leitet von leeren Ringen weiter. `RecoveryDetail` zeigt den ungeprüften Score, historisches Mittel aus allen Kalendertagen und „Schlafscore 0“ als Abzug. `StrainDetail` gibt „Noch unter dem Ziel“, Energie 0 und Schritte 0 aus. `TodayView` zeigt das Ziel auch ohne Erholungsbasis. Für Tage ohne Messung entsteht damit z. B. Erholung 41 und ein Ziel von 25–40. Auch `CoachEngine.localAnswer` hängt immer den Schlafwert an eine vorhandene Erholung. Der externe Kontext übergibt ohne passende Basis Energie, Stress, Schlafschuld und bei vorhandener Belastung auch das ungesicherte Ziel. In der Heute-Wochenkachel sind fehlende Tage inzwischen korrekt aus dem Erholungsmittel gefiltert.

**Warum falsch.** Fehlende Messungen werden zu einem persönlichen Trainingstipp. Mehrere Ansichten können gleichzeitig „keine Daten“ und ein konkretes Ergebnis zu denselben Werten ausgeben.

**Lösung.** Messbasis direkt mit der Bewertung führen und in `TodayView.swift:156–203`, `RingDetailView.swift:95–174,399–431` sowie `CoachEngine.swift:29–48,98–150` gemeinsam verwenden. Fehlende Beiträge als Lücke ausweisen. Ziel nur mit belegter Erholung führen. Einen reinen Grundbedarf klar benennen und den Zeitraum an Wochenmittel schreiben. A-07.

### R-03-05 · P1 · Gleichzeitige Abrufe und Abschluss · 19-Profil.jpg, codebasiert

**Beobachtung.** In `DataHub.refresh` hängt ein weiterer Aufrufer nur an `running.value`. Er kann dessen Ergebnis bekommen, während der mit seinem Signal angeforderte Nachlauf noch lädt. Der zuerst gestartete Aufrufer meldet am Ende immer den letzten Durchlauf, auch wenn dieser einen vorherigen Erfolg durch „unverändert“ überdeckt. Mehrere Aufrufer können für denselben Stand jeweils `afterSync` auslösen. Beim Quellenwechsel verhindert `generation` den späten Daten-Commit, der neue Quellenabruf wartet aber auf den alten. `scheduleRefresh` beendet einen verdrängten Debounce-Aufrufer vor der geplanten Abarbeitung, wodurch der zugehörige HealthKit-Callback bereits quittiert wird. `startObserving` markiert Typen erst nach einem `await`, zwei überlappende Registrierungen können dadurch Beobachter doppeln und Statusmeldungen überschreiben.

**Warum falsch.** Hintergrund-Abrufzeit, tatsächliche Abarbeitung und Coach können verschiedene Stände meinen. Ein langsamer alter Import kann die vom Nutzer neu gewählte Quelle blockieren.

**Lösung.** In `DataHub.swift:93–98,153–195,278–297` Anforderungen je Generation bündeln. Der Abschluss sollte die verarbeiteten Anstöße und den veröffentlichten Snapshot benennen. Verdrängte Observer-Callbacks erst nach Verarbeitung oder dauerhaft gesicherter Nachholung quittieren. In `HealthService.swift:40–69` Registrierung mit einem Zustand „läuft“ vor dem ersten Suspendierungspunkt serialisieren. A-08/A-09. [Apple zum Quittieren nach Abschluss](https://developer.apple.com/documentation/healthkit/executing-observer-queries)

### R-03-06 · P1 · Zeitbudget und Diagnose für Hintergrundabrufe · 19-Profil.jpg, codebasiert

**Beobachtung.** `FormaApp` plant den nächsten BG-Abruf erst nach der Arbeit. Das Ergebnis von `submit` wird verworfen. Die Ganzhistorie wird pro Abruf seriell über neun Abfragen geladen. Tasks für Refresh und Coach sind unstrukturiert erzeugt. Der BG-Handler wartet auf den Import, aber nicht auf die Mitteilungsplanung. Der Abruf prüft geschützte Daten nur vor den Abfragen. Sperrt das Gerät mitten im Ablauf, setzt der Fehlerpfad kein `waitingForUnlock`. HealthKit-Callbackfehler werden quittiert und verworfen. Die Beobachter melden Änderungen nur für sechs der neun importierten Reihen. Automatische Zustellung nach Force-Quit bleibt geräteabhängig und ungeprüft.

**Warum falsch.** Bei Zeitablauf und Kaltstart ist die Nachholung nicht nachweisbar. „Regelmäßiger Hintergrundabruf“ im Profil verspricht mehr, als die Diagnose belegt.

**Lösung.** In `FormaApp.swift:22–26,103–107` bei Start des Hintergrundjobs die nächste Gelegenheit einplanen, Ergebnis sichtbar machen und Zeitablauf bis zum Refresh-Abschluss propagieren. In `HealthService` mit einem begrenzten inkrementellen Hintergrundabruf beginnen. Anstehende Nachholung bei Sperre während einer Abfrage markieren. Coach-Planung im Budget abwarten oder als anstehende Arbeit sichern. T-50 bis T-53 um Start aus geschlossenem Zustand, Gerätesperre während des Imports und deaktivierte Hintergrundaktualisierung erweitern. A-10/A-11. [Apple zu Dauer und Terminierung von Hintergrundaufgaben](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)

### R-03-07 · P1 · Morgenbericht und Konfigurationswechsel · Profil, Sperrbildschirm und 16-Coach.jpg

**Beobachtung.** `RefreshResult.isFresh` akzeptiert jeden Teilimport. `CoachNotifier.afterSync` liest den veränderlichen Hub erst nach einer asynchronen Berechtigungsabfrage. Ein heutiger Schlafwert im Cache reicht selbst dann, wenn genau der Schlafabruf fehlgeschlagen ist. Zusätzlich rufen App-Start, App-Aktivierung, Pull-to-Refresh und „Jetzt synchronisieren“ nur `refresh()` auf. Damit kann die einzige erfolgreiche Synchronisierung des Morgens ohne automatische Berichtsauslösung enden. Zwei Aufrufe können vor dem `await add` beide denselben ungesetzten Tagesstempel sehen. Dieselbe ID ersetzt nach Apple eine noch geplante Mitteilung. Ein einzelner sichtbarer Banner für parallele sofortige Anfragen ist dadurch auf Codeebene nicht belegt.

**Warum falsch.** „Dein Tagesbericht ist bereit“ kann auf einem veralteten Stand beruhen, fehlen oder doppelt ausgelöst werden.

**Lösung.** In `DataHub.swift:185–195` und `CoachNotifier.swift:36–76` einen unveränderlichen, freigegebenen Importstand mit Messdatum und Zustand der Schlafreihe verwenden. Jeden erfolgreichen Eingangsweg über denselben Abschluss führen. Tageszustand mit reservierter ID vor dem ersten `await`, Wiederholbarkeit nach Fehler und erneuter Prüfung der Einstellungen direkt vor der Planung. A-12/A-13. [Apple zur Kennung von Mitteilungen](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/identifier)

### R-03-08 · P1 · Bettzeit, Wecker und schon geplante Mitteilungen · 07-Schlaf-unten.jpg, 17-Coach-Antwort.jpg, 19-Profil.jpg

**Beobachtung.** `RingDetailView` zeigt immer „Beispiel: Wecker um 6:55“, obwohl die Uhrzeit aus dem Profil in den Plan eingeht. Der Picker akzeptiert 00:00, `CoachNotifier.wakeMinutes` interpretiert 0 als fehlende Eingabe und nimmt 06:55. `bedtimePlan` setzt die Uhrzeit einmal und addiert dann Tage. Wurde die Uhrzeit an einem DST-Wechsel auf eine gültige Zeit gerundet, kann die gerundete Stunde in den Folgetag wandern. Die geplante Erinnerung ist an die vorherige Zeitzone gebunden. Ein planloser oder bereits verstrichener Abend räumt den vorherigen Auftrag nicht durchgängig weg. Quellenwechsel, Cache-Löschen und „Werte in Mitteilungen zeigen“ aus stoßen keine Neuplanung an. Ein schon geplanter Text kann weiterhin den geschätzten Bedarf und die aus der Weckzeit abgeleiteten Zeiten enthalten, auch wenn die Option davor geändert wurde. Die Abendplanung lässt auch eine frische Health-Quelle ohne verwertbare aktuelle Schlaf- oder Belastungsbasis zu, wenn sie aus dem Profil gestartet wird.

**Warum falsch.** Falsche Weckzeit, falscher Reiseabend oder unerwartete Vorschau auf dem Sperrbildschirm. Der Befund zum Auftrag ist codebasiert. Auslieferung und Vorschau hängen von iOS-Einstellungen ab.

**Lösung.** In `CoachNotifier.swift:21–24,80–116` Standard bei fehlendem Wert von Mitternacht unterscheiden, gewünschte Uhrzeit pro Kalendertag setzen und explizite Regeln für fehlende oder doppelte Stunden testen. `ProfileView.swift:137–155` auch auf Detailschalter reagieren lassen. Bei Zeit-/Zeitzonenwechsel, Quellenwechsel und Löschung ausstehende Aufträge neu berechnen oder entfernen. Mit ausgeschalteten Werten einen generischen Erinnerungstext verwenden. In `RingDetailView.swift:274` Uhrzeit dynamisch aus demselben Plan anzeigen. A-14/A-15.

### R-03-09 · P1 · Mitternacht und Zeitzone bei Cache und Import · 01-Heute.jpg, 19-Profil.jpg

**Beobachtung.** `DataHub.today` nimmt immer die letzte Zeile. Wenn die App über Mitternacht aktiv bleibt oder der Health-Abruf gesperrt ist, kann der Heutekopf das neue Datum über den alten Ringwerten zeigen. `SyncStore.normalized` deutet ein altes absolutes Mitternachtsdatum in der neuen Zeitzone. Berlin → New York kann denselben Kalendertag auf den vorherigen verschieben. Zudem verwendet `HealthService` die Uhr mehrfach während eines Abrufs und `SyncStore.merge` vergleicht Tagesanfänge mit exakter Date-Gleichheit. Ein Teilimport direkt nach Zonenwechsel kann deshalb alte fehlgeschlagene Reihen verfehlen. Die Demo-Bilder zeigen nur einen Tag in einer Zone.

**Warum falsch.** Der sichtbare Kalender und die Werte verlieren die gemeinsame Zeitbasis. Tagesvergleiche und Datenstand werden bei Reise, Schlaf und länger offener App unzuverlässig.

**Lösung.** In `Metrics.swift:189–202`, `DataHub.swift:217,325–362` und `SyncStore.swift:50–66,85–119` ein kalendergebundenes Importfenster pro Job verwenden. Persistierte Tagesdaten mit zivilem Datum und Herkunftszeitzone beschriften. Beim Wechsel neu aggregieren oder Altstand samt Herkunftsdatum zeigen. Heute bei Tageswechsel und beim Öffnen anhand Kalenderdatum wählen. A-16/A-17.

### R-03-10 · P1 · Schlafanteil und Phasen · 06-Schlaf.jpg, 07-Schlaf-unten.jpg

**Beobachtung.** Bild 06 zeigt 7 h 20 min, Score 93 und „88 % des geschätzten Bedarfs“. `ScoreEngine` nutzt für den Score den Bedarf von gestern. `SleepDetail` rechnet die Prozentzeile mit `s.sleepNeed` für heute Abend. Training kann nur den Prozentwert der schon vergangenen Nacht verändern. Bei fehlender Nacht zeigt das Detail im Ring weiterhin eine 0. Im Wochenchart baut `DayBars` aus fehlenden Nächten 4-pt-Balken und liest sie VoiceOver als null vor. Überlappende Phasen sind nur im Score vereinigt. Legende, Hypnogramm und die Auswahl der Hauptnacht verarbeiten weiterhin überlappende oder unterschiedlich weit reichende Blöcke. Ein Tracker mit ähnlich langen Nächten hat bei exaktem Gleichstand keine dokumentierte stabile Priorität.

**Warum falsch.** Die Zahlen erklären sich gegenseitig nicht. Die Legende kann mehr Zeit anzeigen, als seit dem Einschlafen vergangen ist. Ein Nickerchen kann bei kurzen Trennlücken den Nachtschlaf verlängern.

**Lösung.** In `ScoreEngine.swift:67–83` den Bedarf der bewerteten Nacht ausgeben. `RingDetailView.swift:238–289` darauf stützen und `DayBars` optionale Werte mit Lücke und „keine Messung“ führen lassen. `Metrics.swift:20–36,98–151` Phasen zuschneiden und nach stabiler Regel eindeutig auflösen. Nickerchen separat zeigen, wenn belastbar. A-18.

### R-03-11 · P1 · Aussagekraft von Körperalter und Vergleich · 03-Heute-unten.jpg, 14b-Körperalter.jpg, 14c-Körperalter-Faktoren.jpg, 14d-Körperalter-Methode.jpg

**Beobachtung.** `BodyAge.evaluate` prüft im 30/30-Vergleich dieselben Faktor-IDs und genügend Tage mit irgendeinem Signal. Sieben gegenüber 30 gemessenen Nächten können denselben Faktor liefern. Ein einziges erfasstes Krafttraining im Langzeitfenster macht „0 Minuten Krafttraining“ in beiden Teilfenstern zu einem Faktor, auch wenn dort die Aufzeichnung fehlt. „Gut“ auf 14c bezieht sich auf formale Abdeckung. Auf 14b verstärken ein grüner 27er und „3 Jahre jünger“ den Eindruck einer individuellen biologischen Messung. Die eingebundenen Studien betreffen Zusammenhänge in Gruppen. Die Umrechnung mit Dämpfung und Altersgrenzen bleibt ein eigenes Schätzmodell der App.

**Warum falsch.** Messdichte und beobachteter Verlauf können sich verwechseln. Der methodische Hinweis liegt auf der Karte in Kleinschrift und auf der Detailseite tiefer als die Aussage.

**Lösung.** In `BodyAge.swift:117–145,158–245,297–318` Schwellen pro Faktor und vergleichbare Verteilung der Beobachtungen fordern. Kraftaufzeichnung je Fenster prüfen, Schrittwert 0 nur bei belegter Erfassung übernehmen, Strecken mit fehlender Aufzeichnung markieren. In `BodyAgeView.swift:186–245` vor der Vergleichszahl „Schätzung aus deinen Aufzeichnungen“ und in der Abdeckung konkrete Faktoren nennen. Den Vergleich bei ungleicher Basis mit Grund ausblenden. A-19.

### R-03-12 · P1 · Erhalt des Trainingsentwurfs · 10-Live-Training.jpg, 13-Zusammenfassung.jpg

**Beobachtung.** `AppState.LiveWorkout.save` nimmt einen Fetchfehler für die Abschluss-ID als „keine Einheit gefunden“ und speichert weiter. Der folgende Fehlerpfad rollt den gesamten gemeinsamen Kontext zurück. Restore kürzt auf 30 Übungen und 50 Sätze je Übung. `addSet` und `addExercise` begrenzen die gleichen Werte in der Live-Ansicht nicht. Ein normal angelegter größerer Entwurf kann nach Wiederherstellung dadurch kürzer sein. Das Versionsfeld erzwingt keine Verarbeitung unbekannter künftiger Versionen.

**Warum falsch.** Nutzer können einen kompletten Trainingsstand gespeichert sehen, der beim Neustart kürzer ausfällt. Bei vorübergehendem Persistenzfehler ist Mehrfachanlage möglich.

**Lösung.** In `AppState.swift:198–238,381–397,409–436` dieselben fachlichen Grenzen beim Hinzufügen und Wiederherstellen verwenden oder gültige Altstände vollständig laden. Persistenzfehler von „keine Einheit“ unterscheiden. Abschluss in eigenem Schreibkontext mit eindeutiger Abschluss-ID speichern. A-20.

### R-03-13 · P1 · Lesbarkeit, Trefferflächen und Live-Dock · 01-Heute.jpg, 04-Erholung.jpg, 10-Live-Training.jpg, 11-Pause.jpg, 12-Nächster-Satz.jpg, 15-HRV.jpg

**Beobachtung.** `InfoChip` ist 30 pt hoch und wird direkt als Buttonlabel verwendet. Die 60-pt-Spalte im `ContributionRow` bricht „Schlafscore 93“ auf Bild 04 mitten im Begriff. Die festbreite Balkenspalte nimmt weitere 120 pt ein. Das Live-Dock staffelt zwar Stepper und Reservebeschriftung, bietet aber fünf 44-pt-Knöpfe in *einer* Zeile und eine feste 22-pt-Zahl. Auf 11 ragt schon bei Standardgröße ein angeschnittener Übungstitel hinter die Glasfläche. Zeilenauswahl und Reserve haben VoiceOver-Labels. Der Pausentext und mehrere animierte Wechsel hängen nicht an Reduce Motion. `Theme.textSecondary` erreicht rechnerisch ungefähr 6,5:1 auf `#151515` und 4,9:1 auf `#2D2D2D`. Rastertext und Material hinter dem Dock schwanken. Ein JPEG ist dafür keine dynamische Kontrastprüfung.

**Warum falsch.** Kritische Ziele sind bei großen Schriftgrößen zu gedrängt. Ein visueller Glaseffekt kann zusätzlich Klarheit kosten und kleine Ziele erschweren die Einhandbedienung.

**Lösung.** In `Components.swift:152–166` visuelle Chips bei 30 pt belassen und mindestens 44 pt antippbaren Bereich vorsehen. In `RingDetailView.swift:179–205` Betrag und Einheit bei größerem Text unter dem Titel platzieren. In `LiveWorkoutView.swift:35–45,166–316` den Dock-Inhalt an Textgröße und verfügbare Höhe koppeln, Reserve bei Bedarf umbrechen, RIR als „Reserve“ definieren und Reduce Motion durchreichen. Die Glashierarchie als Navigations- und Bedienebene erhalten, unter dem Dock einen klaren Scrollabschluss schaffen. Für HRV den ausgewählten Tageswert auch als zugängliche Beschreibung anbieten. A-21. [Apple HIG zur Barrierefreiheit](https://developer.apple.com/design/human-interface-guidelines/accessibility)

### R-03-14 · P1 · Trainingsgewichte und Einheiten · 10-Live-Training.jpg, 12-Nächster-Satz.jpg, 13-Zusammenfassung.jpg

**Beobachtung.** Der Routineneditor formatiert kg oder lb, der Stepper verändert aber intern in 2,5-kg-Schritten. Die Live-Ansicht verwendet eigene Schrittweiten. „Letztes Mal“ und Fortschrittstexte kommen als vorformatierte kg-Strings aus `AppState`. Vergleich und 1RM zeigen in `WorkoutSummaryView` kg, auch wenn Trainingsvolumen in lb dargestellt wird. Die Screenshots zeigen ausschließlich kg.

**Warum falsch.** Wer mit lb trainiert, kann ein anders gemeintes Gewicht auflegen. Das fällt besonders bei den kurzen Rückblicken ohne eindeutige Einheit auf.

**Lösung.** In `AppState.swift:108–122,243–271` numerische Vorwerte und Deltas erhalten, erst beim Rendern formatieren. In `RoutineEditorView.swift:94–102`, `LiveWorkoutView` und `WorkoutSummaryView.swift:43–51,107–117` dieselbe Gewichtseinheit und nachvollziehbare Schrittweite verwenden. Scheibensatz nur anzeigen, wenn er zur Stange und Einheit passt. A-22.

### R-03-15 · P1 · App-Name, Berechtigung und Datenschutztext · 19-Profil.jpg und Onboarding

**Beobachtung.** `Info.plist` nennt die App „Health“, Apples deutsche Anleitung nennt das eingebaute Produkt ebenfalls „Health-App“. Bild 19 enthält sinngemäß „Health nutzt die Werte aus Apple Health“ und zwei so bezeichnete Rollen nebeneinander. Im Fehlertext aus `DataHub` steht „in der Health-App unter Profilbild → Apps → Health“. Die HealthKit-Zweckbeschreibung verspricht „Die Daten bleiben auf deinem iPhone“. Anderswo wird die optionale Weitergabe ausgewählter Tageswerte und des Chats an Anthropic erklärt. Das Profil zeigt im Demo-Modus trotzdem „180 von 180 Tage mit Daten“, zählt für diese Zeile im Code nur Schlaf, HRV und Schritte. Keychain-Fehler beim Speichern eines optionalen Schlüssels bleiben ohne Rückmeldung. Fitbit ist als Altquelle versteckt, aber „Wird umgestellt“ lenkt weiterhin vom funktionierenden Import weg.

**Warum falsch.** Dieselbe App-Bezeichnung erschwert Berechtigungsentscheidungen. Der erste Datenschutzhinweis klingt absolut, obwohl nach einer weiteren Zustimmung ein externer Verarbeitungsweg besteht.

**Lösung.** Mit Maxi einen eindeutigen sichtbaren Produktnamen festlegen, etwa „Forma Health“. Bis dahin konsequent „Apples Health-App“ als Quelle und „diese App“ als Auswertung bezeichnen. `Info.plist:7–8,50–53`, `OnboardingView.swift:19–39`, `DataHub.swift:351`, `ProfileView.swift:28–55,71–121` und Morgenbericht gemeinsam prüfen. Im Zwecktext lokale Standardverarbeitung und optionale Claude-Zustimmung konsistent erklären. Klar „180 Beispieltage“ oder echte erfasste Tage mit demselben Zählkriterium anzeigen. Keychain-Status prüfen und Fitbit-Hinweis bei bestehender Altverbindung anbieten. Bundle-ID kann für das Update gleich bleiben. A-23. [Apple Support zur Benennung und Berechtigungsnavigation](https://support.apple.com/de-de/104997)

### R-03-16 · P2 · Aussagekraft des Simulatorrundgangs · 01-Heute.jpg, 02-Heute-gescrollt.jpg

**Beobachtung.** Beide JPGs haben denselben SHA-256. `ScreenTour` macht den ersten Wisch ohne Zustandsassertion. Der UI-Job speichert `status=$?`, beendet den Schritt jedoch stets mit `exit 0`. Der Bilder-Pflichtsatz verlangt 12 Dateinamen, darunter weder 02, Profil, Journal noch den Folgesatz. Die Herkunftsdatei ordnet die tatsächlich veröffentlichten Bilder verlässlich dem Lauf zu.

**Warum falsch.** Erfolgreicher Build und Dateiname „gescrollt“ reichen als Beleg für einen funktionalen UI-Schritt nicht aus. Seltene Zustände bleiben unsichtbar.

**Lösung.** In `ScreenTour.swift:58–69` gezielten Wisch verwenden und vor Bild 02 kompakte Ringleiste oder erwartete Ankerkarte bestätigen. In `.github/workflows/forma-ios.yml:124–171` UI-Status in die Zusammenfassung übernehmen und bei fehlendem Pflichtbild oder bei einem als Pflicht markierten UI-Schritt sichtbar fehlschlagen lassen. Screens für leeren Health-Import und mindestens einen großen Textmodus ergänzen. A-24.

### R-03-17 · P1 · Doppelte und fälschlich unterdrückte Aktivitäten · 08-Belastung.jpg, 14c-Körperalter-Faktoren.jpg

**Beobachtung.** `HealthService.workouts` übernimmt jede Aktivität. In `DataHub.days` verdrängt jede zeitliche Überlappung mit einem vorhandenen Eintrag die Forma-Einheit, auch über Aktivitätstypen hinweg. In `BodyAge.strengthMinutes` findet eine andere Prüfung statt. Zwei Datensätze für dieselbe Aktivität können daher mehrfach zählen. Ein überlappender Spaziergang und ein Krafttraining können sich in der Belastungsansicht fälschlich ersetzen.

**Warum falsch.** Die Trainingsminuten fließen in die Belastungsformel, damit auch in Zielanzeige und Bettzeit. Gleiche Rohdaten können auf zwei Bildschirmen verschieden interpretiert werden.

**Lösung.** In `HealthService.swift:190–204` und `DataHub.swift:16–28` Identität und Aktivitätstyp übernehmen. Plausible Doppelaufzeichnungen derselben Aktivität anhand Quell-/Zeitdaten zusammenführen. Belastung und Kraftminuten aus derselben bereinigten Aktivitätsmenge ableiten. Überschneidende, eigenständige Einheiten erhalten. A-25.

### R-03-18 · P2 · Kleine Bedien- und Textbrüche · 03b-Heute-anpassen.jpg, 09-Training.jpg, 09b-Training-unten.jpg, 13-Zusammenfassung.jpg, 15-HRV.jpg, 18-Journal.jpg

**Beobachtung.** Kacheln haben kein Ziehziel unter der letzten Karte. Der Drop akzeptiert beliebigen Text mit einem passenden Rohwert. Beim Editor-Reset gibt es eine Bestätigung, im Alle-ausgeblendet-Zustand stellt der leere Bildschirm sofort wieder her. Zwei Stellen führen zu „Freies Training“. 13 hat eine lange Überschrift für 1RM. 15 zeigt „60 ms“ ohne „zuletzt am …“. `JournalView.copyPrevious` speichert pro Frage. `set` meldet einen Fehler, der Sammelpfad schreibt danach eine positive Meldung auf Basis der Anzahl bearbeiteter Felder.

**Warum falsch.** Wiederholte Einstiegspunkte und fehlendes Datum machen kleine Ansichten dichter. Eine Erfolgsmeldung im Journal kann verlorene Antworten verschleiern.

**Lösung.** In `Tiles.swift:124–186,232–240` das Ziel „ans Ende“ ergänzen, kachelgebundenen Transfer verwenden und Reset-Wege mit Reduce Motion vereinheitlichen. In `TrainingView` einen klaren Einstieg je Aktion, in der Zusammenfassung „Geschätztes Maximalgewicht“ mit Erklärung darunter verwenden. In `HealthView.swift:145–162` Messdatum am Wert zeigen. In `JournalView.swift:31–39,110–119` gesammelte Änderungen zusammen speichern und bei Fehler sichtbaren Zustand wiederherstellen. A-26.

## Angriffstest mit synthetischen Daten

Die Tabelle beschreibt überprüfte Codepfade und die gewünschten Regressionstests. „Gerät“ kennzeichnet Betriebssystemverhalten, das nur auf einem iPhone zuverlässig überprüft werden kann.

| Fall und Eingabe | Ergebnis laut Code | Risiko | Erwartetes Verhalten im Test |
|---|---|---|---|
| A-01 · Demo → Apple Health, ohne Cache, alle Reihen schlagen fehl | Quelle wird Health, bisherige Demo-Tage bleiben. | P0, R-03-01 | `DataHub` mit simuliertem Import. Nur korrekt gekennzeichnete Demo oder leerer Health-Stand, kein persönlicher Coach-Vorschlag. |
| A-02 · Auf A-01 folgt echter Schrittwert, Schlaf und HRV schlagen fehl | Merge kann die vorherigen Demo-Werte als Altbestand verwenden. | P0, R-03-01 | Nur echte Schritte, keine Beispielnacht, kein Cache mit Demo-Daten. |
| A-03 · Letzten Eintrag bestätigt löschen. Separater Fall mit leerer Sicht nach Änderung der Freigabe | Vollständig leeres Ergebnis behält den alten Stand. Bei einer weiterhin lesbaren anderen Reihe kann die unklare Zeile verschwinden. | P0, R-03-02 | Bestätigte Löschung bleibt auch nach Neustart weg. Unklare Leselage wird als solche gekennzeichnet und bleibt aus automatischen Empfehlungen heraus. |
| A-04 · Eine fehlgeschlagene Reihe enthält die einzig vorhandenen Werte aus dem Cache. Beim Teilimport schlägt auch das Schreiben fehl | `.partial` gilt als frisch und die Warnung nennt nur die Lesefehler. | P0, R-03-02 | Letzten gültigen Messzeitpunkt beibehalten, Altstand ausweisen und Schreibfehler separat melden. |
| A-05 · Lokale Kopie löschen, während eine bereits begonnene Abfrage wartet. Separater simulierter Dateifehler | Alte Abfrage kann die Kopie neu schreiben. Fehler wird ignoriert. | P1, R-03-03 | Löschaktion quittiert Erfolg erst nach Dateiergebnis. Bereits begonnene Abfrage wird verworfen. |
| A-06 · Upgrade mit altem Cache sowie Entfernen der einzigen Messung der letzten 30 Tage bei älteren Daten | Keine Nachmarkierung beim Laden. Merge kann die Datei unverändert lassen. | P1, R-03-03 | Backup-Ausschluss nach Upgrade verifizieren. Absichtlich entfernter Wert bleibt nach Neustart weg. |
| A-07 · Nur Schritte vorhanden. Separat HRV mit Baseline, aber Schlaf fehlt | Detail und Coach kombinieren echte Messungen und Ersatzwerte. | P0, R-03-04 | Leeres Belastungsdetail ohne Ziel. Fehlende Schlafmessung mit Lücke, ohne Standardwert im externen Kontext. |
| A-08 · Zwei Anstöße während eines absichtlich verzögerten Imports | Der zweite Aufrufer erhält das Ergebnis des ersten Durchlaufs vor seinem Nachlauf. | P1, R-03-05 | Abgedeckte Arbeit je Abschluss nachweisen. Zwei Benachrichtigungsanläufe für denselben Stand verhindern. |
| A-09 · Quelle während des Hintergrundabrufs wechseln. Separat zwei HealthKit-Registrierungen gleichzeitig auslösen | Alte Publikation wird verworfen, der neue Abruf wartet. Registrierung kann pro Typ doppelt laufen. | P1, R-03-05 | Die neue Quelle setzt den sichtbaren Stand, alte Ergebnisse lösen keine Planung aus. Genau ein Beobachter pro Typ und eine Quittung je Signal. |
| A-10 · Hintergrundbudget endet oder BG-Scheduling wird vom System abgelehnt | Kein ausdrücklicher Abbruchpfad für den gemeinsamen Job. Planungsfehler bleibt unsichtbar. | P1, R-03-06 | Künstlicher Ablauf über injizierten Scheduler. Arbeit wird beendet oder verlässlich nachgeholt. Nächster Versuch und Grund sind sichtbar. |
| A-11 · Gerät während einer HealthKit-Abfrage sperren, dann entsperren | Der Sperrhinweis wird nur vor den Abfragen gesetzt. | P1, R-03-06, Gerät | Letzter validierter Stand bleibt. Nach Entsperren folgt ein sichtbarer Nachholabruf. Kaltstart und Start nach Wegwischen separat dokumentieren. |
| A-12 · Im Cache liegt eine Nacht vom selben Tag. Aktueller Import für Schlaf schlägt fehl | Teilimport kann einen Bericht mit alter Nacht auslösen. Manueller Erfolg kann Bericht überspringen. | P1, R-03-07 | Bericht erst nach gültiger Nacht für diesen Stand. Manueller Erfolg und Hintergrund-Erfolg führen denselben Abschluss aus. |
| A-13 · Gleichzeitige Morgenplanung, erste Annahme durch Mitteilungsdienst zeitverzögert | Zwei Aufrufe können bis zur Systemannahme kommen. | P1, R-03-07 | Mock zählt genau eine Anmeldung. Bei Ablehnung folgt ein erneuter Versuch. Übergang zu Demo während des Wartens verwirft die Planung. |
| A-14 · Weckzeit 00:00. Separat 02:30 am Tag des Sommerzeitbeginns und am Folgetag | Mitternacht fällt auf 06:55 zurück. Tagesaddition kann eine ersetzte Stunde weiterschreiben. | P1, R-03-08 | Mitternacht bleibt Mitternacht. Nur der betroffene Tag nutzt die definierte Ausweichzeit. Auch die doppelte 02:30 am Ende der Sommerzeit testen. |
| A-15 · Bettzeit mit Detailwerten geplant, danach Detailwerte aus oder andere Zeitzone | Alte Anfrage bleibt geplant, bis ein anderer Pfad sie ersetzt. | P1, R-03-08, Gerät | Wartende Mitteilung sofort aktualisieren oder entfernen. UI und neuer Termin nennen denselben lokalen Plan. Ohne Detailwerte bleibt der Text allgemein. |
| A-16 · 23:59 → 00:01, App offen, Health vorübergehend nicht lesbar | Datum im Kopf kann vorrücken, während „heute“ die letzte alte Zeile liest. | P1, R-03-09 | Alter Wert steht am vorherigen Tag. Heute zeigt keine aktuelle Messung. |
| A-17 · In Berlin gespeicherter Tag, danach Zeitzone New York und HealthKit-Teilimport | Reinterpretation im Cache oder abweichende Date-Schlüssel im Merge. | P1, R-03-09 | Ursprünglicher Messtag bleibt eindeutig, jede Reihe behält ihren zugeordneten Wert bis zur Neuaggregierung. |
| A-18 · Dieselbe Nacht vor und nach Training, eine weitere Nacht fehlt, Tief/REM überschneiden sich | Score bleibt stabil, Prozentanteil kann sich ändern. Die fehlende Nacht erscheint als 0. | P1, R-03-10 | Score, Prozent und Phasen stimmen zusammen. Fehlende Nacht hat eine sichtbare und vorgelesene Lücke. |
| A-19 · 7 gegenüber 30 Nächten, gleich viele Tage mit irgendeinem Signal. Krafttraining nur vor beiden Fenstern | Vergleich kann berechnet werden und Kraft als 0 min je Fenster werten. | P1, R-03-11 | Vergleich begründet ausblenden. Kraftaufzeichnung pro Fenster transparent ausweisen. |
| A-20 · Satz 51 hinzufügen und App neu starten. Separat Fehler beim Lesen der Abschluss-ID | Restore kürzt. Abschlussversuch setzt nach Fetchfehler fort. | P1, R-03-12 | Grenzen werden vor dem Speichern durchgesetzt oder der vollständige Entwurf bleibt erhalten. Fetchfehler erzeugt keine zweite Einheit. |
| A-21 · Kleinster unterstützter Bildschirm, AX5, VoiceOver und Reduce Motion | Feste Breiten/Schriften und unbedingte Animationen bleiben. | P1, R-03-13, Gerät | 44-pt-Ziele, kein abgeschnittener Abschlussbutton, verständliche Reservestufen, vorgelesene Messwerte und ruhige Zustandswechsel. |
| A-22 · In lb Routine bearbeiten, Fortschrittsvorschlag ansehen, Satz speichern und Zusammenfassung öffnen | Mehrere Gewichte oder Schrittweiten bleiben kg-basiert. | P1, R-03-14 | An allen Stellen dieselbe Einheit, fachlich passende Rundung und dieselben gespeicherten Gewichte. |
| A-23 · Berechtigungsdialog und Profil im deutschen iOS prüfen. Optionalen Speicherdienstfehler simulieren | „Health“ steht für zwei Apps. Aktueller Schlüsselbundstatus bleibt ohne Ergebnis. | P1, R-03-15, Gerät | Quelle und Ziel eindeutig benannt, Datenschutzhinweis widerspruchsfrei. Bei gescheitertem Schlüsselbundschreiben verständliche Rückmeldung. |
| A-24 · UI-Wisch ändert keinen sichtbaren Zustand | 01/02 können trotz erfolgreichem Lauf dasselbe Bild enthalten. | P2, R-03-16 | UI-Test prüft kompakten Zustand, bevor das zweite Bild veröffentlicht wird. |
| A-25 · Ein doppelt erfasstes Workout und zwei unterschiedliche überlappende Aktivitäten | Duplikat kann doppelt zählen, echte Aktivität kann verschwinden. | P1, R-03-17 | Duplikat einmal zählen. Unterschiedliche Aktivitäten beide behalten. |
| A-26 · Vortagsantworten übernehmen, Testkontext meldet Speicherausfall | Positive Anzahl kann den Speicherfehler überschreiben. | P2, R-03-18 | Eine konsistente Transaktion, keine Erfolgsmeldung bei nicht gespeicherten Angaben. |

Für die nächste Runde zuerst A-01 bis A-07 und A-12/A-13 als deterministische Tests abdecken. Für Maxis iPhone danach A-10/A-11 und A-14/A-15, mit genauer iOS-Version, Zeitpunkt, Sperrzustand und letzter erfolgreicher Reihe. Xcode-Screenshots belegen Bildzustände, HealthKit-Hintergrundzustellung braucht das Gerät.

## Was bleiben soll

- Erholung steht auf Heute visuell im Zentrum der Ringe. Beschriftungen, Zielbogen und der dunkle Aufbau geben jeder Farbe eine klare Aufgabe.
- Lokaler Coach und Demo sind in der normalen Ansicht klar gekennzeichnet. Der neutrale Morgenbericht und die freiwillige Mitteilungsabfrage in Profil beziehungsweise Pause sind sinnvolle Standards.
- Das Live-Dock hält „Satz abschließen“ und „Pause beenden“ in Daumenreichweite. Satz-ID, optionale Reserve und manuelles Übernehmen des Fortschritts ergeben einen nachvollziehbaren Trainingsablauf.
- Körperalter bleibt auf der Kachel als Schätzung kenntlich. Methode, Faktoren und Datenabdeckung sind zugänglich. Die Erklärung sollte auf diese Tiefe weiter aufbauen.
- Kachelanordnung zusätzlich per Editor und Kontextmenü, Einheiten im deutschen Zahlenformat und nachvollziehbare Herkunft der CI-Bilder.
