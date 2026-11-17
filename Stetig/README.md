# Stetig

Ein kostenloser Gewohnheits-Tracker für iPhone und iPad: jede Gewohnheit bekommt ein Kachel-Raster, das sich Tag für Tag füllt. Gebaut mit SwiftUI, SwiftData und Liquid Glass (iOS 26), mit hellem und dunklem Modus. Kein Konto, keine Werbung, kein Abo – alle Daten bleiben auf dem Gerät.

Stetig ist eine eigenständige App mit eigenem Namen, Icon und Design. Das Raster-Prinzip kennt man von Beitragsgrafiken und anderen Habit-Trackern; Code, Assets und Gestaltung hier sind neu geschrieben.

## Funktionen

**Erfassen**
- Kachel-Raster pro Gewohnheit, Abhaken mit einem Tipp direkt auf der Karte
- Beim Anlegen oben wählen: Gewohnheit **aufbauen** oder etwas **abgewöhnen**
- Zähler mit Tagesziel, Einheit und Schrittweite (z. B. 8 Gläser, 20 min) – Teilmengen färben die Kachel heller
- „Abgewöhnen“-Gewohnheiten: jeder Tag ohne Rückfall zählt automatisch, optional mit Tageslimit
- Rhythmus: täglich, bestimmte Wochentage, x-mal pro Woche oder Monat
- Tage überspringen (Serie bleibt erhalten), Gewohnheiten pausieren, archivieren
- Notizen pro Tag, vergangene Tage im Monatskalender nachtragen
- Timer für Minuten-Gewohnheiten
- Start- und Enddatum für Challenges

**Auswerten**
- Aktuelle und beste Serie (in Tagen, Wochen oder Monaten – passend zum Rhythmus)
- Erfolgsquote, Wochen- und Wochentags-Diagramme, Jahresraster
- Tab „Heute“ mit Tagesfortschritt, auch für vergangene Tage
- Tab „Statistik“ mit Gesamtbild, 30-Tage-Verlauf, Rangliste und 13 Erfolgen
- Wochenrückblick (Quote, Vergleich zur Vorwoche, Tage Mo–So, jede Gewohnheit mit 7 Punkten) und Jahresrückblick (Jahresraster aller Gewohnheiten, Quote je Monat, bester Monat) – mit Blättern in vergangene Wochen und Jahre

**Drumherum**
- Widgets für Home- und Sperrbildschirm, interaktiv (Abhaken ohne die App zu öffnen)
- Steuerelement fürs Kontrollzentrum: eine Gewohnheit mit einem Tipp abhaken
- Siri: „Hey Siri, heute Lesen in Stetig gemacht“, „Wie läuft Lesen in Stetig?“, „Was ist heute in Stetig offen?“ – Siri antwortet mit Serie bzw. offenen Gewohnheiten
- Eigene Siri-Sätze ohne App-Namen („Hey Siri, heute Lesen gemacht“) mit einem Tipp: Einstellungen › Siri-Kurzbefehle › „Hinzufügen“ öffnet Apples Siri-Blatt mit fertig eingetragenem Satz. Dieser Satz öffnet Stetig kurz, hakt ab und zeigt eine Bestätigung
- Lokale Erinnerungen pro Gewohnheit, mit „Erledigt“-Aktion in der Mitteilung, plus täglicher Tagesabschluss
- Kategorien als Filter, drei Ansichten (Raster, Woche, Kompakt), Suche
- Sortieren nach eigener Reihenfolge, Name, Serie oder Quote; Gewohnheiten duplizieren
- iPad-Layout mit mehreren Spalten
- 23 Vorlagen, über 200 Symbole in 10 Gruppen und über 160 Emojis in 9 Gruppen – oder ein beliebiges eigenes Emoji
- 14 kuratierte Farb-Duos (z. B. Sonnenuntergang, Polarlicht, Lagune, Iris, Flamingo, Volt) plus „Mono“ (weiß im Dunkelmodus, schwarz im hellen Modus): Kacheln, Haken und Diagramme verlaufen von Farbe A nach B
- Liquid-Glass-Oberfläche über einem dezent leuchtenden Hintergrund, eigene Akzentfarbe und eigene Farbe für die Kategorie-Leiste wählbar
- Face-ID-Sperre, die auch offene Blätter und das Vorschaubild im App-Umschalter abdeckt
- Backup als JSON (Export/Import mit Zusammenführen), Export als CSV
- App-Sperre mit Face ID, heller/dunkler Modus, Wochenbeginn Montag oder Sonntag
- Verlauf als Bild teilen

## Auf dem eigenen iPhone installieren (Sideload mit Xcode)

Voraussetzungen: ein Mac mit **Xcode 26** oder neuer, ein iPhone/iPad mit **iOS 26** oder neuer, eine Apple-ID (kostenlos reicht).

1. `Stetig/Stetig.xcodeproj` in Xcode öffnen.
2. In Xcode unter *Settings › Accounts* mit der Apple-ID anmelden.
3. Im Projektnavigator das Projekt **Stetig** wählen und für die Targets **Stetig** und **StetigWidgets** jeweils unter *Signing & Capabilities* das eigene Team auswählen.
   Alternativ die Team-ID einmalig in `Config/Config.xcconfig` bei `DEVELOPMENT_TEAM` eintragen.
4. iPhone anschließen, oben als Ziel wählen, **⌘R**.
5. Beim ersten Start auf dem iPhone: *Einstellungen › Allgemein › VPN & Geräteverwaltung* → dem eigenen Entwicklerprofil vertrauen. Falls verlangt: *Datenschutz & Sicherheit › Entwicklermodus* aktivieren.

### Wenn die Signatur hakt

| Meldung | Lösung |
| --- | --- |
| „Failed to register bundle identifier“ | In `Config/Config.xcconfig` die `APP_BUNDLE_ID` ändern, z. B. `.max` anhängen. Widget und App Group ziehen automatisch mit. |
| Fehler rund um „App Groups“ | Bei beiden Targets unter *Signing & Capabilities* die Capability „App Groups“ entfernen. Die App läuft dann normal weiter und speichert im eigenen App-Ordner; nur die Widgets bekommen keine Daten. |
| App startet nach einigen Tagen nicht mehr | Mit kostenloser Apple-ID läuft die Signatur nach 7 Tagen ab. Einfach erneut aus Xcode starten (⌘R) – die Daten bleiben erhalten. |

Hinweise zum kostenlosen Account (Quellen: [Apple – Choosing a Membership](https://developer.apple.com/support/compare-memberships), [Apple – Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)): Profile laufen 7 Tage nach Ausstellung ab, und es lassen sich höchstens 10 App-IDs je 7 Tage registrieren. Stetig braucht zwei (App + Widgets). App Groups sind mit kostenloser Apple-ID erlaubt, die Siri-Berechtigung (SiriKit) und Push-Mitteilungen nicht. Stetig verwendet deshalb keine SiriKit-Intents (die diese Berechtigung brauchen), sondern App Intents und `NSUserActivity`-Kurzbefehle; Erinnerungen laufen lokal. iCloud-Sync ist bewusst nicht eingebaut.

## Projektaufbau

```
Stetig/
├─ Stetig.xcodeproj
├─ Config/            Bundle-ID, App Group, Info.plist, Entitlements
├─ Shared/            Datenmodell, Serien-Logik, Raster – von App und Widgets benutzt
├─ Stetig/            die App (Views, Services, Assets)
├─ StetigWidgets/     Widget-Erweiterung
├─ StetigTests/       Unit-Tests (Swift Testing)
└─ StetigUITests/     UI-Test, der durch die App klickt und Screenshots erzeugt
```

Das Projekt nutzt synchronisierte Ordner: Neue Dateien in diesen Ordnern gehören automatisch zum jeweiligen Target, ohne dass die Projektdatei angefasst werden muss.

Die gesamte Rechenlogik (Serien, Quoten, Kachelstufen) liegt in `Shared/HabitLogic.swift` und arbeitet auf reinen Werten ohne Datenbank. Tage sind fortlaufende Ganzzahlen (`Shared/Day.swift`), dadurch gibt es keine Zeitzonen- oder Sommerzeit-Fehler.

## Tests

In Xcode **⌘U**, oder im Terminal:

```sh
xcodebuild test -project Stetig.xcodeproj -scheme Stetig \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Mit Beispieldaten ausprobieren: *Einstellungen › Daten › Beispieldaten laden*, oder die App mit den Startargumenten `-inMemoryStore -seedDemo` starten (flüchtige Datenbank, echte Daten bleiben unberührt).

Jeder Push auf einen `claude/**`-Branch baut App und Widgets auf einem macOS-Runner und führt Unit- und UI-Tests im iOS-Simulator aus (`.github/workflows/ios.yml`). Die Screenshots des UI-Tests hängen als Artefakt am Lauf.

## Sprache

Die Oberfläche ist deutsch.
