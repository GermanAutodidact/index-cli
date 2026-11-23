---
name: index
description: Lokales, token-minimales Issue-Tracking via CLI im TOON-Format mit Zwei-Wege-GitHub-Sync. Immer nutzen, um Aufgaben abzurufen, zu starten, neu anzulegen, zu blockieren, zu pushen oder abzuschließen.
---

# Agent-Instruktion: `index`

Verwalte Aufgaben ausschließlich über das CLI-Tool `index` und die Markdown-Dateien unter `.issues/`. Nutze keine MCP-Tracker.

## Systemregeln & Datenformat
- **Speicherort:** Offene Tickets liegen unter `.issues/open/<id>-<slug>.md`, erledigte unter `.issues/closed/`.
- **Abhängigkeiten:** Das Frontmatter-Feld `blocked_by: [id]` sperrt ein Ticket automatisch (auch bei `index start`), bis alle gelisteten IDs geschlossen sind.
- **Single-WIP-Constraint:** Es darf immer nur exakt ein Ticket den Status `in_progress` haben.

## Zwingender Ablauf pro Session

1. **Abgleich & Auswahl:**
   Führe zu Beginn immer aus:
   ```bash
   index sync && index ready --toon
   ```
   *(Falls kein GitHub-Repo verbunden ist, nutze direkt `index ready --toon`.)*
   Die Ausgabe folgt dem Schema `issues{id,status,prio,file,title}:` und ist nach aktivem Status und Priorität (`high -> med -> low`) sortiert.

2. **Ticket aktivieren & lesen:**
   - Wähle das oberste Ticket (oder führe ein bereits auf `in_progress` stehendes Ticket zu Ende).
   - Aktiviere es:
     ```bash
     index start <id>
     ```
   - Lies **nur** die in `file` angegebene Markdown-Datei (oder nutze `index show <id>`). Lies niemals pauschal alle Dateien in `.issues/open/`.

3. **Neue Aufgaben & Abhängigkeiten verwalten:**
   Entdeckst du während der Arbeit einen separaten Bug oder eine Teilaufgabe, lege ein eigenes Ticket an, statt den aktuellen Scope zu erweitern:
   ```bash
   index new "Präziser Titel" -prio med
   index block <id> -by <blockerId1,blockerId2>
   index unblock <id> [-by <blockerId>]
   index push [<id>] [--all]
   ```

4. **Abschluss & Session-Ende:**
   Nach erfolgreicher Umsetzung und Prüfung schließe das Ticket mit einer knappen technischen Zusammenfassung:
   ```bash
   index close <id> -note "Zusammenfassung der Änderung und betroffenen Dateien."
   ```
   Beende danach deine Antwort, damit das Kontextfenster auf 0 % zurückgesetzt werden kann.
