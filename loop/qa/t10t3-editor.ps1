# T10-T3 matrix, editor legs A (warm project, editor-side BRP on 15703):
#   grid 8  - sensor gizmo cyan in the viewport screenshot + toggle roundtrip
#   grid 2  - Physics Tool: drag-release settles on the static floor,
#             Space commits one history entry, undo restores, Esc reverts
#   grid 4b - LinearVelocity authored on a dynamic body moves it in-sim
#   grid 7  - collision layers: filtered-out falls through the floor,
#             re-layered one rests on it
# Detached boot via cmd start /B. Logs/screenshots land in loop\t10t3-live.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t10t3-editor.ps1
param(
    [string]$Project = 'H:\workspace_AI\t10-phys\phys-game',
    [int]$Port = 15703
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$Exe  = Join-Path $Repo 'target\debug\jackdaw.exe'
$OutDir = Join-Path $Repo 'loop\t10t3-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Brp([string]$method, $params, [int]$retries = 4) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 10)
        } catch { Start-Sleep -Milliseconds (400 * ($i + 1)) }
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
    Write-Host "wait(idle) timed out after ${TimeoutSec}s (continuing)"
}
$TKEY = 'bevy_transform::components::transform::Transform'
function Get-T($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) {
        return $e.components.PSObject.Properties[$TKEY].Value
    }
    return $e.components[$TKEY]
}
function Snap { (Brp 'jackdaw/scene_snapshot' @{}).result }
# entity bits of the scene entity whose transform is nearest (x,y)
function Find-Ent([object]$snap, [double]$x, [double]$y) {
    $best = $null; $bestD = 1e9
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if ($t) {
            $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
            $d = [Math]::Abs($ex - $x) + [Math]::Abs($ey - $y)
            if ($d -lt $bestD) { $bestD = $d; $best = $e.entity }
        }
    }
    return $best
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

# --- boot -------------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$env:JACKDAW_WINDOW_SIZE  = '1920x1080'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$work = Split-Path -Parent $Exe
cmd /c "start /B /D `"$work`" cmd /c `"`"$Exe`" > `"$OutDir\edA-editor.log`" 2>&1`""
$ready = $false
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 2
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
}
if (-not $ready) { Write-Host 'EDA_BOOT_FAIL'; exit 1 }
Wait-Idle 1800
Start-Sleep -Seconds 5
Write-Host 'editor ready'

# --- scene ------------------------------------------------------------------
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 2
$E_DROP = Find-Ent (Snap) 2.0 4.0
Write-Host ("EDA_DROPCUBE: {0}" -f $E_DROP)
if (-not $E_DROP) { Write-Host 'EDA_FAIL no DroppingCube'; exit 1 }

# --- the static floor (a wide scaled cube) ----------------------------------
$r = Op 'entity.add.cube' @{}
$floor = $r.result.entities | Select-Object -Last 1
Write-Host ("EDA_FLOOR: {0}" -f $floor)
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'scale'; value = '[12.0, 1.0, 12.0]' } | Out-Null
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'translation'; value = '[0.0, -0.5, 0.0]' } | Out-Null
Op 'physics.enable' @{ entity = $floor } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1

# --- grid 8: sensor gizmo cyan in the viewport -------------------------------
$r2 = Op 'entity.add.cube' @{}
$E_SENSOR = $r2.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $E_SENSOR; type_path = $TKEY; field = 'translation'; value = '[1.5, 1.0, 1.5]' } | Out-Null
Op 'physics.enable' @{ entity = $E_SENSOR } | Out-Null
$sensorSet = Op 'component.set' @{ entity = $E_SENSOR; type_path = 'avian3d::dynamics::rigid_body::Sensor'; field = ''; value = 'null' }
Write-Host ("EDA_SENSOR_SET: {0}" -f ($sensorSet | ConvertTo-Json -Depth 5 -Compress))
Op 'view.toggle_collider_gizmos' @{} | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 2
$shot1 = Brp 'jackdaw/screenshot' @{ kind = 'viewport'; path = 't10t3-grid8-sensor-on.png' }
Start-Sleep -Seconds 2
# cyan pixels: SENSOR_WIREFRAME = srgba(0, 0.8, 1.0)
Add-Type -AssemblyName System.Drawing
$png = Join-Path $OutDir 't10t3-grid8-sensor-on.png'
$cyan = 0
if (Test-Path $png) {
    $bmp = New-Object System.Drawing.Bitmap $png
    for ($px = 0; $px -lt $bmp.Width; $px += 2) {
        for ($py = 0; $py -lt $bmp.Height; $py += 2) {
            $c = $bmp.GetPixel($px, $py)
            if ($c.B -gt 200 -and $c.G -gt 150 -and $c.R -lt 90 -and ($c.B - $c.R) -gt 90) { $cyan++ }
        }
    }
    $bmp.Dispose()
}
Write-Host ("GRID8_CYAN_PIXELS(on): {0}" -f $cyan)
Op 'view.toggle_collider_gizmos' @{} | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 2
$shot2 = Brp 'jackdaw/screenshot' @{ kind = 'viewport'; path = 't10t3-grid8-sensor-off.png' }
Start-Sleep -Seconds 2
$png2 = Join-Path $OutDir 't10t3-grid8-sensor-off.png'
$cyan2 = 0
if (Test-Path $png2) {
    $bmp2 = New-Object System.Drawing.Bitmap $png2
    for ($px = 0; $px -lt $bmp2.Width; $px += 2) {
        for ($py = 0; $py -lt $bmp2.Height; $py += 2) {
            $c = $bmp2.GetPixel($px, $py)
            if ($c.B -gt 200 -and $c.G -gt 150 -and $c.R -lt 90 -and ($c.B - $c.R) -gt 90) { $cyan2++ }
        }
    }
    $bmp2.Dispose()
}
Write-Host ("GRID8_CYAN_PIXELS(off): {0}" -f $cyan2)
if ($cyan -gt 30 -and $cyan2 -lt [Math]::Max(5, $cyan / 5)) { Write-Host 'GRID8_PASS' } else { Write-Host 'GRID8_FAIL' }

# --- grid 2: Physics Tool drag-release + Space commit + undo ------------------
# Put the drop cube where the viewport camera looks, high enough to fall.
Op 'component.set' @{ entity = $E_DROP; type_path = $TKEY; field = 'translation'; value = '[0.0, 5.0, 0.0]' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
# select it (an empty operator param set cannot select; the history tool
# works on the selection, so click it in the viewport through ui_click's
# operator surface is unavailable -- use the scene tree selection via
# jackdaw/scene_snapshot entity + outliner click through ui_click text)
# The physics tool operates on the primary selection. The outliner row for
# the entity is addressed by its name below.
$selResp = Op 'selection.select' @{ entity = $E_DROP }
Write-Host ("EDA_SELECT: {0}" -f ($selResp | ConvertTo-Json -Depth 5 -Compress))
Start-Sleep -Milliseconds 600
# Shift+P activates the tool
Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
# drag from viewport center-ish downward: press, move, release
Op 'input.pointer' @{ x = 950; y = 500; action = 'move' } | Out-Null
Start-Sleep -Milliseconds 300
Op 'input.pointer' @{ x = 950; y = 500; action = 'press' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.pointer' @{ x = 950; y = 560; action = 'move' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.pointer' @{ x = 950; y = 560; action = 'release' } | Out-Null
Wait-Idle 60
Start-Sleep -Seconds 3
$yA = Y-Of (Snap) $E_DROP
Start-Sleep -Seconds 2
$yB = Y-Of (Snap) $E_DROP
Write-Host ("GRID2_SETTLE: yA={0} yB={1}" -f $yA, $yB)
if ($null -ne $yA -and $null -ne $yB -and [Math]::Abs([double]$yB - [double]$yA) -lt 0.02 -and $yB -lt 2.0) {
    Write-Host 'GRID2_SETTLE_PASS'
} else { Write-Host 'GRID2_SETTLE_FAIL' }
# Space commits: exactly one history entry on top
$histBefore = Brp 'jackdaw/history' @{ }
$beforeLen = $histBefore.result.undo_len
Op 'input.key' @{ key = 'Space'; action = 'tap' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
$histAfter = Brp 'jackdaw/history' @{ }
$afterLen = $histAfter.result.undo_len
Write-Host ("GRID2_HISTORY: before={0} after={1} top={2}" -f $beforeLen, $afterLen, ($histAfter.result.entries | Select-Object -First 1 | ConvertTo-Json -Compress))
if (($afterLen - $beforeLen) -eq 1) { Write-Host 'GRID2_HISTORY_PASS' } else { Write-Host 'GRID2_HISTORY_FAIL' }
# undo restores the pre-tool pose (y=5)
Op 'history.undo' @{} | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
$yUndo = Y-Of (Snap) $E_DROP
Write-Host ("GRID2_UNDO_Y: {0}" -f $yUndo)
if ($null -ne $yUndo -and [Math]::Abs([double]$yUndo - 5.0) -lt 0.3) { Write-Host 'GRID2_UNDO_PASS' } else { Write-Host 'GRID2_UNDO_FAIL' }

# --- grid 2b: Esc cancels and reverts ----------------------------------------
Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
Op 'input.pointer' @{ x = 950; y = 500; action = 'press' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.pointer' @{ x = 950; y = 570; action = 'move' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.pointer' @{ x = 950; y = 570; action = 'release' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 2
Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
$yEsc = Y-Of (Snap) $E_DROP
Write-Host ("GRID2_ESC_Y: {0}" -f $yEsc)
if ($null -ne $yEsc -and [Math]::Abs([double]$yEsc - 5.0) -lt 0.3) { Write-Host 'GRID2_ESC_PASS' } else { Write-Host 'GRID2_ESC_FAIL' }

# --- grid 4b: LinearVelocity moves a dynamic body in-sim ----------------------
$sel2 = Op 'selection.select' @{ entity = $E_DROP }
Start-Sleep -Milliseconds 600
$lvSet = Op 'component.set' @{ entity = $E_DROP; type_path = 'avian3d::dynamics::rigid_body::LinearVelocity'; field = ''; value = '[2.0, 0.0, 0.0]' }
Write-Host ("EDA_LV_SET: {0}" -f ($lvSet | ConvertTo-Json -Depth 5 -Compress))
Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
Op 'input.pointer' @{ x = 950; y = 500; action = 'press' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.pointer' @{ x = 950; y = 560; action = 'move' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.pointer' @{ x = 950; y = 560; action = 'release' } | Out-Null
Start-Sleep -Seconds 2
$xA = X-Of (Snap) $E_DROP
Start-Sleep -Seconds 2
$xB = X-Of (Snap) $E_DROP
Write-Host ("GRID4B_X: xA={0} xB={1}" -f $xA, $xB)
if ($null -ne $xA -and $null -ne $xB -and ([double]$xB - [double]$xA) -gt 0.4) { Write-Host 'GRID4B_PASS' } else { Write-Host 'GRID4B_FAIL' }
Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1

# --- grid 7: layers filter the fall ------------------------------------------
$r3 = Op 'entity.add.cube' @{}
$E_LAYER = $r3.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $E_LAYER; type_path = $TKEY; field = 'translation'; value = '[-2.0, 3.0, 0.0]' } | Out-Null
Op 'physics.enable' @{ entity = $E_LAYER } | Out-Null
$rbSet = Op 'component.set' @{ entity = $E_LAYER; type_path = 'avian3d::dynamics::rigid_body::RigidBody'; field = ''; value = '{"Dynamic": null}' }
Write-Host ("EDA_RB_SET: {0}" -f ($rbSet | ConvertTo-Json -Depth 5 -Compress))
# red: memberships layer 2 (0b010) filtered against everything but layer 3
# (0b100) -- the floor (layer 1, 0b001) is filtered out, the body falls through
$mSet = Op 'component.set' @{ entity = $E_LAYER; type_path = 'avian3d::collision::layers::CollisionLayers'; field = 'memberships.0'; value = '2' }
$fSet = Op 'component.set' @{ entity = $E_LAYER; type_path = 'avian3d::collision::layers::CollisionLayers'; field = 'filters.0'; value = '4' }
Write-Host ("EDA_LAYERS_RED: m={0} f={1}" -f ($mSet | ConvertTo-Json -Depth 4 -Compress), ($fSet | ConvertTo-Json -Depth 4 -Compress))
$selL = Op 'selection.select' @{ entity = $E_LAYER }
Start-Sleep -Milliseconds 600
Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
Op 'input.pointer' @{ x = 950; y = 500; action = 'press' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.pointer' @{ x = 950; y = 560; action = 'move' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.pointer' @{ x = 950; y = 560; action = 'release' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 3
$yRed = Y-Of (Snap) $E_LAYER
Write-Host ("GRID7_RED_Y: {0}" -f $yRed)
if ($null -ne $yRed -and [double]$yRed -lt -1.0) { Write-Host 'GRID7_RED_PASS (fell through)' } else { Write-Host 'GRID7_RED_FAIL' }
Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
# green: filters admit layer 1 -- the same body now rests on the floor
Op 'component.set' @{ entity = $E_LAYER; type_path = $TKEY; field = 'translation'; value = '[-2.0, 3.0, 0.0]' } | Out-Null
$fSet2 = Op 'component.set' @{ entity = $E_LAYER; type_path = 'avian3d::collision::layers::CollisionLayers'; field = 'filters.0'; value = '3' }
$selL2 = Op 'selection.select' @{ entity = $E_LAYER }
Start-Sleep -Milliseconds 600
Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 1
Op 'input.pointer' @{ x = 950; y = 500; action = 'press' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.pointer' @{ x = 950; y = 560; action = 'move' } | Out-Null
Start-Sleep -Milliseconds 400
Op 'input.pointer' @{ x = 950; y = 560; action = 'release' } | Out-Null
Wait-Idle 60; Start-Sleep -Seconds 3
$yGreen = Y-Of (Snap) $E_LAYER
Start-Sleep -Seconds 2
$yGreen2 = Y-Of (Snap) $E_LAYER
Write-Host ("GRID7_GREEN_Y: y1={0} y2={1}" -f $yGreen, $yGreen2)
if ($null -ne $yGreen2 -and [Math]::Abs([double]$yGreen2 - [double]$yGreen) -lt 0.05 -and $yGreen2 -gt -0.2 -and $yGreen2 -lt 1.2) {
    Write-Host 'GRID7_GREEN_PASS (rests)'
} else { Write-Host 'GRID7_GREEN_FAIL' }
Op 'input.key' @{ key = 'Space'; action = 'tap' } | Out-Null   # commit the resting pose (grid 10 keeps it)
Wait-Idle 60; Start-Sleep -Seconds 1

# --- keep the editor alive for leg B (save/reopen/PIE/export) ----------------
Write-Host 'T10T3_EDITOR_A_DONE (editor left running for leg B)'
