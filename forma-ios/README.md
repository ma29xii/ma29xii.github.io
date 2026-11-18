# Forma (iOS)

Native iPhone-App für Erholung, Schlaf, Belastung und Krafttraining. SwiftUI, iOS 26, Swift 6, Liquid Glass, SwiftData. Keine Fremd-Frameworks.

## IPA bauen und installieren

1. Jeder Push auf den Branch `claude/awesome-hypatia-tnhuis`, der `forma-ios/` ändert, startet den Workflow **Forma iOS (IPA)** (`.github/workflows/forma-ios.yml`).
2. Nach dem Lauf unter *Actions → Forma iOS (IPA) → Artifacts* das Artifact **Forma-IPA** herunterladen und entpacken. Darin liegt `Forma.ipa`.
3. Mit **Sideloadly** auf das iPhone laden. Sideloadly signiert mit deiner Apple-ID neu.

Die IPA ist ad hoc signiert. Sideloadly signiert sie für dein iPhone neu. Bei einer kostenlosen Apple-ID musst du die App in der Regel nach sieben Tagen erneut signieren. [Apple-Mitgliedschaften](https://developer.apple.com/support/compare-memberships/)

## Google Health einrichten

1. **Auf dem iPhone** die Google-Health-App öffnen und mit deinem Google-Konto anmelden. Falls nötig, dein altes Fitbit-Konto auf dieses Google-Konto umziehen. Prüfe in Google Health, ob deine Fitbit-Werte sichtbar sind. [Googles Einrichtungsanleitung](https://developers.google.com/health/setup)
2. **Am PC** die Google Cloud Console öffnen. Oben ein Projekt namens **Health** erstellen. In **APIs & Dienste → Bibliothek** nach **Google Health API** suchen und sie aktivieren. [Google Cloud Console](https://console.cloud.google.com/)
3. **Google Auth Platform** öffnen. Beim Einrichten **Health** als App-Namen, deine Support- und Kontaktadresse und **Extern** als Zielgruppe angeben. Unter **Zielgruppe → Testnutzer** dein Google-Konto hinzufügen. [Google-OAuth-Einrichtung](https://developers.google.com/health/setup)
4. **Datenzugriff → Bereiche hinzufügen oder entfernen** öffnen und die drei Leserechte hinzufügen. [Googles Übersicht der Berechtigungen](https://developers.google.com/health/scopes)

   - `https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly`
   - `https://www.googleapis.com/auth/googlehealth.sleep.readonly`
   - `https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly`

5. **Clients → Client erstellen → iOS** wählen. Als Bundle-ID `com.ma29xii.forma` eintragen. Die **Client-ID** und das angezeigte **iOS-URL-Schema** für den nächsten Schritt bereithalten. [Google-Health-Migration](https://developers.google.com/health/migration/data-access) · [Google-Anleitung für das iOS-URL-Schema](https://developers.google.com/identity/sign-in/ios/start-integrating)
6. **Für die nächste IPA** in `Config.xcconfig` die öffentliche Client-ID bei `GOOGLE_CLIENT_ID` eintragen. Bei `GOOGLE_REDIRECT_SCHEME` den Platzhalter durch das iOS-URL-Schema ersetzen. Lass danach die IPA neu bauen und installiere sie. Die native Anmeldung verwendet PKCE.
7. **In der App Health** das Profil öffnen und **Google Health verbinden** antippen. Dasselbe Google-Konto wählen und die drei Leserechte erlauben. Danach unter **Today** prüfen, ob der letzte Fitbit-Schlaf auftaucht.
8. **Für deine Apple Watch** in der Google-Health-App **Verbindungen → Apps und Dienste → Apple Health** öffnen und Leserechte für die gewünschten Werte erlauben. Google nennt für die Google-Health-App bis zu drei Monate Apple-Health-Verlauf. Ob die API jeden dieser Werte mit identifizierbarer Uhr liefert, hängt vom tatsächlichen Import ab. [Google-Hilfe zu Apple Health](https://support.google.com/googlehealth/answer/17037331?hl=de)
9. **Für die dauerhafte Verbindung** unter **Google Auth Platform → Zielgruppe** den Veröffentlicht-Status prüfen. Im Modus **Testing** kann die Google-Freigabe nach sieben Tagen ablaufen. Im Modus **In Produktion** gelten Googles Anforderungen für die gewählten Berechtigungen. [Google-Dokumentation zu ablaufenden Freigaben](https://developers.google.com/identity/protocols/oauth2#expiration)

## Synchronisierung im Hintergrund

1. Die App fragt die jüngsten sieben Tage beim Öffnen, im Vordergrund und über iOS-Hintergrundaufgaben ab. iOS bestimmt, wann es Netzwerkzeit im Hintergrund gewährt. Der erste längere Import ergänzt schrittweise bis zu 180 Tage. [Apple zu Hintergrundaufgaben](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask)
2. Der letzte erfolgreiche Stand liegt geschützt auf dem iPhone. Bei Teilfehlern bleiben die betroffenen älteren Messwerte verfügbar. Fehlende Messungen bleiben als Lücken sichtbar.
3. **Google Health trennen** entfernt die lokale Messwertkopie und die gespeicherte Anmeldung. Wenn der Widerruf bei Google offline nicht ankommt, kannst du den Zugang in der Google-Health-App unter **Apps und Dienste** entfernen. [Google-Hilfe zum Widerruf](https://developers.google.com/health/troubleshooting#revoke-consent-to-an-app)

## Datenquellen

- **Google Health** liefert echte Messwerte. Fitbit hat Vorrang für Schlaf und nächtliche Vitalwerte. Bei stündlichen Schritten und Tagespuls hat eine eindeutig erkennbare Apple Watch Vorrang. Aktive Energie kommt aus derselben Quelle wie die Schritte der Stunde. Die HRV-Reihe verwendet Fitbit-RMSSD.
- **Beispieldaten** dienen als gekennzeichnete Vorschau. Du kannst sie im Profil aktivieren.
- **Dein Krafttraining** aus dieser App zählt weiterhin zur Belastung. Überlappende Einträge werden nur einmal berücksichtigt.

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

Grenzen: Die Studien zeigen Zusammenhänge, keine sicheren Ursachen. Die VO₂max der Uhr ist eine Schätzung, und die FRIEND-Werte für die mittleren Altersgruppen habe ich nur aus einer Sekundärquelle (der erste und der letzte Wert stehen im Abstract). Das Körperalter ist zur Orientierung gedacht, nicht als Diagnose. Alter und Geschlecht kommen aus *Profil → Über dich*.

## Kacheln

Auf Heute, Training und Gesundheit ist alles unterhalb der Ringe eine Kachel. Lange drücken und ziehen, Kontextmenü (Nach oben/unten, Ausblenden) oder unten „… anpassen“.

## Zusammenarbeit mit Codex

Claude baut, Codex prüft als sehr kritischer Senior Designer. Ablauf und Prüfauftrag stehen in `../AGENTS.md`, die Reviews in `reviews/`.

## Coach

Der Coach berechnet den Tagessatz lokal. Ein eingerichteter Online-Coach braucht deine Zustimmung. Trainingsänderungen gelten nach deiner Bestätigung für das heutige Training.

## Gestaltung

Neutrales Schwarz mit einem Lichtschein in der Farbe der Daten, matte Karten mit Lichtkante, Liquid Glass für Bedienelemente und Chips. Details und Begründungen: `DESIGN.md`.

## Projekt

```
forma-ios/
├─ project.yml            XcodeGen-Projekt (Bundle-ID com.ma29xii.forma)
├─ Config.xcconfig        Google-OAuth-Konfiguration
├─ reviews/             Codex-Reviews und Antworten
└─ Forma/
   ├─ App/                Einstieg, App-Zustand, Live-Training-Modell
   ├─ Design/             Designsystem, Komponenten, Ringe, Kacheln
   ├─ Data/               Google Health, Berechnung, Körperalter, Beispieldaten, SwiftData-Modelle
   ├─ Features/           Heute, Training, Gesundheit, Coach, Journal, Profil
   └─ Resources/          Info.plist, Entitlements, Assets
```

Lokal bauen: `brew install xcodegen && cd forma-ios && xcodegen generate && open Forma.xcodeproj`
