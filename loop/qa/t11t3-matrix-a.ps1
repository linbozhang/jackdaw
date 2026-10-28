# T11-T3 acceptance matrix, editor leg (cells 2/8/9 + N14 live + PIE probe).
# Builds the placement chain THE WAY THE FIXED DOC TEACHES IT (C10): the
# five components through operators -- including PlayerVelocity, which the
# T2 leg had to inject as text because the old doc omitted it. The first
# single-field set after add is the N14 live proof: the saved block must
# spell the sibling field too.
# Cells served:
#   PROBE  : one PIE attempt before anything else -- if the window
#            recovered, PIE-dependent cells go real this run; if it
#            died 0xc0000005 again (T10b driver state), record and carry
#            on with the direct-run channel.
#   M2     : place player + floor through operators, save.
#   N14    : after add -> first set move_speed -> save -> the file spells
#            jump_speed (merged from the schema default).
#   M8/M9  : PlayerController/CameraRig fields edited -> saved -> on disk.
#   M7-pre : mode=FirstPerson and move_speed=8 variants saved as scenes
#            for the direct-run leg.
# Boot is detached: cmd start /B only. No WGPU_BACKEND. RUST_BACKTRACE=1.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t3-matrix-a.ps1
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$Port = 15804
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$OutDir = Join-Path $Repo 'loop\t11t3-live'
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
function Op([string]$id, $params) {
    if ($params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp 'jackdaw/call_operator' @{ id = $id } }
}
function Wait-Idle([int]$TimeoutSec = 600) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp 'jackdaw/wait' @{ until = 'idle' } 1
        if ($r -and $r.result -and $r.result.idle) { return $true }
        Start-Sleep -Seconds 1
    }
    Write-Host 'wait(idle) timeout (continuing)'
    return $false
}
$results = @{}
function Leg([string]$name, [bool]$ok) {
    $results[$name] = $ok
    Write-Host ("{0}_{1}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }))
}
$TKEY = 'bevy_transform::components::transform::Transform'
# entity.add.* returns entities: [id] (array); accept either shape.
function Ent($opResult) {
    if ($opResult -and $opResult.result) {
        if ($opResult.result.entities) { return @($opResult.result.entities)[0] }
        if ($opResult.result.entity) { return $opResult.result.entity }
        if ($opResult.result.result -and $opResult.result.result.entity) { return $opResult.result.result.entity }
    }
    return $null
}

# --- clean boot ----------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = '1600x900'
$env:RUST_BACKTRACE = '1'
$editorLog = Join-Path $OutDir 't11t3-a-editor.log'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"$(Split-Path -Parent $Exe)`" cmd /c `"`"$Exe`" > `"$editorLog`" 2>`&1`""
$ready = $false
for ($i = 0; $i -lt 150; $i++) {
    Start-Sleep -Seconds 2
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process jackdaw -ErrorAction SilentlyContinue)) {
        Write-Host 'EDITOR_BOOT_FAIL'
        exit 1
    }
}
if (-not $ready) { Write-Host 'EDITOR_BOOT_FAIL (timeout)'; exit 1 }
Wait-Idle 600; Start-Sleep -Seconds 5
$st0 = (Brp 'jackdaw/status' @{} 2).result
if ($st0 -and $st0.dialog) {
    Op 'dialog.answer' @{ choice = '0' } | Out-Null
    Start-Sleep -Seconds 2
}
# ProjectTypes need the watcher to pick the schema up (T2 finding: the
# in-process extractor fails in this environment; re-stamp the healthy
# manual-extraction product to trigger the load).
$schemaJson = Join-Path $Project '.jackdaw\schema.json'
if (Test-Path $schemaJson) {
    (Get-Item $schemaJson).LastWriteTime = Get-Date
    Start-Sleep -Seconds 6
}
Write-Host 'EDITOR_READY'

# --- PIE probe (the environment question every PIE cell asks first) -------------
# The T2 crash form kills the PIE game ~7s after launch, BEFORE connecting;
# the editor's own pie state says 'running' for a while after the process
# is gone, so a fast poll false-positives. Cross the crash window (20s),
# then require: game process alive AND editor log free of the exit mark.
# play_current saves the current scene before launching, and refuses on an
# unsaved/untitled scene -- open the template scene (absolute path) first.
$so = Op 'scene.open' @{ path = "$Project\assets\scene.bsn" }
Start-Sleep -Seconds 2
Write-Host ("PIE_PROBE scene.open: {0}" -f ($so | ConvertTo-Json -Depth 4 -Compress))
function Read-EditorLog {
    $fs = [IO.File]::Open($editorLog, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $sr = New-Object IO.StreamReader($fs)
    $t = $sr.ReadToEnd(); $sr.Close()
    return $t
}
$pieAlive = $false
$probeCrashes = 0
for ($attempt = 1; $attempt -le 3; $attempt++) {
    Op 'pie.play_current' | Out-Null
    Start-Sleep -Seconds 20
    $procAlive = [bool](Get-Process t11t1-game -ErrorAction SilentlyContinue)
    $logText = Read-EditorLog
    $exited = ($logText -match "exited before connecting")
    Write-Host ("PIE_PROBE #{0}: procAlive={1} exitedMark={2}" -f $attempt, $procAlive, $exited)
    if ($exited) { $probeCrashes++ }
    if ($procAlive -and -not $exited) {
        $stP = (Brp 'jackdaw/status' @{} 1).result
        if ($stP -and "$($stP.pie)" -match 'running') { $pieAlive = $true; break }
    }
    # a crashed PIE can raise a recovery dialog that blocks operators;
    # dismiss it before the next attempt.
    $stD = (Brp 'jackdaw/status' @{} 1).result
    if ($stD -and $stD.dialog) {
        Write-Host ("PIE_PROBE dialog up: {0}" -f ($stD.dialog | ConvertTo-Json -Depth 3 -Compress))
        Op 'dialog.answer' @{ choice = '0' } | Out-Null
        Start-Sleep -Seconds 2
    }
    foreach ($s in 1..4) {
        Op 'pie.stop' | Out-Null
        Start-Sleep -Seconds 2
        $stS = (Brp 'jackdaw/status' @{} 1).result
        if ($stS -and "$($stS.pie)" -eq 'stopped') { break }
    }
    Start-Sleep -Seconds 2
}
if ($pieAlive) {
    Write-Host 'PIE_PROBE: RECOVERED -- PIE cells run real this round'
} else {
    Write-Host ("PIE_PROBE: DEAD ({0}/3 attempts exited 0xc0000005 before connecting) -- PIE cells degrade per T10 precedent" -f $probeCrashes)
}
Leg 'PIE_PROBE_RECOVERED' $pieAlive
if ($pieAlive) {
    foreach ($attempt in 1..4) {
        Op 'pie.stop' | Out-Null
        Start-Sleep -Seconds 2
        $st = (Brp 'jackdaw/status' @{} 1).result
        if ($st -and "$($st.pie)" -eq 'stopped') { break }
    }
} else {
    Op 'pie.stop' | Out-Null; Start-Sleep -Seconds 2
}
$stD2 = (Brp 'jackdaw/status' @{} 1).result
if ($stD2 -and $stD2.dialog) {
    Op 'dialog.answer' @{ choice = '0' } | Out-Null
    Start-Sleep -Seconds 2
}
Wait-Idle 120

# --- M2: the placement chain exactly as the fixed doc teaches it -----------------
Op 'scene.new' | Out-Null
Start-Sleep -Seconds 2
$r = Op 'entity.add.cube' @{}
$player = Ent $r
if (-not $player) {
    Write-Host ("ENTITY_ADD_FAIL: response={0}" -f ($r | ConvertTo-Json -Depth 6 -Compress))
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    exit 1
}
Op 'component.set' @{ entity = $player; type_path = $TKEY; field = 'translation'; value = '[2.0, 1.0, 2.0]' } | Out-Null

# The five components, by fully-qualified name -- PlayerVelocity included
# (the C10 fix; the pre-fix doc named two and the placed player stood frozen).
$adds = @()
$adds += Op 'component.add' @{ entity = $player; type_path = 't11t1_game::PlayerMarker' }
$adds += Op 'component.add' @{ entity = $player; type_path = 't11t1_game::PlayerController' }
$adds += Op 'component.add' @{ entity = $player; type_path = 't11t1_game::PlayerVelocity' }
$adds += Op 'component.add' @{ entity = $player; type_path = 'avian3d::dynamics::rigid_body::RigidBody' }
$sRB = Op 'component.set' @{ entity = $player; type_path = 'avian3d::dynamics::rigid_body::RigidBody'; field = ''; value = '"Kinematic"' }
$adds += Op 'component.add' @{ entity = $player; type_path = 'jackdaw_avian_integration::AvianCollider' }
$sCap = Op 'component.set' @{ entity = $player; type_path = 'jackdaw_avian_integration::AvianCollider'; field = ''; value = '{"Capsule":{"radius":0.35,"height":1.0}}' }
$fiveOk = $true
foreach ($a in $adds) {
    $state = ''
    if ($a -and $a.result) { $state = "$($a.result.result)" }
    if ($state -ne 'finished') { $fiveOk = $false }
    Write-Host ("  add state: {0}" -f ($a | ConvertTo-Json -Depth 5 -Compress))
}
Write-Host ("M2_ADD five components via operators: {0}" -f $fiveOk)

# N14 live: the FIRST single-field set after add. The saved block must
# spell jump_speed too (merged from the schema default).
$m1 = Op 'component.set' @{ entity = $player; type_path = 't11t1_game::PlayerController'; field = 'move_speed'; value = '2.0' }

$rr = Op 'entity.add.camera_rig' @{}
$rig = Ent $rr
if (-not $rig) { Write-Host ("RIG_ADD_FAIL: {0}" -f ($rr | ConvertTo-Json -Depth 6 -Compress)); $rig = 0 }
# distance tuning goes on the rig that now exists (set BEFORE the rig
# existed silently no-ops -- found the hard way this run).
$d1 = Op 'component.set' @{ entity = $rig; type_path = 'jackdaw_camera_rig::CameraRig'; field = 'distance'; value = '5.0' }
$rp = Op 'entity.reparent' @{ child = $rig; parent = $player }
# The placed rig needs its own activation marker (two rigs in the world:
# the template's spawned one and this one -- lone-rig stands down).
$act = Op 'component.add' @{ entity = $rig; type_path = 'jackdaw_camera_rig::ActiveCameraRig' }

$rf = Op 'entity.add.cube' @{}
$floor = Ent $rf
if (-not $floor) { Write-Host ("FLOOR_ADD_FAIL: {0}" -f ($rf | ConvertTo-Json -Depth 6 -Compress)); $floor = 0 }
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'scale'; value = '[12.0, 1.0, 12.0]' } | Out-Null
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'translation'; value = '[0.0, -0.5, 0.0]' } | Out-Null
$pe = Op 'physics.enable' @{ entity = $floor }

# A wall, so the placed player has a wall to stop at (north, z=-3).
$rw = Op 'entity.add.cube' @{}
$wall = Ent $rw
if (-not $wall) { Write-Host ("WALL_ADD_FAIL: {0}" -f ($rw | ConvertTo-Json -Depth 6 -Compress)); $wall = 0 }
Op 'component.set' @{ entity = $wall; type_path = $TKEY; field = 'scale'; value = '[12.0, 1.5, 0.4]' } | Out-Null
Op 'component.set' @{ entity = $wall; type_path = $TKEY; field = 'translation'; value = '[0.0, 0.75, -3.0]' } | Out-Null
$peW = Op 'physics.enable' @{ entity = $wall }

$sceneMain = "$Project\assets\t11t3-place.bsn"
$sv = Op 'scene.save' @{ path = $sceneMain }
Wait-Idle 60

$saved = ''
if (Test-Path $sceneMain) { $saved = [IO.File]::ReadAllText($sceneMain) }
$hasMs = $saved -match 'move_speed:\s*2\.0'
$hasJs = $saved -match 'jump_speed:\s*4\.5'
$hasDist = $saved -match 'distance:\s*5\.0'
$hasVel = $saved -match 'PlayerVelocity'
$hasKin = $saved -match 'Kinematic'
$hasAct = $saved -match 'ActiveCameraRig'
Write-Host ("N14_LIVE first-set-after-add: move_speed 2.0 on disk={0}; sibling jump_speed 4.5 on disk={1} (the N14 fix's whole point)" -f $hasMs, $hasJs)
Leg 'N14_LIVE_SIBLING_ON_DISK' ($hasMs -and $hasJs)
Leg 'M2_BUILD' ($fiveOk -and $hasVel -and $hasKin -and $hasAct -and $hasDist -and ($sv -and $sv.result -and "$($sv.result.result)" -eq 'finished'))

# M8 second-set control (QA P2 shape): set the OTHER field now; both stand.
$m2 = Op 'component.set' @{ entity = $player; type_path = 't11t1_game::PlayerController'; field = 'jump_speed'; value = '6.0' }
$sens = Op 'component.set' @{ entity = $rig; type_path = 'jackdaw_camera_rig::CameraRig'; field = 'sensitivity'; value = '0.008' }
Op 'scene.save' @{ path = $sceneMain } | Out-Null
Wait-Idle 60
$saved2 = [IO.File]::ReadAllText($sceneMain)
Leg 'M8_SECOND_SET' (($saved2 -match 'move_speed:\s*2\.0') -and ($saved2 -match 'jump_speed:\s*6\.0') -and ($saved2 -match 'sensitivity:\s*0\.008'))

# --- M7-pre: FirstPerson variant scene (mode field edit) --------------------------
$fp = Op 'component.set' @{ entity = $rig; type_path = 'jackdaw_camera_rig::CameraRig'; field = 'mode'; value = '"FirstPerson"' }
$sceneFp = "$Project\assets\t11t3-fp.bsn"
Op 'scene.save' @{ path = $sceneFp } | Out-Null
Wait-Idle 60
$fpSaved = (Test-Path $sceneFp) -and (([IO.File]::ReadAllText($sceneFp)) -match 'FirstPerson')
Write-Host ("M7PRE_FP mode=FirstPerson saved: {0}" -f $fpSaved)

# --- M6-pre: high-speed variant scene (move_speed 8, everything else same) --------
$null = Op 'component.set' @{ entity = $player; type_path = 't11t1_game::PlayerController'; field = 'move_speed'; value = '8.0' }
$sceneFast = "$Project\assets\t11t3-fast.bsn"
Op 'scene.save' @{ path = $sceneFast } | Out-Null
Wait-Idle 60
$fastSaved = (Test-Path $sceneFast) -and (([IO.File]::ReadAllText($sceneFast)) -match 'move_speed:\s*8\.0')
Write-Host ("M6PRE_FAST move_speed=8 saved: {0}" -f $fastSaved)

# --- teardown -------------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
$summary = ($results.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
[IO.File]::WriteAllText((Join-Path $OutDir 't11t3-a-summary.txt'), "$summary`r`n")
Write-Host ("VERDICT_A: {0}" -f $summary)
Write-Host 'T11T3_A_DONE'
