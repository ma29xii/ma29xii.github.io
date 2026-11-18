# Codex-Review 01 – 18.11.2026

Geprüfter Commit: `473e317014525efa5172242077670f41142193d4`

## Gesamturteil

Die drei Ringe geben „Heute“ eine klare Hierarchie und der Trainings-Dock hält die wichtigste Aktion in Daumenreichweite. Für echte Daten fehlen verlässliche Zustände bei Lücken, ein sauberer Vergleichszeitraum und eine belastbare Kennzeichnung der Schätzungen. Die fünf wichtigsten Punkte für Runde 02:

1. **Körperalter** mit echter Datengrundlage erklären. „27,0 Jahre“ und „Verlässlichkeit Hoch“ gehen weit über die geprüften Studien hinaus.
2. **Fitbit-Migration** vor weiteren Arbeiten an der bisherigen API behandeln. Google nennt für die Abschaltung zuletzt den 2. November 2026. Unten stehen konkrete Abfragen für die Google Health API und die alten Entsprechungen. [Google Health API – Abschaltplan](https://developers.google.com/health/about)
3. **Fehlende, verspätete und Beispielwerte** im Modell unterscheiden. Derzeit kann ein leerer Tag als Erholung 41/100, Schlaf 0/100 und Belastung 0/100 erscheinen.
4. **Training** beim Speichern absichern. Ein Schreibfehler kann wie ein erfolgreich gespeichertes Training aussehen. Im Dock den bearbeiteten Satz mit Übung benennen und Reservewahl sowie VoiceOver verbessern.
5. **Lesbarkeit** zentral überarbeiten. Semantische Schriftgrößen, 44-pt-Ziele, AA-Kontrast und eine feste Tab-Leiste verbessern mehrere Bildschirme gleichzeitig.

### Noten

| Bildschirm | Note | Ausschlaggebender Befund |
|---|---:|---|
| Heute, Einstieg – 01 | 7/10 | Starke Ringhierarchie, aber Demo, Scores und aktive Karten schwer auseinanderzuhalten |
| Heute, gescrollt – 02 | 5/10 | Kompakt-Ringe und reduzierte Tab-Leiste verdecken Kontext |
| Heute, unten – 03 | 5/10 | Einblick und Körperalter versprechen zu viel |
| Heute anpassen – 03b | 6/10 | Verständliche Liste, kleine Ziele und sofortiges Zurücksetzen |
| Erholung, Einstieg – 04 | 6/10 | Status verständlich, Beitragsbalken mit uneinheitlicher Skala |
| Erholung, unten – 05 | 5/10 | Zeitbezug in Mini-Charts fehlt |
| Schlaf, Einstieg – 06 | 7/10 | Guter Nachtverlauf, 93 und 88 % brauchen eigene Bezeichnungen |
| Schlaf, unten – 07 | 5/10 | Fester Beispielwecker und unvollständige Nächte im Mittel |
| Belastung – 08 | 6/10 | Zielbereich klar, Wochenwert und Eingangsgrößen missverständlich |
| Training, Einstieg – 09 | 7/10 | Klare Hauptaktion, falsche Beschriftung der Satzgrenze |
| Training, unten – 09b | 6/10 | Routinen gut auffindbar, freies Training versteckt |
| Live-Training – 10 | 6/10 | Klarer aktiver Satz, unklarer Bezug des Docks |
| Pause – 11 | 7/10 | Gute Daumenzone, unklare nächste Aktion für VoiceOver |
| Nächster Satz – 12 | 6/10 | Reserve klein und ohne ausreichenden Kontext |
| Zusammenfassung – 13 | 6/10 | Schnelle Übersicht, Speichersicherheit und 1RM-Einordnung fehlen |
| Gesundheit, Einstieg – 14 | 5/10 | Modellschätzung dominiert Messwerte |
| Körperalter, Einstieg – 14b | 4/10 | Präzision und Trendbezeichnung sind irreführend |
| Körperalter, Faktoren – 14c | 4/10 | Datenabdeckung wird als Verlässlichkeit verkauft |
| Körperalter, Methode – 14d | 5/10 | Quellen sichtbar, Formel und Vergleichsfenster nur teilweise erläutert |
| Gesundheit, unten – 14e | 6/10 | Wiedererkennbare Karten, unklare Aktualität und Datenabdeckung |
| HRV – 15 | 5/10 | Letztes Datum klemmt, Lücken und Kurvenextreme können täuschen |
| Coach – 16 | 4/10 | Auffälliger Widerspruch zum Zielbereich, Fragen schwer auffindbar |
| Onboarding, Profil, Journal, Coach-Antwort, Routineneditor, Übungsbibliothek, Übungsdetails | — | Code geprüft, Bildmaterial für visuelle Noten fehlt |

**Prüfbasis:** Alle 22 JPGs aus `docs/forma-screens/` und Swift-Code. Der Screenshot-Commit ist `9f3b7b4`, der damit gebaute App-Commit `370cc2d`. Der App-Quellcode ist zwischen `370cc2d` und `473e317` identisch. CI-Lauf 8 meldet Erfolg für `ipa` und `screens`, Artifact `Forma-IPA`. Die JPGs wurden auf Höhe 1.000 px skaliert. Größen in pt sind Schätzungen anhand der 16-pt-Seitenränder oder direkt aus Swift. VoiceOver, Bedienung, Synchronisierung und Sideloadly sind hier anhand von Code bzw. Standbildern beurteilt. Sie brauchen noch einen Lauf auf dem iPhone. [CI-Lauf 8](https://github.com/ma29xii/ma29xii.github.io/actions/runs/44318294699)

## Befunde

### R-01-01 · P0 · Körperalter · 14b-Körperalter.jpg, 14c-Körperalter-Faktoren.jpg
**Beobachtung:** Die 64-pt-Zahl „27,0“, die grüne Abweichung „3,0 Jahre jünger als du bist“ und „Verlässlichkeit Hoch“ wirken wie ein persönlicher Messbefund. `BodyAge.evaluate` prüft für „Hoch“ nur mindestens 90 Tage mit irgendeinem der drei Basissignale, mindestens vier Faktoren und das Vorhandensein von VO₂max. Ein einzelner VO₂max-Wert genügt. Ein 30-jähriges Beispiel kann den gleichen Status erhalten wie eine Person mit lückenlosen Messreihen. Die Zahl ergibt sich aus Studien-Koeffizienten, eigener Interpolation, 70-%-Dämpfung und Begrenzung auf ±15 Jahre.

**Warum falsch:** Die Studien beschreiben Zusammenhänge in Gruppen. Die Addition verschieden adjustierter HR/RR setzt eine gemeinsame Referenz, eine einheitliche Bedeutung der Risikomaße und ein kombiniertes Modell voraus. Der feste Faktor 0,7, die acht Jahre und die Begrenzungen kalibrieren das Ergebnis für einzelne Personen nicht. Innerhalb des angenommenen Gompertz-Modells ist die algebraische Umrechnung `ln(HR) × 8 / ln(2)` richtig. Ihre Anwendung auf diese Summe ist eine Produktannahme.

**Lösung:** In `BodyAgeSummaryCard` und `BodyAgeDetailView` Werte in Jahren für echte Nutzerdaten bis zur Validierung ausblenden oder den Abschnitt als „Gesundheitsfaktoren“ mit den fünf Originalwerten und den jeweiligen Quellen darstellen. Falls Jahre in einer Demo sichtbar bleiben, „Beispielrechnung“ direkt über Zahl und Abweichung, ganzjährig gerundet. `Confidence` als „Datenabdeckung“ pro Faktor mit Zahl, Zeitraum und Datum der letzten Messung ausgeben. Für einen späteren Alterswert Kalibrierung und Validierung am vorgesehenen Einsatzbereich nachweisen. [Edwards, Gompertz-Modell](https://pmc.ncbi.nlm.nih.gov/articles/PMC4197997/) · [Gurven et al., Variation der Verdopplungszeiten](https://pmc.ncbi.nlm.nih.gov/articles/PMC6121812/)

### R-01-02 · P0 · Fitbit und Profil · 14-Gesundheit.jpg (Datenansicht), Profil ohne Screenshot
**Beobachtung:** `FitbitService.swift` verwendet weiterhin `www.fitbit.com/oauth2/authorize` und `api.fitbit.com`. Googles aktuelle Übersichtsseite nennt den **02.11.2026** und HTTP 410 für abgeschaltete API- und OAuth-Endpunkte. Ältere Banner nennen 30.10. Beide Termine liegen vor dem Review. `DataHub.refresh` verschluckt API-Fehler über `loadDay`, kann 84 Einzelabfragen pro Kaltstart versuchen und schaltet auf Demo um. 14 geladene Tage erreichen selbst bei vollständigen Messwerten die Körperalter-Schwelle von 21 Tagen nie.

**Warum falsch:** Die Verbindung wird im Profil als normale Option angeboten. Ein verbundener Altzugang oder Beispielwerte können einen funktionierenden Sync suggerieren. Ein öffentlicher Probeaufruf des alten Ruhepuls-Endpunkts ohne Anmeldung lieferte 401 und erlaubt keine Aussage zum Sync eines echten Kontos. Google-Projektzugang und Verbindung mit einem echten Fitbit-Konto wurden für Forma nicht verifiziert.

**Lösung:** In `ProfileView` und `OnboardingView` die alte Verbindung deaktivieren und „Fitbit-Synchronisierung wird umgestellt“ anzeigen. HTTP 410 in `FitbitService.get` und beim Login/Refresh als dauerhaften Verbindungsfehler behandeln. Google-Health-Projektzugang vor der Implementierung prüfen, dann Google OAuth mit neuer Zustimmung und die Zeitraumabfragen unten einsetzen. Alte Fitbit-Autorisierung bleibt laut Google inkompatibel. [Google – Abschaltplan](https://developers.google.com/health/about) · [Google – Autorisierung](https://developers.google.com/health/migration/data-access) · [Älterer Fitbit-Hinweis](https://dev.fitbit.com/build/reference/web-api/sleep/get-sleep-log-by-date-range/)

### R-01-03 · P0 · Datenzustände · 01-Heute.jpg, 04-Erholung.jpg, 06-Schlaf.jpg, 14-Gesundheit.jpg
**Beobachtung:** `ScoreEngine.scores` verarbeitet einen vollständig leeren Tag zu Erholung 41, Schlaf 0 und Belastung 0. `DataHub` akzeptiert Apple Health schon wegen Schritten an irgendeinem Tag in 30 Tagen, prüft bei Fitbit aber nur Schlaf oder HRV. Beim Start liegen bereits Beispieldaten vor. `lastUpdate` springt auch bei Fehlern auf „jetzt“, `lastError` bleibt über erfolgreiche Ladevorgänge hinweg stehen. Die im Code gespeicherte Health-Einwilligung folgt dem erfolgreichen Request-Aufruf.

**Warum falsch:** Null kann ein echter Messwert sein. Die abgeleitete 41 wirkt wie eine Auswertung. Das System teilt einer App die Ablehnung von HealthKit-Lesezugriff nicht zuverlässig mit.

**Lösung:** `DayScores` mit optionalen Werten und `DataHub` mit den Zuständen „Lädt“, „Echte Daten“, „Teilweise/letzter Stand“, „Keine Daten“, „Verbindung fehlgeschlagen“ und explizit gewählter „Demo“ abbilden. Pro Messreihe Mindestgrundlage prüfen. Ersatzansicht „Noch keine Schlafdaten“ mit neu laden und Quellenhinweis. `lastUpdate` als letzter erfolgreicher Import, Warnung bei Erfolg zurücksetzen. UI-Fälle für leere Tage, Schritt-only, verweigerten/teilweisen Zugriff und Fehler nach erfolgreichem Laden prüfen. [Apple – HealthKit-Lesezugriff](https://developer.apple.com/documentation/HealthKit/authorizing-access-to-health-data)

### R-01-04 · P0 · Training speichern · 13-Zusammenfassung.jpg
**Beobachtung:** `AppState.swift`, `LiveWorkout.save(into:)` ignoriert `context.save()`-Fehler und gibt das Session-Objekt zurück. `LiveWorkoutView.finish` entfernt das laufende Training und kann die Zusammenfassung zeigen. Auch andere SwiftData-Wege schlucken Fehler, unter anderem im Journal.

**Warum falsch:** Der Bildschirm signalisiert dauerhaftes Speichern, obwohl die Persistierung gescheitert sein kann. Der laufende Zustand bleibt nur im Speicher.

**Lösung:** `save` als fehlerwerfenden Vorgang führen. Erst nach Erfolg den Dock schließen und Zusammenfassung öffnen. Teilweise eingefügte Objekte im Fehlerfall gezielt zurücknehmen, Wiederholen ohne Duplikate. „Training konnte nicht gespeichert werden. Erneut versuchen“ im Dock. Prüffall mit erzwungenem Schreibfehler sowie App-Neustart nach bestätigtem Speichern.

### R-01-05 · P0 · Coach-Empfehlungen · 01-Heute.jpg, 16-Coach.jpg
**Beobachtung:** Auf „Heute“ sind 39 Punkte im Ziel 35–55. Der Coach sagt nach der Beispiel-Session mit denselben Werten „Bis zum Zielbereich fehlen noch 16 Punkte“ und verspricht, ein Spaziergang reiche. `dailyLine` zieht vom oberen Rand ab. Wenn `hrvDelta` fehlt, behauptet die andere Verzweigung „Deine HRV liegt im Normalbereich“. `suggestion` kann bei fehlenden Teildaten einseitig Sätze streichen oder bei hoher Erholung das Gewicht unabhängig vom letzten Satz anheben.

**Warum falsch:** Die Aussagen widersprechen der Ringansicht bzw. stammen aus fehlenden Daten. Als Handlungsanweisung können sie unnötige Belastung erzeugen.

**Lösung:** `CoachEngine` für Zielphase und Datenqualität an dasselbe Modell wie `StrainDetail` anbinden. Bei 39 im Bereich „Du bist in deinem geschätzten Zielbereich“, bei unter 35 Abstand zur Untergrenze. „Heute fehlt ein HRV-Wert“ bei `nil`. Vorschläge pausieren bei Demo, veralteten oder unvollständigen Werten und keine Mindestdauer/Wirksamkeit zusichern. Fälle 34/35/39/55/56 sowie ohne HRV prüfen.

### R-01-06 · P0 · Schlafdaten · 06-Schlaf.jpg, 07-Schlaf-unten.jpg
**Beobachtung:** `HealthService.sleepNights` gruppiert jedes Segment nach Endzeit plus sechs Stunden und fügt Segmente mehrerer Quellen zusammen. `SleepNight.asleep` summiert Segmente. Fitbit ignoriert `levels.shortData`, etikettiert `restless` als wach und `asleep` als Kernschlaf. `ScoreEngine.sleepScore` setzt auch bei einer Nacht ohne Tief-/REM-Daten ein Gewicht von 20 % für diese Phasen voraus.

**Warum falsch:** Eine Schlafperiode über die feste Grenze um 18 Uhr kann in zwei Datenpunkte aufgeteilt werden. Ein Nickerchen im selben Fenster kann die berechnete Bettzeit um Stunden verlängern. Überlappende Tracker-Einträge können Dauer, Effizienz und Schlafscore verfälschen. Klassische Schlaflogs liefern andere Kategorien als Phasenmessungen.

**Lösung:** In beiden Importern erst eine Hauptnacht als Zeitintervall bestimmen und dem Aufwachdatum zuordnen. Überlappungen und Quellenvorrang als Intervalloperation behandeln. Schlaf ohne Phasen als „Schlaf (Phase unbekannt)“ führen, fehlende Phasengrundlage im Score sichtbar machen oder den Score ausblenden. Prüfen mit 23:00–07:00, Nickerchen, doppeltem Tracker, fehlenden Phasen und Zeitumstellung. [Fitbit – Schlaflog-Format](https://dev.fitbit.com/build/reference/web-api/sleep/get-sleep-log-by-date-range/)

### R-01-07 · P1 · Coach und Datenschutz · 16-Coach.jpg, Profil ohne Screenshot
**Beobachtung:** `CoachView.send` nutzt bei hinterlegtem Schlüssel den externen Client. Er sendet den Chatverlauf und aus `contextSummary` Werte zu Schlaf, Erholung, HRV und Puls sowie ggf. den Namen der geplanten Routine. Der Profiltext erwähnt den Transfer, im Chat selbst ist der Modus nicht sichtbar. „Deine Gesundheitsdaten bleiben auf dem iPhone“ steht im Onboarding ohne Einschränkung. Der Lauf 8 hat nur den Coach-Einstieg fotografiert.

**Warum falsch:** Ob beim Tippen Gesundheitsdaten geteilt werden, muss an der Entscheidung klar sein. Apples App-Review-Regel 5.1.2(i) verlangt bei Weitergabe an Dritte einschließlich KI klare Information und ausdrückliche Zustimmung.

**Lösung:** Lokalen Coach im Chat als Standard zeigen. Für den externen Modus vor dem Senden Anbieter und konkrete Datenarten anzeigen, ausdrückliche Zustimmung und späteren Widerruf anbieten. Datenmenge und Verlauf minimieren. `CoachView` bei Fehler „Externer Coach gerade nicht erreichbar“ plus lokalen Ausweg. Den Onboarding-Satz auf die lokale Standardnutzung beziehen. [Apple – App Review Guidelines, Datenschutz](https://developer.apple.com/app-store/review/guidelines/#privacy)

### R-01-08 · P1 · Körperalter, Quellen und Faktoren · 14c-Körperalter-Faktoren.jpg, 14d-Körperalter-Methode.jpg
**Beobachtung:** Die Faktoren werden als direkte Jahresbeiträge gezeigt. Die 0,7-Dämpfung erfolgt im Modell auf die Summe, in der UI zusätzlich auf jede angezeigte Zeile. Ein Kraftwert oberhalb von 30 min/Woche ergibt rechnerisch −1,2185 Jahre in der UI. Ein MET über Referenz ergibt vor Kappung −1,1251 angezeigte Jahre. Bei Behandlung von Grenzwerten und Rundung kann die sichtbare Summe abweichen.

**Warum falsch:** Die Quellen stützen ausgewählte Gruppenvergleiche. Der Studienbefund und die daraus abgeleitete Formas-Formel brauchen jeweils ihren eigenen verständlichen Satz.

**Lösung:** `BodyAge.swift` und `BodyAgeView.swift` je Faktor mit Einheit, Quelle, Vergleichsgruppe, Mindestdaten und Produktannahme beschriften. Wenn eine Beispielrechnung sichtbar bleibt, Ausgangswert, ungerundete Summe, 70 %, Deckel und Rundung in der Methode zeigen.

| Faktor | Quellenprüfung | Korrektur |
|---|---|---|
| VO₂max | Kodama berichtet RR 0,87 je +1 MET für Gesamtmortalität. Alle 12 Code-Mediane stimmen mit FRIEND 2015, Tabelle 2, überein. FRIEND 2021 berichtet niedrigere Laufband-Normen. [Kodama](https://pubmed.ncbi.nlm.nih.gov/19454641/) · [FRIEND 2015, Tabelle 2](https://www.mayoclinicproceedings.org/article/S0025619615006424/pdf) · [FRIEND 2021](https://pubmed.ncbi.nlm.nih.gov/34809986/) | „Median“ statt „Mittel“, US-Laufband-Referenz nennen und direkt verlinken. Jüngere und ältere Personen außerhalb 20–79 aus dieser Referenzprüfung herausnehmen. Lineare Interpolation zwischen Dezadenmitten, die Kappung und Vergleich mit Wearable-Schätzungen als Annahmen. |
| Ruhepuls | Zhang bestätigt RR 1,09 je +10 Schläge/min für Gesamtmortalität. [Zhang](https://pmc.ncbi.nlm.nih.gov/articles/PMC4754196/) | 65 Schläge/min und die lineare Extrapolation als Annahmen ausweisen. Allgemeine Aussage „niedrig = gut trainiert“ durch beobachteten Zusammenhang ersetzen. |
| Schritte | Paluch bestätigt 3.553/5.801/7.842/10.901 als Quartilmediane und HRs 1/0,60/0,55/0,47. Die altersgetrennten Kurven zeigen abflachende Zusammenhänge bei rund 6.000–8.000 ab 60, 8.000–10.000 unter 60. [Paluch](https://doi.org/10.1016/S2468-2667(21)00302-9) | Die gepoolte Kurve im Code entspricht keinem der altersgetrennten Modelle. „In Studien ging mehr Gehen mit geringerem Risiko einher“ plus Formas 7.000er-Referenz als Annahme. Tage mit ≤500 Schritten nur bei belegter Nichttragezeit aussortieren, sonst Verzerrung nach oben. |
| Schlafdauer | Cappuccio bestätigt gepoolte RR 1,12 bzw. 1,30 bei kurzen bzw. langen Nächten mit unterschiedlichen Schwellen in den eingeschlossenen Studien. [Cappuccio](https://pmc.ncbi.nlm.nih.gov/articles/PMC2864873/) | 7–8 h als Formas Modellreferenz erklären. Die Rampen zu ≤6 h bzw. ≥9 h und die Sättigung kommen aus dem Code. Mögliche Krankheit als Erklärung für beobachtete Zusammenhänge formulieren. Gut gemessene kurze Nächte abbilden. |
| Krafttraining | Momma berichtet RR 0,85 für Gesamtmortalität im Gruppenvergleich, 10–17 % über verschiedene Endpunkte und ein Maximum der beobachteten Assoziation grob bei 30–60 min/Woche. [Momma](https://pmc.ncbi.nlm.nih.gov/articles/PMC9209691/) | 0,86 und Abflachung ab 30 min als Modellannahmen kennzeichnen. Fehlende Aufzeichnungen als „Keine Daten“. Apple-Health- und Forma-Sessions anhand IDs/Zeitintervall deduplizieren. Tagesmaximum unterschlägt separate Einheiten am gleichen Tag. |
| Gompertz und HRV | Etwa acht Jahre sind eine populationsabhängige Faustregel. Apple-SDNN und Fitbit-RMSSD sind unterschiedliche Kennwerte. [Edwards](https://pmc.ncbi.nlm.nih.gov/articles/PMC4197997/) · [Apple – SDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn) · [Fitbit – RMSSD](https://dev.fitbit.com/build/reference/web-api/heart-rate-variability/get-hrv-summary-by-interval/) | Wikipedia durch populationsbezogene Quelle ersetzen. „Wir rechnen HRV wegen unterschiedlicher Messmethoden und fehlender Validierung für dieses Modell nicht ein.“ |

### R-01-09 · P1 · Körperalter, Richtung und Profil · 03-Heute-unten.jpg, 14b-Körperalter.jpg
**Beobachtung:** „Nur die letzten 30 Tage“, „Du hältst dein Niveau“ vergleicht überlappende Fenster und potenziell andere Faktoren. VO₂max zieht für „180 Tage“ bis zu 30 vorhandene Messwerte, auch wenn sie alt sind. Der Altersvergleich kann sich bei geändertem Profil neu berechnen. Manuelles Geburtsjahr wird als 1. Juli in ein Dezimalalter übersetzt. Profil erlaubt bis etwa 14 Jahre, die Referenztabelle umfasst 20–79. „Geburtsjahr und Geschlecht“ im Leerzustand widerspricht `evaluate`, wo unbekanntes Geschlecht nur VO₂max blockiert.

**Warum falsch:** Unterschiede können aus Abdeckung oder Profilannahmen stammen. Ein vergleichbarer zeitlicher Verlauf braucht dieselben Faktoren und transparent datierte Fenster.

**Lösung:** `BodyAge.evaluate` auf je Faktor gleiche, ausdrücklich datierte Abdeckung umstellen. Ohne zwei vergleichbare Fenster „Noch kein Vergleich“. Für kurze Referenz das vorherige vollständige Fenster gleicher Länge verwenden oder „Letzte 30 Tage verglichen mit Gesamtzeitraum“ ohne Richtungsbehauptung benennen. Bei Jahr-only in der UI „Alter ungefähr …“ und bei Demo einen festen Demo-Datensatz samt Demo-Profil verwenden. Profil-CTA nur für tatsächlich benötigte Angaben zeigen.

### R-01-10 · P1 · Typografie und Dynamic Type · 01-Heute.jpg, 03b-Heute-anpassen.jpg, 12-Nächster-Satz.jpg, 14c-Körperalter-Faktoren.jpg
**Beobachtung:** `Theme.swift` nutzt feste Größen von 11 bis 64 pt. `InfoChip` ist 30 pt hoch, der primäre Button hat eine feste Höhe, `MetricRow` stellt Titel, Wert und optionalen Balken nebeneinander. In der Standardgröße drängen bereits die Profilelemente und Beschriftungen im Editor sowie die Einheiten bei „Atemfrequenz“ an ihre Grenzen.

**Warum falsch:** Feste Typografie verhindert die systemweite Textvergrößerung. Größerer Text allein hilft bei festen Höhen und Spalten wenig.

**Lösung:** `formaBody`, `formaCaption`, Titel und Zeilen auf semantische SF-Stile umstellen. Für große Ringziffern skalierte Maße mit `@ScaledMetric` verwenden. `MetricRow` und `RingTrio` bei Accessibility-Größen stapeln. Buttons mit Mindesthöhe und vertikaler Polsterung bauen. Drei Ringe oben als erste Inhaltsgruppe halten. Abnahme mit Standard, XXXL und AX5, langen deutschen Begriffen und VoiceOver. [Apple – Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

### R-01-11 · P1 · Kontrast und Farbsemantik · 02-Heute-gescrollt.jpg, 05-Erholung-unten.jpg, 09-Training.jpg, 15-HRV.jpg
**Beobachtung:** „geschätzt“, „ab RIR 3“, Datumsachsen und Karten-Zusätze verwenden meist `textTertiary` bei 40 % Weiß. In einem sRGB-Modell ergibt das über `#030303` ca. 3,70:1 und über `#202020` ca. 3,74:1. 22 % Weiß als Funktionskontur erreicht ca. 1,81:1 bzw. 2,05:1. Erholungsrot `#FF0026` erreicht über `#202020` ca. 4,10:1. Das sind Token-Rechnungen. Der dynamische Glas-Kontrast wurde im Standbild visuell beurteilt.

**Warum falsch:** Für kleine Schrift gelten 4,5:1 als AA-Benchmark. Für informative Bedienelemente und Grafikmarken gelten 3:1. Sehr dünne, halbtransparente Achsen und Konturen sind bei indirektem Tageslicht schwer zu lesen. Rot, Grün und Gelb tragen je nach Karte unterschiedliche Bedeutungen.

**Lösung:** `Theme.textSecondary` für relevante Zusatztexte und Achsen. Tertiär für Dekoration, funktionsrelevante Konturen mit ≥3:1. Status zu jedem erholungsbezogenen Farbwert als Wort bzw. in der Balkenauswahl als Textwert anbieten. Akzentfarben auf den dunkelsten und hellsten vorgesehenen Hintergründen einschließlich Glas prüfen. [WCAG 2.2 – 1.4.3 und 1.4.11](https://www.w3.org/TR/WCAG22/#contrast-minimum)

### R-01-12 · P1 · Liquid Glass und Tabs · 02-Heute-gescrollt.jpg, 04-Erholung.jpg, 08-Belastung.jpg, 09b-Training-unten.jpg, 14e-Gesundheit-unten.jpg
**Beobachtung:** Beim Scrollen schrumpfen vier Tab-Ziele auf einen Kreis. In 04 leuchtet ein grüner Wochenbalken durch den Coach-Tab, in 08 gerät das Wochenfazit unter das Tab-Ende. In 02 liegen Kompakt-Ringe im Glas vor dem nächsten Datenblock. Der grüne Schein färbt noch die Mitte des Bildschirms. Passiven Chips und Navigationssteuerung gibt `glassEffect` fast denselben Charakter.

**Warum falsch:** Tab-Wechsel brauchen am Ende einer langen Seite einen zusätzlichen Schritt. Interaktive und passive Elemente sind visuell schwer auseinanderzuhalten. Glas kann hier Farben über die falsche Hierarchie transportieren.

**Lösung:** In `RootView` `.tabBarMinimizeBehavior(.never)` für die vier gleichrangigen Tabs ausprobieren und Scroll-Inset bei System-Tab-Leiste messen. `ScreenBackground`: mit Radius 260–300 pt und Grün-Opacity 0,12 starten, Peak im Kopf halten. `InfoChip` für „Ziel“ und „Schlafschuld“ matte Fläche geben. Native Navigation in Glas belassen und in `TodayView` eine kleinere, besser kontrastierte kompakte Ringzeile testen. Reduzierte Transparenz und erhöhten Kontrast mit abnehmen. [Apple – Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

### R-01-13 · P1 · Kacheln bedienen · 03b-Heute-anpassen.jpg, 09b-Training-unten.jpg, 14e-Gesundheit-unten.jpg
**Beobachtung:** Der explizite Einstieg liegt jeweils unten, unter bis zu acht Kacheln. Die Minus-Schaltfläche ist im Code ein 22-pt-Symbol ohne 44-pt-Rahmen. „Standard“ überschreibt sofort. Ziehen legt eine Kachel grundsätzlich vor dem Ziel ab. Einen Zielbereich hinter der letzten Kachel bietet der Stapel nicht. Dieselbe Kartenfläche kann antippen, halten, ziehen und Kontextbefehle auslösen.

**Warum falsch:** Die Anpassung ist schwer auffindbar. Ein Reset lässt sich leicht auslösen. Drag-and-drop und Kontextmenü auf derselben interaktiven Fläche erhöhen die Bedienlast, insbesondere mit VoiceOver.

**Lösung:** In `TileStack` einen einmal sichtbaren Einstieg „Kacheln anpassen“ oben in der Inhaltsgruppe und eindeutige Griffe im Editor testen. Beim Bearbeiten 44×44 pt für Ein-/Ausblenden, explizite „Nach oben“/„Nach unten“-Accessibility-Aktionen, Zeilenposition ansagen und an Abschnittsenden Drop-Ziele anbieten. In `TileEditor` Reset „Standard wiederherstellen“ mit Rückgängig oder Bestätigung. Bei komplett leerem Stapel einen Satz und direkten Wiederherstellungs-Link zeigen. [Apple – Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

### R-01-14 · P2 · Bewegungsreduktion und Feedback · 01-Heute.jpg, 03b-Heute-anpassen.jpg, 04-Erholung.jpg, 11-Pause.jpg
**Beobachtung:** Ringaufbau, Wechsel zum Mini-Ring, Umordnen per `.scale`, Hintergrund-Farbwechsel (0,8 s), Dock-Timer und Scrollsprünge nutzen eigene Animationen. Diese Stellen lesen `accessibilityReduceMotion` im geprüften Code nicht aus. Jede Änderung des gespeicherten Kachelstrings triggert Auswahl-Haptik.

**Warum falsch:** Ein Standbild beweist keine Bewegungsqualität. Aus dem Code folgen unbedingte benutzerdefinierte Animationen an mehreren Stellen, auch bei reduziertem Bewegungsempfinden.

**Lösung:** `accessibilityReduceMotion` in `TodayView`, `ScreenBackground`, `TileStack`, `RingDetailView.DetailHero` und `LiveWorkoutView` berücksichtigen. Ringe direkt im Zielzustand, Kacheln über Überblendung, Timer statisch lesbar. Haptik an die abgeschlossene Nutzeraktion koppeln und Datenupdates ohne Haptik durchlaufen lassen. [Apple – Motion](https://developer.apple.com/design/human-interface-guidelines/motion)

### R-01-15 · P1 · Heute, Start und kompakte Ringe · 01-Heute.jpg, 02-Heute-gescrollt.jpg
**Beobachtung:** Die Ringlegenden stehen eng unter Bögen, in der schmalen Leiste bleiben nur Farbe und etwa 13-pt-Zahlen. Der erste Screen zeigt keinen „von 100“-Kontext und braucht zwei eigenständige Chip-Farben plus grünen Schein. Die erste primäre Trainingsaktion „Start“ ist ungefähr 64×33 pt sichtbar. „Antippen zum Fragen“ ist klein und blass in einer Karte mit eigener langer Geste.

**Warum falsch:** Drei gleich formatierte Zahlen brauchen Benennung und Zeitscope. Der Ringwechsel kann aktuell die Titelposition überblenden, ohne metrischen Kontext sichtbar zu halten. „Start“ ohne Objekt trägt wenig Kontext.

**Lösung:** `RingTrio` mit sichtbarem Score-Label oder einer einmaligen kurzen Einführung „Werte von 0 bis 100“. Kompaktzeile mit zugänglichem Gruppentitel und vollem 44-pt-Hit-Frame je Detailziel prüfen. Abstände im Ringbereich auf 8 pt zwischen Bogen und Legende und 12 pt zu Statuschips vereinheitlichen. `TodayView`: „Training starten“ mit 44 pt Trefferhöhe, Coach-Karte auf Überschrift und klare Aktion „Coach fragen“ reduzieren.

### R-01-16 · P1 · Heute, Einblick · 03-Heute-unten.jpg
**Beobachtung:** „Nach aktiven Tagen schläfst du 20 min länger“ beruht auf einem rohen Mittelwertvergleich. `Insights.split` verlangt je drei Nächte, nutzt 8.000 Schritte als eigene Schwelle und meldet nur das Gesamtn. Im anderen Fall verspricht die Kachel Ergebnisse „nach etwa zwei Wochen“. Antippen schickt den Erklärungstext als Coach-Eingabe.

**Warum falsch:** Kleine Gruppen, Wochentage und fehlende Nächte können die Differenz verschieben. Die Formulierung klingt nach persönlicher Regel. Das Zeitversprechen folgt aus keiner Bedingung.

**Lösung:** „In deinen erfassten Nächten: 20 min Unterschied“ mit Zeitraum und Stichproben je Gruppe. Ein 0-Minuten-Ergebnis als „Kein erkennbarer Unterschied“ formulieren. Bei zu wenig Daten „Es fehlen noch Nächte in mindestens einer Gruppe“. Eine Detailansicht mit beiden Mittelwerten und „Coach dazu fragen“ als separater Aktion anbieten.

### R-01-17 · P2 · Heute, Tag und Woche · 02-Heute-gescrollt.jpg, 03-Heute-unten.jpg
**Beobachtung:** „Schritte“ und „Aktive Energie“ haben Fortschrittslinien ohne beschrifteten Zielwert. „Diese Woche“ bündelt Trainings seit Wochenanfang mit Erholung der letzten sieben Tage. „Volumen 0 kg“ bleibt bei eingestellten Pfund in kg und entsteht, bevor ein erstes Training gespeichert wurde. „Energie 65“ und „Aktive Energie 410 kcal“ sind verschiedene Konzepte. Das zehnteilige Segmentband füllt nur ganze Zehner. Stress steht mit genauer Dezimalstelle neben einem kleinen „geschätzt“.

**Warum falsch:** Zeitraum und Bezug werden beim Überfliegen gleichgesetzt. Zahl und Balken kommunizieren unterschiedliche Präzision.

**Lösung:** In `TodayView` kalendarische Woche und rollende Erholung separat datieren oder beide an dieselbe Auswahl binden. Fortschrittslinien erst bei sichtbarem Ziel zeigen. „Energie (Schätzung)“ und „Aktive Kalorien“ unterscheiden. Wochenvolumen einheitlich über `app.weightUnit` formatieren. Für 65 anteiligen letzten Strich füllen oder Balken weglassen. `kcal`, `ms`, `kg`, `%` mit geschütztem Abstand anzeigen.

### R-01-18 · P1 · Erholung und verspätete Fitbit-Daten · 02-Heute-gescrollt.jpg, 04-Erholung.jpg, 05-Erholung-unten.jpg, 06-Schlaf.jpg
**Beobachtung:** Der Hero verwendet `ringScores`. Bei fehlendem Fitbit-Schlaf kommen Erholung, Schlaf und Ziel von gestern. Beitragszeilen nutzen heute, Vergleiche und Belastungsdetail greifen teils auf `scores` zurück. `TrendRow` verwendet den letzten vorhandenen Wert ohne Datum. Die ca. 120-pt-Beitragsbalken verwenden z-Abweichungen bzw. Schlafpunkte und entsprechen den tatsächlichen Score-Gewichten nicht. Atemfrequenz „0,3“ hat weder Vorzeichen noch Einheit.

**Warum falsch:** Ein alter Score kann mit neuen Beiträgen begründet werden. Die Länge wirkt vergleichbar, obwohl Eingangsgrößen und Gewichtung wechseln.

**Lösung:** `DataHub` soll einen datierten Erholungs-Snapshot samt Herkunft und Beiträgen liefern. Dieselbe Auswahl in Ringen, Wochenmittel und Coach verwenden oder Werte explizit pro Tag trennen. In `ScoreEngine` gewichtete Beitragspunkte zurückgeben, in `ContributionRow` gemeinsame ±Punkte-Skala plus Ausgangswert und `/min`. Gestern auf allen betroffenen Ansichten sichtbar benennen. `TrendRow` bei einem älteren Wert „zuletzt am …“ anzeigen.

### R-01-19 · P2 · Erholung, Wochenverlauf · 04-Erholung.jpg, 05-Erholung-unten.jpg
**Beobachtung:** Oben stehen 78 gegenüber dem Vergleich 58, darunter „Mittel 54“. Die Fenster stehen weit auseinander. Wochentage sind klein, Balkenoberkanten tragen die Statusfarben. Drei glatte Mini-Linien haben weder Datumsachse noch Markierungen. `DayBars` und `Sparkline` sind im Code für VoiceOver ausgeblendet.

**Warum falsch:** Der Nutzer muss den Unterschied zwischen 7 und 30 Tagen selbst ermitteln. Für VoiceOver geht der Verlauf ohne gleichwertigen Text verloren.

**Lösung:** „Heute 78/100“, „Ø der früheren Messungen bis … 58“ und „7 Tage · Ø 54“ an die jeweilige Darstellung. `DayBars` als zugängliche Liste mit Datum, Score und Beschriftung oder per Accessibility Chart Descriptor. `TrendRow` für Messungen und Lücken auf datierte Punkte umstellen und Detailansicht erreichbar machen.

### R-01-20 · P1 · Schlafscore, Bedarf und Bettzeit · 01-Heute.jpg, 06-Schlaf.jpg, 07-Schlaf-unten.jpg
**Beobachtung:** 93 im Ring und 88 % Bedarfsdeckung erscheinen ohne klare Bezeichnung. `ScoreEngine` bewertet die vergangene Nacht mit dem Bedarf aus heutiger Belastung und der bisher vorliegenden Schlafhistorie. `SleepDetail` zeigt 6:55 als Wecker, `CoachEngine.bedtime` berechnet ihn fest. „Schlafschuld“ ist eine gedämpfte Summe aus bis zu sieben Nächten. In der Grafik werden fehlende Nächte als 0 h gemittelt.

**Warum falsch:** Die Bewertung derselben Nacht kann sich nach Bewegung ändern. Ein fest eingestellter Beispielwecker wirkt persönlich. Fehlende Nächte drücken den Mittelwert.

**Lösung:** `ScoreEngine`: Nachtbewertung auf gestern festgelegten Bedarf beziehen. „Schlafscore 93/100“ und „88 % des geschätzten Bedarfs“ direkt benennen. Weckzeit im Profil anbieten und im ungesteuerten Fall „Beispiel: Wecker 6:55 Uhr“ zeigen. 7-Nächte-Mittel aus vorhandenen Nächten mit „5 von 7 Nächten“. Fehlstellen leer, 0 nur bei belegter Messung. Bettzeitberechnung mit derselben gerundeten Anzeige und korrekter Tagesgrenze prüfen.

### R-01-21 · P2 · Schlafphasen · 06-Schlaf.jpg, 07-Schlaf-unten.jpg
**Beobachtung:** „Wach/REM/Kern/Tief“ sinngemäß links, Balkenstreifen und Legende doppeln die Phasen. Labels sind etwa 11 pt und kontrastarm. `Hypnogram` zeichnet auf Canvas. Links und rechts sind nur zwei Uhrzeiten sichtbar. „Effizienz 96 %“ wird nicht am Wert erklärt.

**Warum falsch:** Ähnliche Blautöne, schwaches Label und fehlender zeitlicher Fokus erschweren den Vergleich. Canvas-Inhalte brauchen eine lesbare Entsprechung.

**Lösung:** Eine zugängliche Kurzfassung mit Zeitraum und Phasendauern, jede Phase mit deutschem Namen. Mehrere dezente Zeithilfen im Chart, zugleich Balkenstreifen nur bei zusätzlichem Erkenntniswert beibehalten. „Schlafeffizienz“ als „Anteil der Zeit im Bett, den du geschlafen hast“ erklären. Unbekannte Phasen als solche kennzeichnen.

### R-01-22 · P1 · Belastung · 08-Belastung.jpg
**Beobachtung:** Die Position 39 im gestrichelten Bereich ist lesbar, die Skala fehlt. „Summe 270“ addiert sieben Tageswerte einer sättigenden Kurve. `ScoreEngine.strain` verrechnet aktive Kalorien plus pauschal vier Einheiten pro Trainingsminute. Forma-Training aus SwiftData kommt dort nicht direkt an. Für Fitbit verwendet die bisherige Abfrage `activityCalories`, bei Apple aktive Energie.

**Warum falsch:** Der Tagesindex und seine Summe wirken wie vergleichbare physiologische Belastung. Je nach Quelle kann dieselbe Aktivität unterschiedlich oder über zwei Eingangsgrößen in die Basis einfließen. Die Herleitung der Zielgrenzen 35–55 steht am Ring nicht.

**Lösung:** In `StrainDetail` „Geschätzte Belastung · 39/100“ und „Geschätztes Tagesziel 35–55“ nennen. „7 Tage · Ø …“ plus Anzahl beobachteter Tage anstelle der Summe. Für jede Quelle klar angeben, welche Daten in den Index fließen. `ScoreEngine` mit und ohne Trainingsaufzeichnung bei gleicher aktiver Energie und ohne Kalorienwert prüfen.

### R-01-23 · P1 · Training, harte Sätze · 09-Training.jpg, 09b-Training-unten.jpg
**Beobachtung:** „ab RIR 3“ signalisiert ≥3 verbleibende Wiederholungen. Im Code gilt ≤3 oder `rir < 0` für unbekannt. Fünf leere 0-Balken nehmen knapp 280 pt ein, der graue Strich für zehn Sätze steht ohne Zahlenbezug rechts an den Zeilen.

**Warum falsch:** Unbekannte Anstrengung wird als hart gezählt. Die Orientierung von 10 Sätzen wirkt für jede Muskelgruppe wie ein persönliches Ziel. RIR ist im Einstieg unerklärt.

**Lösung:** In `TrainingView.weeklySets` unbekannte Reserve separat ausweisen. „Harte Sätze · höchstens 3 Wiederholungen übrig“ ausgeschrieben und „Orientierungswert: 10 Sätze pro Woche“ nachrangig. Vor dem ersten Training eine kompakte Erklärung anstelle von fünf 0-Balken. Mit VoiceOver Muskelgruppe, gezählte Sätze und optionale Orientierung vorlesen.

### R-01-24 · P2 · Training, Einstieg und Bibliothek · 09-Training.jpg, 09b-Training-unten.jpg
**Beobachtung:** Die primäre Aktion ist eindeutig, „Freies Training“ liegt jedoch nach Routinen, Verlauf und Übungen unter „Bibliothek“. „Push“ wird direkt darunter nochmals als Routine präsentiert. Eine leere Historie ist informativ, aber „Deine Trainings erscheinen hier“ führt zu keiner Handlung.

**Warum falsch:** Beim Einstieg in ein freies Training ist die Bibliothek die falsche Beschriftung. Der Nutzer muss die Kartenreihenfolge kennen.

**Lösung:** In `TrainingView` sekundären Button „Freies Training“ in der Startgruppe ergänzen, im Bibliotheksblock allein die Übungen anbieten. Trainingsstart, Routine bearbeiten und neue Routine visuell und sprachlich eindeutig trennen. Leere Historie kompakt „Hier siehst du deine abgeschlossenen Trainings“. Beim Start Namen sowie Übungs- und Satzanzahl am selben Ort belassen.

### R-01-25 · P1 · Live-Training, Satz und Dock · 10-Live-Training.jpg, 12-Nächster-Satz.jpg
**Beobachtung:** In 10 stehen „Bankdrücken“ oben und „Schrägbankdrücken Kurzhantel“ direkt über dem Dock, das den aktiven Bankdrücksatz bearbeitet. In 12 ragt der nächste Übungstitel optisch in den Dock. `LiveWorkoutView` fügt nach der Liste 300 pt leeren Raum zusätzlich zur `safeAreaInset` ein. Die kleinen Kreise sehen aus wie eigenständige Abschlussaktionen, die Zeile wählt aber nur den Satz. Erledigte Zeilen sind Buttons ohne Aktion.

**Warum falsch:** Man kann versehentlich den falschen Satz protokollieren. Die leere Zone verlängert den Weg zurück zu den Bedienelementen. Position und Farbe allein reichen zur Orientierung nicht.

**Lösung:** Im Dock vor den Steppern „Bankdrücken · Aufwärmen“ bzw. „Bankdrücken · Satz 1“ bei ≥15 pt anzeigen. Die 300-pt-Fläche nach Test der letzten Zeile durch korrekt gemessenen Inset plus ca. 16 pt Puffer ersetzen. „Aufwärmen“ statt „A“ bei Platz, klare visuelle Auswahlmarkierung. Erledigte Sätze als statische Zeile oder mit echter Korrekturaktion zeigen. `accessibilityValue` für aktiv, erledigt und Reserve hinzufügen.

### R-01-26 · P1 · Live-Training, Eingaben · 10-Live-Training.jpg, 12-Nächster-Satz.jpg
**Beobachtung:** Fünf Reservetasten haben 40×36 pt, ihre Alternative lautet pauschal „4 Wiederholungen in Reserve“ für „4+“. Der Dock setzt `currentRIR` standardmäßig auf 2 und übernimmt die globale Auswahl über Sätze. `completeCurrentSet` überschreibt das Gewicht des ersten offenen Satzes derselben Übung bedingungslos trotz Kommentar „falls noch Standard“. In einer absteigenden Gewichtsfolge kann das geplante Folgesatzgewicht falsch werden. Die 44-pt-Stepper erlauben keinen direkten Werteinstieg.

**Warum falsch:** Ein vorbelegter Wert wirkt als Messung. Das Überschreiben veränderter Werte kann zu einem schwereren Satz führen als geplant. Ein 4+-Wert bedeutet „vier oder mehr“.

**Lösung:** In `LiveWorkout` je Satz `nil` als echte Option, vor einer unbeabsichtigten Übernahme den ursprünglichen Planwert erhalten. Manuell bearbeitete oder bewusst abweichende Folgesätze erhalten. `setControls` mit 44-pt-Zielen, skalierendem Zeilenumbruch und „Wiederholungen übrig“ beschriften. Tap auf Gewicht für direkte Dezimaleingabe anbieten, Pfeiltasten beibehalten. Trainingsablauf mit individuell abweichendem Folgesatz und kg/lb testen.

### R-01-27 · P2 · Pause · 11-Pause.jpg, 12-Nächster-Satz.jpg
**Beobachtung:** Die 56-pt-Uhr und große Zeit stehen gut im unteren Bereich. „Weiter“ erklärt die Folge nicht, im Dock fehlen nächste Übung und Satz. Die pausierte Ansicht nutzt Glas als Panel und nochmals Glas für die Aktionen. Der Timer blendet Zeit und Ring einmal pro Sekunde animiert; nach Ablauf wechselt der Dock ohne ausdrückliche Beschriftung des Fokusziels.

**Warum falsch:** Mit abgelegtem Telefon oder VoiceOver ist das Ende schwerer zu erkennen. Das kleine dunkle Glas für „+15 s“ ist undeutlich, die Aktion „Weiter“ kann als Satzabschluss verstanden werden.

**Lösung:** `restView` mit „Als Nächstes: Bankdrücken, Satz 1“, „Pause beenden“ und „15 Sek. dazu“ (Accessibility ausgeschrieben). Eine Materialebene plus klare Buttons ausprobieren. Pausenende einmal ansagen und auf den Satz-Dock fokussieren. Wiederkehrende Sekunden-Ansagen vermeiden. Timer mit Vorder-/Hintergrundwechsel und Reduce Motion prüfen.

### R-01-28 · P2 · Trainingszusammenfassung und Übungsdetails · 13-Zusammenfassung.jpg, Übungsdetail ohne Screenshot
**Beobachtung:** Eine unterminütige Demo erscheint als „1 min“, „580 kg“ ergibt Satzlast × Wiederholungen, Gewichtseinheiten fehlen in den Satzzeilen. Epley schätzt 72,5 × 8 auf 91,8 kg. In `ExerciseDetailView` kann ein Verlaufseintrag mit ausschließlich Aufwärmsätzen erscheinen, weil die Auswahl alle Sätze prüft und die Kennzahl nur Arbeitssätze.

**Warum falsch:** „Volumen“ kann als bewegte Einzelmasse verstanden werden. 91,8 kg wirkt präziser als die Formel hergibt. Ein 0er aus der Warm-up-Auswahl sieht wie ein echter Rekord aus.

**Lösung:** `WorkoutSummaryView`: „Dauer <1 min“, „Trainingsvolumen“ mit kurzer Erklärung, Einheit je Satz und „Geschätztes Gewicht für 1 Wiederholung“. Formel/Grundlage als Detail anbieten, sehr hohe Wiederholungszahlen und reine Aufwärmsätze aus dem Max-Vergleich herausnehmen. Vergleiche pro Übung auf Arbeitssätze mit vergleichbarer Wiederholungszahl stützen. Löschaktion unter den Abschlussaktionen belassen und ihren Bestätigungsstatus bei Speicherfehlern berücksichtigen.

### R-01-29 · P2 · Routineneditor und Bibliothek · kein Screenshot
**Beobachtung:** `RoutineEditorView` bietet vier getrennte Stepper je Übung und bindet direkt auf das SwiftData-Objekt. In lb rechnet der Editor die Anzeige um, ändert aber weiter intern in 2,5-kg-Schritten. `LiveWorkoutView` verwendet dafür ungefähr 5 lb, und `LiveWorkout.from` zeigt „Letztes Mal“ fest in kg. Bei flexiblen Routinen fehlt ein schneller Einblick in die geplanten Satz- und Pausewerte.

**Warum falsch:** Ein Einheitenwechsel ändert das erwartete Schrittmaß. Das lange Editorlayout erschwert die Routine-Kontrolle und der implizite Speichervorgang macht den Status unklar.

**Lösung:** Die Gewichtseingabe über `WeightUnit` in Editor und Live-Dock mit demselben Schrittmaß und lokaler Dezimalschreibweise ableiten. „Letztes Mal“ über die jeweilige Einheit formatieren. Je Übung eine skalierbare Zeile mit Zusammenfassung und Detailbearbeitung prüfen. Eine klare Nachfrage beim Verlassen mit ungespeicherten Änderungen oder ein sichtbarer Auto-Speicherzustand mit Wiederholen bei Fehler.

### R-01-30 · P1 · Gesundheit, Karten und Historie · 14-Gesundheit.jpg, 14e-Gesundheit-unten.jpg, 02-Heute-gescrollt.jpg
**Beobachtung:** Die Gesundheitsseite führt mit einem farbigen Körperalter in deutlich größerer Typografie als den Messwerten. „Trends der letzten 30 Tage“ steht auch bei weniger Daten. „Normal 51–55 bpm“ wirkt universell, wird aber aus mindestens vier Messungen der vorherigen bis zu 29 Tage mit einer Mindeststreuung von 4 % berechnet. Bei fehlendem Tagesmesswert zeigt `MetricSummaryRow` still den letzten Wert. Der Quellenhinweis am Ende erklärt „Standardabweichung“, ohne den tatsächlichen Umfang je Metrik zu zeigen.

**Warum falsch:** Persönliche Streuung und medizinischer Referenzbereich wirken gleich. Ein alter Wert kann wie heute gemessen aussehen. Wechsel zwischen Fitbit-RMSSD und Apple-SDNN erschwert direkte Vergleiche.

**Lösung:** `HealthView` mit Herz und Atmung beginnen, Körperalter gemäß R-01-01 behandeln. Pro Metrik „Dein üblicher Bereich“ mit Anzahl und Datum, „Zuletzt am …“ bei älterem Wert. Unter `MetricKind` HRV-Quelle und Messmethode neben den Wert setzen. Messbeschreibungen für Ruhepuls, Atemfrequenz und SpO₂ auf die tatsächliche Quellmessung zuschneiden und allgemeine Grenzwerte aus der persönlichen Norm-Zeile heraushalten. [Apple – Gesundheitsverläufe](https://support.apple.com/en-mk/guide/iphone/iphe3d379c32/ios)

### R-01-31 · P1 · HRV und Messwert-Charts · 15-HRV.jpg, 14e-Gesundheit-unten.jpg
**Beobachtung:** Das letzte Datumslabel erscheint abgeschnitten, Endpunkt und rechte 60er-Beschriftung liegen dicht. `MetricDetailView` verwendet Catmull–Rom-Interpolation. Zwischen Lücken laufen Linien weiter und Bögen können über Messpunkte hinausschießen. Der Zeitraumumschalter steuert Stichprobe, Graph und Zusammenfassung, der Wert „zum 30-Tage-Mittel“ bleibt gleich. Der Graph hat keinen expliziten Leerzustand und VO₂max nutzt eine undatierte Mini-Kurve.

**Warum falsch:** Eine geglättete Messreihe kann unbeobachtete Werte suggerieren. Der 7-Tage-Chart kann bei wenigen Messungen einen kürzeren Bereich abbilden. Die Nennung des tatsächlichen Referenzfensters ist Teil der Messinformation.

**Lösung:** `MetricDetailView` mit fester Datumsdomäne der Auswahl und Segmentbrüchen bei Lücken. Linear verbinden, reale Messpunkte auf Wunsch auswählbar, ca. 12–16 pt Achsenreserve für Randlabels. Pro Chart „X Messungen“ und eine Textzusammenfassung für VoiceOver. Für gar keine Messung kompakte Erläuterung und Quelle. Referenzmittel ausdrücklich datieren und Einheit in der Abweichung zeigen, etwa „4 ms über deinem Mittel“.

### R-01-32 · P2 · Körperalter, Typografie und Methode · 14b-Körperalter.jpg, 14c-Körperalter-Faktoren.jpg, 14d-Körperalter-Methode.jpg
**Beobachtung:** Neben der 64-pt-Zahl fehlt im Hero die Einheit in derselben Blickzeile. Die Referenzlinie trägt nur „dein Alter“, die Enden sind unbeschriftet. „±0 Jahre“ hat in 14c einen orangefarbenen Minibalken. Der Methodentext steht als mehrere kompakte 15-pt-Blöcke über sieben gleichgewichteten Quellen, der Navigationskopf überblendet Teile des Texts beim Scrollen.

**Warum falsch:** Null wird farblich als ungünstig gelesen. Ohne Skala vermittelt die Leiste eine Genauigkeit, die der Text später relativiert.

**Lösung:** Wenn das Beispiel bleibt, `AgeScale` mit neutralem Nullzustand und beschriftetem Marker (falls nötig „Schätzung“, „Vergleichsalter“). Quellen als zugängliche Zeilen mit 44 pt Mindesthöhe und Bindung an den jeweiligen Faktor. In `BodyAgeDetailView` die Methode in kurze Abschnitte „Deine Messwerte“, „Vergleich in Studien“, „So entsteht die Beispielzahl“ gliedern. Methodengrenzen direkt oberhalb der detaillierten Liste zeigen.

### R-01-33 · P1 · Coach, Start und Chat · 16-Coach.jpg
**Beobachtung:** Zwischen Tagessatz und Eingabe liegt ein großer freier Bereich. Ein Vorschlagschip endet mit abgeschnittenem Satz, der Sende-Button erscheint klein und ohne sichtbaren Text. `consumePrompt` übernimmt einen aus „Heute“ gesendeten Text als Coach-Nachricht und beantwortet grundsätzlich „erholung“, selbst wenn der Einblick von Schlaf handelt. Der lokale Matcher reagiert auf breite Wörter wie „heute“.

**Warum falsch:** Der leere Bildschirm hilft beim Einstieg wenig. Die gleiche Nutzeraktion kann bei anderem Thema dieselbe Antwort erzeugen. Die Herkunft einer improvisierten Chat-Antwort bleibt unklar.

**Lösung:** `CoachView` mit zwei bis drei vollständig sichtbaren Einstiegsfragen, z. B. „Warum ist meine Erholung so?“ und „Wie rechnet Forma meinen Schlafwert?“. Eingabe mit 44-pt-Senden und Accessibility-Label. `AppState.openCoach` mit konkretem Thema statt bloßem String aufrufen und die erste Antwort darauf beziehen. Nachrichtensicht mit dynamischem Typ, Tastatur, VoiceOver-Reihenfolge und Zeitüberschreitung prüfen.

### R-01-34 · P1 · Journal · kein Screenshot
**Beobachtung:** `JournalView` verspricht, dass der Coach nach etwa zwei Wochen den Einfluss von Gewohnheiten zeigt. `CoachEngine.Context` bekommt keine Journalantworten. `YesNoSwitch` misst insgesamt 116×34 pt. „Wie am Vortag ausfüllen“ übernimmt Antworten sofort und kann ohne Rückmeldung wirkungslos bleiben.

**Warum falsch:** Die versprochene Auswertung fehlt im geprüften Stand. Mehrere gleich benannte „Ja/Nein“-Buttons sind beim linearen Vorlesen schwer einer Frage zuzuordnen.

**Lösung:** Nur die vorhandene Funktion erklären („Halte fest, was gestern zutraf“). `YesNoSwitch` mit je 44 pt, vollständiger Accessibility-Beschriftung samt Frage und Zustand. „Übernimm unbeantwortete Einträge vom Vortag“ plus Anzahl und Rückgängig anzeigen. Bei keinem Vortag deaktivieren und erklären.

### R-01-35 · P1 · Onboarding und Profil · kein Screenshot
**Beobachtung:** Beide bieten Verbindungen an, aber `DataHub.healthAuthorized` speichert nur den gestarteten/bearbeiteten Berechtigungsdialog. `resolveSource(.automatic)` bevorzugt jede als verbunden markierte Fitbit-Quelle vor Apple Health. „Zuletzt aktualisiert“ verwendet den Versuch statt den Messstand. Keine eigene Verifikation einer funktionierenden Apple-Health-Installation mit kostenloser Apple-ID.

**Warum falsch:** Quellenstatus und Datenstatus sind getrennte Informationen. Eine eingerichtete Quelle kann weiterhin leer oder weggefallen sein. Favorisierte Quelle und Diagnose des Imports müssen in Reichweite bleiben.

**Lösung:** In `ProfileView` getrennt „Verbindung“, „Letzter erfolgreicher Import“ und „Abgedeckter Zeitraum“ zeigen. „Daten in Apple Health prüfen“ bei leerem Ergebnis, Verbindung in Onboarding mit Fehlermeldung und weiterem normalen Pfad. Demo als explizite Wahl. Echten Signier- und Leseweg auf Maxis iPhone inklusive Berechtigungsänderung, Neustart und Quellwechsel testen. [Apple – HealthKit-Berechtigungen](https://developer.apple.com/documentation/HealthKit/authorizing-access-to-health-data)

### R-01-36 · P1 · CI-Bildabdeckung · 01-Heute.jpg bis 16-Coach.jpg
**Beobachtung:** `ScreenTour.testTour` nimmt Screenshots nach optionalen Taps, teils mit Koordinaten-Fallback. Lauf 8 war grün, vorhandene Bilder zeigen allein Demo. `17 Coach Antwort`, `18 Journal`, `19 Profil` sind im Script vorgesehen und fehlen in `docs/forma-screens/`. Das Training zeigt den Happy Path mit einer Beispielroutine.

**Warum falsch:** Ein grüner Screenshot-Job lässt eine fehlende Zielansicht unbemerkt. Aussagen zur Einhandbedienung, Skalierung und Fehlerpfaden brauchen weitere Ansichten oder Interaktionen.

**Lösung:** `ScreenTour.swift` mit stabilen Accessibility-IDs und harten Assertions für Start, Pflichtansichten und erzeugte Dateien. Extra Zustände im Simulator für leere und veraltete Daten, große Schrift, Coach-Antwort, Journal/Profil/Onboarding, freie Einheit, Umordnen und Wiederherstellen. Auf echtem Gerät zusätzlich VoiceOver, Bewegung reduzieren, Glas bei heller Umgebung und Daumenzone prüfen.

### R-01-37 · P1 · Fitbit-Datensatz und Zeitraum-Endpunkte · 14-Gesundheit.jpg, 15-HRV.jpg (betroffene Ansichten)
**Beobachtung:** `FitbitService.loadDay` liefert sechs Einzelanfragen je Tag. `DataHub.refresh` legt selbst komplett leere Tage im prozesslokalen Zwischenspeicher ab. Im warmen Fall liegen heute und gestern bei zwölf Requests je Aktualisierung. Bei nur 14 Tagen kann der 30-Tage-Umschalter keinen 30-Tage-Verlauf zeichnen.

**Warum falsch:** Fehler und leere Messungen landen im selben Datenmodell. Ein verspäteter Sync kann alte leere Zeilen zurücklassen. Die Historie geht beim App-Neustart verloren. Googles Abschaltplan macht eine neue Implementierung auf der bisherigen API unabhängig vom Kontingent ungeeignet.

**Lösung:** `FitbitService` durch einen Google-Health-Importer mit `loadRange(start:end:)`, Google-Anmeldung und datierten Ergebnissen pro Metrik ersetzen. `DataHub.refresh` lädt zuerst 30 Tage und ergänzt Historie bedarfsgerecht bis 180 Tage. Zeitdaten pro Nutzer und Metrik in einem lokalen, lesegeschützten Cache mit Erfassungsdatum, Abrufzeit und Herkunft ablegen. Erfolg je Metrik zusammenführen, bei Fehlern den letzten gültigen Datenstand behalten, jüngste 2–3 Tage wegen später Synchronisierung überlappend aktualisieren. Cache nach Kontowechsel oder Trennung isolieren. Aktualisierung bei App-Aktivierung drosseln und zusammenfassen, Pagination beachten, 429 mit `Retry-After`/Backoff abfangen, Berechtigungsfehler und leere Antworten getrennt anzeigen.

#### Google Health API v4 – für die Umsetzung

Basis `https://health.googleapis.com/v4/users/me/dataTypes`. Die Filter unten sind lesbar dargestellt und werden vom Client als URL-Parameter kodiert. Beispielzeitraum vom 20. Oktober bis einschließlich 18. November. Google dokumentiert für Schlaf maximal 25 Logs pro Seite. `dailyRollUp` begrenzt Schritte und aktive Energie auf 90 Tage pro Request. Neue Projekte benötigen Zugang und geeignete Lese-Scope-Freigaben. Der Zugang für Forma ist offen. Ein älteres v4beta-Banner weist darauf hin, dass neue Projekte zeitweise nicht aufgenommen werden. [Google – v4 und Abschaltung](https://developers.google.com/health/about) · [Lese-Scopes und Filter](https://developers.google.com/health/filters) · [Hinweis zur Projektaufnahme](https://developers.google.com/health/reference/rest/v4beta/ActiveEnergyBurnedRollupValue)

| `DayMetrics` | Methode und Pfad relativ zur Basis | Zeitraum und Zuordnung |
|---|---|---|
| `sleep` | `GET /sleep/dataPoints:reconcile` | Filter `sleep.interval.civil_end_time >= "2026-10-20" AND sleep.interval.civil_end_time < "2026-11-19"`, `pageSize=25`. `sleep.metadata.mainSleep`, Intervalle und Stufen übernehmen. Aufwachdatum und Offsets verwenden. Kurze Wachereignisse können überlappen, daher als Ereignisse getrennt behandeln. [Google – Schlaf](https://developers.google.com/health/data-types/sleep) |
| `hrv` | `GET /daily-heart-rate-variability/dataPoints:reconcile` | Filter `daily_heart_rate_variability.date >= "2026-10-20" AND daily_heart_rate_variability.date < "2026-11-19"`. `averageHeartRateVariabilityMilliseconds` ist RMSSD. Apple-SDNN separat halten. [Google – Datenfelder](https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints) |
| `restingHR` | `GET /daily-resting-heart-rate/dataPoints:reconcile` | `daily_resting_heart_rate.date` entsprechend filtern. Tageswert nach Rückgabedatum zuordnen und Berechnungsmethode (mit Schlaf/aus Wachmessungen) als Herkunft bewahren. [Google – Tageswerte](https://developers.google.com/health/data-types) |
| `spo2` | `GET /daily-oxygen-saturation/dataPoints:reconcile` | `daily_oxygen_saturation.date` und den Tagesmittelwert verwenden. Prozent-Skalierung beim Decoder gegen eine dokumentierte Beispielantwort prüfen. [Google – Datenfelder](https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints) |
| `respiratoryRate` | `GET /daily-respiratory-rate/dataPoints:reconcile` | `daily_respiratory_rate.date`, tägliche Atemzüge/min im Hauptschlaf. [Google – Datenfelder](https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints) |
| `steps`, `activeEnergy` | Je `POST /steps/dataPoints:dailyRollUp` und `POST /active-energy-burned/dataPoints:dailyRollUp` | `range.start.date` 20.10., `range.end.date` 19.11., jeweils lokaler Tagesbeginn. `windowSizeDays: 1`, je nach beabsichtigter Herkunft `dataSourceFamily` festlegen. `steps.countSum` und `activeEnergyBurned.kcalSum`; null und echte 0 unterscheiden. [Google – dailyRollUp](https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/dailyRollUp) · [Google – Datenarten](https://developers.google.com/health/data-types) |

Beim Lesebereich ab sichtbaren 30 Tagen zunächst Daten für Ringe und Trends liefern. Für eine längere Ansicht 90-Tage-Blöcke bei den beiden Rollups verwenden und die übrigen Typen mit Zeitfiltern und Pagination laden. Antworten per lokalem Kalenderdatum verbinden. Wenn nur Tracker-Daten gewünscht sind, `users/me/dataSourceFamilies/google-wearables` dokumentiert angeben und gegen Daten mit manuell erfassten Schritten prüfen. Nach der Migration den Belastungsindex mit Alt- und Neudaten vergleichen. Fitbit-`activityCalories` enthält laut Altdoku Grundumsatzanteile für aktive Minuten und ist semantisch verschieden von der neuen aktiven Energie. Testfälle für zwei Konten, späten Sync, Mitternacht/Zeitzonenwechsel, 200 mit Teilantwort, 401, 403, 429, 5xx und Offline-Neustart. [Google – Datenquellen und Pagination](https://developers.google.com/health/endpoints) · [Fitbit – Kalorienbegriffe](https://dev.fitbit.com/build/reference/web-api/activity-timeseries/get-activity-timeseries-by-date-range/)

#### Alte Fitbit-Web-API – Zuordnung für Migration und Vergleich

Die historischen GET-Pfade relativ zu `https://api.fitbit.com`, mit `{start}`/`{end}` als ISO-Datum. Im Code wurden Schritte und Kalorien zusammen aus dem Tages-Summary gelesen. Ihre Zeitraum-Serien sind zwei Pfade.

| Messung | Alter Zeitraum-Endpunkt | Dokumentierter Maximalbereich |
|---|---|---|
| Schlaf | `/1.2/user/-/sleep/date/{start}/{end}.json` | 100 Tage. Über `dateOfSleep` gruppieren und `isMainSleep` bevorzugen. [Fitbit – Schlaf](https://dev.fitbit.com/build/reference/web-api/sleep/get-sleep-log-by-date-range/) |
| HRV | `/1/user/-/hrv/date/{start}/{end}.json` | 30 Tage. `dailyRmssd`. [Fitbit – HRV](https://dev.fitbit.com/build/reference/web-api/heart-variability/get-hrv-summary-by-interval/) |
| Ruhepuls | `/1/user/-/activities/heart/date/{start}/{end}.json` | Ein Jahr. `restingHeartRate`. [Fitbit – Herzfrequenz](https://dev.fitbit.com/build/reference/web-api/heartrate-timeseries/get-heartrate-timeseries-by-date-range/) |
| Schritte | `/1/user/-/activities/steps/date/{start}/{end}.json` | 1.095 Tage. [Fitbit – Aktivität](https://dev.fitbit.com/build/reference/web-api/activity-timeseries/get-activity-timeseries-by-date-range/) |
| Aktivitätskalorien | `/1/user/-/activities/activityCalories/date/{start}/{end}.json` | 30 Tage. [Fitbit – Aktivitätskalorien](https://dev.fitbit.com/build/reference/web-api/activity-timeseries/get-activity-timeseries-by-date-range/) |
| SpO₂ | `/1/user/-/spo2/date/{start}/{end}.json` | Dokumentiert ohne Bereichslimit. Bereichsantwort ist eine Liste mit `dateTime` und `value.avg`. [Fitbit – SpO₂](https://dev.fitbit.com/build/reference/web-api/spo2/get-spo2-summary-by-interval/) |
| Atemfrequenz | `/1/user/-/br/date/{start}/{end}.json` | 30 Tage. [Fitbit – Atemfrequenz](https://dev.fitbit.com/build/reference/web-api/breathing-rate/get-br-summary-by-interval/) |

Ein identischer 14-Tage-Abruf hätte damit historisch sieben statt 84 Requests benötigt. Diese Zahl lässt sich aus den Endpunkten ableiten. Eine Live-Abfrage mit Nutzerdaten war nicht Teil der Prüfung.

## Was bleiben soll

- Die drei fest platzierten Ringe als Einstieg in „Heute“, mit Erholung als Schwerpunkt und lesbarerem Lavendel für Schlaf. Den gestrichelten Zielbogen als sekundäre Markierung erhalten.
- Neutrales Schwarz und matte Datenträger. Weiß als primäre Trainingsaktion und Glas als funktionale Ebene für Navigation und den Trainings-Dock.
- Stets erreichbarer Trainings-Dock, stark abgegrenzter aktiver Satz, gemeinsamer Timer und „15 Sek. dazu“. Die schnelle Daumenbedienung ist der stärkste native Ablauf.
- Persönliche Vergleichswerte direkt bei der Metrik und freie Reihenfolge bei den ergänzenden Karten. Apple Fitness zeigt, wie Trends an zwei konkrete Fenster gebunden sind. Apple Health zeigt Zeitraum und Trend beim jeweiligen Messwert. Forma sollte diese Orientierung mit seinem eigenen Layout verbinden. [Apple Fitness – Trends und Anpassen](https://support.apple.com/en-ae/guide/iphone/iph4c34a8a95/27/ios/27) · [Apple Health – Trends](https://support.apple.com/en-mk/guide/iphone/iphe3d379c32/ios)
- Aufklappbare Erklärung und verlinkte Fachquellen bei Gesundheitsfaktoren. Oura erklärt Messgrundlage und Kalibrierzeit direkt am kardiovaskulären Alter, Bevel dokumentiert Datenfrische pro Biomarker und Gründe für fehlende Werte. Forma kann dieselbe Transparenz zu den eigenen Messwerten und Annahmen nutzen. [Oura – Cardiovascular Age](https://support.ouraring.com/hc/en-us/articles/28451491040019-Cardiovascular-Age) · [Bevel – Biological Age](https://help.bevel.health/en/articles/11586369)
