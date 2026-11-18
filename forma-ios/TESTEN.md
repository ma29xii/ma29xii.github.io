# Health – Stand und Testplan

Die App hieß früher Forma. Auf dem iPhone heißt sie jetzt **Health**.
Bundle-ID (`com.ma29xii.forma`) und Code-Namen bleiben gleich, damit deine Daten beim Update erhalten bleiben.

## A. Was fertig ist

- [x] Native iPhone-App (SwiftUI, iOS 26, Liquid Glass), Bau per GitHub-CI als `Forma.ipa` (Artifact „Forma-IPA“)
- [x] **Heute:** 3 Ringe (Belastung, Erholung, Schlaf), Zielbogen, Kacheln verschiebbar (Coach, Als Nächstes, Energie & Stress, Körper, Tag, Woche, Körperalter, Einblick)
- [x] **Detailseiten** für Erholung, Schlaf (Hypnogramm, Phasen, Bettzeit) und Belastung
- [x] **Training:** Routinen, Routineneditor, Übungsbibliothek, eigene Übungen, Live-Training, Pausentimer, Steigerungsvorschlag, Scheibenrechner, Zusammenfassung mit 1RM, Verlauf, Wiederherstellung nach Absturz
- [x] **Gesundheit:** Messwerte mit Diagrammen (7/14/30 Tage), Körperalter mit offengelegter Methode und Quellen
- [x] **Coach:** lokal auf dem iPhone, optional Claude mit eigenem API-Schlüssel und Zustimmung, Vorschläge nur für heute
- [x] **Coach im Hintergrund:** Morgenbericht, Erinnerung zur Schlafenszeit, Weckzeit im Profil
- [x] **Journal:** Ja/Nein-Fragen, „wie am Vortag“
- [x] **Profil:** Datenquelle, Über dich, Einheiten, Mitteilungen, Synchronisieren, lokale Kopie löschen
- [x] **Apple Health:** nur lesen, 180 Tage, Hintergrund-Abruf, lokale Kopie für Offline-Start
- [x] Codex-Review 01 und 02 umgesetzt, Antworten in `reviews/`
- [x] Umbenennung in „Health“

## B. Was noch offen ist

- [ ] **Grüner CI-Build** für den aktuellen Stand (der letzte grüne Build ist älter)
- [ ] **Test auf deinem iPhone 18 Pro** (dieser Plan, Runde 1)
- [ ] HealthKit mit kostenloser Apple-ID über Sideloadly: noch nicht bestätigt (T-03)
- [ ] Mitteilungen auf dem gesperrten iPhone (T-50 bis T-53), geht nur am echten Gerät
- [ ] Coach mit echtem Claude-Schlüssel (T-45)
- [ ] Codex-Review Runde 03
- [ ] Google-Health-Anbindung (Fitbit-Ersatz): braucht dein Google-Cloud-Projekt
- [ ] Später: Homescreen-Widget, Live Activity für die Pause

## C. So läuft eine Testrunde

1. Claude baut die neue Version und spielt sie per Sideloadly auf dein iPhone.
2. Du gehst die Tests unten durch. Was nicht passt, schreibst du kurz so: **„T-14: Knopf zu klein“**. Ein Screenshot hilft.
3. Claude behebt alles, baut neu, und die nächste Runde startet. Getestet werden dann nur die geänderten Stellen und T-01 bis T-05.

Bewertung pro Test: ✅ passt · ⚠️ geht, sieht aber falsch aus · ❌ kaputt.

## D. Testplan, Runde 1

### Start und Daten
| Nr. | Was du tust | Was passieren soll |
|---|---|---|
| T-01 | App-Symbol auf dem Homescreen ansehen | Name darunter: **Health** |
| T-02 | App zum ersten Mal öffnen | „Willkommen bei Health“, Knopf für Apple Health und „Erst mit Beispieldaten ansehen“ |
| T-03 | Apple Health verbinden, alle Kategorien erlauben | Kein Absturz. Danach erscheinen echte Werte, oben kein Hinweis „Beispieldaten“ |
| T-04 | App schließen (wegwischen), neu öffnen | Startet sofort mit den letzten Werten, kein leerer Bildschirm |
| T-05 | Profil → „Jetzt synchronisieren“ | Kurze Ladeanzeige, danach „Stand“ mit aktueller Uhrzeit |

### Heute
| Nr. | Was du tust | Was passieren soll |
|---|---|---|
| T-10 | Ringe oben ansehen | Erholung groß in der Mitte, Belastung links, Schlaf rechts, Zahlen 0–100. Werte passen grob zu deinem Gefühl |
| T-11 | Nach unten scrollen | Ringe werden klein und bleiben oben in der Leiste |
| T-12 | Auf jeden Ring tippen | Detailseite öffnet sich: Erholung, Schlaf, Belastung |
| T-13 | Jede Kachel einmal antippen (Coach, Als Nächstes, Energie & Stress, Körper, Tag, Woche, Körperalter, Einblick) | Jede öffnet das Passende oder zeigt sinnvollen Inhalt. Kein leerer oder kaputter Text |
| T-14 | Eine Kachel lange drücken und an eine andere Stelle ziehen | Kachel bewegt sich, neue Reihenfolge bleibt nach App-Neustart |
| T-15 | Lange drücken → Kontextmenü: Nach oben, Nach unten, Ausblenden | Jede Aktion wirkt sofort |
| T-16 | Ganz unten „Heute anpassen …“: ausblenden, einblenden, „Standard“ | Liste funktioniert, „Standard“ fragt nach und stellt alles zurück |

### Detailseiten
| Nr. | Was du tust | Was passieren soll |
|---|---|---|
| T-20 | Erholung: „Was beiträgt“ lesen | HRV, Ruhepuls, Schlaf mit Plus/Minus-Punkten, nichts abgeschnitten |
| T-21 | Schlaf: Verlauf der Nacht und Phasen | Hypnogramm stimmt grob mit der Apple-Health-Nacht überein (Uhrzeit, Dauer) |
| T-22 | Schlaf: „Ins Bett“ und Schlafbedarf | Bettzeit passt zur Weckzeit im Profil |
| T-23 | Schlaf: „Letzte 7 Nächte“ | Fehlende Nächte zählen nicht ins Mittel, Text „x von 7 Nächten“ |
| T-24 | Belastung: Aktivitäten heute, Schritte, aktive Energie | Werte stimmen mit Apple Health überein |

### Training
| Nr. | Was du tust | Was passieren soll |
|---|---|---|
| T-30 | Training → „Neue Routine“, 2 Übungen, Sätze/Wdh/Gewicht/Pause einstellen, „Sichern“ | Routine erscheint in der Liste |
| T-31 | Routine öffnen, ändern, sichern. Dann „Routine löschen“ | Änderung bleibt, Löschen fragt nach |
| T-32 | Übungsbibliothek: Übung ansehen, „Eigene Übung“ anlegen | Eigene Übung ist danach auswählbar |
| T-33 | Routine starten | Live-Training öffnet sich, **keine** Systemabfrage für Mitteilungen |
| T-34 | Gewicht und Wdh mit +/− ändern, Reserve wählen, Satz abschließen | Satz ist abgehakt, Pause startet |
| T-35 | In der Pause: „+15 s“, „Pause beenden“, „Bei Pausenende benachrichtigen“ | Timer reagiert. Erst der Knopf fragt nach der Mitteilungs-Erlaubnis |
| T-36 | Pause laufen lassen, iPhone sperren | Am Pausenende kommt eine Mitteilung „Pause vorbei“ (wenn erlaubt) |
| T-37 | Schnell zweimal auf „Satz abschließen“ tippen | Es wird nur **ein** Satz abgeschlossen |
| T-38 | „Satz hinzufügen“, „Übung hinzufügen“ | Neuer Satz bzw. neue Übung erscheint und ist bedienbar |
| T-39 | Scheibenrechner ansehen (z. B. 60 kg) | „Pro Seite“ mit Einheit, rechnet mit 20-kg-Stange |
| T-40 | Steigerungsvorschlag „Übernehmen“ (ab dem 2. Training derselben Routine) | Gewicht ändert sich nur nach Tippen |
| T-41 | Mitten im Training App wegwischen, neu öffnen | Training wird wiederhergestellt, kein Satz fehlt |
| T-42 | „Training beenden“ → Zusammenfassung | Volumen, Sätze, 1RM, Vergleich zum letzten Mal. Training erscheint im Verlauf und **einmal**, nicht doppelt |
| T-43 | Training im Verlauf öffnen → „Training löschen“ | Fragt nach, danach weg |
| T-44 | Freies Training ohne Satz beenden | App bietet kein „fertig“ an bzw. verwirft sauber |

### Coach
| Nr. | Was du tust | Was passieren soll |
|---|---|---|
| T-45 | Coach-Tab: eine der Einstiegsfragen antippen | Sinnvolle Antwort auf Deutsch, passend zu deinen Werten |
| T-46 | Eigene Frage eintippen, senden | Antwort kommt. Ohne Schlüssel steht „lokal“ dabei |
| T-47 | (optional) Profil → Claude-Schlüssel eintragen, Frage senden | Erst kommt die Zustimmungsfrage, danach antwortet Claude |
| T-48 | Trainingsvorschlag annehmen, „Rückgängig“ | Gilt nur für heute, die Routine bleibt unverändert |

### Gesundheit und Körperalter
| Nr. | Was du tust | Was passieren soll |
|---|---|---|
| T-55 | Gesundheit: jede Messwert-Zeile antippen | Diagramm mit 7/14/30 Tagen, Finger auf Diagramm zeigt Tageswert, in Lücken „keine Messung“ |
| T-56 | Körperalter öffnen (Geburtsjahr nötig, sonst „Im Profil eintragen“) | Geschätztes Alter, Faktoren, Datenabdeckung, Methode mit Quellen |
| T-57 | Kacheln in Gesundheit und Training verschieben | Wie T-14 |

### Journal und Profil
| Nr. | Was du tust | Was passieren soll |
|---|---|---|
| T-60 | Journal öffnen, Fragen mit Ja/Nein beantworten, „Fertig“ | Antworten bleiben nach Neustart |
| T-61 | „Offene wie am Vortag ausfüllen“ | Übernimmt nur, wenn es gestern Antworten gab, und zeigt wie viele |
| T-62 | Profil: Geburtsjahr, Geschlecht, Gewicht kg/lb | Einheit ändert sich überall (Training, Zusammenfassung) |
| T-63 | Profil: Quelle wechseln (Automatisch / Apple Health / Beispieldaten) | Daten wechseln sofort, Beispieldaten sind klar gekennzeichnet |
| T-64 | „Lokale Kopie der Apple-Health-Daten löschen“ | Fragt nach, danach lädt die App neu aus Apple Health |

### Hintergrund und Mitteilungen (über 1–2 Tage)
| Nr. | Was du tust | Was passieren soll |
|---|---|---|
| T-50 | Profil: Mitteilungen erlauben, Morgenbericht an, Weckzeit stellen | Erlaubnis-Dialog nur jetzt |
| T-51 | Mit Uhr schlafen, morgens App **nicht** öffnen | Morgens Mitteilung „Dein Tagesbericht ist bereit“, ohne Gesundheitswerte |
| T-52 | Abends | Erinnerung etwa 30 min vor der Bettzeit |
| T-53 | App öffnen nach der Nacht | Neue Nacht ist schon da, ohne Warten |

### Aussehen und Bedienung (überall nebenbei)
| Nr. | Was du prüfst | Was passieren soll |
|---|---|---|
| T-70 | Texte | Deutsch, du-Form, nichts abgeschnitten, keine „…“ mitten im Wort |
| T-71 | Einstellungen → Anzeige → Textgröße groß | Alles noch lesbar und bedienbar, besonders das Trainings-Dock |
| T-72 | Bedienung mit einer Hand | Wichtige Knöpfe unten erreichbar, nichts zu klein |
| T-73 | Allgemeiner Eindruck | Ruhig, modern, eigenständig. Was dich stört, einfach notieren |
