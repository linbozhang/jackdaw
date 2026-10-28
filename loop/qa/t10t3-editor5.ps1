# T10-T3 editor leg A FINAL: clean boot, scene pre-authored with a Sensor
# cube and a layered cube in the document; the tool enters through its
# operators; layers flip by editing the document (save -> edit -> reopen).
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
function Has-Comp([object]$snap, $entity, [string]$suffix) {
    foreach ($e in @($snap)) {
        if ("$($e.entity)" -eq "$entity") {
            $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
            foreach ($p in $props) { if ("$($p.Name)" -like "*$suffix") { return $true } }
        }
    }
    return $false
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

# --- clean boot ----------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$env:JACKDAW_WINDOW_SIZE  = '1920x1080'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"$(Split-Path -Parent $Exe)`" cmd /c `"`"$Exe`" > `"$OutDir\ed5-editor.log`" 2>&1`""
for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Seconds 2; if (Brp 'jackdaw/status' @{} 1) { break } }
Wait-Idle 1800; Start-Sleep -Seconds 5
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2

# --- what the document loaded ----------------------------------------------------
$E_DROP = Find-Ent (Snap) 2.0 4.0 1.0
$E_SENSOR = Find-Ent (Snap) 1.5 1.0 1.0
$E_LAYER = Find-Ent (Snap) -2.0 3.0 1.0
Write-Host ("ED5_ENTS: drop={0} sensor={1} layer={2}" -f $E_DROP, $E_SENSOR, $E_LAYER)
if ($E_SENSOR) {
    $sensorLoaded = Has-Comp (Snap) $E_SENSOR 'Sensor'
    Write-Host ("GRID8_SENSOR_LOADED: {0}" -f $sensorLoaded)
}
if ($E_LAYER) {
    $clLoaded = Has-Comp (Snap) $E_LAYER 'CollisionLayers'
    Write-Host ("GRID7_LAYERS_LOADED: {0}" -f $clLoaded)
}

# --- floor -----------------------------------------------------------------------
$r = Op 'entity.add.cube' @{}
$floor = $r.result.entities | Select-Object -Last 1
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'scale'; value = '[12.0, 1.0, 12.0]' } | Out-Null
Op 'component.set' @{ entity = $floor; type_path = $TKEY; field = 'translation'; value = '[0.0, -0.5, 0.0]' } | Out-Null
Op 'physics.enable' @{ entity = $floor } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 1

# --- grid 8: cyan wireframe differential ------------------------------------------
$off0 = Shot-Count 't10t3-grid8-base.png'
Op 'view.toggle_collider_gizmos' @{} | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
$on = Shot-Count 't10t3-grid8-on.png'
Op 'view.toggle_collider_gizmos' @{} | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2
$off = Shot-Count 't10t3-grid8-off.png'
Write-Host ("GRID8: base(c={0},g={1}) on(c={2},g={3}) off(c={4},g={5})" -f $off0.cyan, $off0.green, $on.cyan, $on.green, $off.cyan, $off.green)
if (($on.cyan - $off.cyan) -gt 15 -and $on.green -gt 50) { Write-Host 'GRID8_PASS' } else { Write-Host 'GRID8_FAIL' }

# --- grid 2 ------------------------------------------------------------------------
if ($E_DROP) {
    Op 'component.set' @{ entity = $E_DROP; type_path = $TKEY; field = 'translation'; value = '[0.0, 5.0, 0.0]' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    Op 'selection.select' @{ entity = $E_DROP } | Out-Null
    Op 'view.frame_selected' @{} | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 2
    $act = Op 'physics.activate' @{}
    Wait-Idle 90; Start-Sleep -Seconds 1
    $dragged = $false
    foreach ($cand in @(@(760, 540), @(960, 540), @(650, 560), @(860, 500), @(1060, 540))) {
        Drag-At $cand[0] $cand[1] 70
        Start-Sleep -Seconds 2
        $yNow = Y-Of (Snap) $E_DROP
        Write-Host ("GRID2_DRAG at({0},{1}): y={2}" -f $cand[0], $cand[1], $yNow)
        if ($null -ne $yNow -and [Math]::Abs([double]$yNow - 5.0) -gt 0.8) { $dragged = $true; break }
    }
    if (-not $dragged) {
        Write-Host 'GRID2_DRAG_FAIL (tool activated, no pointer hit found)'
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
        Op 'physics.commit' @{} | Out-Null
        Wait-Idle 90; Start-Sleep -Seconds 1
        $h1 = (Brp 'jackdaw/history' @{}).result.undo_len
        Write-Host ("GRID2_HISTORY: {0} -> {1}" -f $h0, $h1)
        if (($h1 - $h0) -eq 1) { Write-Host 'GRID2_HISTORY_PASS' } else { Write-Host 'GRID2_HISTORY_FAIL' }
        Op 'history.undo' @{} | Out-Null
        Wait-Idle 90; Start-Sleep -Seconds 1
        $yUndo = Y-Of (Snap) $E_DROP
        Write-Host ("GRID2_UNDO_Y: {0}" -f $yUndo)
        if ($null -ne $yUndo -and [Math]::Abs([double]$yUndo - 5.0) -lt 0.5) { Write-Host 'GRID2_UNDO_PASS' } else { Write-Host 'GRID2_UNDO_FAIL' }
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

# --- grid 4b ------------------------------------------------------------------------
$lvSet = Op 'component.set' @{ entity = $E_DROP; type_path = 'avian3d::dynamics::rigid_body::LinearVelocity'; field = ''; value = '[2.0, 0.0, 0.0]' }
Write-Host ("ED5_LV_SET: warn=[{0}]" -f ($lvSet.result.warnings -join ';'))
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

# --- grid 7: red (authored mask filters the floor out) -------------------------------
if ($E_LAYER -and (Has-Comp (Snap) $E_LAYER 'CollisionLayers')) {
    Op 'selection.select' @{ entity = $E_LAYER } | Out-Null
    Op 'physics.activate' @{} | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
    $hit = $false
    foreach ($cand in @(@(760, 540), @(960, 540), @(860, 500))) {
        Drag-At $cand[0] $cand[1] 70
        Start-Sleep -Seconds 3
        $yNow = Y-Of (Snap) $E_LAYER
        Write-Host ("GRID7_RED_DRAG at({0},{1}): y={2}" -f $cand[0], $cand[1], $yNow)
        if ($null -ne $yNow -and [Math]::Abs([double]$yNow - 3.0) -gt 0.8) { $hit = $true; break }
    }
    if ($hit) {
        Start-Sleep -Seconds 2
        $yRed = Y-Of (Snap) $E_LAYER
        Write-Host ("GRID7_RED_Y: {0}" -f $yRed)
        if ($null -ne $yRed -and [double]$yRed -lt -1.0) { Write-Host 'GRID7_RED_PASS (fell through the filtered floor)' } else { Write-Host 'GRID7_RED_FAIL' }
    } else { Write-Host 'GRID7_RED_FAIL (no drag)' }
    Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
    Wait-Idle 90; Start-Sleep -Seconds 1
} elseif ($E_LAYER) {
    Write-Host 'GRID7_RED_SKIP (CollisionLayers did not load from the document)'
}

# save the staged scene, flip the mask in the document, reopen, go green
Op 'scene.save' @{} | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$bsnPath = Join-Path $Project 'assets\scene.bsn'
$txt = [IO.File]::ReadAllText($bsnPath)
$clIdx = $txt.IndexOf('CollisionLayers')
Write-Host ("ED5_CL_IN_DOC: {0}" -f $clIdx)
if ($clIdx -ge 0) {
    $seg = $txt.Substring($clIdx, [Math]::Min(220, $txt.Length - $clIdx))
    Write-Host ("ED5_CL_TEXT: {0}" -f ($seg -replace "`r`n", ' | '))
    $green = $txt.Replace('CollisionLayers { memberships: 2, filters: 4 }', 'CollisionLayers { memberships: 2, filters: 3 }')
    if ($green -ne $txt) {
        [IO.File]::WriteAllText($bsnPath, $green)
        Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
        Wait-Idle 120; Start-Sleep -Seconds 3
        # rebuild the floor (the reopened scene starts from the document)
        $rf = Op 'entity.add.cube' @{}
        $floor2 = $rf.result.entities | Select-Object -Last 1
        Op 'component.set' @{ entity = $floor2; type_path = $TKEY; field = 'scale'; value = '[12.0, 1.0, 12.0]' } | Out-Null
        Op 'component.set' @{ entity = $floor2; type_path = $TKEY; field = 'translation'; value = '[0.0, -0.5, 0.0]' } | Out-Null
        Op 'physics.enable' @{ entity = $floor2 } | Out-Null
        Wait-Idle 90; Start-Sleep -Seconds 1
        $E_LAYER2 = Find-Ent (Snap) -2.0 3.0 1.0
        if ($E_LAYER2) {
            Op 'selection.select' @{ entity = $E_LAYER2 } | Out-Null
            Op 'physics.activate' @{} | Out-Null
            Wait-Idle 90; Start-Sleep -Seconds 1
            $hit2 = $false
            foreach ($cand in @(@(760, 540), @(960, 540))) {
                Drag-At $cand[0] $cand[1] 70
                Start-Sleep -Seconds 3
                $yNow = Y-Of (Snap) $E_LAYER2
                Write-Host ("GRID7_GREEN_DRAG at({0},{1}): y={2}" -f $cand[0], $cand[1], $yNow)
                if ($null -ne $yNow -and [Math]::Abs([double]$yNow - 3.0) -gt 0.8) { $hit2 = $true; break }
            }
            if ($hit2) {
                Start-Sleep -Seconds 3
                $yG1 = Y-Of (Snap) $E_LAYER2
                Start-Sleep -Seconds 2
                $yG2 = Y-Of (Snap) $E_LAYER2
                Write-Host ("GRID7_GREEN_Y: y1={0} y2={1}" -f $yG1, $yG2)
                if ($null -ne $yG2 -and [Math]::Abs([double]$yG2 - [double]$yG1) -lt 0.05 -and $yG2 -gt -0.2 -and $yG2 -lt 1.2) {
                    Write-Host 'GRID7_GREEN_PASS (rests on the re-layered floor)'
                } else { Write-Host 'GRID7_GREEN_FAIL' }
                Op 'physics.commit' @{} | Out-Null
                Wait-Idle 90; Start-Sleep -Seconds 1
            } else { Write-Host 'GRID7_GREEN_FAIL (no drag)' }
        }
    } else { Write-Host 'GRID7_GREEN_SKIP (mask text not found in document)' }
}
Write-Host 'T10T3_EDITOR5_DONE (editor alive)'
