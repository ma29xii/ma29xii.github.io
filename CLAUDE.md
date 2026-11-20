# Health (Forma) · Einstieg für Claude Code

Claude Code entwickelt die iOS-App **Health** (Code-Name Forma) seit dem 20. November 2026 **allein** weiter (Maxis Entscheidung; KI-Team-Modus `nur-claude` in `C:\Users\maxi\KI-Team\modus.txt`). Codex wird nicht gestartet. Parallele Arbeit nur über weitere Claude-Sessions mit getrennten Dateien.

## Reihenfolge beim Start

1. [HANDOVER.md](HANDOVER.md) lesen – aktueller Stand, Build, Google-Health-Test, Code-Einstiege, offene iPhone-Prüfungen.
2. [AGENTS.md](AGENTS.md) lesen – Design-Regeln, Build/CI, Swift-6-Fallen, Regeln für alle Agenten. Die dortigen Abschnitte zur 50/50-Aufteilung mit Codex gelten nur für frühere Runden.
3. `C:\Users\maxi\KI-Team\WISSEN.md` (gemeinsames Wissen, Swift-Fallen) und das Postfach: `python -I -X utf8 C:\Users\maxi\KI-Team\team.py liste`.
4. Lokaler Übergabeordner: `.teamarbeit/uebergabe-claude/START-HIER.md` (Build-5-IPA, Referenzbild, kurzer Prompt). `.teamarbeit/` ist per `.git/info/exclude` nicht im Repo.
5. `git status --short --branch` und `git log -12 --oneline` – fremde, uncommittete Änderungen anderer Sessions nie mitcommitten.

## Feste Regeln (Kurzfassung)

- Sprache Deutsch, du-Form; Berichte an Maxi in drei nummerierten Punkten, nächste Aktion oben.
- Branch `claude/awesome-hypatia-tnhuis`, Repo `ma29xii/ma29xii.github.io`. Kein Xcode unter Windows: Build, Unit-Tests und UI-Rundgang nur über GitHub Actions (`.github/workflows/forma-ios.yml`). Eine IPA erst als geprüft ausgeben, wenn sie zum genannten Commit gehört.
- Nur eigene Dateien committen (`git add <pfade>`), `git pull --rebase --autostash`, dann `git push`.
- Keine Schlüssel, Tokens, `.env`, `coach-keys.json` lesen oder ausgeben. Kein `taskkill`/`Stop-Process`.
- Design: keine Chevrons, keine Erklärtexte, „Anpassen“ unten, Tabs/Ringnamen Englisch, sonst Deutsch, Dynamic Type, VoiceOver, 44-pt-Ziele, „Bewegung reduzieren“.
