# Forma (iOS)

Native iPhone-App für Erholung, Schlaf, Belastung und Krafttraining. SwiftUI, iOS 26, Swift 6, Liquid Glass, SwiftData. Keine Fremd-Frameworks.

## IPA bauen und installieren

1. Jeder Push auf den Branch `claude/awesome-hypatia-tnhuis`, der `forma-ios/` ändert, startet den Workflow **Forma iOS (IPA)** (`.github/workflows/forma-ios.yml`).
2. Nach dem Lauf unter *Actions → Forma iOS (IPA) → Artifacts* das Artifact **Forma-IPA** herunterladen und entpacken. Darin liegt `Forma.ipa`.
3. Mit **Sideloadly** auf das iPhone laden. Sideloadly signiert mit deiner Apple-ID neu.

Die IPA ist nicht mit einem Zertifikat signiert. Sie trägt nur eine Ad-hoc-Signatur, damit die HealthKit-Berechtigung in der App steckt und Sideloadly sie übernehmen kann.

**Kostenlose Apple-ID:** Die Signatur läuft nach 7 Tagen ab, dann erneut mit Sideloadly installieren. Die Daten bleiben erhalten. HealthKit soll laut Apples Fähigkeiten-Tabelle auch mit kostenloser Apple-ID für die eigene Nutzung gehen ([Expo, mit Verweis auf Apple](https://expo.dev/blog/apple-developer-program-explained-free-vs-paid)), im Entwicklerforum wird aber auch von Fehlern bei der Bereitstellung berichtet ([Apple Developer Forums](https://developer.apple.com/forums/thread/722522)). Verbindlich ist [Apples Tabelle der unterstützten Fähigkeiten](https://developer.apple.com/help/account/reference/supported-capabilities-ios/). Klappt es nicht, zeigt Forma gekennzeichnete Beispieldaten oder nutzt Fitbit.

## Fitbit einrichten (OAuth 2.0 mit PKCE)

1. Auf <https://dev.fitbit.com/apps/new> mit deinem Fitbit-/Google-Konto anmelden und eine App registrieren:
   - **OAuth 2.0 Application Type:** `Personal` (für eigene Daten inklusive HRV und Schlaf) oder `Client`
   - **Redirect URL:** `forma://fitbit`
   - **Default Access Type:** `Read Only`
   - Für die übrigen Pflichtfelder (Website, Datenschutz, Nutzungsbedingungen) reicht z. B. `https://ma29xii.github.io`.
2. Die angezeigte **OAuth 2.0 Client ID** in `forma-ios/Config.xcconfig` bei `FITBIT_CLIENT_ID` eintragen, committen und pushen. Der Workflow baut eine neue IPA.
3. In Forma: *Profil → Mit Fitbit verbinden*. Die Anmeldung läuft in einem sicheren Browserfenster (ASWebAuthenticationSession). Forma bekommt nur Lesezugriff auf Schlaf, Herzfrequenz/HRV, Aktivität, SpO₂ und Atemfrequenz.

Ein Client-Secret wird nicht gebraucht, die App nutzt PKCE. Google stellt Fitbit schrittweise auf Google-Konten und die Google Health API um. Ob und wann die Fitbit Web API abgeschaltet wird, kann ich nicht bestätigen.

## Datenquellen

- **Apple Health:** HRV, Ruhepuls, Schlafphasen, Schritte, aktive Energie, VO₂max, Atemfrequenz, SpO₂, Trainings (nur lesen)
- **Fitbit:** Schlaf, HRV (RMSSD), Ruhepuls, Schritte, Aktivitätskalorien, SpO₂, Atemfrequenz
- **Beispieldaten:** werden ohne Berechtigung oder Daten gezeigt und überall mit „Beispieldaten“ gekennzeichnet

Hat Fitbit für heute noch keinen Schlaf geliefert, zeigt Forma die Werte von gestern gedimmt mit dem Hinweis „Warte auf Fitbit“.

## Berechnung (lokal, nachvollziehbar)

- **Erholung (0–100):** Startwert 58, dazu HRV gegen dein 30-Tage-Mittel (stärkster Faktor), Ruhepuls und Atemfrequenz, plus der Schlafwert
- **Schlaf (0–100):** Dauer gegen Bedarf (60 %), Effizienz (20 %), Tief- und REM-Anteil (20 %)
- **Belastung (0–100):** aktive Energie und Trainingszeit, nähert sich 100
- **Empfohlener Bereich** (gestrichelter Bogen am Belastungsring): gut erholt 35–55, mittel 25–40, wenig erholt 10–25

### Körperalter (Gesundheit und Kachel auf „Heute“)

Wie alt dein Körper nach deinen Messwerten wirkt. Grundlage sind die letzten bis zu 180 Tage, gezeigt wird es ab 21 Tagen mit Daten. Ähnliche Funktionen gibt es bei WHOOP („WHOOP Age“, [WHOOP](https://www.whoop.com/us/en/thelocker/healthspan/)) und Bevel („Biological Age“). Deren genaue Formeln sind nicht öffentlich, Formas Rechnung ist offengelegt:

| Faktor | Effekt aus Studien | Referenz in Forma |
|---|---|---|
| VO₂max | je 1 MET (3,5 ml/kg/min) mehr ≈ 13 % geringeres Sterberisiko ([Kodama 2009](https://pubmed.ncbi.nlm.nih.gov/19454641/)) | Median deiner Alters- und Geschlechtsgruppe (FRIEND-Register, Laufband) |
| Ruhepuls | je 10 bpm mehr ≈ 9 % höheres Risiko ([Zhang 2016](https://pubmed.ncbi.nlm.nih.gov/26598376/)) | 65 bpm (Annahme) |
| Schritte | Quartile 3.553 / 5.801 / 7.842 / 10.901 Schritte: HR 1 / 0,60 / 0,55 / 0,47 ([Paluch 2022](https://doi.org/10.1016/S2468-2667(21)00302-9)) | 7.000 pro Tag (Annahme) |
| Schlafdauer | ≤ 6 h: RR 1,12, ≥ 9 h: RR 1,30 ([Cappuccio 2010](https://pubmed.ncbi.nlm.nih.gov/20469800/)) | 7–8 h |
| Krafttraining | 30–60 min/Woche ≈ 10–17 % geringeres Risiko ([Momma 2022](https://doi.org/10.1136/bjsports-2021-105061)) | kein Krafttraining |

Umrechnung in Jahre: Das Sterberisiko Erwachsener verdoppelt sich etwa alle 8 Jahre (Gompertz), also Jahre = ln(Risiko) · 8 / ln 2. Weil die Faktoren zusammenhängen, zählt die Summe nur zu 70 % (eigene Annahme). HRV fließt nicht ein (SDNN bei Apple und RMSSD bei Fitbit sind nicht vergleichbar, und für Uhren-HRV fehlen Studien zur Lebenserwartung).

Grenzen: Die Studien zeigen Zusammenhänge, keine sicheren Ursachen. Die VO₂max der Uhr ist eine Schätzung, und die FRIEND-Werte für die mittleren Altersgruppen habe ich nur aus einer Sekundärquelle (der erste und der letzte Wert stehen im Abstract). Das Körperalter ist zur Orientierung gedacht, nicht als Diagnose. Alter und Geschlecht kommen aus Apple Health oder aus *Profil → Über dich*.

## Kacheln

Auf Heute, Training und Gesundheit ist alles unterhalb der Ringe eine Kachel. Lange drücken und ziehen, Kontextmenü (Nach oben/unten, Ausblenden) oder unten „… anpassen“.

## Zusammenarbeit mit Codex

Claude baut, Codex prüft als sehr kritischer Senior Designer. Ablauf und Prüfauftrag stehen in `../AGENTS.md`, die Reviews in `reviews/`.

## Coach

Der Tagessatz und die Antworten werden lokal berechnet. Optional lässt sich in *Profil → Coach* ein Anthropic-API-Schlüssel hinterlegen. Er liegt im Schlüsselbund, und freie Fragen gehen dann an Claude. Trainingsänderungen schlägt der Coach nur vor. Übernimmst du einen Vorschlag, gilt er nur für das heutige Training, die gespeicherte Routine bleibt unverändert.

## Gestaltung

Neutrales Schwarz mit einem Lichtschein in der Farbe der Daten, matte Karten mit Lichtkante, Liquid Glass für Bedienelemente und Chips. Details und Begründungen: `DESIGN.md`.

## Projekt

```
forma-ios/
├─ project.yml            XcodeGen-Projekt (Bundle-ID com.ma29xii.forma)
├─ Config.xcconfig        Fitbit-Client-ID
├─ reviews/             Codex-Reviews und Antworten
└─ Forma/
   ├─ App/                Einstieg, App-Zustand, Live-Training-Modell
   ├─ Design/             Designsystem, Komponenten, Ringe, Kacheln
   ├─ Data/               HealthKit, Fitbit, Berechnung, Körperalter, Beispieldaten, SwiftData-Modelle
   ├─ Features/           Heute, Training, Gesundheit, Coach, Journal, Profil
   └─ Resources/          Info.plist, Entitlements, Assets
```

Lokal bauen: `brew install xcodegen && cd forma-ios && xcodegen generate && open Forma.xcodeproj`
