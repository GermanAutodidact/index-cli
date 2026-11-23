# ==============================================================================
# Automatisierte Testsuite für index CLI v2.1 (PS 5.1 & PowerShell 7 kompatibel)
# ==============================================================================
$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$CliScript = Join-Path $RepoRoot "src\index-cli.ps1"
$CmdWrapper = Join-Path $RepoRoot "src\index.cmd"
$InstallerScript = Join-Path $RepoRoot "install-index-v2.ps1"
$RepoSkillFile = Join-Path $RepoRoot ".agents\skills\index\SKILL.md"

$PassCount = 0
$FailCount = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) {
        $script:PassCount++
        Write-Host "[PASS] $Message" -ForegroundColor Green
    } else {
        $script:FailCount++
        Write-Host "[FAIL] $Message" -ForegroundColor Red
    }
}

function Invoke-CliDirect {
    param([string[]]$CliArgs)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $global:LASTEXITCODE = 0
    $out = & $CliScript @CliArgs 2>&1
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $ErrorActionPreference = $prevEAP
    return [PSCustomObject]@{
        Output   = (($out | ForEach-Object { [string]$_ }) -join "`n").Trim()
        ExitCode = $code
    }
}

function Invoke-CliCmd {
    param([string[]]$CliArgs)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & $CmdWrapper @CliArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    return [PSCustomObject]@{
        Output   = (($out | ForEach-Object { [string]$_ }) -join "`n").Trim()
        ExitCode = $code
    }
}

# 1. Synchronität & Encoding zwischen src/index-cli.ps1, src/index.cmd und install-index-v2.ps1
$cliBytes = [System.IO.File]::ReadAllBytes($CliScript)
$instBytes = [System.IO.File]::ReadAllBytes($InstallerScript)
$cmdBytes = [System.IO.File]::ReadAllBytes($CmdWrapper)

Assert-True ($cliBytes.Length -ge 3 -and $cliBytes[0] -eq 0xEF -and $cliBytes[1] -eq 0xBB -and $cliBytes[2] -eq 0xBF) "src/index-cli.ps1 hat UTF-8 BOM"
Assert-True ($instBytes.Length -ge 3 -and $instBytes[0] -eq 0xEF -and $instBytes[1] -eq 0xBB -and $instBytes[2] -eq 0xBF) "install-index-v2.ps1 hat UTF-8 BOM"
Assert-True (-not ($cmdBytes.Length -ge 3 -and $cmdBytes[0] -eq 0xEF -and $cmdBytes[1] -eq 0xBB -and $cmdBytes[2] -eq 0xBF)) "src/index.cmd hat kein BOM"

$cliRaw = ([System.IO.File]::ReadAllText($CliScript, [System.Text.Encoding]::UTF8) -replace "`r?`n", "`n").Trim()
$instRaw = ([System.IO.File]::ReadAllText($InstallerScript, [System.Text.Encoding]::UTF8) -replace "`r?`n", "`n")
$embedMatch = [regex]::Match($instRaw, '(?s)\$CliCode = @''\n(.*?)\n''@')
Assert-True $embedMatch.Success "install-index-v2.ps1 enthält gültigen `$CliCode Here-String"
if ($embedMatch.Success) {
    $embeddedCode = $embedMatch.Groups.Item(1).Value.Trim()
    Assert-True ($embeddedCode -eq $cliRaw) "src/index-cli.ps1 ist 100% synchron mit install-index-v2.ps1"
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("index-cli-test-" + [Guid]::NewGuid().ToString("N"))
$WorkDir = Join-Path $TempRoot "project"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$OrigLoc = (Get-Location).Path
try {
    Set-Location $WorkDir

    # 2. init --skill (via index.cmd)
    $r = Invoke-CliCmd @("init", "--skill")
    Assert-True ($r.ExitCode -eq 0) "init --skill via index.cmd erfolgreich"
    Assert-True (Test-Path ".issues\open") ".issues/open existiert"
    Assert-True (Test-Path ".issues\closed") ".issues/closed existiert"
    Assert-True (Test-Path ".agents\skills\index\SKILL.md") "SKILL.md wurde angelegt"
    $genSkill = ([System.IO.File]::ReadAllText((Join-Path $WorkDir ".agents\skills\index\SKILL.md"), [System.Text.Encoding]::UTF8) -replace "`r?`n", "`n").Trim()
    $repoSkill = ([System.IO.File]::ReadAllText($RepoSkillFile, [System.Text.Encoding]::UTF8) -replace "`r?`n", "`n").Trim()
    Assert-True ($genSkill -eq $repoSkill) "Generiertes SKILL.md entspricht .agents/skills/index/SKILL.md"

    # 3. new -offline mit Sonderzeichen, YAML-Escaping & Dual-Flags
    $specialTitle = 'Doppelpunkt: "Quotes", Pfad C:\temp\ & ÄÖÜß'
    $r = Invoke-CliDirect @("new", $specialTitle, "-prio", "high", "-body", "Zeile A`nZeile B", "-offline")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match 'created: #10000 \(lokal/offline\)') "new -offline erzeugt #10000"

    $r = Invoke-CliCmd @("new", "Zweites Ticket", "--prio=low", "--offline")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match 'created: #10001') "new mit --prio=low & --offline erzeugt #10001"

    $r = Invoke-CliCmd @("new", "Drittes Ticket", "-prio", "med", "-by", "10000", "-offline")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match 'created: #10002') "new mit -by 10000 erzeugt #10002"

    # Parse-Verify via show
    $r = Invoke-CliCmd @("show", "10000")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output.Contains($specialTitle)) "show 10000 liefert Titel inkl. Quotes, Backslashes & Umlauten exakt zurück"

    # 4. ready & ready --toon
    $r = Invoke-CliCmd @("ready", "--toon")
    $lines = @($r.Output -split "`r?`n")
    Assert-True ($r.ExitCode -eq 0 -and $lines.Count -ge 1 -and $lines[0] -eq "issues{id,status,prio,file,title}:") "ready --toon gibt TOON-Header aus"
    Assert-True ($lines.Count -eq 3) "ready --toon blendet blockiertes #10002 aus (2 bereit)"
    $firstCols = if ($lines.Count -ge 2) { $lines[1].Split(',', 5) } else { @() }
    Assert-True ($firstCols.Count -eq 5 -and $lines[1].StartsWith("10000,todo,high,") -and (-not $firstCols[4].Contains(","))) "ready --toon sortiert high zuerst und ersetzt Kommas im Titel"
    Assert-True ($lines.Count -ge 3 -and $lines[2].StartsWith("10001,todo,low,")) "ready --toon listet low danach"

    $r = Invoke-CliCmd @("ready")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "10000" -and $r.Output -match "10001") "ready ohne Flag zeigt Tabelle"

    # 5. block, unblock & DAG Zykluserkennung
    $r = Invoke-CliCmd @("block", "10001", "-by", "10000,10002")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "blocked: #10001") "block mit kommagetrennter ID-Liste funktioniert"

    $r = Invoke-CliCmd @("block", "10000", "-by", "10000")
    Assert-True ($r.ExitCode -ne 0) "Self-Block wird abgelehnt"

    $r = Invoke-CliCmd @("block", "10000", "-by", "10001")
    Assert-True ($r.ExitCode -ne 0 -and $r.Output -match "Zyklische Abhängigkeit") "Indirekter Zyklus (10000 <- 10001 <- 10000) wird abgelehnt"

    $r = Invoke-CliCmd @("unblock", "10001")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "alle Blocker entfernt") "unblock ohne -by entfernt alle Blocker"

    # 6. start, Block-Sperre & Single-WIP
    $r = Invoke-CliCmd @("start", "10002")
    Assert-True ($r.ExitCode -ne 0 -and $r.Output -match "blockiert") "start für blockiertes Ticket wird abgelehnt"

    $r = Invoke-CliCmd @("start", "10000")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "started: #10000") "start #10000 setzt Status auf in_progress"

    $r = Invoke-CliCmd @("start", "10001")
    Assert-True ($r.ExitCode -ne 0 -and $r.Output -match "Single-WIP") "Single-WIP verhindert zweites paralleles in_progress-Ticket"

    # Blockieren eines in_progress Tickets setzt Status zurück auf todo
    $r = Invoke-CliCmd @("block", "10000", "-by", "10001")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "todo") "block auf in_progress Ticket setzt Status auf todo zurück"
    $null = Invoke-CliCmd @("unblock", "10000")
    $null = Invoke-CliCmd @("start", "10000")

    # 7. status --toon & show
    $r = Invoke-CliCmd @("status", "--toon")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "status\{open,ready,blocked,closed,local_only,active_id\}:" -and $r.Output -match "3,2,1,0,3,10000") "status --toon liefert exakte Kennzahlen"

    $r = Invoke-CliCmd @("show", "10002")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "#10000 \(open\)") "show #10002 zeigt Blockerstatus (open)"

    # 8. close & reopen
    $r = Invoke-CliCmd @("close", "10000", "-note", "Basis fertiggestellt")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "closed: #10000" -and $r.Output -match "unblocked: #10002") "close #10000 meldet Freischaltung von #10002"

    $r = Invoke-CliCmd @("ready", "--toon")
    Assert-True ($r.Output -match "10002,todo,med,") "Nach Schließen von #10000 ist #10002 in ready --toon"

    $r = Invoke-CliCmd @("reopen", "10000", "-note", "Reopen-Test")
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "reopened: #10000") "reopen #10000 verschiebt Ticket zurück nach open"

    # 9. Mock-gh Test für 4-Wege-Sync (inkl. body: null & reopen) + push (inkl. Dependency-Rewriting)
    $MockWorkDir = Join-Path $TempRoot "mock-gh-project"
    $MockBinDir = Join-Path $TempRoot "mock-bin"
    New-Item -ItemType Directory -Force -Path $MockWorkDir, $MockBinDir | Out-Null

    $mockStateFile = Join-Path $TempRoot "mock-gh-counter.txt"
    [System.IO.File]::WriteAllText($mockStateFile, "50")

    $mockJson = @'
[
  {"number": 1, "title": "Null-Body & Bug Label", "body": null, "state": "OPEN", "labels": [{"name": "bug"}]},
  {"number": 2, "title": "Lokal offen aber auf GH geschlossen", "body": "Text", "state": "CLOSED", "labels": []},
  {"number": 3, "title": "Lokal zu aber auf GH wieder offen", "body": "Text", "state": "OPEN", "labels": [{"name": "low"}]}
]
'@
    $mockJsonPath = Join-Path $TempRoot "mock-issues.json"
    [System.IO.File]::WriteAllText($mockJsonPath, $mockJson, [System.Text.UTF8Encoding]::new($false))

    $mockPs1 = @"
param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$AllArgs)
`$sub = (`$AllArgs | Select-Object -First 2) -join " "
if (`$sub -eq "issue list") {
    Get-Content -Raw -LiteralPath "$mockJsonPath" -Encoding UTF8
    exit 0
}
if (`$sub -eq "issue create") {
    `$c = [int](Get-Content -LiteralPath "$mockStateFile")
    Set-Content -LiteralPath "$mockStateFile" -Value (`$c + 1)
    Write-Output "https://github.com/GermanAutodidact/index-cli/issues/`$c"
    exit 0
}
if (`$sub -eq "issue close" -or `$sub -eq "issue reopen" -or `$sub -eq "issue comment") {
    exit 0
}
exit 0
"@
    $mockPs1Path = Join-Path $MockBinDir "gh-mock.ps1"
    [System.IO.File]::WriteAllText($mockPs1Path, $mockPs1, [System.Text.UTF8Encoding]::new($true))
    $mockCmd = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$mockPs1Path`" %*`r`nexit /b %ERRORLEVEL%`r`n"
    [System.IO.File]::WriteAllText((Join-Path $MockBinDir "gh.cmd"), $mockCmd, [System.Text.ASCIIEncoding]::new())

    Set-Location $MockWorkDir
    $null = Invoke-CliCmd @("init")

    # Vorbereiten: Issue #2 lokal in open, Issue #3 lokal in closed
    [System.IO.File]::WriteAllText((Join-Path $MockWorkDir ".issues\open\2-alt.md"), "---`nid: 2`ntitle: `"Alt`"`nstatus: todo`nprio: med`n---`n`nBody`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $MockWorkDir ".issues\closed\3-reopen-test.md"), "---`nid: 3`ntitle: `"Alt`"`nstatus: closed`nprio: med`n---`n`nBody`n", [System.Text.UTF8Encoding]::new($false))

    $oldPathEnv = $env:Path
    $env:Path = "$MockBinDir;$env:Path"
    try {
        $r = Invoke-CliCmd @("sync")
        Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "1 neu, 0 aktualisiert, 1 geschlossen, 1 wiedergeöffnet") "4-Wege-Sync: Import (mit null-body), Close und Reopen erkannt"
        Assert-True (Test-Path ".issues\closed\2-alt.md") "Sync hat #2 nach closed verschoben"
        Assert-True (Test-Path ".issues\open\3-reopen-test.md") "Sync hat #3 zurück nach open verschoben"

        $r = Invoke-CliCmd @("show", "1")
        Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "Prio:\s+high") "Sync setzt bug-Label auf Prio high"

        # Offline-Tickets anlegen mit Abhängigkeit (#10001 blockiert durch #10000) & geschlossenes Offline-Ticket (#10002)
        $null = Invoke-CliCmd @("new", "Offline Basis", "-offline")
        $null = Invoke-CliCmd @("new", "Offline Kind", "-by", "10000", "-offline")
        $null = Invoke-CliCmd @("new", "Offline Fertig", "-offline")
        $null = Invoke-CliCmd @("close", "10002", "-note", "Schon fertig")

        $r = Invoke-CliCmd @("push")
        Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "pushed: #10000 -> #50" -and $r.Output -match "pushed: #10001 -> #51") "push lädt offene Offline-Tickets #10000->#50 und #10001->#51 hoch"

        $r = Invoke-CliCmd @("show", "51")
        Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "BlockedBy:\s+#50") "push hat blocked_by [10000] automatisch auf [50] umgeschrieben"

        $r = Invoke-CliCmd @("push", "--all")
        Assert-True ($r.ExitCode -eq 0 -and $r.Output -match "pushed: #10002 -> #52") "push --all lädt auch lokal geschlossene Offline-Tickets hoch"
    } finally {
        $env:Path = $oldPathEnv
    }
} finally {
    Set-Location $OrigLoc
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`nErgebnis: $PassCount bestanden, $FailCount fehlgeschlagen." -ForegroundColor Cyan
if ($FailCount -gt 0) { exit 1 }
exit 0
