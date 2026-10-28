# T10-T3 editor leg A v3: with the avian registration fix in the editor,
# Sensor/CollisionLayers author for real (grid 8 cyan, grid 7 layers), and
# the viewport rect is read from ui_tree to aim the Physics Tool drag.
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
            if ($c.B -gt 100 -and $c.G -gt 70 -and $c.R -lt 70 -and ($c.B - $c.R) -gt 45) { $cyan++ }
            if ($c.G -gt 150 -and $c.R -lt 90 -and ($c.G - $c.B) -gt 25) { $green++ }
        }
    }
    $bmp.Dispose()
    return @{ cyan = $cyan; green = $green }
}

# --- boot ---------------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$env:JACKDAW_WINDOW_SIZE  = '1920x1080'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$work = Split-Path -Parent $Exe
cmd /c "start /B /D `"$work`" cmd /c `"`"$Exe`" > `"$OutDir\ed3-editor.log`" 2>&1`""
$ready = $false
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 2
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
}
if (-not $ready) { Write-Host 'ED3_BOOT_FAIL'; exit 1 }
Wait-Idle 1800
Start-Sleep -Seconds 5
Write-Host 'editor ready'
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2

# --- viewport rect from ui_tree ------------------------------------------------
$tree = Brp 'jackdaw/ui_tree' @{}
$vpx = 760; $vpy = 540
if ($tree -and $tree.result -and $tree.result.nodes) {
    foreach ($n in @($tree.result.nodes)) {
        if ($n.rect -and @($n.rect).Count -ge 4) {
            $r = @($n.rect)
            $w = [double]$r[2]; $h = [double]$r[3]
            if ($w -gt 700 -and $h -gt 500 -and $w -lt 1700) {
                $vpx = [int]($r[0] + $w / 2); $vpy = [int]($r[1] + $h / 2)
                Write-Host ("ED3_VIEWPORT: text={0} rect={1} center=({2},{3})" -f $n.text, ($r -join ','), $vpx, $vpy)
                break
            }
        }
    }
} else { Write-Host 'ED3_VIEWPORT: ui_tree empty, using guess' }

# --- floor --------------------------------------------------------------------
$r = Op 'entity.add.cube' @{}
$floor = $r.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'scale'; value = '[12.0, 1.0, 12.0]' } | Out-Null
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'translation'; value = '[0.0, -0.5, 0.0]' } | Out-Null
Op 'physics.enable' @{ entity = $floor } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1

# --- grid 8 --------------------------------------------------------------------
$r2 = Op 'entity.add.cube' @{}
$E_SENSOR = $r2.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $E_SENSOR; type_path = $TKEY; field = 'translation'; value = '[0.0, 1.2, 0.0]' } | Out-Null
Op 'physics.enable' @{ entity = $E_SENSOR } | Out-Null
$a1 = Op 'component.add' @{ entity = $E_SENSOR; type_path = 'avian3d::dynamics::rigid_body::Sensor' }
Start-Sleep -Milliseconds 800
$off0 = Shot-Count 't10t3-grid8-gizmo-off.png'      # gizmos still off: baseline
Op 'view.toggle_collider_gizmos' @{} | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
$on = Shot-Count 't10t3-grid8-sensor-on.png'
Op 'view.toggle_collider_gizmos' @{} | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
$off = Shot-Count 't10t3-grid8-sensor-off.png'
Write-Host ("GRID8: baseline(cyan={0},green={1}) on(cyan={2},green={3}) off(cyan={4},green={5})" -f `
    $off0.cyan, $off0.green, $on.cyan, $on.green, $off.cyan, $off.green)
# sensor cyan counts against the no-gizmo baseline; green proves the toggle
if (($on.cyan - $off0.cyan) -gt 15 -and $on.green -gt 50 -and $off.green -lt 20 -and $off.cyan -le ($off0.cyan + 10)) {
    Write-Host 'GRID8_PASS'
} else { Write-Host 'GRID8_FAIL' }

# --- grid 2 --------------------------------------------------------------------
$E_DROP = Find-Ent (Snap) 2.0 4.0 1.0
Op 'component.set' @{ entity = $E_DROP; type_path = $TKEY; field = 'translation'; value = '[0.0, 5.0, 0.0]' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1
Op 'selection.select' @{ entity = $E_DROP } | Out-Null
Op 'view.frame_selected' @{} | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1
# status bar check: the tool announces itself
$tree2 = Brp 'jackdaw/ui_tree' @{ }
$toolOn = ''
if ($tree2 -and $tree2.result -and $tree2.result.nodes) {
    foreach ($n in @($tree2.result.nodes)) {
        if ("$($n.text)" -match 'Physics Tool') { $toolOn = $n.text; break }
    }
}
Write-Host ("GRID2_TOOL_STATUS: [{0}]" -f $toolOn)
$dragged = $false
foreach ($cand in @(@($vpx, $vpy), @(960, 540), @($vpx, ($vpy - 80)))) {
    Drag-At $cand[0] $cand[1] 70
    Start-Sleep -Seconds 2
    $yNow = Y-Of (Snap) $E_DROP
    Write-Host ("GRID2_DRAG at({0},{1}): y={2}" -f $cand[0], $cand[1], $yNow)
    if ($null -ne $yNow -and [Math]::Abs([double]$yNow - 5.0) -gt 0.8) { $dragged = $true; break }
}
if (-not $dragged) {
    Write-Host 'GRID2_SETTLE_FAIL (no drag took)'
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
    $h1 = (Brp 'jackdaw/history' @{}).result.undo_len
    Write-Host ("GRID2_HISTORY: {0} -> {1}" -f $h0, $h1)
    if (($h1 - $h0) -eq 1) { Write-Host 'GRID2_HISTORY_PASS' } else { Write-Host 'GRID2_HISTORY_FAIL' }
    Op 'history.undo' @{} | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    $yUndo = Y-Of (Snap) $E_DROP
    Write-Host ("GRID2_UNDO_Y: {0}" -f $yUndo)
    if ($null -ne $yUndo -and [Math]::Abs([double]$yUndo - 5.0) -lt 0.5) { Write-Host 'GRID2_UNDO_PASS' } else { Write-Host 'GRID2_UNDO_FAIL' }
    Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    Drag-At $vpx $vpy 70
    Start-Sleep -Seconds 2
    Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    $yEsc = Y-Of (Snap) $E_DROP
    Write-Host ("GRID2_ESC_Y: {0}" -f $yEsc)
    if ($null -ne $yEsc -and [Math]::Abs([double]$yEsc - 5.0) -lt 0.5) { Write-Host 'GRID2_ESC_PASS' } else { Write-Host 'GRID2_ESC_FAIL' }
}

# --- grid 4b -------------------------------------------------------------------
$lvSet = Op 'component.set' @{ entity = $E_DROP; type_path = 'avian3d::dynamics::rigid_body::LinearVelocity'; field = ''; value = '[2.0, 0.0, 0.0]' }
Write-Host ("ED3_LV_SET: {0} warn={1}" -f $lvSet.result.result, ($lvSet.result.warnings -join ';'))
Op 'selection.select' @{ entity = $E_DROP } | Out-Null
Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1
Drag-At $vpx $vpy 70
Start-Sleep -Seconds 2
$xA = X-Of (Snap) $E_DROP
Start-Sleep -Seconds 2
$xB = X-Of (Snap) $E_DROP
Write-Host ("GRID4B_X: xA={0} xB={1}" -f $xA, $xB)
if ($null -ne $xA -and $null -ne $xB -and ([double]$xB - [double]$xA) -gt 0.5) { Write-Host 'GRID4B_PASS' } else { Write-Host 'GRID4B_FAIL' }
Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1

# --- grid 7: layers (registered now, add + set should author) ------------------
$r3 = Op 'entity.add.cube' @{}
$E_LAYER = $r3.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $E_LAYER; type_path = $TKEY; field = 'translation'; value = '[-2.0, 3.0, 0.0]' } | Out-Null
Op 'physics.enable' @{ entity = $E_LAYER } | Out-Null
$a2 = Op 'component.add' @{ entity = $E_LAYER; type_path = 'avian3d::dynamics::rigid_body::RigidBody' }
$rbSet = Op 'component.set' @{ entity = $E_LAYER; type_path = 'avian3d::dynamics::rigid_body::RigidBody'; field = ''; value = '{"Dynamic": null}' }
$a3 = Op 'component.add' @{ entity = $E_LAYER; type_path = 'avian3d::collision::layers::CollisionLayers' }
Start-Sleep -Milliseconds 800
# red: memberships layer 2 only, filters layer 3 only -> the floor (layer 1) is filtered out
$mSet = Op 'component.set' @{ entity = $E_LAYER; type_path = 'avian3d::collision::layers::CollisionLayers'; field = 'memberships'; value = '2' }
$fSet = Op 'component.set' @{ entity = $E_LAYER; type_path = 'avian3d::collision::layers::CollisionLayers'; field = 'filters'; value = '4' }
Write-Host ("ED3_LAYERS: addRB={0} setRB={1} addCL={2} setM={3} setF={4}" -f `
    $a2.result.result, ($rbSet.result.warnings -join ';'), $a3.result.result, `
    ($mSet.result.warnings -join ';'), ($fSet.result.warnings -join ';'))
if ($mSet.result.warnings.Count -eq 0 -and $fSet.result.warnings.Count -eq 0) {
    # run the two drops through the tool
    Op 'selection.select' @{ entity = $E_LAYER } | Out-Null
    Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    Drag-At $vpx $vpy 70
    Start-Sleep -Seconds 4
    $yRed = Y-Of (Snap) $E_LAYER
    Write-Host ("GRID7_RED_Y: {0}" -f $yRed)
    if ($null -ne $yRed -and [double]$yRed -lt -1.5) { Write-Host 'GRID7_RED_PASS (fell through)' } else { Write-Host 'GRID7_RED_FAIL' }
    Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    Op 'component.set' @{ entity = $E_LAYER; type_path = $TKEY; field = 'translation'; value = '[-2.0, 3.0, 0.0]' } | Out-Null
    Op 'component.set' @{ entity = $E_LAYER; type_path = 'avian3d::collision::layers::CollisionLayers'; field = 'filters'; value = '3' } | Out-Null
    Start-Sleep -Milliseconds 800
    Op 'selection.select' @{ entity = $E_LAYER } | Out-Null
    Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    Drag-At $vpx $vpy 70
    Start-Sleep -Seconds 4
    $yG1 = Y-Of (Snap) $E_LAYER
    Start-Sleep -Seconds 2
    $yG2 = Y-Of (Snap) $E_LAYER
    Write-Host ("GRID7_GREEN_Y: y1={0} y2={1}" -f $yG1, $yG2)
    if ($null -ne $yG2 -and [Math]::Abs([double]$yG2 - [double]$yG1) -lt 0.05 -and $yG2 -gt -0.2 -and $yG2 -lt 1.2) {
        Write-Host 'GRID7_GREEN_PASS (rests)'
    } else { Write-Host 'GRID7_GREEN_FAIL' }
    Op 'input.key' @{ key = 'Space'; action = 'tap' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
} else {
    Write-Host 'GRID7_SKIPPED (layer set refused; see warnings)'
}
Write-Host 'T10T3_EDITOR3_DONE (editor alive)'
