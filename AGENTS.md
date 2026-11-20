# AGENTS.md – Übergabe für Codex: App „Health“ selbstständig weiterentwickeln

> **Stand 20.11.2026 abends: Codex macht allein weiter.** Zuerst `.teamarbeit/uebergabe-codex-20261120-abend.md` lesen (aktueller Stand, offener CI-Lauf, Feedback 05–07), dann [HANDOVER.md](HANDOVER.md).


Bei Wechsel zwischen Claude Code und Codex oder bei der iPhone-Testversion zuerst [HANDOVER.md](HANDOVER.md) lesen. Dort stehen die aktuellen Entscheidungen, der GitHub-Lauf und der bereits eingerichtete Google-Health-Testclient.

Codex liest diese Datei automatisch. Sie enthält alles, um **ohne Claude** weiterzubauen: Ziel, Aufbau, Design-Regeln, Ablauf, offene Punkte.
Sprache: **Deutsch**, du-Form. Nutzer und Entscheider: **Maxi** (testet auf dem iPhone).

## 1. Ziel (Maxis Dauerauftrag, gilt bis er „Stopp“ sagt)

Die App soll mit den modernsten Apps mithalten („krass, das ist eine krasse App“): **cleanes Design auf Jony-Ive-/WHOOP-Niveau**, viele neue Features, gründlich testen und debuggen, in Runden wiederholen.
Codex und Claude teilen sich die Arbeit **etwa 50/50** – Codex baut echte Features, nicht nur Reviews.
Modell: **höchstens GPT-6.2** (kleine Aufgaben `medium`, große `high`).

## 2. Die App

- Anzeigename **„Health“**. Code-Namen bleiben **Forma** (Ordner `forma-ios/`, Target `Forma`, Bundle-ID `com.ma29xii.forma`, App Group `group.com.ma29xii.forma`). Nicht umbenennen.
- SwiftUI, **iOS 26**, **Swift 6 strict concurrency**, Liquid Glass, SwiftData, Swift Charts, WidgetKit, ActivityKit, App Intents. **XcodeGen** (`forma-ios/project.yml`), keine Fremd-Frameworks.
- **Einzige Datenquelle: Google Health API** (Fitbit 24/7 + Apple Watch tagsüber, ohne Doppelzählung; `Data/GoogleHealth*.swift`). Kein Apple-HealthKit (kostenlose Apple-ID kann es nicht).
- Beispieldaten-Modus (`SampleData.swift`, 180 Tage) für Vorschau und CI. Beispieldaten schreiben nie in echte Einstellungen (`FoodSettings.store(isSample:)`).
- Coach läuft **direkt auf dem iPhone** (Anthropic → OpenAI-Rückfall, `Features/Coach/CoachProviders.swift`), Schlüssel nur im Schlüsselbund, nie im Repo.

### Tabs und Bildschirme (Stand Runde 12)

| Tab | Inhalt | Ordner |
|---|---|---|
| **Today** | Kopf: Recovery groß in der Mitte, Strain/Sleep als Kapseln links/rechts – wählbar auch als **3 Ringe** (langer Druck auf den Kopf oder „Anpassen“). Darunter Kacheln: Health Monitor (kompakt), Stress, Energie, Schritte mit adaptivem Ziel (Strich-Halbkreis), Mein Tag. Ring antippen → Detailseite. | `Features/Today/` |
| **Food** | YAZIO-artig: Kalorien Mitte, Protein links, Kohlenhydrate rechts, Ballaststoffe, Mahlzeiten, Wasser, Fasten, Wochenplan + Einkaufsliste. | `Features/Food/` |
| **Health** | Health Age als **Partikelkreis** (WHOOP-Age-Vorbild), Alterungstempo, Biomarker, Gewohnheit (14-Tage-Vergleich), Health Monitor. | `Features/Health/` |
| **Coach** | Chat mit Lumo (schlichter, atmender Lichtpunkt), Fotos senden. | `Features/Coach/`, `Design/Mascot.swift` |
| **Plus** (Knopf rechts) | Kachel-Menü, springt aus der Ecke auf: Nährwerte tracken (Scan/Foto/Suche), Essen planen, **Training** (Hevy-artig, Muskelkarte, Supersätze, Live-Training), Wasser, Fasten, Gewicht. | `Features/Plus/`, `Features/Training/` |

Weitere: Profil/Body/Designs (Themes: Standard, Schwarz, Blau #4D8EB6, Bordeaux #5C2624, Verläufe), Onboarding, Erfolge, Teilen-Karten, Widgets (Recovery/Sleep/Strain + Wasser +250 ml, Control Center), Live Activity fürs Training, Siri-Kurzbefehle.

## 3. Design-Regeln (aus Maxis Feedback – verbindlich)

1. **Keine Chevrons/Pfeile** in Listen und Kacheln. Antippen geht trotzdem.
2. **Keine Erklär- oder Berechnungstexte** („So wird gerechnet“, „Deine Messwerte deuten darauf hin …“, Fußnoten). Höchstens hinter einem kleinen (i).
3. **Kein „Heute vs. 30-Tage-Schnitt“**, kein Datum unter großen Werten, keine Tagesauswahl durch Tippen in Diagrammen, kein „Schätzung“, kein „Stand 17:00“.
4. **Alles auf einen Blick beim Scrollen** – keine Extra-Tipps für Standardinhalte; nur sehr spezielle Daten in Unterseiten.
5. **„Anpassen“ immer ganz unten.**
6. **Etwas mehr Farbe** – Ringfarben als Akzente (Recovery grün/gelb/rot, Strain blau, Sleep lila), nicht bunt.
7. **Einheitliche Skala** (`Design/MetricScale.swift`) statt eigener Varianten.
8. **Englische Ring- und Tab-Namen** (Recovery, Strain, Sleep; Today, Food, Health, Coach), sonst Deutsch.
9. **Apple-Gesten**: vom Rand zurück, Blätter wegwischen, Wischen zum Löschen, Kontextmenü, Ziehen zum Aktualisieren.
10. Eigene Formen – **keine 1:1-Kopie** von WHOOP/Bevel/YAZIO/Hevy (Rechtsrisiko), aber deren Qualität.
11. Dark Mode zuerst, Dynamic Type, VoiceOver-Labels, Tippziele ≥ 44 pt, Reduce Motion beachten.

Maxis Original-Feedback: `.teamarbeit/feedback-maxi-03.md` (Kürzel T1, H1 …), WHOOP-Age-Referenz `.teamarbeit/whoop-age-referenz.webp`, WHOOP-PDF `C:\Users\maxi\Downloads\Forma-Referenzbilder.pdf`, Inspiration `.teamarbeit/recherche-inspiration.md`, Feature-Ideen `.teamarbeit/recherche-features.md`.

## 4. Ablauf, Build, Git

- Branch **`claude/awesome-hypatia-tnhuis`**, Repo `ma29xii/ma29xii.github.io`. Keine PRs.
- Windows-Rechner: **kein Xcode**. Bauen und testen nur über **GitHub Actions** (`.github/workflows/forma-ios.yml`): Job `ipa` baut die IPA (Artifact `Forma-IPA`), Job `screens` führt `FormaTests` (müssen grün sein) und den UI-Rundgang `FormaUITests/ScreenTour.swift` aus (Artifact `Health-Screenshots`, Pflichtbilder in `REQUIRED`).
- Neue Pushes **ersetzen wartende CI-Läufe** – bei vielen Commits erst am Ende einen Lauf abwarten.
- **Codex kann in seiner Sandbox nicht committen** (`.git` gesperrt). Lege Änderungen nur im Arbeitsbaum ab und schreibe `.teamarbeit/ergebnis-<name>.md`; Claude oder Maxi committet. Wenn Maxi Codex mit Git-Rechten startet: nur eigene Dateien `git add`, Commit `[codex-<runde>] Runde NN: …`, `git pull --rebase --autostash`, `git push`.
- IPA für Maxi: nach grünem Lauf `gh run download <id> -n Forma-IPA` → `C:\Users\maxi\Downloads\Health.ipa`. Installation per Sideloadly (kostenlose Apple-ID, 7 Tage gültig).
- Testplan fürs iPhone: `forma-ios/TESTEN.md`.

### Häufige Swift-6-Fallen (schon passiert)
- Statische Konstanten in Views/MainActor-Typen, die Tests lesen → `nonisolated static let` oder Test `@MainActor`.
- `UserDefaults.register(defaults:)` gilt prozessweit → nie für Vorschau-Speicher verwenden.
- Nicht-Sendable ActivityKit-Objekte über `await` → `nonisolated(unsafe) let`.
- Keine erfundenen APIs (z. B. gab es `IntentExecutionTargets` nicht).
- Definition und erster Aufruf eines neuen Members **im selben Commit** liefern, sonst bricht der Build dazwischen.

## 5. Dateibesitz pro Runde

Pro Runde gibt es eine `.teamarbeit/REGELN-runde-NN.md` mit Tabelle „wer ändert welche Dateien“ und festen Schnittstellen. **Nur eigene Dateien ändern.** Aktuell: `REGELN-runde-11.md`. Arbeitet Codex allein, gehört ihm alles – dann trotzdem in kleinen, in sich kompilierbaren Schritten.

## 6. Offene Punkte (Backlog, nach Nutzen sortiert)

1. **CI-Lauf von Runde 11/12 prüfen** und Compile-/Testfehler beheben (viele Teile noch nie kompiliert).
2. Schlafplan (Codex G, Runde 12) fertigstellen, ggf. an `CoachNotifier` (Bettzeit-Erinnerung) anbinden.
3. Gegenprüfung 05 Restpunkte: A5 einheitliche Skala auch für Schritte/Stress/Alterungstempo; H1 Feinschliff Partikelkreis.
4. Ideen: Gerätevergleich bei widersprüchlichem Schlaf (zwei Zeitachsen, Korrektur), Rezepte/Favoriten-Ausbau, Jetlag-Plan, Wochenrückblick als Story, Achievements-Ausbau.
5. Google-Health-Testclient ist eingerichtet. Anmeldung, Rücksprung und Datenabruf auf Maxis iPhone prüfen. Einzelheiten und aktueller Build stehen in [HANDOVER.md](HANDOVER.md).

## 7. Regeln für alle Agenten

- Keine Fakten erfinden; Unbelegtes kennzeichnen.
- Keine Schlüssel, Tokens oder `.env` lesen, ausgeben oder committen. `coach-keys.json` nie in die Standard-IPA.
- Bestehende Tests nicht löschen oder abschwächen; nur anpassen, wenn Maxis Wunsch sie direkt ändert (im Commit nennen).
- Nicht in `docs/forma-screens/` schreiben (macht die CI).
- Am Ende jeder Aufgabe auf Deutsch in 3 Stichpunkten: was geändert, was getestet, was offen.
