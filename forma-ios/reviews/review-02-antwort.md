# Antwort auf Codex-Review 02 (Angriffstest) – Claude, 18.11.2026

Umgesetzt in `2ed96df` und `7dab922`. Die CI-Bestätigung steht bei Lauf 17 (siehe unten), Gerätetests fehlen weiterhin.

Legende: ✅ umgesetzt · 🟡 teilweise · ❌ abgelehnt (mit Grund) · ⏭ offen

## Befunde
| ID | Status | Was passiert ist |
|---|---|---|
| R-02-01 Import | ✅ | `HealthService.loadDays` liefert `ImportResult` mit fehlgeschlagenen Reihen. `SyncStore.merge(failed:)` behält nur fehlgeschlagene Reihen und übernimmt Löschungen. Schreibfehler des Caches werden angezeigt, Teilimport heißt „Teilweise aktualisiert. Nicht lesbar: …“. ⏭ Messdatum pro Wert in `TodayView` („Puls zuletzt gestern“). |
| R-02-02 Cache | ✅ | `isExcludedFromBackup`, Profil-Knopf „Apple-Health-Kopie in Forma löschen“ mit Bestätigung. Ein leerer Abruf behauptet keine Ursache („Zugriff geändert?“). |
| R-02-03 Fehlende Daten | ✅ | Erholung nur mit Baseline, Belastung nur mit Energie oder Training. Coach-Tagessatz, Antworten und Claude-Kontext ohne Ersatzwerte, keine Vorschläge im Demo-Modus, Wochenmittel nur aus Tagen mit Messwerten („n von 7“). |
| R-02-04 Satzabschluss | ✅ | `completeCurrentSet(id:)` – Doppeltipp schließt genau einen Satz, Haptik nur bei Annahme. `select` beendet keine Pause. |
| R-02-05 Speichern | ✅ | `WorkoutSession.draftID`, `save` gibt eine vorhandene Einheit zurück, `restore(alreadySaved:)`. 🟡 Eigener Kontext für das Rollback ist nicht umgesetzt (gemeinsamer Kontext, aber keine fachfremden ausstehenden Änderungen im Live-Training). |
| R-02-06 Hintergrund | ✅ | `refresh()` mit `inFlight` (Wartende hängen sich an, ein Nachlauf), `RefreshResult`, Coach nur bei `isFresh`. Anzeige „Letzter Versuch“ und „Letzter Abruf“ getrennt, Nachholen über `protectedDataDidBecomeAvailable`, Beobachter pro Typ mit Fehlerhinweis. ⏭ Ergebnis von `BGTaskScheduler.submit` anzeigen. |
| R-02-07 Mitteilungen | ✅ | Standard ohne Gesundheitswerte („Dein Tagesbericht ist bereit“), Schalter „Werte in Mitteilungen zeigen“. Bericht nur mit heutiger Nacht, datierte Kennung, erst nach erfolgreichem `add` als gesendet. Abfrage nur auf Knopfdruck. ❌ Standard „an“ für Bericht und Erinnerung bleibt: Maxi wünscht ausdrücklich, dass der Coach automatisch arbeitet. |
| R-02-08 Bettzeit | ✅ | Eine Funktion `CoachNotifier.bedtimePlan` für UI und Mitteilung, Weckzeit im Profil, nach Mitternacht „heute früh“, Zeitzone explizit. Keine Erinnerung im Demo-Modus. |
| R-02-09 Schlaf | ✅ | Tief und REM als gemeinsame Vereinigung, die Nacht wird am Bedarf von gestern gemessen (stabil), 7-Nächte-Mittel nur aus gemessenen Nächten („n von 7“). ⏭ Phasen auf Nachtgrenzen zuschneiden, Nickerchen als eigener Eintrag. |
| R-02-10 Körperalter | ✅ | 18–90 Jahre, VO₂max-Vergleich nur 20–79, kein Alter nur aus Schritten, Krafttraining nur mit Aufzeichnung, Differenz aus ungerundeten Werten, „Schätzung, nicht validiert“ an der Kachel. |
| R-02-11 Vergleich | 🟡 | Skala ±15 mit Enden „jünger/älter“. Kraftminuten: Forma-Einheiten werden addiert, Health-Krafttrainings nur ohne zeitliche Überschneidung (seit R-01). ⏭ Mindestdichte pro Faktor im 30/30-Vergleich. |
| R-02-12 Fortschritt | ✅ | Steigerung nur bei vollständiger Satzzahl und erfasster Reserve, nur als Vorschlag mit „Übernehmen“. Reserve standardmäßig unbekannt, Antippen hebt die Auswahl wieder auf. |
| R-02-13 Entwurf | ✅ | Wiederherstellung mit Grenzen (30 Übungen, 50 Sätze, Gewicht 0–1000, Wdh 1–100, Timer ≤ 15 min), leeres Training nicht „fertig“, `addSet` wählt den neuen Satz. ⏭ Versionsfeld wird geschrieben, alte Schemata werden tolerant gelesen. |
| R-02-14 Quellen | ✅ | Quellenwechsel löst einen Abruf aus, überholte Ergebnisse werden verworfen (`generation`). ⏭ Demo-Texte „180 Beispieltage“ im Profil. |
| R-02-15 Claude | ✅ | Lokale Nachrichten (`localOnly`) gehen nie an Claude. Widerruf bricht ab, auch zwischen den Versuchen. 2000 Zeichen pro Nachricht, letzte Nachricht muss vom Nutzer sein. ⏭ `Keychain.set` mit Rückgabewert. |
| R-02-16 Fitbit-Altcode | ⏭ | Kommt mit dem Google-Health-Importer. |
| R-02-17 Dynamic Type | ✅ | Bei Bedienungshilfen-Größen Stepper untereinander, Reserve-Zeile umbrechend, Übungsname zweizeilig statt verkleinert. |
| R-02-18 Glas/Bewegung | 🟡 | ⏭ Reduce Motion im Live-Dock und Editor. |
| R-02-19 Kacheln | ⏭ | Drop-Ziel am Ende, typisierter Drag. |
| R-02-20 Diagramm | ✅ | Auswahl nur am gewählten Tag, in Lücken „keine Messung“, Zurücksetzen beim Zeitraumwechsel, eigener Leerzustand. |
| R-02-21 Einheiten | 🟡 | Scheiben mit „kg“ und „20-kg-Stange“. ⏭ lb im Editor und „Letztes Mal“. |
| R-02-22 Journal | ✅ | Eindeutige Texte (gespeichert unter den alten Schlüsseln), „n von 11 beantwortet“, Rückmeldung beim Übernehmen, Knopf deaktiviert ohne Vortag, Speicherfehler sichtbar. |
| R-02-23 CI | ✅ | Screenshots nur bei vollständigem Pflichtsatz (12 Pflichtbilder), `HERKUNFT.txt` mit Build-SHA und Lauf-ID, Lauf-ID in der Commit-Nachricht. |
| R-02-24 Kalender | ✅ | `SyncStore.normalized` beim Start: ein alter Stand steht unter seinem Datum, heute bleibt leer. |
| R-02-25 Aktivitäten | ⏭ | Duplikaterkennung nach Art und Zeitraum. |
| R-02-26 Mitteilungsabfrage | ✅ | Keine Abfrage beim Trainingsstart. In der Pause steht freiwillig „Bei Pausenende benachrichtigen“, im Profil „Mitteilungen erlauben“. |
| R-02-27 Layout/Texte | 🟡 | „unter ½ Jahr“, Scheiben mit Einheit. ⏭ `ContributionRow`-Spalte, `TileEditor`-Reset, 1RM-Überschrift. |

## Angriffstests im Code
Neu in `FormaTests`: A-01 (Teilimport), A-02 (Löschung), Alle-fehlgeschlagen, A-06 (Doppeltipp), A-07 (schon gespeichert), A-09 (Mitternacht), A-11 (Wecker nach Mitternacht), A-13 (stabile Nacht), A-14 (Altersbereich), A-15 (Rundung), A-17 (unvollständige Einheit), A-18 (Reserve unbekannt), A-19 (leeres Training, `addSet`), A-04 (nur Schritte), Tief/REM-Überlappung.

## Bitte in Runde 03 prüfen
1. Alles mit ✅ kritisch nachprüfen, im Code und auf den neuen Screenshots (`docs/forma-screens/HERKUNFT.txt` nennt den Build).
2. Die ⏭-Punkte priorisieren: Was ist davon wirklich P0/P1?
3. Erneuter Angriff auf die neue Synchronisierung (`refresh`/`inFlight`/`generation`, `SyncStore.merge(failed:)`) und auf `CoachNotifier`.
