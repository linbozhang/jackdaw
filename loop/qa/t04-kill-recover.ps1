# T04-T2 real-machine kill chain (manual.md section 7 tools):
# launch the editor on my-game with an isolated JACKDAW_CONFIG_DIR ->
# make an edit through the operator chain -> wait for the crash journal to
# land under <config>/state/sessions/<project-hash>/<pid>-<ts>/journal.json
# -> taskkill /F -> assert the session directory (and journal) survived ->
# relaunch on the same config dir -> assert the dead session is still
# there (the "something happened" signal) alongside the new live one.
param(
    [Parameter(Mandatory = $true)][ValidateSet('launch', 'kill', 'relaunch', 'wrap')][string]$Phase,
    [int]$Port = 15813,
    [string]$Proj = 'C:\Users\linbo.zhang\Projects\my-game',
    [string]$Cfg = "$env:TEMP\t04-kill-cfg",
    [string]$EditorLog = "$env:TEMP\t04-kill-editor.log"
)
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t04t2-kill'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$State = "$env:TEMP\t04-kill-state.txt"

function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 10
        } catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout waiting for $Method $Params"
}
# Short-circuit readiness: `jackdaw/wait until=idle` stalls for minutes
# while the project's background PIE pre-build keeps the editor busy
# (the T2 lesson). `jackdaw/status` answering is readiness enough for a
# chain that asserts on files; wait for idle only when asked to.
function Wait-Ready([int]$T = 120) { Brp-Call 'jackdaw/status' @{} $T | Out-Null }
function Wait-Idle([int]$T = 60) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }
function Start-Editor {
    $sysroot = (& rustc --print sysroot).Trim()
    $tcLib = Join-Path $sysroot 'lib\rustlib\x86_64-pc-windows-msvc\lib'
    $deps = 'E:\Project\rust\jackdaw\target\debug\deps'
    $bat = "$env:TEMP\t04-kill-launch.cmd"
    $lines = @(
        "@echo off",
        "set PATH=$deps;$tcLib;%PATH%",
        "set JACKDAW_OPEN_PROJECT=$Proj",
        "set JACKDAW_REMOTE_PORT=$Port",
        "set JACKDAW_CONFIG_DIR=$Cfg",
        "set JACKDAW_SKIP_SETUP_CHECK=1",
        "cd /d E:\Project\rust\jackdaw",
        "start `"t04kill`" /MIN cmd /c `"target\debug\jackdaw.exe > $EditorLog 2>&1`"",
        "exit"
    )
    [System.IO.File]::WriteAllLines($bat, $lines)
    $shell = New-Object -ComObject Shell.Application
    $shell.ShellExecute('open', "`"$bat`"", '', 'open', 0) | Out-Null
    $deadline = (Get-Date).AddSeconds(180); $ok = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 4
        if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break }
    }
    if (-not $ok) { throw 'editor never listened' }
    Brp-Call 'jackdaw/status' @{} 90 | Out-Null
    Wait-Ready 120
}
function Find-Journal {
    Get-ChildItem -Path (Join-Path $Cfg 'state\sessions') -Recurse -Filter journal.json -File -ErrorAction SilentlyContinue
}

switch ($Phase) {
    'launch' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (Test-Path $Cfg) { Remove-Item $Cfg -Recurse -Force }
        Start-Editor
        $status = (Brp-Call 'jackdaw/status' @{}).result
        Write-Output ("[pid] " + $status.pid + "  [scene] " + $status.scene)
        # One unsaved edit through the operator chain lights the tab.
        $r = Op 'entity.add.cube' @{}
        Write-Output ("[add cube] " + ($r | ConvertTo-Json -Depth 6 -Compress))
        Wait-Idle
        $dirty = (Brp-Call 'jackdaw/status' @{}).result.dirty
        Write-Output ("[dirty] " + $dirty)
        if (-not $dirty) { throw 'the edit did not light the tab; journal would never land' }
        # The debounce is 2s; poll for the journal to land.
        $deadline = (Get-Date).AddSeconds(30); $journal = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $journal = Find-Journal | Select-Object -First 1
            if ($journal) { break }
        }
        if (-not $journal) { throw 'journal.json never landed' }
        $age = ((Get-Date) - $journal.LastWriteTime).TotalSeconds
        Write-Output ("[journal] " + $journal.FullName + " (fresh ${age}s, " + $journal.Length + " bytes)")
        if ($age -gt 30) { throw "journal is stale (${age}s)" }
        Copy-Item $journal.FullName (Join-Path $OutDir '10-pre-kill-journal.json') -Force
        # Record the session dir and pid for the kill phase.
        "$($status.pid)|$($journal.DirectoryName)" | Set-Content -Encoding UTF8 $State
        Write-Output 'LAUNCH VERDICT: PASS'
    }
    'kill' {
        $parts = (Get-Content $State) -split '\|', 2
        $pidToKill = [int]$parts[0]; $sessionDir = $parts[1]
        taskkill /F /PID $pidToKill | Out-Null
        Start-Sleep -Seconds 2
        $journal = Join-Path $sessionDir 'journal.json'
        if (-not (Test-Path $journal)) { throw "kill left no journal behind: $journal" }
        $bytes = (Get-Item $journal).Length
        Write-Output ("[after kill] $journal survived ($bytes bytes)")
        Copy-Item $journal (Join-Path $OutDir '11-post-kill-journal.json') -Force
        Write-Output 'KILL VERDICT: PASS (session directory survived the hard kill)'
    }
    'relaunch' {
        $parts = (Get-Content $State) -split '\|', 2
        $deadDir = $parts[1]
        Start-Editor
        $status = (Brp-Call 'jackdaw/status' @{}).result
        Write-Output ("[relaunched pid] " + $status.pid)
        if (-not (Test-Path (Join-Path $deadDir 'journal.json'))) { throw 'the dead session vanished on relaunch' }
        $live = Find-Journal | Where-Object { $_.DirectoryName -ne $deadDir }
        $dirs = Get-ChildItem (Join-Path $Cfg 'state\sessions') -Recurse -Directory |
            Where-Object { $_.GetFiles('journal.json').Count -ge 0 -and $_.Name -match '^\d+-\d+$' }
        Write-Output ("[dead session kept] " + $deadDir)
        Write-Output ("[session dirs now] " + (($dirs | ForEach-Object { $_.Name }) -join ', '))
        if ($dirs.Count -lt 2) { throw 'expected the dead session and the new live session side by side' }
        Write-Output 'RELAUNCH VERDICT: PASS (dead session residue is the recovery signal)'
    }
    'wrap' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output "editor stopped; isolated config kept at $Cfg as evidence"
    }
}
