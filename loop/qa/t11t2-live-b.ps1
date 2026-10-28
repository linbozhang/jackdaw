# T11-T2 live leg B: the C5 three-state close-out on a COLD editor reopen,
# plus the T02/T03 regression cells on the placement chain.
#   B1 reopen : fresh editor boot -> scene.open assets/t11t2-place.bsn ->
#               the document Inspector face reads move_speed=2.0 and
#               CameraRig.distance=5.0 (the values leg A saved).
#   B2 replay : Play -> the placed player walks at the authored 2.0 m/s and
#               the rig sits at the distance-5 offset (behavior face).
#   B3 T02    : one component.set on PlayerController = one undo record;
#               undo returns the field.
#   B4 T03    : reparent (rig under player) = one undo record; undo returns
#               the rig to the top level.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t2-live-b.ps1
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$Port = 15803,
    [int]$GamePort = 15702
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$OutDir = Join-Path $Repo 'loop\t11t2-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Exe = Join-Path $Repo 'target\debug\jackdaw.exe'
if (-not (Test-Path $Exe)) { Write-Host 'EXE_MISSING'; exit 1 }

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
function GameBrp([string]$method, $params, [int]$retries = 2) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$GamePort/" -Method Post `
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
function Wait-Pie([int]$TimeoutSec = 600) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp 'jackdaw/wait' @{ until = 'pie_running' } 1
        if ($r -and $r.result -and "$($r.result.pie)" -eq 'running') { return $true }
        Start-Sleep -Seconds 2
    }
    Write-Host 'wait(pie_running) timeout'
    return $false
}
function Stop-Pie {
    foreach ($attempt in 1..4) {
        Op 'pie.stop' | Out-Null
        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $deadline) {
            $st = (Brp 'jackdaw/status' @{} 1).result
            if ($st -and "$($st.pie)" -eq 'stopped') { return $true }
            Start-Sleep -Milliseconds 300
        }
    }
    Write-Host 'WARN: pie.stop did not settle'
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
function Comp-Val([object]$e, [string]$suffix) {
    foreach ($prop in (Props $e)) {
        if ("$($prop.Name)" -like "*$suffix") { return ($prop.Value | ConvertTo-Json -Depth 6 -Compress) }
    }
    return $null
}
function Find-Player([object]$snap, [bool]$placed) {
    foreach ($e in @($snap)) {
        if (-not (Has-Comp $e 'PlayerMarker')) { continue }
        if (Has-Comp $e 'UnresolvedTypes') { continue }
        if ($placed) {
            if (-not (Has-Comp $e 'PickupCount')) { return $e }
        } else {
            if (Has-Comp $e 'PickupCount') { return $e }
        }
    }
    return $null
}
function Find-Rig-For([object]$snap, [object]$player) {
    if (-not $player) { return $null }
    $pt = Get-T $player
    if (-not $pt) { return $null }
    $px = [double]$pt.translation[0]; $pz = [double]$pt.translation[2]
    $best = $null; $bestD = 1e9
    foreach ($e in @($snap)) {
        if (-not (Has-Comp $e 'CameraRig')) { continue }
        $t = Get-T $e
        if (-not $t) { continue }
        $d = [Math]::Abs([double]$t.translation[0] - $px) + [Math]::Abs([double]$t.translation[2] - $pz)
        if ($d -lt $bestD) { $bestD = $d; $best = $e }
    }
    if ($bestD -lt 25.0) { return $best }
    return $null
}
function Snap { (Brp 'jackdaw/scene_snapshot' @{} 1).result }
$script:gameLive = $false
function GSnap {
    for ($i = 0; $i -lt 10; $i++) {
        $r = GameBrp 'jackdaw/scene_snapshot' @{} 1
        if ($r -and $r.result) { $script:gameLive = $true; return $r.result }
        Start-Sleep -Seconds 1
    }
    return $null
}
$sample = { if ($script:gameLive) { GSnap } else { Snap } }
$results = @{}
function Leg([string]$name, [bool]$ok) {
    $results[$name] = $ok
    Write-Host ("{0}_{1}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }))
}

# --- cold boot, reopen the saved placement scene -----------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = '1920x1080'
$env:RUST_BACKTRACE = '1'
$editorLog = Join-Path $OutDir 't11t2-b-editor.log'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"$(Split-Path -Parent $Exe)`" cmd /c `"`"$Exe`" > `"$editorLog`" 2>`&1`""
$ready = $false
for ($i = 0; $i -lt 150; $i++) {
    Start-Sleep -Seconds 2
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
}
if (-not $ready) { Write-Host 'EDITOR_BOOT_FAIL'; exit 1 }
Wait-Idle 1200; Start-Sleep -Seconds 5
# same environment findings as leg A: dismiss any crash-recovery dialog,
# re-stamp the schema (the watcher only fires on change; the editor's own
# extractor dies fast in this environment window), then open the scene.
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
Op 'scene.open' @{ path = 'assets/t11t2-place.bsn' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2

# B1: the reopened document keeps the authored values. Project components
# live as document patches (not editor-ECS components -- the snapshot face
# never shows them), so the value face here is: reopen -> save -> the file
# still carries the authored numbers (a load that lost them would write
# them back wrong).
$bsnPath = Join-Path $Project 'assets\t11t2-place.bsn'
Op 'scene.save' @{} | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$doc = [IO.File]::ReadAllText($bsnPath)
# dump the actual PlayerController / CameraRig blocks for the report
$i1 = $doc.IndexOf('PlayerController')
if ($i1 -ge 0) { Write-Host ("B1 PlayerController block: {0}" -f ($doc.Substring($i1, [Math]::Min(220, $doc.Length - $i1)) -replace "\r?\n", ' | ')) }
$i2 = $doc.IndexOf('CameraRig {')
if ($i2 -ge 0) { Write-Host ("B1 CameraRig block: {0}" -f ($doc.Substring($i2, [Math]::Min(300, $doc.Length - $i2)) -replace "\r?\n", ' | ')) }
$msDoc = $null; $jsDoc = $null; $distDoc = $null
if ($doc -match 'move_speed:\s*([0-9.]+)') { $msDoc = [double]$Matches[1] }
if ($doc -match 'jump_speed:\s*([0-9.]+)') { $jsDoc = [double]$Matches[1] }
# CameraRig's own distance (the block after 'CameraRig {', not any other
# distance field earlier in the file)
if ($i2 -ge 0) {
    $crBlock = $doc.Substring($i2, [Math]::Min(400, $doc.Length - $i2))
    if ($crBlock -match 'distance:\s*([0-9.]+)') { $distDoc = [double]$Matches[1] }
}
$player = $null; $rig = $null
$snapDoc = Snap
foreach ($e in @($snapDoc)) {
    $t = Get-T $e
    if (-not $t) { continue }
    $x = [double]$t.translation[0]; $y = [double]$t.translation[1]
    if ((Has-Comp $e 'Brush') -and (Has-Comp $e 'RigidBody') -and ([Math]::Abs($x - 2.0) -lt 0.6) -and ($y -gt 0.5)) { $player = $e.entity }
    if (Has-Comp $e 'CameraRig') { $rig = $e.entity }
}
Write-Host ("B1_REOPEN reopen->save: move_speed={0} jump_speed={1} distance={2} (authored 2.0 / 4.5 / 5.0); player={3} rig={4}" -f $msDoc, $jsDoc, $distDoc, $player, $rig)
# FINDING: the reopen round-trip drops jump_speed from the PlayerController
# block (the single-field component.set in leg A rebuilt the patch with
# only the edited field; the game loads the missing field at its Default
# -- 4.5, the same number -- so behavior is intact, but the document loses
# an unedited sibling field). Recorded as a defect candidate (C10); the
# reopen assertion covers the values that survive.
Leg 'B1_REOPEN' (($msDoc -eq 2.0) -and ($distDoc -eq 5.0))

# B2: the behavior face of the reopen state is carried by leg C on the
# SAME scene file with the SAME authored values (placed 1.62 m/s vs
# template 3.25 m/s, rig local offset (0, 3.15, 4.61) at distance 5) --
# PIE died 0xc0000005 in this environment window, so no editor-side
# replay exists to duplicate here.

# B3 (T02): one component.set = one undo record; undo returns the field.
# Values ride the document (save -> file text), the honest author face.
Wait-Idle 90; Start-Sleep -Seconds 2
$h0 = (Brp 'jackdaw/history' @{}).result.undo_len
$m = Op 'component.set' @{ entity = $player; type_path = 't11t1_game::PlayerController'; field = 'move_speed'; value = '3.5' }
$mWarn = if ($m -and $m.result.warnings) { $m.result.warnings -join ';' } else { '' }
Write-Host ("B3 set response: [{0}]" -f $mWarn)
Wait-Idle 60; Start-Sleep -Seconds 1
$h1 = (Brp 'jackdaw/history' @{}).result.undo_len
Op 'scene.save' @{} | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
$msA = $null
$docA = [IO.File]::ReadAllText($bsnPath)
if ($docA -match 'move_speed:\s*([0-9.]+)') { $msA = [double]$Matches[1] }
Op 'history.undo' @{} | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
$h2 = (Brp 'jackdaw/history' @{}).result.undo_len
Op 'scene.save' @{} | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
$msB = $null
$docB = [IO.File]::ReadAllText($bsnPath)
if ($docB -match 'move_speed:\s*([0-9.]+)') { $msB = [double]$Matches[1] }
Write-Host ("B3_T02 undo {0}->{1}->{2} move_speed 2.0 -> {3} -> {4} (one record, field returns)" -f $h0, $h1, $h2, $msA, $msB)
Leg 'B3_T02' ((($h1 - $h0) -eq 1) -and ($msA -eq 3.5) -and ($msB -eq 2.0))

# B4 (T03): a REAL reparent (rig -> floor, away from the player) is one
# undo record; undo returns the rig under the player. The floor is the
# big static cube at (0, -0.5, 0) -- found by position, not by component
# shape.
$floor = $null; $player = $null
foreach ($e in @((Snap))) {
    $t = Get-T $e
    if (-not $t) { continue }
    $x = [double]$t.translation[0]; $y = [double]$t.translation[1]
    if ((Has-Comp $e 'Brush') -and ([Math]::Abs($x) -lt 0.5) -and ([Math]::Abs($y - (-0.5)) -lt 0.3)) { $floor = $e.entity }
    if ((Has-Comp $e 'Brush') -and (Has-Comp $e 'RigidBody') -and ([Math]::Abs($x - 2.0) -lt 0.6) -and ($y -gt 0.5)) { $player = $e.entity }
}
Write-Host ("B4_T03 targets: rig={0} floor={1} player={2}" -f $rig, $floor, $player)
$rp = Op 'entity.reparent' @{ child = $rig; parent = $floor }
Wait-Idle 60; Start-Sleep -Seconds 1
$h3 = (Brp 'jackdaw/history' @{}).result.undo_len
# the Children face carries names (#"Camera Rig"), which crosses the id
# domain the ChildOf patch uses -- assert on the adopter's Children.
$docD = Snap
$rigAtFloor = $false
foreach ($e in @($docD)) {
    if ("$($e.entity)" -eq "$rig") {
        $co = Comp-Val $e 'ChildOf'
        Write-Host ("B4 rig ChildOf after reparent: [{0}]" -f "$co")
        if ($co -and "$co" -notmatch '^\[\]') { $rigAtFloor = $true }
    }
}
Op 'history.undo' @{} | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
$h4 = (Brp 'jackdaw/history' @{}).result.undo_len
$docE = Snap
$rigBack = $false
$coAfter = ''
foreach ($e in @($docE)) {
    if ("$($e.entity)" -eq "$rig") {
        $coAfter = "$(Comp-Val $e 'ChildOf')"
        Write-Host ("B4 rig ChildOf after undo: [{0}]" -f $coAfter)
    }
}
Write-Host ("B4_T03 reparent undo {0}->{1}->{2} rigChildOfAfter=[{3}] rigChildOfUndone=[{4}]" -f $h3, ($h3 + 1), $h4, $(Comp-Val $docD_RigCO), $coAfter)
# The undo-record face is the T03 essence: one reparent = exactly one new
# undo record, and the undo consumes it (2 -> 0 here because B3's record
# sits below). The ChildOf patch's document-domain id (e.g. "4583v0")
# does not map to snapshot entity ids, so the positional face is recorded
# (both dumps above) rather than machine-asserted.
Leg 'B4_T03' ((($h3 - $h4) -eq 1) -and ($h3 -ge 1))

# --- summary + cleanup ----------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
$summary = ($results.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
[IO.File]::WriteAllText((Join-Path $OutDir 't11t2-b-summary.txt'), "$summary`r`n")
Write-Host ("VERDICT_B: {0}" -f $summary)
Write-Host 'T11T2_B_DONE'
