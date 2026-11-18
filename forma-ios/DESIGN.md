# Forma – Gestaltungsprinzipien (native App, Iteration 6)

Abweichungen nur mit Begründung, die hier nachgetragen wird. Kritik von Codex steht in `reviews/`.

## Was sich in Iteration 6 geändert hat (Wunsch von Maxi: „nicht so blau, moderner, gern mehr Glas“)
| Vorher | Jetzt | Warum |
|---|---|---|
| Blaugrauer Verlauf #16212A → #080C0F | Neutrales Schwarz #030303 | kein Farbstich, wirkt hochwertiger auf OLED |
| Hintergrund immer gleich | Weicher Lichtschein oben in der Farbe der Daten (Heute: Erholungsfarbe, Detailseiten: Ringfarbe) | Farbe bleibt bedeutungsvoll, der Bildschirm „atmet“ mit dem Zustand |
| Abschnitt mit Überschrift über der Fläche | Kachel-Karte mit Kopfzeile innen (Symbol + Titel) | Kacheln sind verschiebbar, also braucht jede eine eigene Identität |
| Flächen 4,5 % Weiß, Radius 20 | Matte Karte mit Verlauf 7,5 → 3,5 % und Lichtkante oben, Radius 24 | moderner, mehr Tiefe, ohne Glas auf Inhalt |
| Chips aus Fläche | Chips und Hinweise aus echtem Liquid Glass | mehr Glas dort, wo es Apple vorsieht: kleine Bedien- und Statuselemente |
| Schlaf #67AEE6 (zweites Blau) | Schlaf #8E8CFF (Lavendel) | Belastung und Schlaf waren zu leicht zu verwechseln |
| Zahlen SF Pro | Große Zahlen SF Pro Rounded | freundlicher, eigenständig, bleibt tabellarisch |
| Ringe flach | Leichter Schein der Ringfarbe | Tiefe ohne zusätzliche Elemente |

## Feste Vorgaben
- Dunkel zuerst, die drei Ringe stehen auf „Heute“ **immer oben** und sind nicht verschiebbar.
- Ringfarben: Erholung nach Zone (#16EC06 / #FFDE00 / #FF0026), Belastung #0093E7, Schlaf #8E8CFF.
- Ringe zeigen 0–100 ohne Prozentzeichen, Antippen öffnet die Detailseite.
- Gestrichelter Bogen am Belastungsring = heute empfohlener Bereich.

## Kacheln (Heute, Training, Gesundheit)
- Alles unterhalb der Ringe ist eine Kachel. Drei Wege zum Anordnen:
  1. lange drücken und ziehen (Drop auf eine andere Kachel setzt davor ein),
  2. Kontextmenü: Nach oben, Nach unten, Ausblenden,
  3. Knopf „… anpassen“ unten (Glas): Liste zum Sortieren, Ein- und Ausblenden, „Standard“.
- Gespeichert pro Bildschirm (`forma.tiles.today|training|health`). Neue Kacheln aus Updates hängen sich unten an.
- Coach ist bewusst ohne Kacheln: Er ist ein Chat und hat eine feste Reihenfolge.

## Prinzipien
1. **Glas ist Bedienung und Status.** Tab-Leiste, Toolbar, angehefteter Ring-Streifen, Trainings-Dock, Chips, Hinweise, Knöpfe. Inhalte liegen auf matten Karten, kein Glas auf Glas.
2. **Eine Hauptsache pro Bildschirm.** Heute: Ring-Trio (Erholung 120 pt, die anderen 88 pt). Detailseiten: ein großer Ring oder eine große Zahl.
3. **Farbe bedeutet etwas.** Bereichsfarben, Warnung #FFB547, Körperalter jünger #3DDC97 / älter #FF8A5B. Auswahl und Erledigt sind neutral.
4. **Jede Zahl mit Bezug:** Normalbereich, Zielbogen, Vergleich zum Mittel oder (Körperalter) zum echten Alter.
5. **Typografie:** SF Pro, große Zahlen SF Pro Rounded, alle Zahlen `monospacedDigit`.
6. **Raster 4 pt, Seitenrand 16, Abstand zwischen Kacheln 12.**
7. **Radien:** Karten 24, kleine Felder 12, Dock 30, Bedienelemente kapselförmig.
8. **Daumenzone:** Im Training liegt alles Wichtige im Glas-Dock unten, Tippflächen mindestens 44 pt.
9. **Bewegung erklärt:** Ringe animieren vom letzten Wert, gestaffelt, nur bei neuen Daten. Der Lichtschein blendet weich in die neue Farbe.
10. **Ehrlichkeit:** Schätzungen heißen Schätzung, Beispieldaten und Annahmen sind gekennzeichnet, Quellen sind verlinkt.

## Bewusste Entscheidungen
- **Tabs:** Heute · Training · Gesundheit · Coach. Journal und Profil erreichst du über die Kachel „Als Nächstes“ bzw. den Profil-Knopf.
- **Körperalter** statt „biologisches Alter“: Wir messen kein Blut und keine Gene, also bleibt der Name bescheiden.
- **Coach-Vorschläge** gelten nur für das heutige Training, die Routine bleibt unverändert.
- **Fehlender Fitbit-Sync:** Erholung und Schlaf zeigen gedimmt den Wert von gestern, dazu „Warte auf Fitbit“. Der Lichtschein bleibt neutral.
