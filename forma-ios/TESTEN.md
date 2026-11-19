# Health – Testplan fürs iPhone

## So installierst du

1. Verbinde dein iPhone per USB mit dem PC. Bestätige „Diesem Computer vertrauen?“, falls gefragt.
2. Öffne Sideloadly, wähle dein iPhone und zieh `Health.ipa` aus **Downloads** ins Fenster.
3. Nutze deine kostenlose Apple-ID und klicke auf **Start**. [Sideloadly](https://sideloadly.io/)
4. Aktiviere bei Bedarf auf dem iPhone unter **Einstellungen → Datenschutz & Sicherheit** den **Entwicklermodus**. Starte das iPhone neu und bestätige. [Apple](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
5. Öffne **Health**. Mit einer kostenlosen Apple-ID gilt die Signatur sieben Tage. Danach kannst du die App mit derselben Apple-ID erneut signieren. [Sideloadly-FAQ](https://sideloadly.io/faq)

📱 = nur auf einem echten iPhone testen. Du kannst mit Beispieldaten anfangen. Bei Tests zum dauerhaften Speichern, zu Google Health und zu iPhone-Anzeigen nutze den Modus ohne Beispieldaten. Wenn etwas hakt, notiere die Testnummer und was du siehst, etwa **T-05 – Anmeldung bricht ab**.

## Start und Google Health

- **T-01** 📱 Öffne **Health** über das App-Symbol → Auf einem frischen Stand erscheint die Auswahl zwischen Google Health und Beispieldaten.
- **T-02** Tippe auf „Erst mit Beispieldaten ansehen“ → Today öffnet sich mit dem Hinweis „Beispieldaten“. Training, Health und Coach sind erreichbar.
- **T-03** 📱 Öffne Health nach einem Update mit derselben Apple-ID → Deine bisherigen Routinen und Trainings sind weiter da.
- **T-04** 📱 Öffne Profil → „Mit Google Health verbinden“. Brich die Anmeldung ab → Du landest wieder in Health. Google Health bleibt getrennt und du kannst es erneut versuchen.
- **T-05** 📱 Verbinde ein Google-Konto mit Messwerten und erlaube den Zugriff → Der Status zeigt die Verbindung. Schritte und Schlaf erscheinen für die passenden Tage, sofern Google sie liefert.
- **T-06** 📱 Tippe im Profil auf „Jetzt aktualisieren“ → Bei Erfolg erscheint der neue Abrufstand. Vergleiche die Schritte eines abgeschlossenen Tages mit Google Health.
- **T-07** 📱 Schalte nach einem Abruf am selben Tag WLAN und mobile Daten aus. Öffne Health neu und versuche zu aktualisieren → Die zuletzt geladenen Werte bleiben sichtbar. Der Abrufstand springt bei Fehlern nicht auf jetzt.
- **T-08** 📱 Lass Health mit erlaubter Hintergrundaktualisierung über Nacht im Hintergrund → Prüfe morgens den Abrufstand im Profil. Eine Uhrzeit vor dem Öffnen zeigt, dass Health im Hintergrund abgerufen hat.
- **T-09** 📱 Tippe auf „Google Health trennen“ und bestätige → Die importierten Messwerte verschwinden. Verbinde Google Health wieder, bevor du mit eigenen Werten weiter testest.

## Today

- **T-10** Tippe nacheinander auf **Strain**, **Recovery** und **Sleep** → Jeder Ring öffnet sein eigenes Detail mit Verlauf und Erklärung.
- **T-11** Öffne **Sleep** mit Daten für eine Nacht → Beginn, Ende und Schlafphasen passen zu der aufgezeichneten Nacht.
- **T-12** Scrolle auf Today nach unten und tippe auf die kleine Leiste mit den Tageswerten → Die Ansicht springt zurück nach oben.
- **T-13** Tippe auf den Coach-Hinweis und danach auf die Schritte unter „Kennzahlen“ → Der Hinweis öffnet Coach. Die Schritte öffnen ihren Verlauf.
- **T-14** Öffne den Stress Monitor und zieh über die Kurve → Die Uhrzeit und der geschätzte Stress erscheinen. Stunden ohne Messung bleiben leer.
- **T-15** Tippe unten auf „Anpassen“. Zieh eine Kachel am Griff und blende eine per Minus aus → Nach „Fertig“ bleibt die neue Reihenfolge. Über „Anpassen“ und Plus holst du die Kachel zurück.

## Plus, Essen und Getränke

- **T-16** Tippe im Coach-Tab auf **+** und zieh das Menü nach unten zu → Es zeigt Essen, Wasser, Fasten, Gewicht und Training. Danach bist du wieder im Coach-Tab.
- **T-17** Tippe auf **+ → Essen suchen**. Suche nach Haferflocken, wähle einen Treffer und trage 50 g ein → Das Produkt steht unter der gewählten Mahlzeit in „Ernährung heute“. Die Nährwerte passen zur Menge.
- **T-18** Tippe bei einem Produkt ins Mengenfeld und gib 0 ein → „Eintragen“ ist gesperrt. Mit einer gültigen Menge kannst du fortfahren.
- **T-19** Wische in „Ernährung heute“ einen Testeintrag nach links und tippe auf „Löschen“ → Der Eintrag verschwindet und die Tagessumme sinkt um seinen Anteil.
- **T-20** 📱 Tippe auf **+ → Mahlzeit scannen → Kamera starten**. Zeig einen bekannten Produktbarcode → Das passende Produkt öffnet sich mit Menge und Nährwerten.
- **T-21** 📱 Lehne die Kamera-Freigabe beim Scannen ab → Health erklärt, wie du den Zugriff erlauben kannst. Die Suche nach Produktnamen bleibt bedienbar.
- **T-22** 📱 Tippe auf **+ → Essen fotografieren**. Erteile die Foto-Freigabe für Essen, wenn der Online-Coach eingerichtet und erlaubt ist → Nach der Aufnahme erscheinen bei erfolgreicher Analyse geschätzte Lebensmittel und Mengen. Du kannst sie ändern und erst dann eintragen.
- **T-23** 📱 Öffne **+ → Essen fotografieren** ohne Freigabe für Essensfotos → Health zeigt, welche Freigabe fehlt. Das Öffnen allein sendet kein Foto.
- **T-24** Tippe auf **+ → Wasser → Glas · 250 ml** und dann auf das Minus → Die Menge steigt um 250 ml und sinkt wieder auf den alten Stand.
- **T-25** Tippe auf **+ → Fasten**, wähle **16:8** und starte den Timer. Öffne die Ansicht neu und beende das Fasten → Die laufende Zeit bleibt erhalten. Danach steht der Versuch im Verlauf.
- **T-26** Tippe auf **+ → Gewicht**, trage einen gültigen Messwert ein und sichere ein Ziel → Der Messwert steht im Verlauf. Die Anzeige zeigt den Abstand zum Ziel.

## Training

- **T-27** Tippe auf „Neue Routine“, gib ihr einen Namen und füge zwei Übungen hinzu → Zurück unter „Routinen“ steht der neue Plan mit beiden Übungen.
- **T-28** Öffne deine Routine und tippe auf „Training starten“ → Das Live-Training zeigt die erste Übung und den ersten Satz.
- **T-29** Ändere Gewicht und Wiederholungen. Tippe schnell zweimal auf „Satz abschließen“ → Ein Satz wird abgehakt und der Pausentimer startet.
- **T-30** Tippe in der Pause auf „+15 s“ und dann auf „Pause beenden“ → Der Timer gewinnt 15 Sekunden und endet beim zweiten Knopf sofort.
- **T-31** Wische die App bei laufendem Training aus der App-Übersicht und öffne sie erneut → Der Entwurf öffnet sich mit den bereits erfassten Sätzen.
- **T-32** Tippe nach erledigten Sätzen auf „Training beenden“ oder „Beenden → Speichern und beenden“ → Die Zusammenfassung zeigt die Sätze. Im Verlauf steht das Training einmal.
- **T-33** Öffne „Kalender und alle Trainings“ und tippe auf den Tag mit deinem Training → Die Liste zeigt die Einheiten dieses Tages. Ein Tipp öffnet die Zusammenfassung.
- **T-34** Öffne nach einem erfassten Training „Muskeln, 7 Tage“ und tippe auf einen markierten Muskel → Die Karte zeigt die Belastung der Woche. Der Muskel öffnet passende Übungen.
- **T-35** Öffne in der Übungsbibliothek eine bekannte Übung und tippe auf „Ausführung“ und „Verlauf“ → Du siehst die Muskelkarte und Anleitung. Im Verlauf stehen vorhandene Trainings oder ein Hinweis auf fehlende Daten.
- **T-36** Tippe in der Übungsbibliothek auf **+**, lege eine eigene Übung an und füge sie einer Routine hinzu → Die Übung ist in der Suche auffindbar und auswählbar.
- **T-37** Tippe auf „Freies Training“, füge eine Übung und einen Satz hinzu → Du kannst beide direkt im Live-Training bearbeiten.
- **T-38** Tippe bei einer Routine mit Übungen auf **+ → Training starten** → Die im Menü genannte Routine startet direkt.
- **T-39** 📱 Tippe in der Pause auf „Bei Pausenende benachrichtigen“. Erlaube Mitteilungen und sperre das iPhone → Bei Ablauf kommt die Pausenmeldung.

## Health und Health Age

- **T-40** Öffne **Health** mit Beispieldaten und tippe auf „Health Age“ → Oben steht das geschätzte Alter. Die Details zeigen Vergleich, Einflussfaktoren, Datenabdeckung und Quellen.
- **T-41** Öffne **Health** mit eigenen Daten ohne Geburtsjahr und tippe auf „Geburtsjahr eintragen“ → Das Profil öffnet sich. Im Health-Tab steht bis zur Angabe ein Hinweis statt einer Alterszahl.
- **T-42** Öffne **Health** mit eingetragenem Geburtsjahr, aber zu wenigen Messungen → Health Age zeigt, wie viele Messtage für die erste Schätzung noch fehlen.
- **T-43** Tippe unter „Biomarker“ auf Ruhepuls. Wechsle zwischen 7, 30 und 90 Tagen und zieh über das Diagramm → Zeitraum und Zusammenfassung wechseln. Tage ohne Wert zeigen „keine Messung“.
- **T-44** Tippe auf „Health Monitor“ → Du siehst die vorhandenen Messwerte mit ihrem persönlichen Bereich. Ohne genügend Messungen steht „Noch kein Vergleich“.

## Coach und Lumo

- **T-45** Öffne **Coach** und tippe auf eine Einstiegsfrage → Lumo bleibt sichtbar. Auf die Frage folgt eine Antwort auf Deutsch.
- **T-46** Sende eine Frage ohne Internet mit ausgeschalteter Online-Freigabe → Der Coach antwortet auf dem iPhone.
- **T-47** Sende bei eingerichtetem Online-Coach erstmals eine Frage und tippe auf „Nur lokal antworten“ → Die App erklärt vorab die Datenfreigabe. Danach kommt die lokale Antwort.
- **T-48** Tippe im Chat auf „Foto hinzufügen → Fotos“. Wähle ein Bild und entferne es vor dem Senden → Die Vorschau erscheint und lässt sich wieder entfernen.
- **T-49** 📱 Tippe im Chat auf „Foto hinzufügen → Kamera“. Nimm ein Foto auf und sende es bei eingerichtetem Online-Coach erstmals → Das Bild erscheint als Vorschau. Vor dem Senden fragt Health nach der Foto-Freigabe. Bei Freigabe erscheint das Foto im Chat.
- **T-50** Tippe bei einem Trainingsvorschlag auf „Übernehmen“ und danach auf „Rückgängig“ → Der Vorschlag gilt zunächst fürs nächste Training heute und ist danach wieder weg.
- **T-51** 📱 Erlaube Mitteilungen und lass Health über Nacht im Hintergrund → Wenn Health am Morgen neue Schlafdaten abruft, erscheint der Tagesbericht einmal. Die Standardmeldung enthält keine Messwerte.
- **T-52** 📱 Stelle bei erlaubten Mitteilungen und vorhandenem Schlafbedarf im Profil die Weckzeit ein → Rund 30 Minuten vor der vorgeschlagenen Bettzeit kommt eine Erinnerung.

## Profil und Body

- **T-53** Tippe aufs Profilsymbol → „Body“. Setze Geburtsjahr und Geschlecht, speichere Größe und Gewicht → Die Angaben sind beim erneuten Öffnen da.
- **T-54** Stell unter **Body → Einheiten** von Kilogramm auf Pfund um → Das Training zeigt die Gewichte in lb.
- **T-55** Wähle ein Profilbild aus „Fotos“ und öffne die App neu → Das Bild bleibt am Profilsymbol. Über „Bild entfernen“ kannst du es löschen.
- **T-56** Schalte „Beispieldaten zeigen“ ein und wieder aus → Die Beispielwerte sind klar gekennzeichnet. Danach siehst du wieder deinen eigenen Stand.
- **T-57** Tippe unter „Freigaben“ auf „Fragen an den Online-Coach“, wenn sie erteilt ist → Die Freigabe wird widerrufen. Der Coach antwortet wieder lokal und Online-Fotos brauchen erneut eine Freigabe.

## Widgets, Live Activity und Siri

- **T-58** 📱 Füge das kleine oder mittlere Health-Widget „Today“ zum Homescreen hinzu → Mit geladenen Google-Daten stimmen die angezeigten Ringwerte mit Today überein.
- **T-59** 📱 Füge „Today“ zum Sperrbildschirm hinzu und schalte danach Beispieldaten ein → Sobald sich das Widget aktualisiert, zeigt es „Keine Messung“.
- **T-60** 📱 Starte ein Training mit ausgeschalteten Beispieldaten und schließe einen Satz ab. Sperre das iPhone → Die Live Activity zeigt die laufende Pause. Nach Trainingsende verschwindet sie.
- **T-61** 📱 Füge im Kontrollzentrum „Training starten“ von Health hinzu und tippe darauf → Health startet das nächste Training. Ohne Routine startet ein freies Training.
- **T-62** 📱 Sag „Siri, Training mit Health starten“ → Health öffnet das Training. Erneutes Aufrufen startet kein zweites.
- **T-63** 📱 Sag „Siri, wie ist meine Erholung in Health?“ → Nach dem Entsperren nennt Siri den heutigen Wert samt Uhrzeit oder meldet, dass keine Messung vorliegt.
- **T-64** 📱 Sag „Siri, Essen mit Health scannen“ → Health öffnet die Barcode-Ansicht.

## Bedienung

- **T-65** Stell in iOS eine sehr große Schrift ein. Öffne Today, das Plus-Menü und ein Live-Training → Texte bleiben lesbar und die wichtigen Knöpfe erreichbar.
- **T-66** 📱 Schalte VoiceOver ein und streiche durch Today, das Plus-Menü und das Live-Training → VoiceOver liest Ringwerte, Knöpfe und den Stand des aktuellen Satzes verständlich vor.
