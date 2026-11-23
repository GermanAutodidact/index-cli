# `index` CLI v2.1

Zero-Dependency Local-First Issue-Tracker für Windows 11 (PowerShell 5.1 & PowerShell 7) mit **TOON-Format** für KI-Agenten, **Abhängigkeitsverwaltung (inkl. Zyklenschutz)** und **4-Wege-GitHub-Issues-Sync**.

---

## Features

- **Zero Dependencies:** Läuft nativ auf Windows (PowerShell 5.1 oder `pwsh` 7+). GitHub-Sync nutzt optional die offizielle [`gh` CLI](https://cli.github.com/).
- **Token-minimales `--toon`-Format:** Kompaktes `issues{id,status,prio,file,title}:`-Format für Agenten und LLMs — ohne Markdown-Overhead im Kontextfenster.
- **4-Wege-GitHub-Sync (`index sync`):**
  1. Importiert neue offene GitHub-Issues nach `.issues/open/`.
  2. Aktualisiert geänderte Titel & Prioritäten bestehender lokaler Tickets.
  3. Verschiebt auf GitHub geschlossene Issues automatisch nach `.issues/closed/`.
  4. Reaktiviert auf GitHub wiedergeöffnete Issues zurück nach `.issues/open/`.
- **Offline-First & `index push`:** Offline erstellte Tickets erhalten kollisionsfreie IDs ab `10000` (`local_only: true`). Mit `index push` lassen sie sich nachträglich auf GitHub anlegen — inklusive automatischem Umbenennen und **Dependency-Rewriting** aller `blocked_by`-Verweise.
- **Abhängigkeiten mit DAG-Zyklenschutz:** `index block <id> -by <id1,id2>` verhindert Selbst-Blockierungen und zirkuläre Abhängigkeitsketten. `index close` zeigt automatisch an, welche Tickets dadurch freigeschaltet (`unblocked`) wurden.
- **Single-WIP-Constraint:** `index start <id>` erlaubt genau ein aktives `in_progress`-Ticket gleichzeitig.
- **Dual-Flag-Parser:** Versteht sowohl PowerShell-Syntax (`-prio high`, `-toon`, `-by 1,2`) als auch POSIX-Syntax (`--prio=high`, `--toon`, `--blocked-by 1,2`).

---

## Installation (Einzeldatei-Installer)

```powershell
git clone https://github.com/GermanAutodidact/index-cli.git
cd index-cli
.\install-index-v2.ps1
```

Nur global installieren (ohne `.issues/` und `.agents/skills/index/SKILL.md` im aktuellen Ordner anzulegen):

```powershell
.\install-index-v2.ps1 -GlobalOnly
```

Der Installer legt `index-cli.ps1` und `index.cmd` unter `%LOCALAPPDATA%\Programs\index` ab, entfernt ggf. eine veraltete `index.ps1` (um PowerShell-Command-Discovery- und ExecutionPolicy-Probleme zu vermeiden) und ergänzt den Benutzer-`PATH`.

---

## Befehlsübersicht

| Befehl | Beschreibung |
| :--- | :--- |
| `index init [--skill]` | Initialisiert `.issues/open` & `.issues/closed` (mit `--skill` auch `.agents/skills/index/SKILL.md`). |
| `index sync` | 4-Wege-Abgleich mit GitHub Issues (neu, geändert, geschlossen, wiedergeöffnet). |
| `index ready [--toon]` | Zeigt sofort startbare (unblockierte) Tickets als Tabelle oder kompaktes TOON. |
| `index status [--toon]` | Kompakte Projekt-Übersicht (`open`, `ready`, `blocked`, `closed`, `local_only`, `active_id`). |
| `index show <id>` | Zeigt Metadaten (inkl. Blocker-Status) und vollständigen Ticket-Body. |
| `index new "Titel" [-prio high\|med\|low] [-body "..."] [-by 1,2] [-offline]` | Erstellt ein Ticket auf GitHub (oder offline ab `#10000`). |
| `index start <id>` | Aktiviert Ticket als `in_progress` (prüft Blocker & Single-WIP). |
| `index close <id> [-note "..."]` | Schließt Ticket lokal und auf GitHub; meldet neu freigeschaltete Tickets. |
| `index reopen <id> [-note "..."]` | Öffnet ein geschlossenes Ticket lokal und auf GitHub erneut. |
| `index block <id> -by <id1,id2>` | Fügt Blocker hinzu (inkl. Self-Block- & Zyklusprüfung). |
| `index unblock <id> [-by <id1,id2>]` | Entfernt angegebene oder alle Blocker eines Tickets. |
| `index push [<id>] [--all]` | Lädt Offline-Tickets (`>=10000`) zu GitHub hoch inkl. Dependency-Rewriting. |
| `index help` | Zeigt die Befehlsübersicht an. |

---

## Beispiel-Workflow für KI-Agenten

```bash
index init --skill
index sync
index ready --toon
index start 12
index show 12
index close 12 -note "Parser für Sonderzeichen und Backslashes korrigiert."
```

## Tests lokal ausführen

```powershell
pwsh -NoProfile -File .\tests\test-index.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-index.ps1
```

## Lizenz

[MIT](LICENSE)
