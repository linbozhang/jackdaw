# T11-T2 live leg A: the editor placement chain, end to end, all through
# the editor's operators (the acceptance sentence "place a player and a
# floor and it plays", taken literally):
#   A1 build the chain    : empty scene -> Add Entity cube (the player) ->
#                           Add Component PlayerMarker/PlayerController ->
#                           RigidBody=Kinematic + AvianCollider capsule ->
#                           Add Entity Camera Rig -> reparent under the
#                           player -> floor cube + physics.enable -> save.
#   A2 C9 dead-camera leg : Play with TWO rigs in the world (the template's
#                           spawned one + the placed one): lone-rig
#                           activation stands down (documented semantics) --
#                           no rig materializes a camera; capture refuses.
#   A3 activate + play    : add ActiveCameraRig on the placed rig in the
#                           document (the template doc's instruction) and
#                           find out whether the save path strips it; if it
#                           does, add it Live (the running-game stream) and
#                           record the discrepancy against the doc.
#   A4 four behaviors     : walk (W series), jump (Space y series), wall
#                           stop (north wall clamp), camera follow (rig
#                           world offset constant across two positions).
#   A5 C7 Look            : input.motion dx=240 -> rig yaw -1.2 (math
#                           assert); RMB held + same motion -> single
#                           channel only (bridge yields, crate channel
#                           drives) or zero if the forwarded event never
#                           reaches AccumulatedMouseMotion -- whichever,
#                           measured, not assumed; never double.
# Sampling: the editor's scene_snapshot (live projection) is the primary
# channel; the game's own BRP on 15702 (the warm project wires
# JackdawRemotePlugin) is probed and used when it answers.
# Boot is detached: cmd start /B only. No WGPU_BACKEND (driver OOM is a
# known state, not a code defect). RUST_BACKTRACE=1 is set (N13 watch).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t2-live-a.ps1
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$Port = 15802,
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
function Wait-Pie([int]$TimeoutSec = 900) {
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
    $p = Props $e
    foreach ($prop in $p) { if ("$($prop.Name)" -eq $TKEY) { return $prop.Value } }
    return $null
}
function Comp-Json($e, [string]$suffix) {
    foreach ($prop in (Props $e)) {
        if ("$($prop.Name)" -like "*$suffix") { return ($prop.Value | ConvertTo-Json -Depth 6 -Compress) }
    }
    return $null
}
function Has-Comp([object]$e, [string]$suffix) {
    if (-not $e) { return $false }
    foreach ($prop in (Props $e)) { if ("$($prop.Name)" -like "*$suffix") { return $true } }
    return $false
}
# The placed player stands at (2, ~0.86, 2); the template's spawned one at
# (-2, ~0.86, 0). Position first (the projection's component list is not
# guaranteed to carry project components); the PickupCount discriminator
# (only the template's carries it) refines when present.
function Find-Player([object]$snap, [bool]$placed) {
    $wantX = -2.0; $wantZ = 0.0
    if ($placed) { $wantX = 2.0; $wantZ = 2.0 }
    $best = $null; $bestD = 1e9
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if (-not $t) { continue }
        $x = [double]$t.translation[0]; $z = [double]$t.translation[2]
        $d = [Math]::Abs($x - $wantX) + [Math]::Abs($z - $wantZ)
        if ($d -lt $bestD) { $bestD = $d; $best = $e }
    }
    if ($bestD -lt 1.6) { return $best }
    # fallback: component discriminator
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
# Rigs: prefer entities actually carrying CameraRig (an engine type the
# projection lists) within the follow window; fall back to geometry (a
# non-player entity 4..12 m out horizontally, riding 3..6.5 m above).
function Find-Rig-For([object]$snap, [object]$player) {
    if (-not $player) { return $null }
    $pt = Get-T $player
    if (-not $pt) { return $null }
    $px = [double]$pt.translation[0]; $py = [double]$pt.translation[1]; $pz = [double]$pt.translation[2]
    $bestTagged = $null; $bestTaggedD = 1e9
    $bestGeom = $null; $bestGeomD = 1e9
    foreach ($e in @($snap)) {
        if ("$($e.entity)" -eq "$($player.entity)") { continue }
        $t = Get-T $e
        if (-not $t) { continue }
        $x = [double]$t.translation[0]; $y = [double]$t.translation[1]; $z = [double]$t.translation[2]
        $d = [Math]::Sqrt([Math]::Pow($x - $px, 2) + [Math]::Pow($z - $pz, 2))
        if ((Has-Comp $e 'CameraRig') -and $d -gt 0.5 -and $d -lt 16.0) {
            if ($d -lt $bestTaggedD) { $bestTaggedD = $d; $bestTagged = $e }
        } elseif ($d -gt 3.0 -and $d -lt 12.0 -and ($y - $py) -gt 2.5 -and ($y - $py) -lt 7.0) {
            if ($d -lt $bestGeomD) { $bestGeomD = $d; $bestGeom = $e }
        }
    }
    if ($null -ne $bestTagged) { return $bestTagged }
    return $bestGeom
}
function Py([object]$e) { $t = Get-T $e; if ($t) { return [double]$t.translation[1] } ; return $null }
function Snap { (Brp 'jackdaw/scene_snapshot' @{} 1).result }
# The game-side snapshot when 15702 answers (the warm project wires the
# RemotePlugin; PIE runs the same binary).
$script:gameLive = $false
function GSnap {
    for ($i = 0; $i -lt 10; $i++) {
        $r = GameBrp 'jackdaw/scene_snapshot' @{} 1
        if ($r -and $r.result) { $script:gameLive = $true; return $r.result }
        Start-Sleep -Seconds 1
    }
    return $null
}
$results = @{}
function Leg([string]$name, [bool]$ok) {
    $results[$name] = $ok
    Write-Host ("{0}_{1}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }))
}

# --- clean boot -----------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = '1920x1080'
$env:RUST_BACKTRACE = '1'
# The schema extractor's 120s default was too short on this box (the first
# extraction raced shader compilation after the 7-minute cold build and got
# killed mid-startup; a manual run of the same extractor answers in ~15s
# with a 900KB schema). Give the editor's own extractor room.
$env:JACKDAW_SCHEMA_EXTRACT_TIMEOUT_SECS = '600'
$editorLog = Join-Path $OutDir 't11t2-a-editor.log'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"$(Split-Path -Parent $Exe)`" cmd /c `"`"$Exe`" > `"$editorLog`" 2>`&1`""
$ready = $false
for ($i = 0; $i -lt 150; $i++) {
    Start-Sleep -Seconds 2
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process jackdaw -ErrorAction SilentlyContinue)) {
        $log = ''
        if (Test-Path $editorLog) { $log = [IO.File]::ReadAllText($editorLog) }
        if ($log -match '0x8007000E|Queue creation failed') {
            Write-Host 'EDITOR_BOOT_FAIL: known DX12 driver OOM (0x8007000E), not a code defect'
        } else {
            Write-Host "EDITOR_BOOT_FAIL; log tail: $($log.Substring([Math]::Max(0, $log.Length - 600)))"
        }
        exit 1
    }
}
if (-not $ready) { Write-Host 'EDITOR_BOOT_FAIL (timeout)'; exit 1 }
Wait-Idle 1200; Start-Sleep -Seconds 8
# A hard kill in a previous run can leave the crash-recovery dialog up; it
# has no bearing on this leg, so dismiss it (keep the fresh state).
$st0 = (Brp 'jackdaw/status' @{} 2).result
if ($st0 -and $st0.dialog) {
    Write-Host ("boot dialog up: {0}" -f ($st0.dialog | ConvertTo-Json -Depth 3 -Compress))
    Op 'dialog.answer' @{ choice = '0' } | Out-Null
    Start-Sleep -Seconds 2
}
# The editor's in-process extractor keeps failing fast (non-zero exit ~8s,
# not the 600s deadline -- an environment-level finding, logged); the
# extractor binary itself is healthy (a manual run of the same command
# answers in ~15s with a 901KB schema). The watcher only fires on CHANGE,
# so re-stamp the extractor's own output to load ProjectTypes.
$schemaJson = Join-Path $Project '.jackdaw\schema.json'
if (Test-Path $schemaJson) {
    $stamp = Get-Date
    (Get-Item $schemaJson).LastWriteTime = $stamp
    Write-Host ("schema.json re-stamped {0:HH:mm:ss}; watcher should refresh project types" -f $stamp)
    Start-Sleep -Seconds 6
}
# Concurrent-extractor probe: run the same extractor command by hand WHILE
# the editor is alive, to pin whether the in-process failure is a
# concurrent-with-editor condition (data for the report; not a blocker).
$gameExe = Join-Path $Project '.jackdaw\target\game\debug\t11t1-game.exe'
if (Test-Path $gameExe) {
    $probeOut = Join-Path $OutDir 't11t2-a-extractor-concurrent-stdout.log'
    $p = Start-Process -FilePath $gameExe -ArgumentList '--jackdaw-extract-schema' -WorkingDirectory $Project -PassThru `
        -RedirectStandardOutput $probeOut -RedirectStandardError (Join-Path $OutDir 't11t2-a-extractor-concurrent-stderr.log') -WindowStyle Hidden
    $done = $p.WaitForExit(120000)
    Write-Host ("extractor concurrent probe: exited={0} code={1}" -f $done, $(if ($done) { $p.ExitCode } else { 'timeout' }))
    if (-not $done) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
}
Write-Host 'editor ready'

# --- A1: build the placement chain ------------------------------------------------
Op 'scene.new' | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1

$r = Op 'entity.add.cube' @{}
$player = $r.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $player; type_path = $TKEY; field = 'translation'; value = '[2.0, 1.0, 2.0]' } | Out-Null
$adds = @()
$adds += Op 'component.add' @{ entity = $player; type_path = 't11t1_game::PlayerMarker' }
$adds += Op 'component.add' @{ entity = $player; type_path = 't11t1_game::PlayerController' }
$adds += Op 'component.add' @{ entity = $player; type_path = 'avian3d::dynamics::rigid_body::RigidBody' }
$sRB = Op 'component.set' @{ entity = $player; type_path = 'avian3d::dynamics::rigid_body::RigidBody'; field = ''; value = '"Kinematic"' }
$adds += Op 'component.add' @{ entity = $player; type_path = 'jackdaw_avian_integration::AvianCollider' }
# capsule shape, JSON enum shape first; fall back to the default collider
$sCap = Op 'component.set' @{ entity = $player; type_path = 'jackdaw_avian_integration::AvianCollider'; field = ''; value = '{"Capsule":{"radius":0.35,"height":1.0}}' }
$capWarn = if ($sCap -and $sCap.result.warnings) { $sCap.result.warnings -join ';' } else { '' }
Write-Host ("A1 capsule set: [{0}]" -f $capWarn)
if ($capWarn) {
    $sCap2 = Op 'component.set' @{ entity = $player; type_path = 'jackdaw_avian_integration::AvianCollider'; field = ''; value = '"Capsule"' }
    $capWarn2 = if ($sCap2 -and $sCap2.result.warnings) { $sCap2.result.warnings -join ';' } else { '' }
    Write-Host ("A1 capsule bare-variant fallback: [{0}]" -f $capWarn2)
}
$chainOk = $true
foreach ($a in $adds) { if (-not ($a -and "$($a.result.result)" -eq 'finished')) { $chainOk = $false } }
if ($sRB -and $sRB.result.warnings) { Write-Host ("A1 RigidBody set warnings: {0}" -f ($sRB.result.warnings -join ';')) }

$rr = Op 'entity.add.camera_rig' @{}
$rig = $rr.result.entities | Select-Object -Last 1
$rp = Op 'entity.reparent' @{ child = $rig; parent = $player }

$rf = Op 'entity.add.cube' @{}
$floor = $rf.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'scale'; value = '[12.0, 1.0, 12.0]' } | Out-Null
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'translation'; value = '[0.0, -0.5, 0.0]' } | Out-Null
$pe = Op 'physics.enable' @{ entity = $floor }
Wait-Idle 90; Start-Sleep -Seconds 2

$sv = Op 'scene.save' @{ path = "$Project\assets\t11t2-place.bsn" }
Wait-Idle 120; Start-Sleep -Seconds 2
$bsnPath = Join-Path $Project 'assets\t11t2-place.bsn'
$bsn = ''
if (Test-Path $bsnPath) { $bsn = [IO.File]::ReadAllText($bsnPath) }
$docOk = ($bsn -match 'PlayerMarker') -and ($bsn -match 'PlayerController') -and ($bsn -match 'CameraRig')
$defaultsSeen = ($bsn -match 'move_speed') -and ($bsn -match '4\.0')
Write-Host ("A1_CHAIN ops={0} save={1} docHas={2} defaults={3}" -f $chainOk, (Test-Path $bsnPath), $docOk, $defaultsSeen)
Leg 'A1_CHAIN' ($chainOk -and (Test-Path $bsnPath) -and $docOk)

# --- A2: C9 dead-camera leg (two rigs, none activated) -----------------------------
Op 'pie.play_current' @{} | Out-Null
$running = Wait-Pie 900
Start-Sleep -Seconds 5
if (-not $running) {
    Write-Host 'A2 abort: pie never ran'
    Leg 'A2_DEAD' $false
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    exit 1
}
$g = GSnap
$s = if ($g) { $g } else { Snap }
Write-Host ("A2 sample channel: {0}" -f $(if ($g) { 'game15702' } else { 'editor-projection' }))
if (-not $g) {
    # diagnostics: does the PIE game listen on 15702 at all?
    $netstat = (netstat -ano | Select-String ':15702\s')
    Write-Host ("A2 netstat 15702: {0}" -f ($(if ($netstat) { ($netstat | ForEach-Object { $_.Line.Trim() }) -join ' | ' } else { 'not listening' })))
    # projection shape dump: entities with transforms + their component count
    $withT = @()
    foreach ($e in @($s)) { if (Get-T $e) { $withT += $e } }
    Write-Host ("A2 projection: {0} entities, {1} with transforms" -f @($s).Count, $withT.Count)
    foreach ($e in ($withT | Select-Object -First 12)) {
        $t = Get-T $e
        $names = @()
        foreach ($prop in (Props $e)) { $names += ($prop.Name -replace '^.*::', '') }
        Write-Host ("  [{0}] ({1:F1},{2:F1},{3:F1}): {4}" -f $e.entity, [double]$t.translation[0], [double]$t.translation[1], [double]$t.translation[2], ($names -join ','))
    }
}
$tplPlayer = Find-Player $s $false
$plPlayer = Find-Player $s $true
$tplRig = Find-Rig-For $s $tplPlayer
$plRig = Find-Rig-For $s $plPlayer
Write-Host ("A2 entities: tplPlayer={0} placedPlayer={1} tplRig={2} placedRig={3}" -f `
        ($null -ne $tplPlayer), ($null -ne $plPlayer), ($null -ne $tplRig), ($null -ne $plRig))
$anyActive = $false
foreach ($e in @($s)) {
    if (Has-Comp $e 'ActiveCameraRig') { $anyActive = $true }
}
$capDenied = $false
$t = Op 'pie.play_input_toggle' @{}
if ($t -and "$($t.result.result)" -eq 'cancelled') { $capDenied = $true }
Write-Host ("A2_DEAD: anyActiveRig={0} captureRefused={1} (two rigs, lone-rig stands down)" -f $anyActive, $capDenied)
Leg 'A2_DEAD' ((-not $anyActive) -and ($null -ne $tplRig) -and ($null -ne $plRig))
Stop-Pie
Wait-Idle 120; Start-Sleep -Seconds 2

# --- A3: activate the placed rig ---------------------------------------------------
# Document-state add while stopped (component.add streams to the running
# game when the entity has a live mirror -- that path cannot touch the
# document), then the save/play round trip tells whether the marker the
# template doc tells users to add actually survives to the game.
$aAct = Op 'component.add' @{ entity = $rig; type_path = 'jackdaw_camera_rig::ActiveCameraRig' }
$actDocAdd = ($aAct -and "$($aAct.result.result)" -eq 'finished')
Op 'scene.save' @{ } | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$bsn2 = ''
if (Test-Path $bsnPath) { $bsn2 = [IO.File]::ReadAllText($bsnPath) }
$actInDoc = ($bsn2 -match 'ActiveCameraRig')
Write-Host ("A3_DOCADD: add={0} savedDocContainsActiveCameraRig={1} (scene_io strips the marker from saves)" -f $actDocAdd, $actInDoc)

# Re-play from the saved document: does the placed rig come up active?
Op 'pie.play_current' @{} | Out-Null
$null = Wait-Pie 600
Start-Sleep -Seconds 4
$g2 = GSnap
if (-not $g2) { $g2 = Snap }
$plRig2 = Find-Rig-For $g2 (Find-Player $g2 $true)
$actFromDoc = Has-Comp $plRig2 'ActiveCameraRig'
$matFromDoc = Has-Comp $plRig2 'Projection'
Write-Host ("A3_FROMDOC: activeMarker={0} materializedCamera={1}" -f $actFromDoc, $matFromDoc)

# The live leg: stream the marker straight into the running game.
$aLive = Op 'component.add' @{ entity = $rig; type_path = 'jackdaw_camera_rig::ActiveCameraRig' }
Start-Sleep -Seconds 3
$g3 = if ($g2) { GSnap } else { Snap }
$plRig3 = Find-Rig-For $g3 (Find-Player $g3 $true)
$actLive = Has-Comp $plRig3 'ActiveCameraRig'
$matLive = Has-Comp $plRig3 'Projection'
Write-Host ("A3_LIVEADD: add={0} activeMarkerVisible={1} materializedCamera={2}" -f `
        ($aLive -and "$($aLive.result.result)" -eq 'finished'), $actLive, $matLive)
Leg 'A3_ACTIVATE' ($matLive)

# --- A4: four behaviors -------------------------------------------------------------
$cap = Op 'pie.play_input_toggle' @{}
Write-Host ("A4 capture: {0}" -f ($cap | ConvertTo-Json -Depth 3 -Compress))
Start-Sleep -Seconds 1
$chan = { param() if ($g) { GSnap } else { Snap } }
$sample = {
    param()
    $s2 = if ($script:gameLive) { GSnap } else { Snap }
    return $s2
}
# settle: let the placed player depenetrate onto the floor
Start-Sleep -Seconds 2
$s3 = & $sample
$pl = Find-Player $s3 $true
$py0 = Py $pl
Write-Host ("A4 placed player settled y={0}" -f ('{0:F3}' -f $py0))

# A4a walk: hold W (yaw 0 -> -z), sample the z series
Op 'input.key' @{ key = 'KeyW'; action = 'press' } | Out-Null
$zSeries = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt 26; $i++) {
    Start-Sleep -Milliseconds 120
    $e = Find-Player (& $sample) $true
    if ($e) { $zSeries.Add(('{0:F3}' -f ((Get-T $e).translation[2]))) }
    if ($i -gt 8) {
        $last = [double]$zSeries[$zSeries.Count - 1]
        $prev = [double]$zSeries[$zSeries.Count - 2]
        if ([Math]::Abs($last - $prev) -lt 0.005 -and $last -lt -2.2) { break }
    }
}
Op 'input.key' @{ key = 'KeyW'; action = 'release' } | Out-Null
$zEnd = [double]$zSeries[$zSeries.Count - 1]
Write-Host ("A4a_WALK z: {0} -> end {1:F3} (north wall face -2.8 + capsule ~-2.44)" -f ($zSeries -join ' '), $zEnd)
Leg 'A4a_WALK' (($zSeries.Count -ge 4) -and ($zEnd -lt -2.0) -and ($zEnd -gt -2.60))

# A4d camera follow: offset at two player positions. Walk east (D) from the
# wall corner, sample rig-vs-player offset twice.
$sA = & $sample
$plA = Find-Player $sA $true; $rigA = Find-Rig-For $sA $plA
function OffsetNow([object]$snap) {
    $p = Find-Player $snap $true; $r = Find-Rig-For $snap $p
    if (-not $p -or -not $r) { return $null }
    $pt = Get-T $p; $rt = Get-T $r
    return @([double]$rt.translation[0] - [double]$pt.translation[0], `
            [double]$rt.translation[1] - [double]$pt.translation[1], `
            [double]$rt.translation[2] - [double]$pt.translation[2], `
            [double]$pt.translation[0], [double]$pt.translation[2])
}
$oa = OffsetNow $sA
Op 'input.key' @{ key = 'KeyD'; action = 'press' } | Out-Null
Start-Sleep -Milliseconds 1500
Op 'input.key' @{ key = 'KeyD'; action = 'release' } | Out-Null
Start-Sleep -Milliseconds 400
$ob = OffsetNow (& $sample)
$drift = 9.9
if ($oa -and $ob) {
    $drift = [Math]::Sqrt([Math]::Pow($oa[0] - $ob[0], 2) + [Math]::Pow($oa[1] - $ob[1], 2) + [Math]::Pow($oa[2] - $ob[2], 2))
    Write-Host ("A4d_FOLLOW at({0:F2},{1:F2}) off=({2:F2},{3:F2},{4:F2}) -> at({5:F2},{6:F2}) off=({7:F2},{8:F2},{9:F2}) drift={10:F3}" -f `
            $oa[3], $oa[4], $oa[0], $oa[1], $oa[2], $ob[3], $ob[4], $ob[0], $ob[1], $ob[2], $drift)
} else { Write-Host 'A4d_FOLLOW: player or rig missing' }
Leg 'A4d_FOLLOW' ($drift -lt 0.25)

# A4b jump: tap Space, track the y series
$e = Find-Player (& $sample) $true
$yBase = Py $e
Op 'input.key' @{ key = 'Space'; action = 'press' } | Out-Null
Start-Sleep -Milliseconds 60
Op 'input.key' @{ key = 'Space'; action = 'release' } | Out-Null
$yS = New-Object System.Collections.Generic.List[string]
$apex = $yBase
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 60
    $e2 = Find-Player (& $sample) $true
    if ($e2) {
        $y = Py $e2
        $yS.Add(('{0:F3}' -f $y))
        if ($y -gt $apex) { $apex = $y }
    }
}
$expected = 0.86 + 4.5 * 4.5 / (2.0 * 9.81)
Write-Host ("A4b_JUMP y: {0} apex={1:F3} expected~{2:F3}" -f ($yS -join ' '), $apex, $expected)
Leg 'A4b_JUMP' (([Math]::Abs($apex - $expected)) -lt 0.3)

# A4c wall stop is folded into A4a's terminal clamp; the slide half: W+D from
# the corner -- z stays clamped while x runs (the same evidence shape as the
# T1 live L5 leg, on the placed player).
$x0 = [double]((Get-T (Find-Player (& $sample) $true)).translation[0])
Op 'input.key' @{ key = 'KeyW'; action = 'press' } | Out-Null
Op 'input.key' @{ key = 'KeyD'; action = 'press' } | Out-Null
for ($i = 0; $i -lt 14; $i++) { Start-Sleep -Milliseconds 120; $null = & $sample }
Op 'input.key' @{ key = 'KeyW'; action = 'release' } | Out-Null
Op 'input.key' @{ key = 'KeyD'; action = 'release' } | Out-Null
Start-Sleep -Milliseconds 300
$e3 = Find-Player (& $sample) $true
$x1 = [double]((Get-T $e3).translation[0])
$zSlide = [double]((Get-T $e3).translation[2])
Write-Host ("A4c_SLIDE x {0:F2} -> {1:F2} (along-wall travel {2:F2} m), zEnd={3:F3}" -f $x0, $x1, ($x1 - $x0), $zSlide)
Leg 'A4c_SLIDE' ((($x1 - $x0) -gt 0.8) -and ($zSlide -gt -2.60) -and ($zSlide -lt -2.30))

# --- A5: C7 Look --------------------------------------------------------------------
# Single channel first: capture engaged, RMB up. dx=240 -> yaw -= 240*0.005
# = -1.2 rad. Observable: the rig's world offset rotates around the player
# by exactly that yaw (horizontal angle atan2(dx, dz)).
function RigYaw([object]$snap) {
    $o = OffsetNow $snap
    if (-not $o) { return $null }
    return [Math]::Atan2($o[0], $o[2])
}
Start-Sleep -Seconds 1
$sY0 = & $sample
$yaw0 = RigYaw $sY0
Op 'input.motion' @{ dx = 240; dy = 0; steps = 24 } | Out-Null
Start-Sleep -Seconds 2
$yaw1 = RigYaw (& $sample)
$dyawBridge = 9.9
if ($null -ne $yaw0 -and $null -ne $yaw1) { $dyawBridge = $yaw1 - $yaw0 }
Write-Host ("A5_BRIDGE yaw {0:F3} -> {1:F3} delta={2:F3} (expected -1.2 +- 0.15)" -f $yaw0, $yaw1, $dyawBridge)
Leg 'A5_BRIDGE' ([Math]::Abs($dyawBridge - (-1.2)) -lt 0.2)

# Dual channel: RMB held. The bridge yields (decision 3-3); the crate's own
# RMB channel reads AccumulatedMouseMotion -- if the forwarded synthetic
# motion reaches that accumulator the rig still turns (single rate); if not,
# it stalls. Either is a finding; double (-2.4) would be the C7 bug.
$yawB0 = RigYaw (& $sample)
Op 'input.pointer' @{ button = 'right'; action = 'press' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.motion' @{ dx = 240; dy = 0; steps = 24 } | Out-Null
Start-Sleep -Seconds 2
Op 'input.pointer' @{ button = 'right'; action = 'release' } | Out-Null
$yawB1 = RigYaw (& $sample)
$dyawRmb = 9.9
if ($null -ne $yawB0 -and $null -ne $yawB1) { $dyawRmb = $yawB1 - $yawB0 }
Write-Host ("A5_RMB yaw {0:F3} -> {1:F3} delta={2:F3} (single -1.2 = crate channel took it; ~0 = motion never reaches the accumulator; -2.4 = double-write bug)" -f $yawB0, $yawB1, $dyawRmb)
Leg 'A5_NO_DOUBLE' ([Math]::Abs($dyawRmb - (-2.4)) -gt 0.3)

# --- A6: parameter edits (C5 author + behavior halves; the reopen half is leg B) ----
Stop-Pie
Wait-Idle 120; Start-Sleep -Seconds 2

$m = Op 'component.set' @{ entity = $player; type_path = 't11t1_game::PlayerController'; field = 'move_speed'; value = '2.0' }
$mWarn = if ($m -and $m.result.warnings) { $m.result.warnings -join ';' } else { '' }
if ($mWarn) {
    $m = Op 'component.set' @{ entity = $player; type_path = 't11t1_game::PlayerController'; field = 'move_speed'; value = 2.0 }
    $mWarn = if ($m -and $m.result.warnings) { $m.result.warnings -join ';' } else { '' }
}
if ($mWarn) {
    $m = Op 'component.set' @{ entity = $player; type_path = 't11t1_game::PlayerController'; field = 'move_speed'; value = '"2.0"' }
    $mWarn = if ($m -and $m.result.warnings) { $m.result.warnings -join ';' } else { '' }
}
if ($mWarn) {
    $m = Op 'component.set' @{ entity = $player; type_path = 't11t1_game::PlayerController'; field = ''; value = '{"move_speed":2.0,"jump_speed":4.5}' }
    $mWarn = if ($m -and $m.result.warnings) { $m.result.warnings -join ';' } else { '' }
}
Write-Host ("A6 move_speed 4.0->2.0: [{0}]" -f $mWarn)
$d = Op 'component.set' @{ entity = $rig; type_path = 'jackdaw_camera_rig::CameraRig'; field = 'distance'; value = '5.0' }
$dWarn = if ($d -and $d.result.warnings) { $d.result.warnings -join ';' } else { '' }
Write-Host ("A6 distance 10.0->5.0: [{0}]" -f $dWarn)
Op 'scene.save' @{ } | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$bsn3 = ''
if (Test-Path $bsnPath) { $bsn3 = [IO.File]::ReadAllText($bsnPath) }
$diskMs = ($bsn3 -match 'move_speed:\s*2\.0')
$diskDist = ($bsn3 -match 'distance:\s*5\.0')
Write-Host ("A6_SAVE disk move_speed=2.0: {0}; distance=5.0: {1}" -f $diskMs, $diskDist)

Op 'pie.play_current' @{} | Out-Null
$null = Wait-Pie 900
Start-Sleep -Seconds 4
$null = GSnap
# the live rig needs the marker again (the save strips it; the game spawns
# from the document): stream it in, the same as A3.
$aLive2 = Op 'component.add' @{ entity = $rig; type_path = 'jackdaw_camera_rig::ActiveCameraRig' }
Start-Sleep -Seconds 3
Start-Sleep -Seconds 2
# walk speed: template player (4.0) vs placed player (2.0) over the same
# window -- the "halved speed" behavior evidence, internally controlled.
function Xz($snap, $placed) {
    $e4 = Find-Player $snap $placed
    if (-not $e4) { return $null }
    $t4 = Get-T $e4
    return @([double]$t4.translation[0], [double]$t4.translation[2])
}
$sW0 = & $sample
$pl0 = Xz $sW0 $true; $tp0 = Xz $sW0 $false
Op 'input.key' @{ key = 'KeyD'; action = 'press' } | Out-Null
Start-Sleep -Milliseconds 1400
Op 'input.key' @{ key = 'KeyD'; action = 'release' } | Out-Null
Start-Sleep -Milliseconds 250
$sW1 = & $sample
$pl1 = Xz $sW1 $true; $tp1 = Xz $sW1 $false
$vPl = $vTp = $null
if ($pl0 -and $pl1) { $vPl = [Math]::Sqrt([Math]::Pow($pl1[0] - $pl0[0], 2) + [Math]::Pow($pl1[1] - $pl0[1], 2)) / 1.65 }
if ($tp0 -and $tp1) { $vTp = [Math]::Sqrt([Math]::Pow($tp1[0] - $tp0[0], 2) + [Math]::Pow($tp1[1] - $tp0[1], 2)) / 1.65 }
Write-Host ("A6_SPEED placed={0} m/s (move_speed 2.0) template={1} m/s (4.0)" -f ('{0:F2}' -f $vPl), ('{0:F2}' -f $vTp))
Leg 'A6_HALFSPEED' (($null -ne $vPl) -and ($null -ne $vTp) -and ($vPl -gt 1.4) -and ($vPl -lt 2.6) -and ($vTp -gt 3.0))

# camera distance 5: the rig sits at pitch 0.4 -> offset (0, 1.2+5*sin0.4,
# 5*cos0.4) = (0, 3.147, 4.605) at yaw 0 (fresh play reset the look).
$oD = OffsetNow (& $sample)
if ($oD) {
    Write-Host ("A6_DISTANCE offset=({0:F2},{1:F2},{2:F2}) expected (0, 3.15, 4.61)" -f $oD[0], $oD[1], $oD[2])
    Leg 'A6_DISTANCE' (([Math]::Abs($oD[1] - 3.147) -lt 0.25) -and ([Math]::Abs($oD[2] - 4.605) -lt 0.35))
} else { Leg 'A6_DISTANCE' $false }

Stop-Pie
Wait-Idle 90
Start-Sleep -Seconds 1

# --- summary + cleanup ----------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
$summary = ($results.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
[IO.File]::WriteAllText((Join-Path $OutDir 't11t2-a-summary.txt'), "$summary`r`nactInDoc=$actInDoc dyawRmb=$dyawRmb`r`n")
Write-Host ("VERDICT_A: {0}" -f $summary)
Write-Host 'T11T2_A_DONE'
