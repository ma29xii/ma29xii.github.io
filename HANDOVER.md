# Health · Übergabe an Claude Code

Stand 20. November 2026. Diese Datei ergänzt [AGENTS.md](AGENTS.md). Für den aktuellen Code-, Build- und Google-Stand gilt diese Übergabe. Maxi testet auf dem iPhone. Berichte ihm kurz auf Deutsch in drei nummerierten Punkten, mit der nächsten Aktion ganz oben.

## Als Erstes

1. Öffne `C:\Users\maxi\Downloads\Forma\Forma`. Lies `AGENTS.md` sowie `C:\Users\maxi\KI-Team\README.md` und `WISSEN.md`. Prüfe den Arbeitsbaum, den Branch und die letzten Commits. Codex und Claude arbeiten auf demselben Branch. Andere Änderungen können während der Arbeit hinzukommen.
2. Prüfe den Google-Import aus **Build 5** auf einem echten iPhone. Maxi hat in der offiziellen Google-Health-App aktuelle Werte. Bei der vorherigen Forma-IPA war die Verbindung erfolgreich, die Werte fehlten aber in Forma. Das Cloud-Dashboard zeigte erfolgreiche List-Aufrufe, ohne Inhalt der Antworten.
3. Öffne **Profil → Datenquelle → Jetzt aktualisieren** und vergleiche in **Today** zuerst Schritte und die letzte Schlafdauer. Danach prüfe **Sleep unmittelbar nach Kaltstart** und **Strain während eines Abrufs**. Nutze den [iPhone-Testplan](forma-ios/TESTEN.md).

```powershell
git status --short --branch
git log -12 --oneline
python -I -X utf8 C:\Users\maxi\KI-Team\team.py liste --fuer claude
```

## Arbeitsweise und Entscheidungen

- Stabilität hat bei einem gemeldeten Hänger Vorrang. Reproduziere die genaue Reihenfolge auf dem passenden Stand. Prüfe zuerst, welche Daten, Views und Animationen beim Einstieg ausgelöst werden. Ändere die kleinste gemeinsame Ursache und wiederhole den Einstieg. Ein grüner Simulator ist ein Prüfpunkt, der iPhone-Befund entscheidet über den gemeldeten Fehler.
- Verwende SwiftUI und vorhandene Forma-Komponenten, Datenmodelle, Navigation und Design-Tokens. WHOOP, Bevel und Oura dienen als Funktionsreferenzen. Die App nutzt eigene Formen und die vorhandene visuelle Sprache. Achte auf Dynamic Type, VoiceOver, 44-pt-Tippziele und „Bewegung reduzieren“.
- Zeige echte Werte mit Quelle und sinnvollen Einheiten. Fehlende Messung bleibt fehlend. Erfasste und geplante Kalorien stehen getrennt. Beispielmodus und echte Daten haben eigene Einstellungen und Speicher. Eine bestehende alte Einstellung muss nach Updates weiter funktionieren.
- Löse klar benannte Designwünsche direkt. Für Entscheidungen im Detail nutze die vorhandene App und eine echte iPhone-Größe. Nutze kurze Titel, keine Chevron-Pfeile und „Anpassen“ unten. Tabs und Ringnamen bleiben Englisch, übrige UI auf Deutsch.
- Prüfe erst `git status` und den Besitz von Dateien. Committe nur die eigenen abgeschlossenen Änderungen. Tests bleiben aktiv. Passe einen Test an, wenn Maxi genau das bisher geprüfte Verhalten geändert hat. Die CI schreibt `docs/forma-screens/`. Verwende keine Passwörter, PINs, API-Schlüssel, `.env`-Dateien oder Tokens. Halte dich bei Versand und Zugriff an die Freigaben. Auf Windows weder `taskkill` noch `Stop-Process` einsetzen.
- Melde getrennt, was im Quellcode geändert wurde, was Xcode und Simulator bestätigt haben und was auf dem echten iPhone offen ist. Gib eine IPA erst als geprüft aus, wenn die Datei zum genannten Commit gehört. Verstecke einen Fehler weder durch einen weicheren Test noch durch ein älteres IPA mit neuem Namen.

## Stand und Prüfungen

| Stand | Inhalt und Nachweis |
|---|---|
| `cb8aa55` · Health 1.0 Build 3 | IPA, 369 Unit-Tests und Simulator-Rundgang grün. Die Bettzeit-Erinnerung greift nach Mitternacht den nächsten noch bevorstehenden Termin. Claude hatte den Randfall gefunden. Build 3 entstand vor der Google-Konfiguration. [Lauf 137](https://github.com/ma29xii/ma29xii.github.io/actions/runs/44702732781) |
| `9cf2c12` | Sleep-Diagnose `SleepProbe` und `-probeHide` entfernt. Der Simulator-Rundgang deckt den Einstieg in Sleep und Strain ab. |
| `18d5092`, `c381df4` · ab Build 4 | Ladescreen, Food, Today, Ringdetails, Coach und Plus überarbeitet. [Erfolgreicher Lauf 160](https://github.com/ma29xii/ma29xii.github.io/actions/runs/44776817882). |
| `e4bcd4b` und bestehende Runden 16–19 | Wochen-Widget, Fasten-Live-Aktivität, Smart-Wasser-Erinnerung, Wochenrückblick als Story und Claudes Atemübung im Stress Monitor sind bereits im Branch. Erhalte vorhandene Einstiege, Datenquellen und Freigaben bei Änderungen. |
| `faf7e4a`, `b1e2c48` | Öffentlicher Google-iOS-Client samt URL-Schema eingebunden. Der IRGen-Absturz ist seit der Änderung am Schalter für die Trink-Erinnerung behoben. |
| `9ec19b2`, `271a6bf` · Build 5 | Der Vordergrundabruf startet nach der Freigabe. Profil zeigt Abruf, Datenstand und konkrete Fehlermeldungen. Für Schritte und Schlaf prüft Forma bei leeren Rohdaten oder ausschließlich unbekannten Quellen zusätzlich den von Google abgeglichenen Wearables-Datenstrom. Verwertbare Rohdaten haben Vorrang. Fehlende Quellenangaben einzelner Rohdatensätze blockieren übrige Messwerte nicht. |

Build 4 liegt unter `C:\Users\maxi\Downloads\Health-1.0-build-4.ipa`. Build 5 erhält nach dem Paketcheck den Namen `C:\Users\maxi\Downloads\Health-1.0-build-5.ipa`.

## Maxis letzter Auftrag und Code-Einstiege

| Bereich | Aktueller Auftrag und Umsetzung |
|---|---|
| Start, Sleep, Strain | App hing auf Maxis iPhone kurz nach dem Start beim Öffnen der Details. `FormaApp.swift` und `Design/HealthStartupView.swift` zeigen den lokalen Startvorgang. `TodayView.swift` hält die Navigation außerhalb des aktualisierten Inhalts. `RingDetailView.swift` baut die Abschnitte im ScrollView verzögert auf. Der Xcode-Rundgang öffnet Sleep zuerst. Prüfe mit frischem Start, Rückweg zu Today, frühem Tap auf Strain und laufendem Google-Import. |
| Today | Recovery in der Mitte, Strain und Sleep als Seitenkapseln. Die Ringe laufen beim Zurückwechseln erneut hoch. Zwischenleiste, sichtbarer Link „Alle Vitalwerte“ und „Mein Tag“ sind entfernt. Der Stress Monitor zeigt Wert und Stundenbalken, und führt weiterhin in das Detail mit Atemübung. Neue Kacheln öffnen Schlafplan und Wasser. [`TodayView.swift`](forma-ios/Forma/Features/Today/TodayView.swift), [`TodayTiles.swift`](forma-ios/Forma/Features/Today/TodayTiles.swift), [`StressMonitor.swift`](forma-ios/Forma/Features/Today/StressMonitor.swift) |
| Vitalwerte und Ringdetails | Karten und schmale Balken sind über ein Layout-Menü wechselbar. Atmung, Ruhepuls, HRV, SpO₂, Hauttemperatur und Schlaf bleiben einzeln antippbar. Auch Sleep, Strain und Recovery haben umschaltbare Beitragskacheln. Persönliche Bereiche nur mit ausreichenden Messungen. Referenz anbei `C:\Users\maxi\Downloads\IMG_0726 (1).jpg`. [`HealthMonitor.swift`](forma-ios/Forma/Features/Health/HealthMonitor.swift), [`RingDetailView.swift`](forma-ios/Forma/Features/Today/RingDetailView.swift) |
| Food | Ringe und Tageskalorien stehen oben, Ballaststoffe in eigener Kachel. Frühstück, Mittag und Abend zeigen erfasste Kalorien und vorhandene geplante Kalorien. Hierfür die gespeicherten `FoodPlanItem`-Einträge verwenden. Wasser, Fasten, Plan und Gewicht stehen als ruhige Aktionen nach dem Tagebuch. Mahlzeiten-Logging und Löschen per Wischen bleiben erreichbar. [`FoodHomeView.swift`](forma-ios/Forma/Features/Food/FoodHomeView.swift) |
| Health | Der animierte Partikelkreis bleibt. Das Datum oberhalb des Health Age und die Kachel „Gewohnheit“ sind entfernt. Die Vitalwerte und Biomarker erscheinen ohne redundante Überschriften. Detaillinks bleiben antippbar. [`HealthView.swift`](forma-ios/Forma/Features/Health/HealthView.swift), [`BodyAgeView.swift`](forma-ios/Forma/Features/Health/BodyAgeView.swift) |
| Coach und Plus | Tippen in den Chat schließt die Tastatur und lässt den mehrzeiligen Entwurf stehen. Absätze gehen über Return, Versand über den Sendeknopf. Plus bleibt rechts in der Tab-Leiste und dreht sich zum X. Das Plus-Menü lässt die aktuelle Ansicht sichtbar. Food bleibt ein eigener Tab. [`CoachView.swift`](forma-ios/Forma/Features/Coach/CoachView.swift), [`FormaApp.swift`](forma-ios/Forma/App/FormaApp.swift), [`PlusMenu.swift`](forma-ios/Forma/Features/Plus/PlusMenu.swift) |

Frühere Designentscheidungen gelten weiter. Trends verwenden **W, M, 6M** und eine ausklappbare Liste **Einzelwerte**. Messwertdetails sind antippbar, der frühere Datumsschalter und die Teilen-Symbole in den normalen Ringdetails sind entfernt. Fitness öffnet über **Plus** und behält die Muskelkarte. Das Coach-Maskottchen bleibt entfernt. Die Design-Auswahl enthält unter anderem Blau `#4D8EB6` und Bordeaux `#5C2624`. Energie und Stress bleiben direkt erreichbar. Der Wochenrückblick hat seinen eigenen Story-Teilen-Knopf.

### Ideen für weitere Today-Kacheln

- Ein kurzes Belastungsziel mit passender nächster Trainingsroutine ist naheliegend. WHOOP zeigt Strain Targets und Wochenpläne auf Home. Die App hat bereits ein belastungsabhängiges Ziel und die gespeicherten Routinen. [WHOOP Basics](https://support.whoop.com/s/article/WHOOP-Basics)
- Eine Tageskarte mit gemessener Erholungszeit passt neben den Stressverlauf. Oura zeigt stressige und erholte Zeiten auf dem Today-Bildschirm. Verwende für eine Umsetzung nur vorhandene Stress-Zeitslots und unterscheide gemessene Zeit von Lücken. [Oura Daytime Stress](https://support.ouraring.com/hc/en-us/articles/21205822135315-Daytime-Stress)
- Hydration und Kalorien/Makros sind sinnvolle direkte Einstiege. Die Wasser- und Food-Kacheln dieser Runde decken das bereits ab. [Bevel Übersicht](https://help.bevel.health/en/articles/10431489)

## Google Health ist für den Test eingerichtet

- In Google Cloud ist im Projekt **Health** die Google Health API aktiv. Der OAuth-Client **Health iPhone** ist vom Typ **iOS** und hat die Bundle-ID `com.ma29xii.forma`. Externe Zielgruppe im Testmodus, genau das angemeldete Google-Konto als Testnutzer eingetragen. Die Einstellungen wurden nach Neuladen des Browsers bestätigt. [Google Cloud Clients](https://console.cloud.google.com/auth/clients?project=health-515313)
- Gespeicherte Leserechte sind `googlehealth.activity_and_fitness.readonly`, `googlehealth.sleep.readonly` und `googlehealth.health_metrics_and_measurements.readonly`. App-Eintrag und abgeleitetes Rücksprung-Schema stehen in [`Config.xcconfig`](forma-ios/Config.xcconfig), die Zuordnung in [`Info.plist`](forma-ios/Forma/Resources/Info.plist). Die Verbindung nutzt den Systembrowser mit PKCE und speichert die Freigabe im iOS-Schlüsselbund. Die API ist die einzige Quelle für importierte Gesundheitswerte.
- Auf Maxis iPhone in der Google-Health-App prüfen, dass die Fitbit-Werte im selben angemeldeten Konto sichtbar sind. Danach in der neuen Test-IPA **Profil → Mit Google Health verbinden** öffnen und die drei Leserechte auf dem iPhone bestätigen. Teste zuerst den letzten Schlaf, dann Schritte und Puls. Im Testmodus kann die Freigabe nach sieben Tagen ablaufen. [Google Health OAuth-Einrichtung](https://developers.google.com/health/setup)
- Geprüft sind die Cloud-Konfiguration und die lokale Zuordnung. Die Anmeldung, Rückkehr aus dem Browser und der Abruf echter Werte brauchen das iPhone. Erst nach diesem Test eine verbindliche Aussage treffen.

## CI und Test-IPA

1. Arbeitsbranch `claude/awesome-hypatia-tnhuis`, Repo `ma29xii/ma29xii.github.io`. Kein Xcode auf Windows. [`forma-ios.yml`](.github/workflows/forma-ios.yml) baut auf dem Mac-Runner. Zwischen-Pushes ersetzen wartende Läufe. Lies dann den neuesten nachweislich passenden Lauf.
2. Prüfe Job `ipa`, Unit-Tests und den tatsächlichen `UI-Rundgang-Ergebnis`-Schritt. Der UI-Schritt sammelt Anhänge auch bei einem Testfehler. Ein grüner Sammelschritt allein belegt keinen bestandenen Rundgang. Im Simulator kann die native Plus-Taste ihre Kennung verlieren. Der Test nutzt dann das sichtbare Label als Rückfall.
3. Lade das Artefakt `Forma-IPA` des verifizierten Laufs. Wenn `gh` nicht angemeldet ist, nutze GitHub Actions im angemeldeten Browser. Vergleiche die ZIP-Prüfsumme mit GitHub und prüfe in der entpackten IPA Bundle-ID, Anzeigenamen `Health`, Version `1.0`, Build `4`, iOS-Mindestversion `26.0`, Widget und Google-Client samt Callback. Die Standard-IPA enthält keine `coach-keys.json`. Über Sideloadly mit derselben Bundle-ID und dem eigenen Konto installieren.

## Team und Referenzen

- `20261120-074917-codex` und `20261120-080329-codex` sind abgeschlossene Claude-Aufträge zur 1.0-Abnahme und zum Schlafplan. `20261120-141820-codex` liegt als lesende Gegenprüfung der Testversion im Postfach. Prüfe den aktuellen Status vor Arbeitsbeginn. Bei eigenständiger Weiterarbeit liefert diese Übergabe den Stand auch ohne den alten Chat.
- [`AGENTS.md`](AGENTS.md) enthält die dauerhaften Regeln. [`forma-ios/README.md`](forma-ios/README.md) beschreibt Architektur, Grenzen und den Google-Aufbau. [`forma-ios/TESTEN.md`](forma-ios/TESTEN.md) enthält 83 Prüfungen. Lokale visuelle Referenzen liegen bei Maxi unter `C:\Users\maxi\Downloads\Forma-Referenzbilder.pdf`, `IMG_0726 (1).jpg` und der Fitness-Bildschirmaufnahme vom 20. November 2026. Die Referenzen zeigen Funktion und Richtung für ein eigenes Forma-Design.
