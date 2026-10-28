# QA manual assertions for the relaunch phase (the steps script's status
# poll stalls in the busy window, same as the programmer hit).
$ErrorActionPreference = 'Stop'
$Cfg = "$env:TEMP\t04-kill-cfg-qa"
$root = Join-Path $Cfg 'state\sessions'
$dead = 'C:\Users\linbo.zhang\AppData\Local\Temp\t04-kill-cfg-qa\state\sessions\01004ec43583bb23\23236-1792918434'

# 1. dead session residue survived the relaunch
$deadJournal = Join-Path $dead 'journal.json'
if (-not (Test-Path $deadJournal)) { throw "the dead session vanished on relaunch: $deadJournal" }
Write-Output ("[dead journal] survived, " + (Get-Item $deadJournal).Length + " bytes")

# 2. dead journal parses
$parsed = Get-Content $deadJournal -Raw | ConvertFrom-Json
Write-Output ("[dead journal tabs] " + $parsed.tabs.Count + " -> " + (($parsed.tabs | ForEach-Object { "$($_.kind):$($_.display_name) entities=$($_.entity_count) saved_at=$($_.saved_at)" }) -join '; '))

# 3. side-by-side sessions
$sessionDirs = @()
foreach ($hash in @(Get-ChildItem $root -Directory)) {
    foreach ($s in @(Get-ChildItem -LiteralPath $hash.FullName -Directory)) { $sessionDirs += $s }
}
Write-Output "[session dirs] " + (($sessionDirs | ForEach-Object { $_.Name }) -join ', ')
if ($sessionDirs.Count -lt 2) { throw "expected the dead session and the new live session side by side" }
$live = $sessionDirs | Where-Object { $_.Name -ne (Split-Path $dead -Leaf) } | Select-Object -First 1
Write-Output ("[new session] " + $live.Name)
$liveJournal = Join-Path $live.FullName 'journal.json'
Write-Output ("[new session journal] " + $(if (Test-Path $liveJournal) { "EXISTS (" + (Get-Item $liveJournal).Length + " bytes)" } else { "absent (clean tabs journal nothing - correct)" }))

# 4. live editor pid matches the new session dir
$proc = Get-Process jackdaw -ErrorAction Stop | Select-Object -First 1
Write-Output ("[live pid] " + $proc.Id + " (session dir says " + ($live.Name -split '-')[0] + ")")
if ($proc.Id -ne [int](($live.Name -split '-')[0])) { throw "live session dir does not match the running pid" }
Write-Output 'RELAUNCH VERDICT: PASS (dead session residue is the recovery signal, new session side by side)'
