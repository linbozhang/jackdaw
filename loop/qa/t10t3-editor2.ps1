# T10-T3 matrix, editor legs A v2 (fresh editor boot, all fixes):
#   grid 8  - sensor cyan (relaxed threshold for the 0.5-alpha blend) +
#             gizmo toggle roundtrip (green collider count on/off)
#   grid 2  - Physics Tool drag-release (frame_selected + candidate
#             viewport coordinates), settle, Space = +1 history, undo
#             restores, Esc reverts
#   grid 4b - LinearVelocity moves a dynamic body in-sim
#   grid 7  - layers via scene.bsn authoring: filtered-out falls through,
#             re-layered rests; the authored mask survives save/reopen
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t10t3-editor2.ps1
param(
    [string]$Project = 'H:\workspace_AI\t10-phys\phys-game',
    [int]$Port = 15703
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$Exe  = Join-Path $Repo 'target\debug\jackdaw.exe'
$OutDir = Join-Path $Repo 'loop\t10t3-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Add-Type -AssemblyName System.Drawing

function Brp([string]$method, $params, [int]$retries = 4) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 12)
        } catch { Start-Sleep -Milliseconds (400 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp 'jackdaw/call_operator' @{ id = $id } }
}
function Wait-Idle([int]$TimeoutSec = 90) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp 'jackdaw/wait' @{ until = 'idle' } 1
        if ($r -and $r.result -and $r.result.idle) { return $true }
        Start-Sleep -Seconds 1
    }
    Write-Host "wait(idle) timeout ${TimeoutSec}s (continuing)"
}
$TKEY = 'bevy_transform::components::transform::Transform'
function Get-T($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) {
        return $e.components.PSObject.Properties[$TKEY].Value
    }
    return $e.components[$TKEY]
}
function Snap { (Brp 'jackdaw/scene_snapshot' @{}).result }
function Find-Ent([object]$snap, [double]$x, [double]$y, [double]$band) {
    $best = $null; $bestD = 1e9
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if ($t) {
            $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
            $d = [Math]::Abs($ex - $x) + [Math]::Abs($ey - $y)
            if ($d -lt $bestD) { $bestD = $d; $best = $e.entity }
        }
    }
    if ($bestD -lt $band) { return $best } else { return $null }
}
function Y-Of([object]$snap, $entity) {
    foreach ($e in @($snap)) {
        if ("$($e.entity)" -eq "$entity") {
            $t = Get-T $e
            if ($t) { return [double]$t.translation[1] }
        }
    }
    return $null
}
function X-Of([object]$snap, $entity) {
    foreach ($e in @($snap)) {
        if ("$($e.entity)" -eq "$entity") {
            $t = Get-T $e
            if ($t) { return [double]$t.translation[0] }
        }
    }
    return $null
}
# one press-move-release drag through the synthetic input queue
function Drag-At([double]$x, [double]$y, [double]$dy) {
    Op 'input.pointer' @{ x = $x; y = $y; action = 'move' } | Out-Null
    Start-Sleep -Milliseconds 300
    Op 'input.pointer' @{ x = $x; y = $y; action = 'press' } | Out-Null
    Start-Sleep -Milliseconds 450
    Op 'input.pointer' @{ x = $x; y = ($y + $dy); action = 'move' } | Out-Null
    Start-Sleep -Milliseconds 450
    Op 'input.pointer' @{ x = $x; y = ($y + $dy); action = 'release' } | Out-Null
    Wait-Idle 60
}
function Shot-Count([string]$name) {
    # viewport screenshot lands in the project root; move it, count pixels
    Brp 'jackdaw/screenshot' @{ kind = 'viewport'; path = $name } | Out-Null
    Start-Sleep -Seconds 2
    $inproj = Join-Path $Project $name
    $arc = Join-Path $OutDir $name
    if (Test-Path $inproj) { Move-Item $inproj $arc -Force }
    if (-not (Test-Path $arc)) { return $null }
    $bmp = New-Object System.Drawing.Bitmap $arc
    $cyan = 0; $green = 0
    for ($x = 0; $x -lt $bmp.Width; $x++) {
        for ($y = 0; $y -lt $bmp.Height; $y++) {
            $c = $bmp.GetPixel($x, $y)
            # sensor wireframe: srgba(0, 0.8, 1.0, 0.5) over a dark scene --
            # blended to roughly (10, 110, 135)
            if ($c.B -gt 100 -and $c.G -gt 70 -and $c.R -lt 70 -and ($c.B - $c.R) -gt 45) { $cyan++ }
            if ($c.G -gt 150 -and $c.R -lt 90 -and ($c.G - $c.B) -gt 25) { $green++ }
        }
    }
    $bmp.Dispose()
    return @{ cyan = $cyan; green = $green }
}

# --- fresh boot ---------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$env:JACKDAW_WINDOW_SIZE  = '1920x1080'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$work = Split-Path -Parent $Exe
cmd /c "start /B /D `"$work`" cmd /c `"`"$Exe`" > `"$OutDir\ed2-editor.log`" 2>&1`""
$ready = $false
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 2
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
}
if (-not $ready) { Write-Host 'ED2_BOOT_FAIL'; exit 1 }
Wait-Idle 1800
Start-Sleep -Seconds 5
Write-Host 'editor ready (fresh)'
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2

# --- the floor ---------------------------------------------------------------
$r = Op 'entity.add.cube' @{}
$floor = $r.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'scale'; value = '[12.0, 1.0, 12.0]' } | Out-Null
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'translation'; value = '[0.0, -0.5, 0.0]' } | Out-Null
Op 'physics.enable' @{ entity = $floor } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1
Write-Host ("ED2_FLOOR: {0}" -f $floor)

# --- grid 8: sensor cyan + toggle roundtrip -----------------------------------
$r2 = Op 'entity.add.cube' @{}
$E_SENSOR = $r2.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $E_SENSOR; type_path = $TKEY; field = 'translation'; value = '[1.5, 1.0, 1.5]' } | Out-Null
Op 'physics.enable' @{ entity = $E_SENSOR } | Out-Null
$a1 = Op 'component.add' @{ entity = $E_SENSOR; type_path = 'avian3d::dynamics::rigid_body::Sensor' }
Write-Host ("ED2_SENSOR_ADD: {0}" -f ($a1.result.result))
Wait-Idle 90; Start-Sleep -Seconds 2
Op 'view.toggle_collider_gizmos' @{} | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
$on = Shot-Count 't10t3-grid8-sensor-on.png'
Op 'view.toggle_collider_gizmos' @{} | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
$off = Shot-Count 't10t3-grid8-sensor-off.png'
Write-Host ("GRID8: on(cyan={0},green={1}) off(cyan={2},green={3})" -f $on.cyan, $on.green, $off.cyan, $off.green)
if ($on.cyan -gt 20 -and $off.cyan -lt [Math]::Max(3, $on.cyan / 5) -and $on.green -gt 50 -and $off.green -lt 20) {
    Write-Host 'GRID8_PASS'
} else { Write-Host 'GRID8_FAIL' }

# --- grid 2: Physics Tool -----------------------------------------------------
$E_DROP = Find-Ent (Snap) 2.0 4.0 1.0
Write-Host ("ED2_DROPCUBE: {0}" -f $E_DROP)
Op 'component.set' @{ entity = $E_DROP; type_path = $TKEY; field = 'translation'; value = '[0.0, 5.0, 0.0]' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1
Op 'selection.select' @{ entity = $E_DROP } | Out-Null
Op 'view.frame_selected' @{} | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1
$dragged = $false
foreach ($cand in @(@(760, 540), @(960, 540), @(650, 560), @(1100, 540))) {
    Drag-At $cand[0] $cand[1] 70
    Start-Sleep -Seconds 2
    $yNow = Y-Of (Snap) $E_DROP
    Write-Host ("GRID2_DRAG at({0},{1}): y={2}" -f $cand[0], $cand[1], $yNow)
    if ($null -ne $yNow -and [Math]::Abs([double]$yNow - 5.0) -gt 0.8) { $dragged = $true; break }
}
if (-not $dragged) {
    Write-Host 'GRID2_SETTLE_FAIL (no drag took; candidates exhausted)'
} else {
    Start-Sleep -Seconds 3
    $yA = Y-Of (Snap) $E_DROP
    Start-Sleep -Seconds 2
    $yB = Y-Of (Snap) $E_DROP
    Write-Host ("GRID2_SETTLE: yA={0} yB={1}" -f $yA, $yB)
    if ($null -ne $yA -and $null -ne $yB -and [Math]::Abs([double]$yB - [double]$yA) -lt 0.05 -and $yB -lt 2.0) {
        Write-Host 'GRID2_SETTLE_PASS'
    } else { Write-Host 'GRID2_SETTLE_FAIL' }
    $h0 = (Brp 'jackdaw/history' @{}).result.undo_len
    Op 'input.key' @{ key = 'Space'; action = 'tap' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    $h1 = (Brp 'jackdaw/history' @{}).result
    Write-Host ("GRID2_HISTORY: {0} -> {1}" -f $h0, $h1.undo_len)
    if (($h1.undo_len - $h0) -eq 1) { Write-Host 'GRID2_HISTORY_PASS' } else { Write-Host 'GRID2_HISTORY_FAIL' }
    Op 'history.undo' @{} | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    $yUndo = Y-Of (Snap) $E_DROP
    Write-Host ("GRID2_UNDO_Y: {0}" -f $yUndo)
    if ($null -ne $yUndo -and [Math]::Abs([double]$yUndo - 5.0) -lt 0.5) { Write-Host 'GRID2_UNDO_PASS' } else { Write-Host 'GRID2_UNDO_FAIL' }
    # Esc round
    Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    Drag-At 760 540 70
    Start-Sleep -Seconds 2
    Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    $yEsc = Y-Of (Snap) $E_DROP
    Write-Host ("GRID2_ESC_Y: {0}" -f $yEsc)
    if ($null -ne $yEsc -and [Math]::Abs([double]$yEsc - 5.0) -lt 0.5) { Write-Host 'GRID2_ESC_PASS' } else { Write-Host 'GRID2_ESC_FAIL' }
}

# --- grid 4b: LinearVelocity --------------------------------------------------
$lvSet = Op 'component.set' @{ entity = $E_DROP; type_path = 'avian3d::dynamics::rigid_body::LinearVelocity'; field = ''; value = '[2.0, 0.0, 0.0]' }
Write-Host ("ED2_LV_SET: {0} warn={1}" -f $lvSet.result.result, ($lvSet.result.warnings -join ';'))
Op 'selection.select' @{ entity = $E_DROP } | Out-Null
Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1
Drag-At 760 540 70
Start-Sleep -Seconds 2
$xA = X-Of (Snap) $E_DROP
Start-Sleep -Seconds 2
$xB = X-Of (Snap) $E_DROP
Write-Host ("GRID4B_X: xA={0} xB={1}" -f $xA, $xB)
if ($null -ne $xA -and $null -ne $xB -and ([double]$xB - [double]$xA) -gt 0.5) { Write-Host 'GRID4B_PASS' } else { Write-Host 'GRID4B_FAIL' }
Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1

# --- grid 7: layers through the scene document --------------------------------
$r3 = Op 'entity.add.cube' @{}
$E_LAYER = $r3.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $E_LAYER; type_path = $TKEY; field = 'translation'; value = '[-2.0, 3.0, 0.0]' } | Out-Null
Op 'physics.enable' @{ entity = $E_LAYER } | Out-Null
$a2 = Op 'component.add' @{ entity = $E_LAYER; type_path = 'avian3d::dynamics::rigid_body::RigidBody' }
$rbSet = Op 'component.set' @{ entity = $E_LAYER; type_path = 'avian3d::dynamics::rigid_body::RigidBody'; field = ''; value = '{"Dynamic": null}' }
Write-Host ("ED2_LAYER_RB: add={0} set={1}" -f $a2.result.result, ($rbSet.result.warnings -join ';'))
$a3 = Op 'component.add' @{ entity = $E_LAYER; type_path = 'avian3d::collision::layers::CollisionLayers' }
Write-Host ("ED2_LAYER_ADD: {0}" -f $a3.result.result)
Wait-Idle 90; Start-Sleep -Seconds 1
# author the red mask in the document itself (the serde path refuses LayerMask)
Op 'scene.save' @{} | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$bsn = Join-Path $Project 'assets\scene.bsn'
$txt = [IO.File]::ReadAllText($bsn)
$layerIdx = $txt.IndexOf('CollisionLayers')
Write-Host ("ED2_BSN_LAYERS_AT: {0}" -f $layerIdx)
if ($layerIdx -ge 0) {
    $seg = $txt.Substring($layerIdx, [Math]::Min(260, $txt.Length - $layerIdx))
    Write-Host ("ED2_BSN_LAYERS_TEXT: {0}" -f ($seg -replace "`r`n", ' | '))
}
Write-Host 'T10T3_EDITOR2_PART1_DONE (editor alive)'
