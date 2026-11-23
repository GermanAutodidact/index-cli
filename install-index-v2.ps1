# ==============================================================================
# index v2.1 - Single-File Installer & CLI (Zero Dependencies für Windows 11)
# ==============================================================================
param(
    [switch]$GlobalOnly,
    [switch]$NoSkill
)

$ErrorActionPreference = "Stop"
$InstallDir = "$env:LOCALAPPDATA\Programs\index"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Veraltete index.ps1 entfernen, damit PowerShell immer index.cmd auflöst
$LegacyPs1 = Join-Path $InstallDir "index.ps1"
if (Test-Path -LiteralPath $LegacyPs1) {
    Remove-Item -LiteralPath $LegacyPs1 -Force
}

$CliCode = @'
# ==============================================================================
# index v2.1 - Zero-Dependency Issue-Tracker CLI (PowerShell 5.1 & 7)
# ==============================================================================
$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$ScriptVersion = "2.1.0"
$dirOpen = ".issues\open"
$dirClosed = ".issues\closed"

function Fail([string]$msg) {
    [Console]::Error.WriteLine("error: $msg")
    exit 1
}

function Safe-Trim($val) {
    if ($null -eq $val) { return "" }
    return ([string]$val).Trim()
}

function Resolve-ProjectPath([string]$path) {
    if ([System.IO.Path]::IsPathRooted($path)) { return $path }
    return (Join-Path (Get-Location).Path $path)
}

function Get-RelPath([string]$fullPath) {
    $cwd = (Get-Location).Path.TrimEnd('\', '/')
    $normFull = $fullPath -replace '/', '\'
    if ($normFull.StartsWith($cwd + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($normFull.Substring($cwd.Length + 1) -replace '\\', '/')
    }
    return ($normFull -replace '\\', '/')
}

function Ensure-Dirs {
    New-Item -ItemType Directory -Force -Path (Resolve-ProjectPath $dirOpen) | Out-Null
    New-Item -ItemType Directory -Force -Path (Resolve-ProjectPath $dirClosed) | Out-Null
}

function Get-Slug([string]$text) {
    $norm = $text.ToLower()
    $norm = $norm -replace 'ä', 'ae' -replace 'ö', 'oe' -replace 'ü', 'ue' -replace 'ß', 'ss'
    $s = ($norm -replace '[^a-z0-9]+', '-').Trim('-')
    if ($s.Length -gt 40) { $s = $s.Substring(0, 40).TrimEnd('-') }
    if ([string]::IsNullOrWhiteSpace($s)) { return "task" }
    return $s
}

function Sanitize-Title([string]$text) {
    if ($null -eq $text) { return "" }
    return (($text -replace '[\r\n]+', ' ').Trim())
}

function Parse-IdList($val) {
    $ids = New-Object System.Collections.Generic.List[int]
    if ($null -eq $val) { return @() }
    $items = if ($val -is [System.Array]) { $val } else { @($val) }
    foreach ($item in $items) {
        $str = [string]$item
        foreach ($part in ($str -split ',')) {
            $trimmed = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $parsed = 0
                if ([int]::TryParse($trimmed, [ref]$parsed) -and $parsed -gt 0) {
                    if (-not $ids.Contains($parsed)) { $ids.Add($parsed) }
                } else {
                    Fail "Ungültige Issue-ID: '$trimmed'"
                }
            }
        }
    }
    return $ids.ToArray()
}

function Invoke-Gh {
    param([string[]]$GhArgs)
    if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ Output = ""; Error = "GitHub CLI 'gh' nicht gefunden."; ExitCode = 127 }
    }
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $stdoutLines = New-Object System.Collections.Generic.List[string]
        $stderrLines = New-Object System.Collections.Generic.List[string]
        & gh @GhArgs 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $stderrLines.Add($_.ToString())
            } else {
                $stdoutLines.Add([string]$_)
            }
        }
        $code = $LASTEXITCODE
        return [PSCustomObject]@{
            Output   = ($stdoutLines -join "`n")
            Error    = ($stderrLines -join "`n").Trim()
            ExitCode = $code
        }
    } catch {
        return [PSCustomObject]@{ Output = ""; Error = $_.Exception.Message; ExitCode = 1 }
    } finally {
        $ErrorActionPreference = $prevEAP
    }
}

function Parse-Issue([string]$path) {
    $fullPath = Resolve-ProjectPath $path
    if (-not (Test-Path -LiteralPath $fullPath)) { return $null }
    $raw = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
    $fmMatch = [regex]::Match($raw, '(?s)^---\r?\n(.*?)\r?\n---\r?\n?(.*)$')
    if (-not $fmMatch.Success) { return $null }

    $yaml = $fmMatch.Groups.Item(1).Value
    $body = $fmMatch.Groups.Item(2).Value.Trim()

    $obj = [PSCustomObject]@{
        ID        = 0
        Title     = ""
        Status    = "todo"
        Prio      = "med"
        LocalOnly = $false
        BlockedBy = @()
        Body      = $body
        FilePath  = ($path -replace '\\', '/')
    }

    foreach ($line in ($yaml -split '\r?\n')) {
        $kv = [regex]::Match($line, '^([a-zA-Z0-9_]+):\s*(.*)$')
        if ($kv.Success) {
            $k = $kv.Groups.Item(1).Value.Trim()
            $v = $kv.Groups.Item(2).Value.Trim()
            if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) {
                $q = $v.Substring(0, 1)
                $v = $v.Substring(1, $v.Length - 2)
                if ($q -eq '"') {
                    $v = [regex]::Replace($v, '\\(\\|")', { param($m) $m.Groups.Item(1).Value })
                }
            }
            switch ($k) {
                "id"         { $parsedId = 0; if ([int]::TryParse($v, [ref]$parsedId)) { $obj.ID = $parsedId } }
                "title"      { $obj.Title = $v }
                "status"     { $obj.Status = $v }
                "prio"       { $obj.Prio = $v }
                "local_only" { $obj.LocalOnly = ($v -eq "true") }
                "blocked_by" {
                    $clean = $v.Trim('[', ']')
                    if (-not [string]::IsNullOrWhiteSpace($clean)) {
                        $deps = New-Object System.Collections.Generic.List[int]
                        foreach ($part in ($clean -split ',')) {
                            $depId = 0
                            if ([int]::TryParse($part.Trim(), [ref]$depId) -and $depId -gt 0) {
                                if (-not $deps.Contains($depId)) { $deps.Add($depId) }
                            }
                        }
                        $obj.BlockedBy = $deps.ToArray()
                    }
                }
            }
        }
    }

    if ($obj.ID -gt 0) { return $obj }
    return $null
}

function Write-Issue($iss, [string]$targetPath) {
    $fullTarget = Resolve-ProjectPath $targetPath
    $parentDir = Split-Path -Parent $fullTarget
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    }
    $safeTitle = ((Sanitize-Title $iss.Title) -replace '\\', '\\') -replace '"', '\"'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("---")
    $lines.Add("id: $($iss.ID)")
    $lines.Add("title: `"$safeTitle`"")
    $lines.Add("status: $($iss.Status)")
    $lines.Add("prio: $($iss.Prio)")
    if ($iss.LocalOnly) { $lines.Add("local_only: true") }
    if ($iss.BlockedBy -and @($iss.BlockedBy).Count -gt 0) {
        $lines.Add("blocked_by: [$((@($iss.BlockedBy)) -join ', ')]")
    }
    $lines.Add("---")
    $lines.Add("")
    $trimmedBody = Safe-Trim $iss.Body
    if (-not [string]::IsNullOrWhiteSpace($trimmedBody)) {
        $lines.Add($trimmedBody)
    }
    [System.IO.File]::WriteAllText($fullTarget, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Load-Issues([string]$dir) {
    $fullDir = Resolve-ProjectPath $dir
    if (-not (Test-Path -LiteralPath $fullDir)) { return @() }
    $list = New-Object System.Collections.Generic.List[PSObject]
    $files = @(Get-ChildItem -LiteralPath $fullDir -Filter "*.md" -File)
    foreach ($f in $files) {
        $parsed = Parse-Issue $f.FullName
        if ($parsed) {
            $parsed.FilePath = Get-RelPath $f.FullName
            $list.Add($parsed)
        }
    }
    return $list.ToArray()
}

function Test-Cycle([int]$targetId, [int[]]$newBlockers, $allMap) {
    foreach ($startDep in $newBlockers) {
        if ($startDep -eq $targetId) { return $true }
        $visited = New-Object 'System.Collections.Generic.HashSet[int]'
        $stack = New-Object 'System.Collections.Generic.Stack[int]'
        $stack.Push($startDep)
        while ($stack.Count -gt 0) {
            $curr = $stack.Pop()
            if ($curr -eq $targetId) { return $true }
            if ($visited.Add($curr) -and $allMap.ContainsKey($curr)) {
                foreach ($nextDep in @($allMap[$curr].BlockedBy)) {
                    $stack.Push([int]$nextDep)
                }
            }
        }
    }
    return $false
}

function Get-SkillMarkdown {
    return @(
        '---',
        'name: index',
        'description: Lokales, token-minimales Issue-Tracking via CLI im TOON-Format mit Zwei-Wege-GitHub-Sync. Immer nutzen, um Aufgaben abzurufen, zu starten, neu anzulegen, zu blockieren, zu pushen oder abzuschließen.',
        '---',
        '',
        '# Agent-Instruktion: `index`',
        '',
        'Verwalte Aufgaben ausschließlich über das CLI-Tool `index` und die Markdown-Dateien unter `.issues/`. Nutze keine MCP-Tracker.',
        '',
        '## Systemregeln & Datenformat',
        '- **Speicherort:** Offene Tickets liegen unter `.issues/open/<id>-<slug>.md`, erledigte unter `.issues/closed/`.',
        '- **Abhängigkeiten:** Das Frontmatter-Feld `blocked_by: [id]` sperrt ein Ticket automatisch (auch bei `index start`), bis alle gelisteten IDs geschlossen sind.',
        '- **Single-WIP-Constraint:** Es darf immer nur exakt ein Ticket den Status `in_progress` haben.',
        '',
        '## Zwingender Ablauf pro Session',
        '',
        '1. **Abgleich & Auswahl:**',
        '   Führe zu Beginn immer aus:',
        '   ```bash',
        '   index sync && index ready --toon',
        '   ```',
        '   *(Falls kein GitHub-Repo verbunden ist, nutze direkt `index ready --toon`.)*',
        '   Die Ausgabe folgt dem Schema `issues{id,status,prio,file,title}:` und ist nach aktivem Status und Priorität (`high -> med -> low`) sortiert.',
        '',
        '2. **Ticket aktivieren & lesen:**',
        '   - Wähle das oberste Ticket (oder führe ein bereits auf `in_progress` stehendes Ticket zu Ende).',
        '   - Aktiviere es:',
        '     ```bash',
        '     index start <id>',
        '     ```',
        '   - Lies **nur** die in `file` angegebene Markdown-Datei (oder nutze `index show <id>`). Lies niemals pauschal alle Dateien in `.issues/open/`.',
        '',
        '3. **Neue Aufgaben & Abhängigkeiten verwalten:**',
        '   Entdeckst du während der Arbeit einen separaten Bug oder eine Teilaufgabe, lege ein eigenes Ticket an, statt den aktuellen Scope zu erweitern:',
        '   ```bash',
        '   index new "Präziser Titel" -prio med',
        '   index block <id> -by <blockerId1,blockerId2>',
        '   index unblock <id> [-by <blockerId>]',
        '   index push [<id>] [--all]',
        '   ```',
        '',
        '4. **Abschluss & Session-Ende:**',
        '   Nach erfolgreicher Umsetzung und Prüfung schließe das Ticket mit einer knappen technischen Zusammenfassung:',
        '   ```bash',
        '   index close <id> -note "Zusammenfassung der Änderung und betroffenen Dateien."',
        '   ```',
        '   Beende danach deine Antwort, damit das Kontextfenster auf 0 % zurückgesetzt werden kann.'
    ) -join "`n"
}

function Show-Usage {
    Write-Output "index v$ScriptVersion - Zero-Dependency Local & GitHub Issue CLI"
    Write-Output ""
    Write-Output "Nutzung:"
    Write-Output "  index init [--skill]                       Initialisiert .issues/ (optional + SKILL.md)"
    Write-Output "  index sync                                 4-Wege-Sync mit GitHub Issues"
    Write-Output "  index ready [--toon]                       Listet sofort startbare Tickets"
    Write-Output "  index status [--toon]                      Zeigt Projekt-Zusammenfassung"
    Write-Output "  index show <id>                            Zeigt Details und Body eines Tickets"
    Write-Output "  index new `"Titel`" [-prio high|med|low] [-body `"...`"] [-by 1,2] [-offline]"
    Write-Output "  index start <id>                           Setzt Ticket auf in_progress (Single-WIP)"
    Write-Output "  index close <id> [-note `"...`"]            Schließt Ticket lokal & auf GitHub"
    Write-Output "  index reopen <id> [-note `"...`"]           Öffnet ein geschlossenes Ticket erneut"
    Write-Output "  index block <id> -by <id1,id2>             Fügt Blocker hinzu (mit Zyklusprüfung)"
    Write-Output "  index unblock <id> [-by <id1,id2>]         Entfernt Blocker (oder alle ohne -by)"
    Write-Output "  index push [<id>] [--all]                  Lädt Offline-Tickets (>=10000) zu GitHub hoch"
}

# ==============================================================================
# Robustes Argument-Parsing (unterstützt PS '-flag' & POSIX '--flag[=val]')
# ==============================================================================
$Positionals = New-Object System.Collections.Generic.List[string]
$prio = "med"
$note = ""
$bodyArg = ""
$UseToon = $false
$Offline = $false
$IncludeAll = $false
$WithSkill = $false
$ShowHelp = $false
$BlockedByIds = New-Object System.Collections.Generic.List[int]

$idx = 0
$endOfOptions = $false
while ($idx -lt $args.Count) {
    $rawArg = $args[$idx]
    $argStr = if ($null -eq $rawArg) { "" } else { [string]$rawArg }

    if (-not $endOfOptions -and $argStr -eq "--") {
        $endOfOptions = $true
        $idx++
        continue
    }

    if (-not $endOfOptions -and $argStr.StartsWith("-") -and $argStr.Length -gt 1) {
        $trimmedFlag = $argStr.TrimStart('-')
        $eqPos = $trimmedFlag.IndexOf('=')
        if ($eqPos -ge 0) {
            $flagName = $trimmedFlag.Substring(0, $eqPos).ToLower()
            $flagVal = $trimmedFlag.Substring($eqPos + 1)
            $hasInlineVal = $true
        } else {
            $flagName = $trimmedFlag.ToLower()
            $flagVal = $null
            $hasInlineVal = $false
        }

        switch ($flagName) {
            { $_ -in @("h", "help", "?") } { $ShowHelp = $true }
            "toon"    { $UseToon = $true }
            "offline" { $Offline = $true }
            "all"     { $IncludeAll = $true }
            "skill"   { $WithSkill = $true }
            "prio" {
                if (-not $hasInlineVal) {
                    $idx++; if ($idx -ge $args.Count) { Fail "Fehlender Wert für -$flagName" }
                    $flagVal = [string]$args[$idx]
                }
                $prio = $flagVal.ToLower()
            }
            "note" {
                if (-not $hasInlineVal) {
                    $idx++; if ($idx -ge $args.Count) { Fail "Fehlender Wert für -$flagName" }
                    $flagVal = [string]$args[$idx]
                }
                $note = $flagVal
            }
            "body" {
                if (-not $hasInlineVal) {
                    $idx++; if ($idx -ge $args.Count) { Fail "Fehlender Wert für -$flagName" }
                    $flagVal = [string]$args[$idx]
                }
                $bodyArg = $flagVal
            }
            { $_ -in @("by", "blocked-by", "blocked_by") } {
                if (-not $hasInlineVal) {
                    $idx++; if ($idx -ge $args.Count) { Fail "Fehlender Wert für -$flagName" }
                    $flagVal = $args[$idx]
                }
                foreach ($bid in @(Parse-IdList $flagVal)) {
                    if (-not $BlockedByIds.Contains($bid)) { $BlockedByIds.Add($bid) }
                }
            }
            default { Fail "Unbekanntes Flag: $argStr" }
        }
    } else {
        $Positionals.Add($argStr)
    }
    $idx++
}

$Command = if ($Positionals.Count -ge 1) { $Positionals[0].ToLower() } else { "" }
$Arg1    = if ($Positionals.Count -ge 2) { $Positionals[1] } else { "" }

if ($ShowHelp -or [string]::IsNullOrWhiteSpace($Command) -or $Command -eq "help") {
    Show-Usage
    exit 0
}

# ==============================================================================
# CLI-Befehle
# ==============================================================================
switch ($Command) {
    "init" {
        Ensure-Dirs
        $extraInfo = ""
        if ($WithSkill) {
            $skillDir = Resolve-ProjectPath ".agents\skills\index"
            New-Item -ItemType Directory -Force -Path $skillDir | Out-Null
            $skillFile = Join-Path $skillDir "SKILL.md"
            [System.IO.File]::WriteAllText($skillFile, (Get-SkillMarkdown) + "`n", [System.Text.UTF8Encoding]::new($false))
            $extraInfo = " + .agents/skills/index/SKILL.md erstellt"
        }
        Write-Output "ok: .issues/open und .issues/closed bereit$extraInfo"
    }

    "sync" {
        Ensure-Dirs
        $res = Invoke-Gh @("issue", "list", "--state", "all", "--limit", "300", "--json", "number,title,body,state,labels")
        if ($res.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($res.Output)) {
            $errDetail = if ($res.Error) { $res.Error } else { "ist 'gh' installiert und 'gh auth status' aktiv?" }
            Fail "gh sync fehlgeschlagen: $errDetail"
        }

        $ghIssues = @($res.Output | ConvertFrom-Json)
        $openLocal = @(Load-Issues $dirOpen)
        $closedLocal = @(Load-Issues $dirClosed)
        $openMap = @{}; foreach ($o in $openLocal) { $openMap[[int]$o.ID] = $o }
        $closedMap = @{}; foreach ($c in $closedLocal) { $closedMap[[int]$c.ID] = $c }

        $imported = 0; $updated = 0; $closedCount = 0; $reopenedCount = 0
        foreach ($gi in $ghIssues) {
            $num = [int]$gi.number
            $ghState = (Safe-Trim $gi.state).ToUpper()
            $cleanTitle = Sanitize-Title (Safe-Trim $gi.title)
            $ghBody = Safe-Trim $gi.body

            $p = "med"
            foreach ($l in @($gi.labels)) {
                $n = (Safe-Trim $l.name).ToLower()
                if ($n -in @("high", "urgent", "bug", "p1", "critical")) { $p = "high"; break }
                elseif ($n -in @("low", "p3", "chore")) { $p = "low" }
            }

            if ($ghState -eq "OPEN") {
                if ($openMap.ContainsKey($num)) {
                    $loc = $openMap[$num]
                    if (-not $loc.LocalOnly -and ($loc.Title -ne $cleanTitle -or $loc.Prio -ne $p)) {
                        $loc.Title = $cleanTitle
                        $loc.Prio = $p
                        Write-Issue $loc $loc.FilePath
                        $updated++
                    }
                } elseif ($closedMap.ContainsKey($num)) {
                    $loc = $closedMap[$num]
                    if (-not $loc.LocalOnly) {
                        $loc.Status = "todo"
                        $loc.Title = $cleanTitle
                        $loc.Prio = $p
                        $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm 'UTC'")
                        $loc.Body = ($loc.Body + "`n`n## Wiedereröffnet ($stamp)`nAutomatisch reaktiviert via GitHub-Sync.").Trim()
                        $newPath = Join-Path $dirOpen (Split-Path $loc.FilePath -Leaf)
                        Write-Issue $loc $newPath
                        Remove-Item -LiteralPath (Resolve-ProjectPath $loc.FilePath) -Force
                        $reopenedCount++
                    }
                } else {
                    $iss = [PSCustomObject]@{
                        ID        = $num
                        Title     = $cleanTitle
                        Status    = "todo"
                        Prio      = $p
                        LocalOnly = $false
                        BlockedBy = @()
                        Body      = $ghBody
                    }
                    $file = Join-Path $dirOpen "$num-$(Get-Slug $cleanTitle).md"
                    Write-Issue $iss $file
                    $imported++
                }
            } elseif ($ghState -eq "CLOSED") {
                if ($openMap.ContainsKey($num) -and -not $openMap[$num].LocalOnly) {
                    $loc = $openMap[$num]
                    $loc.Status = "closed"
                    $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm 'UTC'")
                    $loc.Body = ($loc.Body + "`n`n## Abschluss ($stamp)`nAutomatisch geschlossen via GitHub-Sync.").Trim()
                    $newPath = Join-Path $dirClosed (Split-Path $loc.FilePath -Leaf)
                    Write-Issue $loc $newPath
                    Remove-Item -LiteralPath (Resolve-ProjectPath $loc.FilePath) -Force
                    $closedCount++
                }
            }
        }
        Write-Output "sync_ok: $imported neu, $updated aktualisiert, $closedCount geschlossen, $reopenedCount wiedergeöffnet"
    }

    "ready" {
        $open = @(Load-Issues $dirOpen)
        $openMap = @{}; foreach ($o in $open) { $openMap[[int]$o.ID] = $true }
        $prioRank = @{ "high" = 1; "med" = 2; "low" = 3 }

        $ready = @($open | Where-Object {
            $blocked = $false
            foreach ($dep in @($_.BlockedBy)) {
                if ($openMap.ContainsKey([int]$dep)) { $blocked = $true; break }
            }
            -not $blocked
        } | Sort-Object @{Expression={$_.Status -ne "in_progress"}}, @{Expression={ if ($prioRank.ContainsKey($_.Prio)) { $prioRank[$_.Prio] } else { 2 } }}, ID)

        if ($UseToon) {
            Write-Output "issues{id,status,prio,file,title}:"
            foreach ($r in $ready) {
                $t = (Sanitize-Title $r.Title) -replace ',', ';'
                Write-Output "$($r.ID),$($r.Status),$($r.Prio),$($r.FilePath),$t"
            }
        } else {
            if ($ready.Count -eq 0) {
                Write-Output "Keine offenen (unblockierten) Issues vorhanden."
            } else {
                $ready | Select-Object ID, Status, Prio, Title, FilePath | Format-Table -AutoSize
            }
        }
    }

    "status" {
        $open = @(Load-Issues $dirOpen)
        $closed = @(Load-Issues $dirClosed)
        $openMap = @{}; foreach ($o in $open) { $openMap[[int]$o.ID] = $true }
        $readyCount = 0; $blockedCount = 0; $active = $null
        foreach ($o in $open) {
            if ($o.Status -eq "in_progress") { $active = $o }
            $isBlocked = $false
            foreach ($dep in @($o.BlockedBy)) {
                if ($openMap.ContainsKey([int]$dep)) { $isBlocked = $true; break }
            }
            if ($isBlocked) { $blockedCount++ } else { $readyCount++ }
        }
        $localCount = @(@($open + $closed) | Where-Object { $_.LocalOnly }).Count
        $activeId = if ($active) { "$($active.ID)" } else { "none" }

        if ($UseToon) {
            Write-Output "status{open,ready,blocked,closed,local_only,active_id}:"
            Write-Output "$($open.Count),$readyCount,$blockedCount,$($closed.Count),$localCount,$activeId"
        } else {
            Write-Output "Open: $($open.Count) (Ready: $readyCount, Blocked: $blockedCount) | Closed: $($closed.Count) | LocalOnly: $localCount"
            if ($active) {
                Write-Output "Active (in_progress): #$($active.ID) - $($active.Title)"
            } else {
                Write-Output "Active (in_progress): keines"
            }
        }
    }

    "show" {
        $id = 0
        if (-not [int]::TryParse($Arg1, [ref]$id) -or $id -le 0) { Fail "Nutzung: index show <id>" }
        $open = @(Load-Issues $dirOpen)
        $closed = @(Load-Issues $dirClosed)
        $openMap = @{}; foreach ($o in $open) { $openMap[[int]$o.ID] = $o }
        $closedMap = @{}; foreach ($c in $closed) { $closedMap[[int]$c.ID] = $c }

        $target = if ($openMap.ContainsKey($id)) { $openMap[$id] } elseif ($closedMap.ContainsKey($id)) { $closedMap[$id] } else { $null }
        if (-not $target) { Fail "Issue #$id nicht gefunden." }

        $depLabels = New-Object System.Collections.Generic.List[string]
        foreach ($dep in @($target.BlockedBy)) {
            if ($openMap.ContainsKey([int]$dep)) { $depLabels.Add("#$dep (open)") }
            elseif ($closedMap.ContainsKey([int]$dep)) { $depLabels.Add("#$dep (closed)") }
            else { $depLabels.Add("#$dep (missing)") }
        }
        $depText = if ($depLabels.Count -gt 0) { $depLabels -join ", " } else { "keine" }

        Write-Output "ID:        #$($target.ID)"
        Write-Output "Title:     $($target.Title)"
        Write-Output "Status:    $($target.Status)"
        Write-Output "Prio:      $($target.Prio)"
        Write-Output "LocalOnly: $($target.LocalOnly)"
        Write-Output "BlockedBy: $depText"
        Write-Output "File:      $($target.FilePath)"
        if (-not [string]::IsNullOrWhiteSpace($target.Body)) {
            Write-Output "---"
            Write-Output $target.Body
        }
    }

    "new" {
        if ([string]::IsNullOrWhiteSpace($Arg1)) {
            Fail 'Nutzung: index new "Titel" [-prio high|med|low] [-body "..."] [-by 1,2] [-offline]'
        }
        if ($prio -notin @("high", "med", "low")) { $prio = "med" }
        Ensure-Dirs

        $cleanTitle = Sanitize-Title $Arg1
        $cleanBody = Safe-Trim $bodyArg

        $existing = @(@(Load-Issues $dirOpen) + @(Load-Issues $dirClosed))
        $existingIds = @{}; foreach ($e in $existing) { $existingIds[[int]$e.ID] = $true }
        foreach ($bid in $BlockedByIds) {
            if (-not $existingIds.ContainsKey($bid)) {
                Fail "Abgebrochen: Blocker-Issue #$bid existiert nicht."
            }
        }

        $id = 0
        $isLocalOnly = $false
        if (-not $Offline) {
            $ghCreateBody = if (-not [string]::IsNullOrWhiteSpace($cleanBody)) { $cleanBody } else { "Erstellt via index CLI" }
            $res = Invoke-Gh @("issue", "create", "--title", $cleanTitle, "--body", $ghCreateBody)
            $urlMatch = [regex]::Match((Safe-Trim $res.Output), '/(\d+)\s*$')
            if ($res.ExitCode -eq 0 -and $urlMatch.Success) {
                $id = [int]$urlMatch.Groups.Item(1).Value
            } else {
                $isLocalOnly = $true
            }
        } else {
            $isLocalOnly = $true
        }

        if ($isLocalOnly) {
            $maxLocal = ($existing | Where-Object { $_.ID -ge 10000 } | Measure-Object -Property ID -Maximum).Maximum
            $id = if ($maxLocal) { [int]$maxLocal + 1 } else { 10000 }
        }

        $iss = [PSCustomObject]@{
            ID        = $id
            Title     = $cleanTitle
            Status    = "todo"
            Prio      = $prio
            LocalOnly = $isLocalOnly
            BlockedBy = $BlockedByIds.ToArray()
            Body      = $cleanBody
        }
        $file = Join-Path $dirOpen "$id-$(Get-Slug $cleanTitle).md"
        Write-Issue $iss $file
        $modeTag = if ($isLocalOnly) { " (lokal/offline)" } else { "" }
        Write-Output "created: #$id$modeTag -> $($file -replace '\\', '/')"
    }

    "start" {
        $id = 0
        if (-not [int]::TryParse($Arg1, [ref]$id) -or $id -le 0) { Fail "Nutzung: index start <id>" }
        $open = @(Load-Issues $dirOpen)
        $active = $open | Where-Object { $_.Status -eq "in_progress" -and $_.ID -ne $id } | Select-Object -First 1
        if ($active) {
            Fail "Abgebrochen: #$($active.ID) ist bereits in_progress (Single-WIP-Regel)."
        }
        $target = $open | Where-Object { $_.ID -eq $id } | Select-Object -First 1
        if (-not $target) { Fail "Issue #$id nicht in .issues/open gefunden." }

        $openIds = @{}; foreach ($o in $open) { $openIds[[int]$o.ID] = $true }
        foreach ($dep in @($target.BlockedBy)) {
            if ($openIds.ContainsKey([int]$dep)) {
                Fail "Abgebrochen: Issue #$id ist noch blockiert durch offenes Issue #$dep."
            }
        }
        $target.Status = "in_progress"
        Write-Issue $target $target.FilePath
        Write-Output "started: #$id ($($target.Title))"
    }

    "close" {
        $id = 0
        if (-not [int]::TryParse($Arg1, [ref]$id) -or $id -le 0) { Fail 'Nutzung: index close <id> [-note "Text"]' }
        $closeNote = if ([string]::IsNullOrWhiteSpace($note)) { "Erledigt." } else { $note }
        $open = @(Load-Issues $dirOpen)
        $target = $open | Where-Object { $_.ID -eq $id } | Select-Object -First 1
        if (-not $target) { Fail "Issue #$id nicht in .issues/open gefunden." }

        $target.Status = "closed"
        $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm 'UTC'")
        $target.Body = ($target.Body + "`n`n## Abschluss ($stamp)`n$closeNote").Trim()
        Ensure-Dirs
        $newPath = Join-Path $dirClosed (Split-Path $target.FilePath -Leaf)
        Write-Issue $target $newPath
        Remove-Item -LiteralPath (Resolve-ProjectPath $target.FilePath) -Force

        if (-not $target.LocalOnly) {
            $ghRes = Invoke-Gh @("issue", "close", "$id", "--comment", $closeNote)
            if ($ghRes.ExitCode -ne 0) {
                [Console]::Error.WriteLine("warning: GitHub issue #$id konnte nicht geschlossen werden: $($ghRes.Error)")
            }
        }

        $remainingOpenIds = @{}
        foreach ($o in $open) {
            if ([int]$o.ID -ne $id) { $remainingOpenIds[[int]$o.ID] = $true }
        }
        $unblockedList = New-Object System.Collections.Generic.List[string]
        foreach ($o in $open) {
            if ([int]$o.ID -eq $id) { continue }
            $deps = @($o.BlockedBy | ForEach-Object { [int]$_ })
            if ($deps -contains $id) {
                $stillBlocked = $false
                foreach ($d in $deps) {
                    if ($remainingOpenIds.ContainsKey($d)) { $stillBlocked = $true; break }
                }
                if (-not $stillBlocked) { $unblockedList.Add("#$($o.ID)") }
            }
        }

        $unlockSuffix = if ($unblockedList.Count -gt 0) { " | unblocked: $($unblockedList -join ', ')" } else { "" }
        Write-Output "closed: #$id -> $($newPath -replace '\\', '/')$unlockSuffix"
    }

    "reopen" {
        $id = 0
        if (-not [int]::TryParse($Arg1, [ref]$id) -or $id -le 0) { Fail 'Nutzung: index reopen <id> [-note "Text"]' }
        $open = @(Load-Issues $dirOpen)
        if ($open | Where-Object { $_.ID -eq $id } | Select-Object -First 1) {
            Fail "Issue #$id ist bereits offen."
        }
        $closed = @(Load-Issues $dirClosed)
        $target = $closed | Where-Object { $_.ID -eq $id } | Select-Object -First 1
        if (-not $target) { Fail "Issue #$id nicht in .issues/closed gefunden." }

        $target.Status = "todo"
        $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm 'UTC'")
        $reason = if ([string]::IsNullOrWhiteSpace($note)) { "Manuell wiedereröffnet." } else { $note }
        $target.Body = ($target.Body + "`n`n## Wiedereröffnet ($stamp)`n$reason").Trim()
        Ensure-Dirs
        $newPath = Join-Path $dirOpen (Split-Path $target.FilePath -Leaf)
        Write-Issue $target $newPath
        Remove-Item -LiteralPath (Resolve-ProjectPath $target.FilePath) -Force

        if (-not $target.LocalOnly) {
            $ghRes = Invoke-Gh @("issue", "reopen", "$id")
            if ($ghRes.ExitCode -ne 0) {
                [Console]::Error.WriteLine("warning: GitHub issue #$id konnte nicht wiedereröffnet werden: $($ghRes.Error)")
            } elseif (-not [string]::IsNullOrWhiteSpace($note)) {
                Invoke-Gh @("issue", "comment", "$id", "--body", $note) | Out-Null
            }
        }
        Write-Output "reopened: #$id -> $($newPath -replace '\\', '/')"
    }

    "block" {
        $id = 0
        if (-not [int]::TryParse($Arg1, [ref]$id) -or $id -le 0 -or $BlockedByIds.Count -eq 0) {
            Fail "Nutzung: index block <id> -by <id1[,id2,...]>"
        }
        $open = @(Load-Issues $dirOpen)
        $closed = @(Load-Issues $dirClosed)
        $allIssues = @($open + $closed)
        $allMap = @{}; foreach ($a in $allIssues) { $allMap[[int]$a.ID] = $a }
        $openMap = @{}; foreach ($o in $open) { $openMap[[int]$o.ID] = $o }

        if (-not $openMap.ContainsKey($id)) { Fail "Issue #$id nicht in .issues/open gefunden." }
        $target = $openMap[$id]

        foreach ($bid in $BlockedByIds) {
            if ($bid -eq $id) { Fail "Abgebrochen: Issue #$id kann sich nicht selbst blockieren." }
            if (-not $allMap.ContainsKey($bid)) { Fail "Abgebrochen: Blocker-Issue #$bid existiert nicht." }
        }
        if (Test-Cycle $id $BlockedByIds.ToArray() $allMap) {
            Fail "Abgebrochen: Zyklische Abhängigkeit erkannt."
        }

        $merged = New-Object System.Collections.Generic.List[int]
        foreach ($d in @($target.BlockedBy)) {
            $di = [int]$d
            if (-not $merged.Contains($di)) { $merged.Add($di) }
        }
        foreach ($bid in $BlockedByIds) {
            if (-not $merged.Contains($bid)) { $merged.Add($bid) }
        }
        $target.BlockedBy = $merged.ToArray()

        $statusNote = ""
        if ($target.Status -eq "in_progress") {
            $hasOpenBlocker = $false
            foreach ($d in $target.BlockedBy) {
                if ($openMap.ContainsKey([int]$d)) { $hasOpenBlocker = $true; break }
            }
            if ($hasOpenBlocker) {
                $target.Status = "todo"
                $statusNote = " (Status auf todo zurückgesetzt)"
            }
        }
        Write-Issue $target $target.FilePath
        $depStr = ($target.BlockedBy | ForEach-Object { "#$_" }) -join ", "
        Write-Output "blocked: #$id by $depStr$statusNote"
    }

    "unblock" {
        $id = 0
        if (-not [int]::TryParse($Arg1, [ref]$id) -or $id -le 0) {
            Fail "Nutzung: index unblock <id> [-by <id1[,id2,...]>]"
        }
        $open = @(Load-Issues $dirOpen)
        $target = $open | Where-Object { $_.ID -eq $id } | Select-Object -First 1
        if (-not $target) { Fail "Issue #$id nicht in .issues/open gefunden." }

        if ($BlockedByIds.Count -gt 0) {
            $remaining = @($target.BlockedBy | Where-Object { $BlockedByIds -notcontains ([int]$_) })
            $target.BlockedBy = $remaining
        } else {
            $target.BlockedBy = @()
        }
        Write-Issue $target $target.FilePath
        if (@($target.BlockedBy).Count -gt 0) {
            $remStr = ($target.BlockedBy | ForEach-Object { "#$_" }) -join ", "
            Write-Output "unblocked: #$id (verbleibend: $remStr)"
        } else {
            Write-Output "unblocked: #$id (alle Blocker entfernt)"
        }
    }

    "push" {
        $targetId = 0
        if (-not [string]::IsNullOrWhiteSpace($Arg1)) {
            if (-not [int]::TryParse($Arg1, [ref]$targetId) -or $targetId -le 0) {
                Fail "Nutzung: index push [<id>] [--all]"
            }
        }

        $open = @(Load-Issues $dirOpen)
        $closed = @(Load-Issues $dirClosed)
        $allIssues = @($open + $closed)

        if ($targetId -gt 0) {
            $match = $allIssues | Where-Object { $_.ID -eq $targetId } | Select-Object -First 1
            if (-not $match) { Fail "Issue #$targetId nicht gefunden." }
            if (-not $match.LocalOnly) { Fail "Issue #$targetId ist bereits mit GitHub synchronisiert." }
            $candidates = @($match)
        } else {
            $pool = if ($IncludeAll) { $allIssues } else { $open }
            $candidates = @($pool | Where-Object { $_.LocalOnly } | Sort-Object ID)
        }

        if ($candidates.Count -eq 0) {
            Write-Output "Keine lokalen Offline-Issues zum Hochladen vorhanden."
            exit 0
        }

        foreach ($iss in $candidates) {
            $oldId = [int]$iss.ID
            $oldPath = $iss.FilePath
            $ghBody = if (-not [string]::IsNullOrWhiteSpace($iss.Body)) { $iss.Body } else { "Erstellt via index CLI (Offline-ID #$oldId)" }

            $res = Invoke-Gh @("issue", "create", "--title", $iss.Title, "--body", $ghBody)
            $urlMatch = [regex]::Match((Safe-Trim $res.Output), '/(\d+)\s*$')
            if ($res.ExitCode -ne 0 -or -not $urlMatch.Success) {
                $errDetail = if ($res.Error) { $res.Error } else { "gh issue create fehlgeschlagen" }
                Fail "Push für #$oldId fehlgeschlagen: $errDetail"
            }

            $newId = [int]$urlMatch.Groups.Item(1).Value
            if ($iss.Status -eq "closed") {
                $closeRes = Invoke-Gh @("issue", "close", "$newId", "--comment", "Synchronisiert aus lokal geschlossenem Ticket (ehemals #$oldId).")
                if ($closeRes.ExitCode -ne 0) {
                    [Console]::Error.WriteLine("warning: GitHub issue #$newId konnte nach Push nicht geschlossen werden: $($closeRes.Error)")
                }
            }

            # Dependency-Rewriting in allen anderen lokalen Tickets
            foreach ($other in $allIssues) {
                if ([int]$other.ID -eq $oldId) { continue }
                $deps = @($other.BlockedBy | ForEach-Object { [int]$_ })
                if ($deps -contains $oldId) {
                    $rewritten = New-Object System.Collections.Generic.List[int]
                    foreach ($d in $deps) {
                        $mapped = if ($d -eq $oldId) { $newId } else { $d }
                        if (-not $rewritten.Contains($mapped)) { $rewritten.Add($mapped) }
                    }
                    $other.BlockedBy = $rewritten.ToArray()
                    Write-Issue $other $other.FilePath
                }
            }

            $targetDir = if ($iss.Status -eq "closed") { $dirClosed } else { $dirOpen }
            $newPath = Join-Path $targetDir "$newId-$(Get-Slug $iss.Title).md"
            $iss.ID = $newId
            $iss.LocalOnly = $false
            $iss.FilePath = ($newPath -replace '\\', '/')
            Write-Issue $iss $newPath
            if ($oldPath -ne $iss.FilePath -and (Test-Path -LiteralPath (Resolve-ProjectPath $oldPath))) {
                Remove-Item -LiteralPath (Resolve-ProjectPath $oldPath) -Force
            }
            Write-Output "pushed: #$oldId -> #$newId ($($iss.FilePath))"
        }
    }

    default {
        Fail "Unbekannter Befehl '$Command'. Nutze 'index help' für eine Übersicht."
    }
}
'@

[System.IO.File]::WriteAllText("$InstallDir\index-cli.ps1", $CliCode, [System.Text.UTF8Encoding]::new($true))

$CmdWrapper = @"
@echo off
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 goto :use_pwsh
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0index-cli.ps1" %*
exit /b %ERRORLEVEL%

:use_pwsh
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0index-cli.ps1" %*
exit /b %ERRORLEVEL%
"@
[System.IO.File]::WriteAllText("$InstallDir\index.cmd", $CmdWrapper, [System.Text.ASCIIEncoding]::new())

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathEntries = @()
if ($UserPath) {
    $PathEntries = @($UserPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
if ($PathEntries -notcontains $InstallDir) {
    $NewUserPath = ($PathEntries + $InstallDir) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
}
if (($env:Path -split ';') -notcontains $InstallDir) {
    $env:Path = "$env:Path;$InstallDir"
}

if (-not $GlobalOnly) {
    $initArgs = @("init")
    if (-not $NoSkill) { $initArgs += "--skill" }
    & "$InstallDir\index-cli.ps1" @initArgs
}

Write-Host "`n[OK] 'index' v2.1 wurde global installiert ($InstallDir)!" -ForegroundColor Green
Write-Host "Teste direkt: index status  oder  index sync; index ready --toon" -ForegroundColor Cyan
