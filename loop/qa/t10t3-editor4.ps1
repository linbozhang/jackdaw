# T10-T3 editor leg A v4: the tool enters through its operators
# (physics.activate / physics.commit) instead of synthesized Shift+P/Space,
# the sensor gizmo is asserted structurally, grid 7 stages the layer entity
# and saves the document for the value edit.
param([int]$Port = 15703)
$ErrorActionPreference = 'Continue'
$Project = 'H:\workspace_AI\t10-phys\phys-game'
$OutDir = 'E:\Project\rust\jackdaw\loop\t10t3-live'

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
    Write-Host "wait(idle) timeout (continuing)"
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

# editor assumed alive from v3; reset the scene from disk
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2

# floor
$r = Op 'entity.add.cube' @{}
$floor = $r.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'scale'; value = '[12.0, 1.0, 12.0]' } | Out-Null
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'translation'; value = '[0.0, -0.5, 0.0]' } | Out-Null
Op 'physics.enable' @{ entity = $floor } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1

# grid 8 structural: sensor authored and visible as a component
$r2 = Op 'entity.add.cube' @{}
$E_SENSOR = $r2.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $E_SENSOR; type_path = $TKEY; field = 'translation'; value = '[1.5, 1.0, 1.5]' } | Out-Null
Op 'physics.enable' @{ entity = $E_SENSOR } | Out-Null
$a1 = Op 'component.add' @{ entity = $E_SENSOR; type_path = 'avian3d::dynamics::rigid_body::Sensor' }
Write-Host ("GRID8_SENSOR_ADD: {0} warn=[{1}]" -f $a1.result.result, ($a1.result.warnings -join ';'))
Start-Sleep -Milliseconds 800
# the sensor round-trips into the document
Op 'scene.save' @{} | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$bsnText = [IO.File]::ReadAllText((Join-Path $Project 'assets\scene.bsn'))
$sensorInDoc = $bsnText -match 'Sensor'
Write-Host ("GRID8_SENSOR_IN_DOC: {0}" -f $sensorInDoc)

# --- grid 2: the tool through its operators -----------------------------------
$E_DROP = Find-Ent (Snap) 2.0 4.0 1.0
Write-Host ("ED4_DROPCUBE: {0}" -f $E_DROP)
if ($E_DROP) {
    Op 'component.set' @{ entity = $E_DROP; type_path = $TKEY; field = 'translation'; value = '[0.0, 5.0, 0.0]' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    Op 'selection.select' @{ entity = $E_DROP } | Out-Null
    Op 'view.frame_selected' @{} | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 2
    $act = Op 'physics.activate' @{}
    Write-Host ("ED4_ACTIVATE: {0}" -f ($act | ConvertTo-Json -Depth 5 -Compress))
    Wait-Idle 90; Start-Sleep -Seconds 1
    $dragged = $false
    foreach ($cand in @(@(760, 540), @(960, 540), @(650, 560), @(860, 500))) {
        Drag-At $cand[0] $cand[1] 70
        Start-Sleep -Seconds 2
        $yNow = Y-Of (Snap) $E_DROP
        Write-Host ("GRID2_DRAG at({0},{1}): y={2}" -f $cand[0], $cand[1], $yNow)
        if ($null -ne $yNow -and [Math]::Abs([double]$yNow - 5.0) -gt 0.8) { $dragged = $true; break }
    }
    if (-not $dragged) {
        Write-Host 'GRID2_SETTLE_FAIL (no drag took even with the operator-entered tool)'
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
        $commit = Op 'physics.commit' @{}
        Wait-Idle 90; Start-Sleep -Seconds 1
        $h1 = (Brp 'jackdaw/history' @{}).result.undo_len
        Write-Host ("GRID2_HISTORY: {0} -> {1} (commit={2})" -f $h0, $h1, $commit.result.result)
        if (($h1 - $h0) -eq 1) { Write-Host 'GRID2_HISTORY_PASS' } else { Write-Host 'GRID2_HISTORY_FAIL' }
        Op 'history.undo' @{} | Out-Null
        Wait-Idle 90; Start-Sleep -Seconds 1
        $yUndo = Y-Of (Snap) $E_DROP
        Write-Host ("GRID2_UNDO_Y: {0}" -f $yUndo)
        if ($null -ne $yUndo -and [Math]::Abs([double]$yUndo - 5.0) -lt 0.5) { Write-Host 'GRID2_UNDO_PASS' } else { Write-Host 'GRID2_UNDO_FAIL' }
        # Esc round
        Op 'physics.activate' @{} | Out-Null
        Wait-Idle 90; Start-Sleep -Seconds 1
        Drag-At 760 540 70
        Start-Sleep -Seconds 2
        Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
        Wait-Idle 90; Start-Sleep -Seconds 1
        $yEsc = Y-Of (Snap) $E_DROP
        Write-Host ("GRID2_ESC_Y: {0}" -f $yEsc)
        if ($null -ne $yEsc -and [Math]::Abs([double]$yEsc - 5.0) -lt 0.5) { Write-Host 'GRID2_ESC_PASS' } else { Write-Host 'GRID2_ESC_FAIL' }
    }
}

# --- grid 4b --------------------------------------------------------------------
$lvSet = Op 'component.set' @{ entity = $E_DROP; type_path = 'avian3d::dynamics::rigid_body::LinearVelocity'; field = ''; value = '[2.0, 0.0, 0.0]' }
Write-Host ("ED4_LV_SET: warn=[{0}]" -f ($lvSet.result.warnings -join ';'))
Op 'selection.select' @{ entity = $E_DROP } | Out-Null
Op 'physics.activate' @{} | Out-Null
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

# --- grid 7 staging: the layer entity + the saved document ----------------------
$r3 = Op 'entity.add.cube' @{}
$E_LAYER = $r3.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $E_LAYER; type_path = $TKEY; field = 'translation'; value = '[-2.0, 3.0, 0.0]' } | Out-Null
Op 'physics.enable' @{ entity = $E_LAYER } | Out-Null
Op 'component.set' @{ entity = $E_LAYER; type_path = 'avian3d::dynamics::rigid_body::RigidBody'; field = ''; value = '{"Dynamic": null}' } | Out-Null
$a3 = Op 'component.add' @{ entity = $E_LAYER; type_path = 'avian3d::collision::layers::CollisionLayers' }
Start-Sleep -Milliseconds 800
Op 'scene.save' @{} | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$txt = [IO.File]::ReadAllText((Join-Path $Project 'assets\scene.bsn'))
$clIdx = $txt.IndexOf('CollisionLayers')
Write-Host ("ED4_CL_IN_DOC: {0}" -f $clIdx)
if ($clIdx -ge 0) {
    $seg = $txt.Substring($clIdx, [Math]::Min(300, $txt.Length - $clIdx))
    Write-Host ("ED4_CL_TEXT: {0}" -f ($seg -replace "`r`n", ' | '))
    [IO.File]::WriteAllText((Join-Path $OutDir 't10t3-scene-with-layers.bsn'), $txt)
}
Write-Host 'T10T3_EDITOR4_DONE (editor alive)'
