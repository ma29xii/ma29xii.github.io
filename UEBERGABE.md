# Übergabe: Forma – alles Wichtige aus der bisherigen Sitzung

Stand: 18.11.2026, letzter Commit auf `claude/awesome-hypatia-tnhuis` siehe `git log`.
Diese Datei ist für die **neue Sitzung auf dem Mac** (Claude Code und Codex). Zuerst lesen, dann `AGENTS.md`.

## 1. Wer, was, wie
- **Nutzer:** Maxi. iPhone 18 Pro, Mac. Installiert Apps per **Sideloadly** (unsignierte IPA).
- **Sprache:** immer Deutsch, du-Form, klar und menschlich.
- **Arbeitsweise, die Maxi will:**
  - Wahrheit vor Tempo, nichts erfinden („Ich kann das nicht bestätigen“), Quellen nennen.
  - Fakten, Interpretation und Empfehlung trennen. Ergebnis zuerst.
  - Selbstständig durcharbeiten, höchstens eine Rückfrage.
  - Nichts senden, löschen oder ändern ohne Freigabe (außer im eigenen Projekt).
  - Nach jedem größeren Schritt committen und pushen.
  - **Am Ende jeder Antwort eine kurze Checkliste:** was fertig ist, was offen ist, ob der letzte CI-Build grün war und wie das Artifact heißt („Forma-IPA“).
  - Design auf Senior-Designer-Niveau, ruhig, eigenständig, **keine Whoop-Kopie**.
- **Rollen:** Claude baut. **Codex prüft extrem kritisch** als Senior Designer (jedes kleine Detail), Claude setzt um. Der Ablauf steht in `AGENTS.md`.

## 2. Was Forma ist
Native iPhone-App (SwiftUI, iOS 26, Swift 6, echtes Liquid Glass, XcodeGen, keine Fremd-Frameworks), Bundle-ID `com.ma29xii.forma`, Ordner `forma-ios/`.

| Bereich | Inhalt |
|---|---|
| **Heute** | 3 Ringe 0–100 **immer oben** (Belastung · Erholung groß · Schlaf), gestrichelter Zielbogen am Belastungsring, beim Scrollen kompakt in der Navigationsleiste. Darunter **verschiebbare Kacheln**: Coach, Als Nächstes, Energie & Stress, Körper, Tag, Woche, Körperalter, Einblick |
| **Training** | Hevy-Stil: Routinen, Übungsbibliothek, Live-Training (Gewicht/Wdh/RIR, Pausentimer +15 s), Zusammenfassung mit Volumen und 1RM, Verlauf (SwiftData). Kacheln verschiebbar |
| **Gesundheit** | Körperalter, Herz & Atmung, Fitness (VO₂max), Schlaf & Aktivität, Detailseiten mit Charts. Kacheln verschiebbar |
| **Coach** | lokaler Tagessatz und Chat. Optional Claude-API-Schlüssel (Keychain). Schlägt Trainingsänderungen nur vor, Maxi bestätigt, die Routine bleibt |
| **Journal** | Ja/Nein-Fragen |
| **Profil** | Datenquelle (automatisch/Health/Fitbit/Beispiel), Über dich (Geburtsjahr, Geschlecht), Einheiten, Fitbit verbinden, Coach-Schlüssel |
| **Daten** | Apple Health (nur lesen, 180 Tage), Fitbit Web API mit PKCE, sonst gekennzeichnete Beispieldaten |

**Nicht in V1:** Ernährung, Körperentwicklung, Freunde/Teilen. (Ein biologisches Alter war ursprünglich ausgeschlossen. Maxi hat es später ausdrücklich als **Körperalter** gewünscht, inzwischen ist es gebaut.)

## 3. Wünsche aus der letzten Runde (umgesetzt)
1. **Körperalter** in Gesundheit (wie WHOOP Age / Bevel Biological Age, aber eigene, offengelegte Methode, siehe `forma-ios/README.md` und `Forma/Data/BodyAge.swift`).
2. **Hintergrund nicht blau, moderner, gern mehr Liquid Glass:** jetzt neutrales Schwarz, Lichtschein in der Datenfarbe, Glas-Chips, Karten mit Lichtkante, große Zahlen in SF Pro Rounded, Schlaf in Lavendel statt zweitem Blau.
3. **Verschiebbare Kacheln überall** (Heute, Training, Gesundheit): lange drücken und ziehen, Kontextmenü oder „… anpassen“. Die Ringe bleiben fest oben. Coach bleibt ohne Kacheln (Chat).
4. **Zusammenarbeit mit Codex:** `AGENTS.md` mit Prüfauftrag und Format, Reviews in `forma-ios/reviews/`.

## 4. Wichtige Entscheidungen (mit Grund)
- SF Pro statt Inter (Dynamic Type, Lesbarkeit). Große Zahlen in Rounded.
- Tabs: Heute · Training · Gesundheit · Coach. Journal über „Als Nächstes“, Profil über den Knopf oben rechts.
- Glas nur für Bedienung und Status, Inhalte auf matten Karten, kein Glas auf Glas.
- Fehlender Fitbit-Sync: Werte von gestern gedimmt, dazu „Warte auf Fitbit“.
- Körperalter: Summe der Faktoren auf 70 % gedämpft (eigene Annahme wegen Überlappung). HRV zählt nicht (SDNN und RMSSD sind nicht vergleichbar, und für Uhren-HRV fehlen Studien zur Lebenserwartung).
- Mehr dazu in `forma-ios/DESIGN.md`.

## 5. Bau und Installation
- Jeder Push auf `claude/awesome-hypatia-tnhuis`, der `forma-ios/**` ändert (außer `.md` und `reviews/`), startet `.github/workflows/forma-ios.yml`:
  - Job **ipa:** xcodegen → xcodebuild für iphoneos ohne Signatur → Ad-hoc-codesign mit Entitlements → `Forma.ipa` → Artifact **Forma-IPA**
  - Job **screens:** UI-Rundgang im Simulator, die CI committet die Screenshots nach `docs/forma-screens/`
- Installation: GitHub → Actions → Forma iOS (IPA) → Artifact **Forma-IPA** → entpacken → Sideloadly.
- **Auf dem Mac lokal bauen:** `brew install xcodegen && cd forma-ios && xcodegen generate && open Forma.xcodeproj`, dann in Xcode das iPhone wählen und ausführen. Mit Apple-ID signieren, das ersetzt Sideloadly.

## 6. Offen / bekannte Punkte
- [ ] **CI-Lauf 8** (Commit 370cc2d) lief beim Schreiben dieser Datei noch. Bei Lauf 7 wurde der IPA-Job ohne freien Mac-Runner abgebrochen. Falls das wieder passiert: in `forma-ios.yml` beim Job `screens` den Eintrag `needs: ipa` setzen (Jobs nacheinander).
- [ ] **Codex-Review 01** anstoßen (Prompt unten) und die Befunde umsetzen.
- [ ] **Fitbit:** Client-ID in `forma-ios/Config.xcconfig` eintragen (Anleitung im README). Außerdem auf die Zeitraum-Endpunkte umbauen, wegen des Limits von etwa 150 Anfragen pro Stunde (aktuell 6 Anfragen pro Tag mit Zwischenspeicher).
- [ ] **Test auf dem iPhone 18 Pro**, ob HealthKit mit kostenloser Apple-ID per Sideloadly funktioniert (nicht bestätigt).
- [ ] Coach-Chat mit echtem Anthropic-API-Schlüssel testen.
- [ ] Ideen für später: Homescreen-Widget (WidgetKit), Live Activity für die Pause, Schlafregelmäßigkeit als Faktor im Körperalter (erst nach Quellenprüfung).

## 7. Prompt für Codex (einfügen)
> Lies AGENTS.md und UEBERGABE.md im Hauptordner und mach Review 01. Du bist der extrem kritische Senior Designer: Prüf die Screenshots in docs/forma-screens/ und den Code in forma-ios/Forma/ (besonders Design/, Tiles.swift, BodyAge.swift). Sprich jedes kleine Detail an. Schreib das Ergebnis nach forma-ios/reviews/review-01.md, im Format aus AGENTS.md. Ändere keine Swift-Dateien, commite nur die Review-Datei und pushe auf den Branch.

## 8. Prompt für die neue Claude-Sitzung (einfügen)
> Lies UEBERGABE.md, AGENTS.md, forma-ios/README.md und forma-ios/DESIGN.md. Du bist der Builder für Forma. Prüfe den CI-Stand und die Screenshots in docs/forma-screens/. Wenn forma-ios/reviews/review-NN.md von Codex da ist, setz jeden Punkt um oder begründe die Ablehnung in review-NN-antwort.md. Arbeite auf Branch claude/awesome-hypatia-tnhuis und ende jede Antwort mit der Checkliste.

## 9. Verlauf in Kürze
1. Baukasten v3/v4 (HTML, Liquid Glass, viele Varianten). Ein Tipp-Fehler kam von eingefrorenen db-Daten, behoben.
2. HTML-Prototyp Iteration 4 und 5: eigene Designsprache, unabhängige Kritik, Prinzipien dokumentiert.
3. Native App V1: alle Funktionen, CI grün (Läufe 1–6), Design-Fixes nach Screenshots.
4. Iteration 6 (heute): Körperalter, Kacheln überall, neutrales Design, Codex-Ablauf.
