# Health 1.0 – Testplan fürs iPhone

## So installierst du

1. Verbinde dein iPhone per USB mit dem PC. Bestätige „Diesem Computer vertrauen?“, falls gefragt.
2. Öffne Sideloadly, wähle dein iPhone und zieh die Health-IPA aus **Downloads** ins Fenster.
3. Nutze deine kostenlose Apple-ID und klicke auf **Start**. [Sideloadly](https://sideloadly.io/)
4. Aktiviere bei Bedarf auf dem iPhone unter **Einstellungen → Datenschutz & Sicherheit** den **Entwicklermodus**. Starte das iPhone neu und bestätige. [Apple](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
5. Öffne **Health**. Die Signatur gilt sieben Tage. Danach signierst du die App mit derselben Apple-ID neu, deine Daten bleiben.

📱 = nur auf einem echten iPhone testbar. Ohne Zeichen geht der Test auch mit Beispieldaten.
**Voraussetzungen:** Für Google-Tests brauchst du eine eingetragene Google-Client-ID in der App (sonst steht im Profil „Vorschau-Version“). Für Online-Coach und Essensfoto brauchst du die IPA mit Coach-Schlüsseln (`Health-mit-Coach.ipa`). Für Mitteilungen, Widgets, Siri und Kontrollzentrum: Beispieldaten aus.
Wenn etwas hakt, notiere Testnummer und was du siehst, z. B. **T-05 – Anmeldung bricht ab**.

## Start und Google Health

- **T-01** 📱 Öffne Health frisch installiert → Du wählst zwischen Google Health und Beispieldaten.
- **T-02** Tippe auf „Erst mit Beispieldaten ansehen“ → Today öffnet sich mit dem Hinweis „Beispieldaten“. Food, Health und Coach sind erreichbar.
- **T-03** 📱 Installiere eine neue IPA über die alte → Routinen, Trainings, Essen und Einstellungen sind noch da.
- **T-04** 📱 Profil → „Mit Google Health verbinden“, Anmeldung abbrechen → Du bist zurück in Health, Google bleibt getrennt, ein neuer Versuch geht.
- **T-05** 📱 Google-Konto mit Messwerten verbinden → „Rufe Messwerte ab …“ zeigt den sofortigen ersten Abruf. Schritte, Schlaf und Puls erscheinen für die passenden Tage. Wenn Google für heute keine Werte liefert, steht das im Profil.
- **T-06** 📱 Profil → Datenquelle → „Jetzt aktualisieren“ → Neuer Abrufstand. Schritte eines abgeschlossenen Tages mit der offiziellen Google-Health-App vergleichen. „Hintergrundaktualisierung“ zeigt den iOS-Termin getrennt vom manuellen Abruf.
- **T-07** 📱 Flugmodus an, Health neu öffnen, aktualisieren → Die letzten Werte bleiben sichtbar, der Abrufstand springt nicht auf „jetzt“.
- **T-08** 📱 Health über Nacht im Hintergrund lassen → Morgens zeigt der Abrufstand eine Uhrzeit vor dem Öffnen.
- **T-09** 📱 „Google Health trennen“ bestätigen → Importierte Werte verschwinden, auch aus dem Widget (kann bis zu 15 Minuten dauern).

## Today

- **T-10** Today ansehen → Recovery groß in der Mitte, Strain links und Sleep rechts als Balken. Oben schimmert es in der Recovery-Farbe bis unter die Statusleiste, nichts ist abgeschnitten.
- **T-11** 📱 Health aus der App-Übersicht schließen und neu öffnen. Sobald Today sichtbar ist, sofort **Sleep** öffnen, zurück und **Strain** antippen → Beide Seiten öffnen sich und lassen sich scrollen. Auch während der ersten Google-Aktualisierung prüfen.
- **T-12** Im Trend zwischen W, M und 6M wechseln → Die Linie wechselt; bei 6M Wochenmittel ohne Zucken. Antippen ins Diagramm wählt keinen Tag aus.
- **T-13** Im Trend „Einzelwerte“ aufklappen → Liste mit Datum und Wert der echten Messungen, neueste zuerst; erneut tippen klappt zu.
- **T-14** Sleep-Detail → Kapsel beschriftet mit „Sleep“, darunter Schlafstunden/Schlafbedarf, Schlafkonstanz direkt sichtbar ohne weiteren Tipp.
- **T-15** Die Vitalwerte sowie Stress, Energie und Schritte antippen → Jede Kachel öffnet ihre Details. Das Layout-Symbol der Vitalwerte wechselt zwischen Karten und Balken. Die Zwischenleiste und „Mein Tag“ erscheinen auf Today nicht mehr.
- **T-16** Kachel Schritte → Halbkreis mit Strichen zeigt Tagesziel und erreichte Schritte (z. B. 6.240 von 8.550). Das Ziel ändert sich von Tag zu Tag je nach Recovery und Schlaf.
- **T-17** Today zeigt Stresswert, Zone und Tagesbalken. Antippen öffnet Skala, Zeit in Zonen und Atemübung.
- **T-18** Auf Today **Schlafplan** und **Wasser** antippen → Beide öffnen ihre Details. Von Today zu Food und zurück wechseln → Die Ringe spielen ihre Animation erneut ab.
- **T-19** Ganz nach unten scrollen, „Anpassen“ → Kacheln per Griff verschieben, per Minus ausblenden; nach „Fertig“ bleibt die Reihenfolge.
- **T-20** Nach unten ziehen → Today aktualisiert sich.

## Plus-Menü

- **T-21** Auf **+** rechts unten tippen → Ein Kachelfeld springt aus der Ecke des Plus-Knopfs auf: Nährwerte tracken, Essen planen, Fitness, Wasser, Fasten, Gewicht. Der Plus-Knopf wird zum X.
- **T-22** Menü schließen auf drei Wegen: X tippen, daneben auf den Bildschirm tippen, (VoiceOver) Zwei-Finger-Wischen → Das Menü geht zu, du bleibst im gleichen Tab.
- **T-23** Plus aus Today, Food, Health und Coach öffnen → Das Menü erscheint jedes Mal am Plus-Knopf, nicht über einem anderen Tab.
- **T-24** Plus → eine Kachel wählen → Das Ziel öffnet sich sofort als Blatt; nach Schließen bist du im vorherigen Tab.

## Food

- **T-25** Tab **Food** → Ringe oben, erfasste Kalorien mit Tagesziel darunter. Ballaststoffe stehen in einer eigenen Kachel. Wasser, Fasten, Plan und Gewicht stehen unter den Mahlzeiten.
- **T-26** Plus → Nährwerte tracken → Suchen: „Haferflocken“, Treffer wählen, 50 g eintragen → Eintrag steht unter der Mahlzeit, Summen passen.
- **T-27** Bei „Frühstück“ auf **+** tippen und etwas eintragen → Der Eintrag landet unter Frühstück. Frühstück, Mittag und Abend zeigen je erfasste kcal und bei einem bestehenden Essensplan auch die geplanten kcal.
- **T-28** Mengenfeld 0 → „Eintragen“ gesperrt.
- **T-29** Eintrag nach links wischen oder lange drücken → Löschen; Summe sinkt.
- **T-30** Lebensmittel ohne Proteinangabe eintragen → Oben steht „≥“ bzw. „–“ statt einer falschen exakten Zahl.
- **T-31** 📱 Nährwerte tracken → Scannen, bekannten Barcode zeigen → Produkt öffnet sich mit Nährwerten.
- **T-32** 📱 Kamera-Freigabe ablehnen → Hinweis, wie du sie erlaubst; Suche bleibt bedienbar.
- **T-33** 📱 Nährwerte tracken → Foto (mit Coach-Schlüsseln und Foto-Freigabe) → Geschätzte Lebensmittel und Mengen, vor dem Speichern änderbar.
- **T-34** 📱 Foto ohne Freigabe → Health sagt, welche Freigabe fehlt; nichts wird gesendet.
- **T-35** Plus → Essen planen: für morgen eine Mahlzeit planen, dann „Einkauf“ → Zutaten erscheinen in der Einkaufsliste, abhakbar.
- **T-36** Am geplanten Tag „Übernehmen“ → Die Mahlzeit steht im Tagebuch.
- **T-37** Plus → Wasser → „Glas · 250 ml“ und Minus → Menge steigt und sinkt um 250 ml.
- **T-38** Plus → Fasten → 16:8 starten, App schließen und wieder öffnen → Zeit läuft weiter; Beenden speichert den Versuch.
- **T-39** Plus → Gewicht → Wert eintragen → Kachel in Food zeigt den letzten Eintrag statt „Eintragen“.

## Fitness (Training)

- **T-40** Plus → Fitness → Blatt „Fitness“ mit „Fertig“. Beim Scrollen bleibt der Titel lesbar und überlagert keinen Knopf.
- **T-41** Fitness → „Als Nächstes“ → „<Routine> starten“ → Live-Training mit erster Übung und Satz. Es öffnet sich genau ein Live-Training.
- **T-42** Gewicht/Wdh. ändern, schnell zweimal „Satz abschließen“ → Ein Satz abgehakt, Pause startet.
- **T-43** Pause → „+15 s“ und „Pause beenden“ → +15 s (am Limit nur der mögliche Rest), dann sofort Ende.
- **T-44** Während der Pause den letzten offenen Satz löschen → Pause und Pausen-Mitteilung enden.
- **T-45** App bei laufendem Training aus der App-Übersicht wischen und neu öffnen → Training mit erfassten Sätzen ist wieder da.
- **T-46** „Beenden → Speichern“ → Zusammenfassung; nach „Fertig“ ist wieder Fitness offen, das Training steht einmal unter Aktivitäten.
- **T-47** Routine mit zwei Übungen als **Supersatz** koppeln und starten → Übungen wechseln sich ab, Pause erst nach dem Paar.
- **T-48** „Neue Routine“ anlegen, zwei Übungen hinzufügen → Routine steht in der Liste; lange drücken → Löschen.
- **T-49** Muskelkarte „Muskeln, 7 Tage“: einen Muskel antippen → Name, Sätze und letzte Belastung; untrainierte Muskeln grau.
- **T-50** Übungsbibliothek → bekannte Übung → Ausführung und Verlauf sichtbar.
- **T-51** „Freies Training“ → Übung und Satz hinzufügen → im Live-Training bearbeitbar.
- **T-52** 📱 Pause mit „Bei Pausenende benachrichtigen“, iPhone sperren → Meldung bei Ablauf.

## Health

- **T-53** Tab **Health** → Health Age als Kreis aus grünen Lichtpunkten, große Zahl, darunter „x Jahre jünger/älter“. Kein „Schätzung“.
- **T-54** Health Age antippen → Alterungstempo mit Skala, Beiträge, Trend; alles zeigt den heutigen Stand.
- **T-55** Biomarker (z. B. Ruhepuls) antippen, 7/30/90 Tage wechseln → Verlauf wechselt; Antippen ins Diagramm wählt keinen Tag.
- **T-56** Health Monitor öffnen → Karten mit persönlichem Bereich; jede Karte antippbar. Erklärung nur hinter (i).
- **T-57** Health nach unten scrollen → Vitalwerte und Biomarker bleiben antippbar. Die separate Kachel „Gewohnheit“ und Überschriften zwischen den Kacheln fehlen.
- **T-58** „Anpassen“ steht ganz unten → Kacheln verschieben/ausblenden funktioniert.

## Schlaf und Coach

- **T-59** Sleep-Detail mit Beispieldaten → Karte „Schlafplan“ → Weckzeit für Arbeitstage und freie Tage ändern → Bettzeitfenster verschiebt sich sofort mit.
- **T-60** Profil → Mitteilungen: „Coach am Morgen“, „Bettzeit-Erinnerung“ und „Werte in der Mitteilung“ lassen sich schalten; der Schlafplan steht nicht mehr im Profil, nur im Sleep-Detail und auf Today. Profil → Allgemein → Wochenstart „Sonntag“ → Trainingskalender beginnt mit Sonntag.
- **T-61** Coach öffnen, eine Nachricht mit Absatz schreiben, daneben in den Chat tippen → Die Tastatur schließt sich und der Entwurf bleibt erhalten. Über den Senden-Knopf abschicken → Antwort auf Deutsch.
- **T-62** Coach mit Beispieldaten fragen „Wie viele Schritte sollte ich heute gehen?“ → Er nennt das heutige Schrittziel.
- **T-63** Ohne Internet und ohne Online-Freigabe fragen → Antwort kommt lokal vom iPhone.
- **T-64** Foto im Chat hinzufügen und vor dem Senden entfernen → Vorschau erscheint und verschwindet.
- **T-65** 📱 Mitteilungen erlauben, Schlafplan gesetzt → Rund 30 Minuten vor der geplanten Bettzeit kommt eine Erinnerung; nach „Google trennen“ keine mehr.

## Profil

- **T-66** Profil → Body: Geburtsjahr, Geschlecht, Größe, Gewicht → bleiben nach Neustart; keine Pfeile in der Liste.
- **T-67** Body → Einheiten auf Pfund → Training zeigt lb.
- **T-68** Profil → Design: Standard, Schwarz, Blau, Bordeaux, Verläufe durchprobieren → Hintergrund, Schimmer und Akzent wechseln überall; Schwarz ist reines Schwarz; Ringfarben bleiben lesbar.
- **T-69** Profil → Erfolge → Abzeichen sichtbar.
- **T-70** Beispieldaten ein und aus → klar gekennzeichnet; danach wieder dein eigener Stand, Gewicht nicht überschrieben.
- **T-71** Freigaben „Fragen an den Online-Coach“ und „Essensfotos“ einzeln widerrufen → Jede Zeile sagt, was danach nicht mehr online geht.

## Widgets, Kontrollzentrum, Siri

- **T-72** 📱 Widget „Today“ (klein, mittel) auf den Homescreen → Recovery, Sleep, Strain mit Kürzeln R/S/St, Werte wie in Today.
- **T-73** 📱 Widget auf dem Sperrbildschirm → drei Werte gut zuordenbar.
- **T-74** 📱 Wasser-Widget: „+250 ml“ tippen, dann Health öffnen → Glas steht in Food, Widget zeigt den Tagesstand; nichts doppelt.
- **T-75** 📱 Kontrollzentrum: „Wasser +250 ml“ und „Training starten“ hinzufügen und tippen → Glas wird gezählt bzw. das nächste Training startet (ohne Routine ein freies).
- **T-76** 📱 Training starten, Satz abschließen, iPhone sperren → Live Activity zeigt die Pause; nach Trainingsende weg.
- **T-77** 📱 „Siri, Training mit Health starten“ zweimal → nur ein Training läuft.
- **T-78** 📱 „Siri, wie ist meine Erholung in Health?“ → Wert mit Uhrzeit oder „keine Messung“.
- **T-79** 📱 „Siri, Essen mit Health scannen“ (auch während eines Trainings) → Scanner öffnet sich, im Training erst nach dem Beenden.

## Bedienung

- **T-80** Sehr große Schrift (Einstellungen → Anzeige) → Today, Plus-Menü, Food und Live-Training bleiben lesbar, Knöpfe erreichbar.
- **T-81** 📱 VoiceOver an → Ringwerte, Plus-Kacheln und aktueller Satz werden verständlich vorgelesen.
- **T-82** Bewegung reduzieren an → Plus-Menü blendet nur ein, Health-Age-Punkte stehen still.
- **T-83** Vom linken Rand wischen und Blätter nach unten ziehen → zurück bzw. geschlossen, überall.
