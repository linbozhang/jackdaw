# T11-T2 probe: verify the editor tool-face assumptions before the real
# placement-chain leg. Questions this probe answers:
#   1. Does component.add accept the project components (PlayerMarker,
#      PlayerController) on a freshly added cube?
#   2. Does component.add + component.set build the physical body
#      (RigidBody=Kinematic, AvianCollider capsule) the same way the
#      template's spawn_player does?
#   3. Does entity.add.camera_rig + entity.reparent parent a rig under
#      the placed player?
#   4. Once PIE plays, does the game's own BRP (15702, the warm project's
#      RemotePlugin) answer, giving a direct behavior-sampling channel?
#   5. What do the snapshot component names look like (finding the placed
#      player/rig by component, the pickup-free twin of the template's)?
# Boot is detached: cmd start /B only. No WGPU_BACKEND (driver OOM is a
# known state, not a code defect).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t2-probe.ps1
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$Port = 15801,
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
$TKEY = 'bevy_transform::components::transform::Transform'
function Dump-Entity([object]$e, [string]$tag) {
    $names = @()
    $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
    foreach ($p in $props) { $names += ($p.Name -replace '^.*::', '') }
    Write-Host ("  {0} [{1}]: {2}" -f $tag, $e.entity, ($names -join ', '))
}

# --- clean boot -----------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = '1920x1080'
$env:RUST_BACKTRACE = '1'
$editorLog = Join-Path $OutDir 'probe-editor.log'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"$(Split-Path -Parent $Exe)`" cmd /c `"`"$Exe`" > `"$editorLog`" 2>`&1`""
$ready = $false
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 2
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
}
if (-not $ready) { Write-Host 'PROBE_FAIL editor never answered'; exit 1 }
Wait-Idle 1200; Start-Sleep -Seconds 8
Write-Host 'PROBE: editor ready'

# --- the placement chain, one operator at a time --------------------------------
# Fresh scene so the document is exactly what we place (the template's own
# player still spawns at Play from the startup system; that is the point
# of the C9 two-rigs semantics).
Op 'scene.new' | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1

$r = Op 'entity.add.cube' @{}
$player = $r.result.entities | Select-Object -Last 1
Write-Host ("PROBE player cube: {0}" -f $player)
Op 'component.set' @{ entity = $player; type_path = $TKEY; field = 'translation'; value = '[2.0, 1.0, 2.0]' } | Out-Null
Wait-Idle 60

# project components
$a1 = Op 'component.add' @{ entity = $player; type_path = 'PlayerMarker' }
Write-Host ("PROBE add PlayerMarker: {0}" -f ($a1 | ConvertTo-Json -Depth 4 -Compress))
$a2 = Op 'component.add' @{ entity = $player; type_path = 'PlayerController' }
Write-Host ("PROBE add PlayerController: {0}" -f ($a2 | ConvertTo-Json -Depth 4 -Compress))

# physical body: RigidBody=Kinematic + capsule AvianCollider (the template's
# spawn_player shape). Try fully-qualified paths first; the probe prints the
# operator's complaint if the short name fails.
$rbSet = Op 'component.add' @{ entity = $player; type_path = 'avian3d::dynamics::rigid_body::RigidBody' }
Write-Host ("PROBE add RigidBody: {0}" -f ($rbSet | ConvertTo-Json -Depth 4 -Compress))
$s1 = Op 'component.set' @{ entity = $player; type_path = 'avian3d::dynamics::rigid_body::RigidBody'; field = ''; value = '"Kinematic"' }
Write-Host ("PROBE set RigidBody=Kinematic: {0}" -f ($s1 | ConvertTo-Json -Depth 4 -Compress))
$a3 = Op 'component.add' @{ entity = $player; type_path = 'jackdaw_avian_integration::AvianCollider' }
Write-Host ("PROBE add AvianCollider: {0}" -f ($a3 | ConvertTo-Json -Depth 4 -Compress))
$s2 = Op 'component.set' @{ entity = $player; type_path = 'jackdaw_avian_integration::AvianCollider'; field = ''; value = '"Capsule { radius: 0.35, height: 1.0 }"' }
Write-Host ("PROBE set AvianCollider capsule: {0}" -f ($s2 | ConvertTo-Json -Depth 4 -Compress))
Wait-Idle 60; Start-Sleep -Seconds 1

# camera rig under the player
$rr = Op 'entity.add.camera_rig' @{}
$rig = $rr.result.entities | Select-Object -Last 1
Write-Host ("PROBE camera rig: {0}" -f $rig)
$rp = Op 'entity.reparent' @{ child = $rig; parent = $player }
Write-Host ("PROBE reparent: {0}" -f ($rp | ConvertTo-Json -Depth 4 -Compress))

# floor
$rf = Op 'entity.add.cube' @{}
$floor = $rf.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'scale'; value = '[12.0, 1.0, 12.0]' } | Out-Null
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'translation'; value = '[0.0, -0.5, 0.0]' } | Out-Null
$pe = Op 'physics.enable' @{ entity = $floor }
Write-Host ("PROBE physics.enable floor: {0}" -f ($pe | ConvertTo-Json -Depth 4 -Compress))
Wait-Idle 90; Start-Sleep -Seconds 2

# what the document holds now
$snap = (Brp 'jackdaw/scene_snapshot' @{}).result
Write-Host 'PROBE document entities:'
foreach ($e in @($snap)) { Dump-Entity $e 'doc' }

$sv = Op 'scene.save_as' @{ path = 'assets/t11t2-place.bsn' }
Write-Host ("PROBE scene.save_as: {0}" -f ($sv | ConvertTo-Json -Depth 4 -Compress))
Wait-Idle 120; Start-Sleep -Seconds 2
$bsnPath = Join-Path $Project 'assets\t11t2-place.bsn'
$bsn = Get-Content $bsnPath -Raw -ErrorAction SilentlyContinue
if ($bsn) {
    Write-Host ("PROBE t11t2-place.bsn excerpt:`n{0}" -f ($bsn.Substring(0, [Math]::Min(1600, $bsn.Length))))
} else {
    Write-Host 'PROBE t11t2-place.bsn NOT on disk'
}

# --- PIE: does the game's own BRP answer? --------------------------------------
Op 'pie.play_current' @{} | Out-Null
$running = Wait-Pie 900
Write-Host ("PROBE pie running: {0}" -f $running)
Start-Sleep -Seconds 5
$gst = GameBrp 'jackdaw/status' @{}
Write-Host ("PROBE game BRP 15702: {0}" -f ($gst | ConvertTo-Json -Depth 4 -Compress))
if ($gst) {
    $gsnap = (GameBrp 'jackdaw/scene_snapshot' @{}).result
    Write-Host 'PROBE game entities:'
    foreach ($e in @($gsnap)) { Dump-Entity $e 'game' }
}

# capture + one key hold through the editor channel
$t = Op 'pie.play_input_toggle' @{}
Write-Host ("PROBE capture toggle: {0}" -f ($t | ConvertTo-Json -Depth 4 -Compress))
Start-Sleep -Seconds 1
if ($gst) {
    $before = (GameBrp 'jackdaw/scene_snapshot' @{}).result
    $pzBefore = $null
    foreach ($e in @($before)) {
        $t2 = $null
        $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
        foreach ($p in $props) {
            if ("$($p.Name)" -like '*PlayerMarker' -and -not ("$($p.Name)" -like '*Unresolved*')) {
                $t2 = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties[$TKEY].Value } else { $e.components[$TKEY] }
            }
        }
        if ($t2) { $pzBefore = [double]$t2.translation[2]; $pcount = 0; foreach ($p in $props) { if ("$($p.Name)" -like '*PickupCount') { $pcount = 1 } }; if (-not $pcount) { break } else { $pzBefore = $null } }
    }
    Write-Host ("PROBE placed player z before: {0}" -f $pzBefore)
    Op 'input.key' @{ key = 'KeyW'; action = 'press' } | Out-Null
    Start-Sleep -Seconds 1
    $mid = (GameBrp 'jackdaw/scene_snapshot' @{}).result
    Op 'input.key' @{ key = 'KeyW'; action = 'release' } | Out-Null
    $pzAfter = $null
    foreach ($e in @($mid)) {
        $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
        $hasPM = $false; $hasPK = $false; $t2 = $null
        foreach ($p in $props) {
            if ("$($p.Name)" -like '*PlayerMarker' -and -not ("$($p.Name)" -like '*Unresolved*')) { $hasPM = $true }
            if ("$($p.Name)" -like '*PickupCount') { $hasPK = $true }
            if ("$($p.Name)" -eq $TKEY) { $t2 = $p.Value }
        }
        if ($hasPM -and -not $hasPK -and $t2) { $pzAfter = [double]$t2.translation[2]; break }
    }
    Write-Host ("PROBE placed player z after 1s W: {0}" -f $pzAfter)
}

Op 'pie.stop' @{} | Out-Null
Start-Sleep -Seconds 4
$st = (Brp 'jackdaw/status' @{}).result
Write-Host ("PROBE pie after stop: {0}" -f $st.pie)

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host 'PROBE_DONE'
