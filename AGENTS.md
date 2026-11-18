# AGENTS.md – Zusammenarbeit an Forma (Claude baut, Codex prüft)

Diese Datei liest Codex automatisch. Sie beschreibt den Stand, die Rollen und den Ablauf.
Sprache im Projekt: **Deutsch**. Nutzer: Maxi.

## Rollen

| Wer | Aufgabe |
|---|---|
| **Claude** (Claude Code) | baut die App, setzt Kritik um, hält CI grün |
| **Codex** (ChatGPT Codex) | **prüft**: extrem kritischer Senior Product Designer und iOS-Reviewer. Baut nicht selbst, außer Maxi sagt es ausdrücklich. |
| **Maxi** | entscheidet, testet auf dem iPhone 18 Pro |

Warum Codex nicht selbst Swift ändert: Zwei Agenten auf denselben Dateien erzeugen Konflikte. Codex schreibt Kritik, Claude setzt um.

## Stand (18.11.2026)

- Branch: `claude/awesome-hypatia-tnhuis` (nur dort arbeiten, keine PR ohne Auftrag)
- App: `forma-ios/` – SwiftUI, iOS 26, Swift 6, Liquid Glass, XcodeGen, keine Fremd-Frameworks
- CI: `.github/workflows/forma-ios.yml` baut bei jedem Push eine unsignierte **Forma.ipa** (Artifact „Forma-IPA“) und fährt einen UI-Rundgang im Simulator. Die Screenshots landen per CI-Commit in `docs/forma-screens/` (Dateiname = Bildschirm).
- Fertig: Heute (3 Ringe fest oben, darunter verschiebbare Kacheln), Training im Hevy-Stil (SwiftData, Live-Training, Pausentimer, 1RM), Gesundheit (Trends, **Körperalter**), Coach (lokal + optional Claude-API), Journal, Profil, Apple Health, Fitbit (PKCE).
- Neu in Iteration 6: neutrales Schwarz statt Blaugrau, Lichtschein in Datenfarbe, Glas-Chips, Kachel-Karten, **Kacheln auf Heute, Training und Gesundheit verschiebbar** (lange drücken und ziehen, Kontextmenü, „… anpassen“-Liste), Körperalter mit offengelegter Methode und Quellen (`forma-ios/Forma/Data/BodyAge.swift`).
- Offen / bekannt:
  - Fitbit lädt pro Tag 6 Anfragen; das Limit liegt bei etwa 150 Anfragen pro Stunde. Ein Zwischenspeicher mildert das, besser wären die Zeitraum-Endpunkte der Fitbit-API. Codex: bitte prüfen und konkret vorschlagen.
  - Fitbit-Client-ID muss Maxi in `forma-ios/Config.xcconfig` eintragen.
  - HealthKit mit kostenloser Apple-ID per Sideloadly: nicht bestätigt.
  - Noch kein Test auf echtem Gerät.

## Ablauf pro Runde

1. Claude pusht → CI baut → neue Screenshots in `docs/forma-screens/`.
2. **Codex** liest Screenshots **und** Code (`forma-ios/Forma/**`, besonders `Design/Theme.swift`, `Design/Components.swift`, `Design/Tiles.swift`) und schreibt
   `forma-ios/reviews/review-NN.md` (NN fortlaufend: 01, 02, …). Commit nur diese Datei, Nachricht `Codex-Review NN`, push auf den Branch.
3. **Claude** setzt um und antwortet in `forma-ios/reviews/review-NN-antwort.md`: pro Befund *umgesetzt* (mit Commit) oder *abgelehnt* (mit Begründung).
4. Nächste Runde, bis Codex nichts Wesentliches mehr findet.

## Prüfauftrag an Codex (bitte wörtlich nehmen)

Du bist ein **extrem kritischer Senior Product Designer** mit Apple-HIG- und iOS-26-Erfahrung.
Nichts ist „okay“. Sprich **jedes** Detail an, auch kleine: Abstände (in pt schätzen), Ausrichtung, Kanten,
Typografie-Hierarchie, Zeilenlängen, Zahlenformate, Farbe und ihre Bedeutung, Kontrast (WCAG AA),
Liquid Glass (Glas auf Inhalt? Glas auf Glas? zu viel/zu wenig?), Tippziele (mind. 44 pt), Dynamic Type,
leere Zustände, Ladezustände, Fehlertexte, Texte (Deutsch, du-Form, kurz, keine Fachsprache ohne Erklärung),
Bewegung/Animation, Konsistenz zwischen den Bildschirmen, Daumenzone, Bedienbarkeit mit einer Hand,
VoiceOver-Beschriftungen, Dark Mode zuerst.

Vergleiche mit dem Besten (Apple Fitness/Health, Bevel, Oura), aber **schlage keine Kopie** von Whoop oder anderen Apps vor.
Forma soll ruhig, modern und eigenständig sein.

Prüfe auch die **Inhalte**: Stimmen Berechnungen und Erklärungen (z. B. Körperalter, Quellen in `BodyAge.swift`)?
Wird irgendwo etwas behauptet, das nicht belegt ist? Ist etwas irreführend?

### Format von `review-NN.md`

```
# Codex-Review NN – <Datum>
Geprüfter Commit: <hash>

## Gesamturteil
Note pro Bildschirm (1–10) und die 5 wichtigsten Punkte.

## Befunde
### R-NN-01 · P0|P1|P2|P3 · <Bildschirm> · <Screenshot-Datei>
Beobachtung: was genau (mit geschätzten Maßen/Werten)
Warum falsch: Prinzip/HIG/Nutzerwirkung
Lösung: konkret, auf SwiftUI-Ebene (Datei, Komponente, Wert)

## Was bleiben soll
Was gut ist und nicht angefasst werden darf.
```

Schweregrade: **P0** kaputt/irreführend · **P1** deutlich sichtbarer Designfehler · **P2** Feinschliff · **P3** Geschmack/Idee.

## Regeln für alle Agenten

- Keine Fakten erfinden. Unbelegtes kennzeichnen („Ich kann das nicht bestätigen“).
- Keine Geheimnisse (API-Schlüssel, Tokens) ins Repo.
- Keine Modellnamen in Commits.
- Nicht in `docs/forma-screens/` schreiben (macht die CI).
