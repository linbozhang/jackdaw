# T11-T2 QA acceptance: independent re-verification of the parameter
# three-state chain (edit -> disk -> cold-reopen) plus a sharper C11 probe.
# The implementer's C11 evidence happened to lose jump_speed while it sat at
# its Default (4.5 == 4.5, no visible harm). This QA pass sets jump_speed to
# a NON-default 6.0 first, then edits only move_speed: if the unedited
# sibling drops from the saved document, a tuned value is silently lost --
# the data-loss face of C11, not just the cosmetic one.
# Legs:
#   P1_SET1   : set jump_speed=6.0 -> save(abs path) -> disk shows 6.0
#   P2_SET2   : set move_speed=3.0 -> save -> disk shows 3.0; is jump_speed
#               still 6.0?  (C11 verdict cell: kept / lost / reset-to-default)
#   P3_REOPEN : cold editor restart -> open the QA file -> save to a second
#               file -> move_speed=3.0 survives (three-state close-out)
# Source scene assets/t11t2-place.bsn is never written (all saves go to
# QA-owned absolute paths; scene.save needs absolute paths -- T2 tooling
# finding #4).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t2-qa-param.ps1
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$Port = 15806
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$QaDir = Join-Path $Repo 'loop\qa'
$Exe = Join-Path $Repo 'target\debug\jackdaw.exe'
if (-not (Test-Path $Exe)) { Write-Host 'EXE_MISSING'; exit 1 }
$SaveDir = 'H:\workspace_AI\t11-live\qa'
New-Item -ItemType Directory -Force -Path $SaveDir | Out-Null
$QaBsn  = Join-Path $SaveDir 'qa-param.bsn'
$QaBsn2 = Join-Path $SaveDir 'qa-param-reopen.bsn'
Remove-Item $QaBsn, $QaBsn2 -Force -ErrorAction SilentlyContinue

function Brp([string]$method, $params, [int]$retries = 3) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 12)
        } catch { Start-Sleep -Milliseconds (300 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp 'jackdaw/call_operator' @{ id = $id } }
}
function Wait-Idle([int]$TimeoutSec = 120) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp 'jackdaw/wait' @{ until = 'idle' } 1
        if ($r -and $r.result -and $r.result.idle) { return $true }
        Start-Sleep -Seconds 1
    }
    Write-Host 'wait(idle) timeout (continuing)'
    return $false
}
$TKEY = 'bevy_transform::components::transform::Transform'
function Props($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) { return $e.components.PSObject.Properties }
    return $e.components
}
function Get-T($e) {
    foreach ($prop in (Props $e)) { if ("$($prop.Name)" -eq $TKEY) { return $prop.Value } }
    return $null
}
function Has-Comp([object]$e, [string]$suffix) {
    if (-not $e) { return $false }
    foreach ($prop in (Props $e)) { if ("$($prop.Name)" -like "*$suffix") { return $true } }
    return $false
}
function Snap { (Brp 'jackdaw/scene_snapshot' @{} 1).result }
function Find-PlacedPlayer {
    foreach ($e in @((Snap))) {
        $t = Get-T $e
        if (-not $t) { continue }
        $x = [double]$t.translation[0]; $y = [double]$t.translation[1]
        if ((Has-Comp $e 'Brush') -and (Has-Comp $e 'RigidBody') -and ([Math]::Abs($x - 2.0) -lt 0.6) -and ($y -gt 0.5)) { return $e.entity }
    }
    return $null
}
$results = @{}
function Leg([string]$name, [bool]$ok) {
    $results[$name] = $ok
    Write-Host ("{0}_{1}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }))
}
function Read-Doc([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    return [IO.File]::ReadAllText($path)
}
function Parse-Block([string]$doc) {
    # returns @{ move_speed; jump_speed } from the PlayerController block
    $out = @{ move_speed = $null; jump_speed = $null }
    if (-not $doc) { return $out }
    $i = $doc.IndexOf('PlayerController')
    if ($i -lt 0) { return $out }
    $blk = $doc.Substring($i, [Math]::Min(260, $doc.Length - $i))
    Write-Host ("  doc block: {0}" -f (($blk -replace "\r?\n", ' | ').Substring(0, [Math]::Min(200, $blk.Length))))
    if ($blk -match 'move_speed:\s*([0-9.]+)') { $out.move_speed = [double]$Matches[1] }
    if ($blk -match 'jump_speed:\s*([0-9.]+)') { $out.jump_speed = [double]$Matches[1] }
    return $out
}
function Kill-All {
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Milliseconds 800
}
function Start-Editor([string]$logName) {
    Kill-All
    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT = "$Port"
    $env:JACKDAW_WINDOW_SIZE = '1920x1080'
    $env:RUST_BACKTRACE = '1'
    $editorLog = Join-Path $QaDir $logName
    $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
    $env:PATH = "$deps;$env:PATH"
    cmd /c "start /B /D `"$(Split-Path -Parent $Exe)`" cmd /c `"`"$Exe`" > `"$editorLog`" 2>`&1`""
    for ($i = 0; $i -lt 150; $i++) {
        Start-Sleep -Seconds 2
        if (Brp 'jackdaw/status' @{} 1) { return $true }
    }
    return $false
}
function Post-Boot-Hygiene {
    $st0 = (Brp 'jackdaw/status' @{} 2).result
    if ($st0 -and $st0.dialog) {
        Write-Host ("boot dialog up: {0}" -f ($st0.dialog | ConvertTo-Json -Depth 3 -Compress))
        Op 'dialog.answer' @{ choice = '0' } | Out-Null
        Start-Sleep -Seconds 2
    }
    $schemaJson = Join-Path $Project '.jackdaw\schema.json'
    if (Test-Path $schemaJson) {
        (Get-Item $schemaJson).LastWriteTime = Get-Date
        Start-Sleep -Seconds 6
    }
}

# --- round 1: edit chain -------------------------------------------------------------
if (-not (Start-Editor 't11t2-qa-param-editor1.log')) { Write-Host 'EDITOR_BOOT_FAIL'; exit 1 }
Wait-Idle 1200; Start-Sleep -Seconds 3
Post-Boot-Hygiene
Op 'scene.open' @{ path = 'assets/t11t2-place.bsn' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
$player = Find-PlacedPlayer
Write-Host ("placed player entity: {0}" -f $player)
if (-not $player) { Write-Host 'PLAYER_NOT_FOUND'; Kill-All; exit 1 }

# P1: set jump_speed to a NON-default value, save, read disk
$r1 = Op 'component.set' @{ entity = $player; type_path = 't11t1_game::PlayerController'; field = 'jump_speed'; value = '6.0' }
$w1 = if ($r1 -and $r1.result.warnings) { $r1.result.warnings -join ';' } else { '' }
Write-Host ("P1 set jump_speed=6.0 response warnings: [{0}]" -f $w1)
Wait-Idle 60; Start-Sleep -Seconds 1
Op 'scene.save' @{ path = $QaBsn } | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$b1 = Parse-Block (Read-Doc $QaBsn)
Write-Host ("P1 disk: move_speed={0} jump_speed={1} (expect 2.0 / 6.0)" -f $b1.move_speed, $b1.jump_speed)
Leg 'P1_SET1' (($b1.jump_speed -eq 6.0) -and ($w1 -eq ''))

# P2: set ONLY move_speed, save, is the tuned jump_speed still there? (C11 cell)
$r2 = Op 'component.set' @{ entity = $player; type_path = 't11t1_game::PlayerController'; field = 'move_speed'; value = '3.0' }
$w2 = if ($r2 -and $r2.result.warnings) { $r2.result.warnings -join ';' } else { '' }
Write-Host ("P2 set move_speed=3.0 response warnings: [{0}]" -f $w2)
Wait-Idle 60; Start-Sleep -Seconds 1
Op 'scene.save' @{ path = $QaBsn } | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$b2 = Parse-Block (Read-Doc $QaBsn)
Write-Host ("P2 disk: move_speed={0} jump_speed={1} (move_speed must be 3.0; jump_speed kept=6.0 / lost=absent / reset=4.5)" -f $b2.move_speed, $b2.jump_speed)
Leg 'P2_SET2' ($b2.move_speed -eq 3.0)
Leg 'P2_C11_JUMP_KEPT' ($b2.jump_speed -eq 6.0)

# --- round 2: cold restart, reopen the QA file, values survive ------------------------
if (-not (Start-Editor 't11t2-qa-param-editor2.log')) { Write-Host 'EDITOR_BOOT_FAIL'; exit 1 }
Wait-Idle 1200; Start-Sleep -Seconds 3
Post-Boot-Hygiene
$openR = Op 'scene.open' @{ path = $QaBsn }
Wait-Idle 90; Start-Sleep -Seconds 2
Op 'scene.save' @{ path = $QaBsn2 } | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$b3 = Parse-Block (Read-Doc $QaBsn2)
Write-Host ("P3 reopen->save: move_speed={0} jump_speed={1} (three-state close-out expects move_speed=3.0)" -f $b3.move_speed, $b3.jump_speed)
Leg 'P3_REOPEN' ($b3.move_speed -eq 3.0)
Leg 'P3_C11_JUMP_KEPT' ($b3.jump_speed -eq 6.0)

Kill-All
$summary = ($results.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
[IO.File]::WriteAllText((Join-Path $QaDir 't11t2-qa-param-summary.txt'), "$summary`r`n")
Write-Host ("VERDICT_QA_PARAM: {0}" -f $summary)
Write-Host 'T11T2_QA_PARAM_DONE'
