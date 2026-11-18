# Forma – Gestaltungsprinzipien (native App)

Übernommen aus der HTML-Iteration 5 und für iOS 26 angepasst. Abweichungen nur mit Begründung, die hier nachgetragen wird.

## Feste Vorgaben
- Dunkel zuerst (`UIUserInterfaceStyle = Dark`), ruhiger blaugrauer Grund (#16212A → #080C0F)
- Ringfarben: Erholung nach Zone (#16EC06 / #FFDE00 / #FF0026), Belastung #0093E7, Schlaf #67AEE6
- Ringe zeigen 0–100 ohne Prozentzeichen; Antippen öffnet die Detailseite
- Gestrichelter Bogen außen am Belastungsring = heute empfohlener Bereich

## Prinzipien
1. **Glas ist Bedienung.** `glassEffect` nur für System-Tab-Leiste, Toolbar, angehefteten Ring-Streifen, Trainings-Dock, Eingabefeld und Knöpfe im Coach. Inhalte liegen auf `Plate` (4,5 % Weiß, 0,5-pt-Kante).
2. **Eine Hauptsache pro Bildschirm.** Heute: das Ring-Trio, wobei die Erholung größer ist (120 statt 88 pt). Detailseiten: ein Ring mit 196 pt und darunter ein Satz.
3. **Gruppieren statt stapeln.** Abschnitte mit 20-pt-Überschrift, darin Zeilen mit Haarlinien. Keine Karte pro Zahl.
4. **Farbe bedeutet etwas.** Bereichsfarben und Warnung (#FFB547). Auswahl und Erledigt sind neutral (#EEF2F5 auf #0B0F12). Vergangene Balken sind grau mit 3-pt-Farbkappe.
5. **Jede Zahl mit Bezug:** Normalbereich (Mittel ± 1 SD über 30 Tage) als Bereichsbalken, Zielbogen oder Vergleich zum Mittel.
6. **Typografie:** SF Pro, Zahlen immer `monospacedDigit`. Größen: 34 / 28 / 22 / 20 / 17 / 16 / 15 / 13 / 11.
   *Abweichung vom Prototyp (Inter):* Die Systemschrift bringt Dynamic Type, optische Größen und die beste Lesbarkeit auf dem iPhone.
7. **Raster 4 pt, Seitenrand 16, Abschnittsabstand 32.** Zwei linke Kanten: 16 (Seite) und 32 (Inhalt in Flächen).
8. **Radien:** Flächen 20, kleine Felder 12, Dock 30, Bedienelemente kapselförmig.
9. **Daumenzone:** Im Training sitzen Gewicht, Wiederholungen, Reserve und „Satz abschließen“ in einem Glas-Dock unten. Tippflächen sind mindestens 44 pt.
10. **Bewegung erklärt:** Die Ringe animieren vom zuletzt gezeigten Wert, gestaffelt um 80 ms, nur beim Öffnen und bei neuen Daten. Die Pause läuft sichtbar ab, abgeschlossene Sätze geben ein haptisches Signal.

## Bewusste Entscheidungen
- **Tabs:** Heute · Training · Gesundheit · Coach. Journal und Profil erreichst du über die Startseite bzw. den Profil-Knopf.
- **Coach-Vorschläge:** Übernommene Vorschläge gelten nur für das heutige Training, die gespeicherte Routine bleibt unverändert.
- **Fehlender Fitbit-Sync:** Erholung und Schlaf zeigen den Wert von gestern gedimmt, dazu den Hinweis „Warte auf Fitbit“.
- **Beispieldaten:** sind immer mit einem Hinweis gekennzeichnet und führen zu den Datenquellen.
