# probe 4: pixel-analyze the two viewport shots (grid 8), then try the
# physics-tool drag at candidate window coordinates (viewport area guess).
$Port = 15703
$OutDir = 'E:\Project\rust\jackdaw\loop\t10t3-live'
Add-Type -AssemblyName System.Drawing
foreach ($name in @('t10t3-grid8-sensor-on.png', 't10t3-grid8-sensor-off.png')) {
    $p = Join-Path $OutDir $name
    if (-not (Test-Path $p)) { Write-Host "$name missing"; continue }
    $bmp = New-Object System.Drawing.Bitmap $p
    $cyan = 0; $green = 0
    for ($x = 0; $x -lt $bmp.Width; $x++) {
        for ($y = 0; $y -lt $bmp.Height; $y++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.B -gt 190 -and $c.G -gt 130 -and $c.R -lt 100 -and ($c.B - $c.R) -gt 80) { $cyan++ }
            if ($c.G -gt 170 -and $c.R -lt 100 -and $c.B -lt 170 -and ($c.G - $c.B) -gt 30) { $green++ }
        }
    }
    Write-Host ("{0}: {1}x{2} cyan={3} green={4}" -f $name, $bmp.Width, $bmp.Height, $cyan, $green)
    $bmp.Dispose()
}

function Brp([string]$method, $params) {
    $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
    if ($params) { $body.params = $params }
    Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -TimeoutSec 25 -Body ($body | ConvertTo-Json -Depth 12)
}
function Op([string]$id, $params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
function Wait-Idle([int]$TimeoutSec = 60) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp 'jackdaw/wait' @{ until = 'idle' } 1
        if ($r -and $r.result -and $r.result.idle) { return }
        Start-Sleep -Seconds 1
    }
}
$TKEY = 'bevy_transform::components::transform::Transform'
function Y-Of($snap, $entity) {
    foreach ($e in @($snap)) {
        if ("$($e.entity)" -eq "$entity") {
            $t = $e.components.PSObject.Properties[$TKEY].Value
            if ($t) { return [double]$t.translation[1] }
        }
    }
    return $null
}
$snap = (Brp 'jackdaw/scene_snapshot' @{}).result
$drop = $null
foreach ($e in @($snap)) {
    $t = $e.components.PSObject.Properties[$TKEY].Value
    if ($t) {
        $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
        if ([Math]::Abs($ex - 0.0) -lt 0.5 -and [Math]::Abs($ey - 5.0) -lt 0.6) { $drop = $e.entity }
    }
}
Write-Host ("drop cube: {0}" -f $drop)
if (-not $drop) { exit 1 }
Op 'selection.select' @{ entity = $drop } | Out-Null
Op 'view.frame_selected' @{} | Out-Null
Wait-Idle; Start-Sleep -Seconds 2
Op 'input.key' @{ key = 'KeyP'; mods = 'shift'; action = 'tap' } | Out-Null
Wait-Idle; Start-Sleep -Seconds 1
foreach ($cand in @(@(760, 540), @(960, 540), @(700, 520))) {
    $x = $cand[0]; $y = $cand[1]
    Op 'input.pointer' @{ x = $x; y = $y; action = 'move' } | Out-Null
    Start-Sleep -Milliseconds 300
    Op 'input.pointer' @{ x = $x; y = $y; action = 'press' } | Out-Null
    Start-Sleep -Milliseconds 400
    Op 'input.pointer' @{ x = $x; y = ($y + 70); action = 'move' } | Out-Null
    Start-Sleep -Milliseconds 400
    Op 'input.pointer' @{ x = $x; y = ($y + 70); action = 'release' } | Out-Null
    Wait-Idle; Start-Sleep -Seconds 3
    $yNow = Y-Of (Brp 'jackdaw/scene_snapshot' @{}).result $drop
    Write-Host ("drag at ({0},{1}): dropY={2}" -f $x, $y, $yNow)
    if ($null -ne $yNow -and [Math]::Abs([double]$yNow - 5.0) -gt 0.8) { Write-Host "DRAG_WORKS_AT $x,$y"; break }
}
