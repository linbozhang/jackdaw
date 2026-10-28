# T11-T1 live reruns (direct run, game-side BRP on 15702).
# Each leg boots a FRESH game process (boot is a few seconds; fresh
# state beats cross-leg choreography):
#   - L1 baseline   : player settled on the stage, rig child active
#                     (ActiveCameraRig + Projection on it — the snapshot
#                     skip-list hides Camera3d/CameraLook camera
#                     internals; the guards carry the mechanism legs),
#                     three pickups present.
#   - L2 T09 Move re-pin + wall stop: hold W from the spawn (inside the
#                     north wall's span): walks ~4 m/s north and stops at
#                     wall face + radius + skin (~-2.44).
#   - L5 slide      : W+D into the wall diagonally: +x keeps moving,
#                     z stays clamped.
#   - L4 T10 pickup chain rerun: hold D along the lane (z ~ 0), hop the
#                     settled cube mid-lane (tap Space), return west for
#                     the last pickup; PickupCount 0->3 + "Level clear!".
#   - L3 T09 Jump re-pin: tap Space from the spawn: apex ~1.89
#                     (rest 0.86 + v^2/2g 1.03), lands stable.
#   - L6 follow     : the rig's world placement (player transform
#                     composed with the rig's local) keeps a constant
#                     offset from the player across two positions.
# Boot is detached: cmd start /B only. NEVER set WGPU_BACKEND=dx12 here
# (the driver's DX12 device creation currently OOMs 0x8007000E; if the
# game dies with that, it is the known driver state, not this code).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t1-live.ps1
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$GamePort = 15702
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$OutDir = Join-Path $Repo 'loop\t11t1-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Exe = Join-Path $Project 'target\debug\t11t1-game.exe'
if (-not (Test-Path $Exe)) { Write-Host "EXE_MISSING: $Exe"; exit 1 }

# --- helpers ----------------------------------------------------------------
function Brp([string]$method, $params, [int]$retries = 3) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$GamePort/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 10)
        } catch { Start-Sleep -Milliseconds (300 * ($i + 1)) }
    }
    return $null
}
$TKEY = 'bevy_transform::components::transform::Transform'
function Get-T($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) {
        return $e.components.PSObject.Properties[$TKEY].Value
    }
    return $e.components[$TKEY]
}
function Snap { (Brp 'jackdaw/scene_snapshot' @{}).result }
function Has-Comp([object]$e, [string]$suffix) {
    $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
    foreach ($prop in $props) { if ("$($prop.Name)" -like "*$suffix") { return $true } }
    return $false
}
function Find-Player([object]$snap) {
    foreach ($e in @($snap)) { if (Has-Comp $e 'PickupCount') { return $e } }
    return $null
}
function Find-Rig([object]$snap) {
    foreach ($e in @($snap)) { if (Has-Comp $e 'ActiveCameraRig') { return $e } }
    return $null
}
function Pickup-Count([object]$snap) {
    $p = Find-Player $snap
    if (-not $p) { return -1 }
    $props = if ($p.components -is [System.Management.Automation.PSObject]) { $p.components.PSObject.Properties } else { $p.components }
    foreach ($prop in $props) {
        if ("$($prop.Name)" -like '*PickupCount') {
            $j = $prop.Value | ConvertTo-Json -Compress
            if ("$j" -match '(\d+)') { return [int]$Matches[1] }
        }
    }
    return -1
}
function Coord([object]$snap, [int]$axis) {
    $p = Find-Player $snap
    if (-not $p) { return $null }
    return [double](Get-T $p).translation[$axis]
}
function Px([object]$snap) { Coord $snap 0 }
function Py([object]$snap) { Coord $snap 1 }
function Pz([object]$snap) { Coord $snap 2 }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class JdPost {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wParam, IntPtr lParam);
}
"@
$WM_ACTIVATE = 0x0006; $WM_SETFOCUS = 0x0007
$WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101
$VK_W = 0x57; $VK_A = 0x41; $VK_S = 0x53; $VK_D = 0x44; $VK_SPACE = 0x20
$script:hwnd = [IntPtr]::Zero
function Down([byte]$vk) { [void][JdPost]::PostMessage($script:hwnd, $WM_KEYDOWN, [IntPtr]$vk, [IntPtr]0) }
function Up([byte]$vk) { [void][JdPost]::PostMessage($script:hwnd, $WM_KEYUP, [IntPtr]$vk, [IntPtr]0) }
function Tap([byte]$vk) { Down $vk; Start-Sleep -Milliseconds 60; Up $vk }

function Stop-Game {
    Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Milliseconds 700
}
function Boot-Game {
    Stop-Game
    $deps = Join-Path $Project 'target\debug\deps'
    $env:PATH = "$deps;$env:PATH"
    $script:gameLog = Join-Path $OutDir 't11t1-game-stdout.log'
    cmd /c "start /B /D `"$Project`" cmd /c `"`"$Exe`" > `"$script:gameLog`" 2>`&1`""
    $ready = $false
    for ($i = 0; $i -lt 80; $i++) {
        Start-Sleep -Milliseconds 250
        if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
        if (-not (Get-Process t11t1-game -ErrorAction SilentlyContinue)) {
            $log = ''
            if (Test-Path $script:gameLog) { $log = [IO.File]::ReadAllText($script:gameLog) }
            if ($log -match '0x8007000E|Queue creation failed') {
                Write-Host 'GAME_BOOT_FAIL: known DX12 driver OOM (0x8007000E), not a code defect'
            } else {
                Write-Host "GAME_BOOT_FAIL; log tail: $($log.Substring([Math]::Max(0, $log.Length - 800)))"
            }
            exit 1
        }
    }
    if (-not $ready) { Write-Host 'GAME_BOOT_FAIL (timeout)'; exit 1 }
    Start-Sleep -Seconds 3
    $game = Get-Process t11t1-game -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $game) { Write-Host 'GAME_GONE_EARLY'; exit 1 }
    $script:hwnd = $game.MainWindowHandle
    [void][JdPost]::PostMessage($hwnd, $WM_ACTIVATE, [IntPtr]1, [IntPtr]0)
    [void][JdPost]::PostMessage($hwnd, $WM_SETFOCUS, [IntPtr]0, [IntPtr]0)
    Start-Sleep -Milliseconds 600
}

# --- L1 baseline --------------------------------------------------------------
$results = @{}
Boot-Game
$snap = Snap
$player0 = Find-Player $snap
$rig0 = Find-Rig $snap
$px0 = Px $snap; $py0 = Py $snap; $pz0 = Pz $snap
$count0 = Pickup-Count $snap
$pickups = 0
foreach ($e in @($snap)) {
    $t = Get-T $e
    if ($t) {
        $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]; $ez = [double]$t.translation[2]
        if ([Math]::Abs($ey - 0.5) -lt 0.1 -and [Math]::Abs($ez) -lt 0.1 -and [Math]::Abs($ex) -le 1.01) { $pickups++ }
    }
}
$rigCam = $false
if ($rig0) { $rigCam = (Has-Comp $rig0 'CameraRig') -and (Has-Comp $rig0 'Projection') }
Write-Host ("L1_BASE: player=({0:F3},{1:F3},{2:F3}) count={3} pickups={4} rigActive={5} rigCamera={6}" -f `
        $px0, $py0, $pz0, $count0, $pickups, ($null -ne $rig0), $rigCam)
$results['L1'] = ($null -ne $player0) -and ($null -ne $rig0) -and $rigCam -and ($count0 -eq 0) -and ($pickups -eq 3) `
    -and ([Math]::Abs($px0 + 2.0) -lt 0.3) -and ($py0 -gt 0.7) -and ($py0 -lt 1.0)
Write-Host ("L1_{0}" -f $(if ($results['L1']) { 'PASS' } else { 'FAIL' }))

# --- L2 + L5: wall stop, then slide (same boot; the spawn is inside the span) --
Down $VK_W
$zSeries = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt 24; $i++) {
    Start-Sleep -Milliseconds 120
    $zSeries.Add(('{0:F3}' -f (Pz (Snap))))
    if ($i -gt 6) {
        $last = [double]$zSeries[$zSeries.Count - 1]
        $prev = [double]$zSeries[$zSeries.Count - 2]
        if ([Math]::Abs($last - $prev) -lt 0.005 -and $last -lt -2.3) { break }
    }
}
$zWall = Pz (Snap)
Write-Host ("L2_Z_SERIES: {0}" -f ($zSeries -join ' '))
Write-Host ("L2_WALL_STOP: z={0:F3} (wall face -2.80 + radius 0.35 + skin -> ~-2.44)" -f $zWall)
$results['L2'] = ($zWall -gt -2.56) -and ($zWall -lt -2.34)
$xSlide0 = Px (Snap)
Down $VK_D
for ($i = 0; $i -lt 16; $i++) {
    Start-Sleep -Milliseconds 120
    $null = Pz (Snap)
}
Up $VK_W; Up $VK_D
Start-Sleep -Milliseconds 400
$s = Snap
$zEnd = Pz $s
$xSlide1 = Px $s
Write-Host ("L5_SLIDE: xAlongWall={0:F2} m, zEnd={1:F3} (z clamped at the wall while x runs)" -f ($xSlide1 - $xSlide0), $zEnd)
$results['L5'] = (($xSlide1 - $xSlide0) -gt 2.0) -and ($zEnd -gt -2.60) -and ($zEnd -lt -2.30)
Write-Host ("L2_{0}" -f $(if ($results['L2']) { 'PASS' } else { 'FAIL' }))
Write-Host ("L5_{0}" -f $(if ($results['L5']) { 'PASS' } else { 'FAIL' }))
Stop-Game

# --- L4: the pickup chain from a fresh spawn ----------------------------------
Boot-Game
$seq = New-Object System.Collections.Generic.List[string]
$hopped = $false
Down $VK_D
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Milliseconds 60
    $s = Snap
    $x = Px $s
    $seq.Add(('{0:F2}/{1:F2}/c{2}' -f $x, (Py $s), (Pickup-Count $s)))
    if (-not $hopped -and $x -gt -0.6) { Tap $VK_SPACE; $hopped = $true }
    if ($x -gt 3.4) { break }
    if ((Pickup-Count $s) -ge 3) { break }
}
Up $VK_D
Start-Sleep -Milliseconds 200
Down $VK_A
for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 60
    $s = Snap
    $x = Px $s
    $seq.Add(('{0:F2}/{1:F2}/c{2}' -f $x, (Py $s), (Pickup-Count $s)))
    if ((Pickup-Count $s) -ge 3) { break }
    if ($x -lt 0.45) { break }   # stop before the cube
}
Up $VK_A
Start-Sleep -Milliseconds 400
$s = Snap
$count4 = Pickup-Count $s
$left = 0
foreach ($e in @($s)) {
    $t = Get-T $e
    if ($t) {
        $ey = [double]$t.translation[1]; $ez = [double]$t.translation[2]; $ex = [double]$t.translation[0]
        if ([Math]::Abs($ey - 0.5) -lt 0.1 -and [Math]::Abs($ez) -lt 0.1 -and [Math]::Abs($ex) -le 1.01) { $left++ }
    }
}
Write-Host ("L4_SEQ: {0} ... {1}" -f (($seq | Select-Object -First 6) -join ' '), (($seq | Select-Object -Last 6) -join ' '))
Write-Host ("L4_FINAL: count={0} pickupsLeft={1} player=({2:F2},{3:F2},{4:F2})" -f $count4, $left, (Px $s), (Py $s), (Pz $s))
$results['L4'] = ($count4 -ge 3) -and ($left -eq 0)
Write-Host ("L4_{0}" -f $(if ($results['L4']) { 'PASS' } else { 'FAIL' }))
Stop-Game
Start-Sleep -Seconds 1
$logText = ''
if (Test-Path $script:gameLog) { $logText = [IO.File]::ReadAllText($script:gameLog) }
$clearLog = $logText -match 'Level clear'
Write-Host ("CLEAR_LOG: {0}" -f $clearLog)
$results['L4'] = $results['L4'] -and $clearLog

# --- L3: jump re-pin from a fresh spawn ---------------------------------------
Boot-Game
$yBase = Py (Snap)
Tap $VK_SPACE
$ySamples = New-Object System.Collections.Generic.List[string]
$apex = $yBase
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 60
    $y = Py (Snap)
    $ySamples.Add(('{0:F3}' -f $y))
    if ($y -gt $apex) { $apex = $y }
}
$yFinal = [double]$ySamples[$ySamples.Count - 1]
$expected = 0.86 + 4.5 * 4.5 / (2.0 * 9.81)
Write-Host ("L3_Y_SERIES: {0}" -f ($ySamples -join ' '))
Write-Host ("L3_APEX: {0:F3} expected {1:F3} (rest 0.86 + v2/2g 1.03); final {2:F3}" -f $apex, $expected, $yFinal)
$results['L3'] = (($apex - $expected) -gt -0.25) -and (($apex - $expected) -lt 0.25) -and ([Math]::Abs($yFinal - $yBase) -lt 0.12)
Write-Host ("L3_{0}" -f $(if ($results['L3']) { 'PASS' } else { 'FAIL' }))

# --- L6: camera follow, same boot (spawn, then walk east) ----------------------
# rig world = player transform composed with the rig's local transform.
function Offset-Vec([object]$snap) {
    $p = Find-Player $snap; $r = Find-Rig $snap
    if (-not $p -or -not $r) { return $null }
    $pt = Get-T $p; $rt = Get-T $r
    $px = [double]$pt.translation[0]; $py = [double]$pt.translation[1]; $pz = [double]$pt.translation[2]
    $pr = @($pt.rotation)
    $lx = [double]$rt.translation[0]; $ly = [double]$rt.translation[1]; $lz = [double]$rt.translation[2]
    $qw = [double]$pr[3]; $qx = [double]$pr[0]; $qy = [double]$pr[1]; $qz = [double]$pr[2]
    $tx = 2.0 * ($qy * $lz - $qz * $ly)
    $ty = 2.0 * ($qz * $lx - $qx * $lz)
    $tz = 2.0 * ($qx * $ly - $qy * $lx)
    $wx = [double]($px + $lx + $qw * $tx + ($qy * $tz - $qz * $ty))
    $wy = [double]($py + $ly + $qw * $ty + ($qz * $tx - $qx * $tz))
    $wz = [double]($pz + $lz + $qw * $tz + ($qx * $ty - $qy * $tx))
    $ox = [double]($wx - $px); $oy = [double]($wy - $py); $oz = [double]($wz - $pz)
    return "$ox|$oy|$oz|$px|$py|$pz"
}
$oa = Offset-Vec (Snap)
Down $VK_D
Start-Sleep -Milliseconds 1500
Up $VK_D
Start-Sleep -Milliseconds 500
$ob = Offset-Vec (Snap)
if ($oa -and $ob) {
    $a = [double[]]($oa.Split('|'))
    $b = [double[]]($ob.Split('|'))
    $dx = [double]($a[0] - $b[0]); $dy = [double]($a[1] - $b[1]); $dz = [double]($a[2] - $b[2])
    $drift = [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz)
    Write-Host ("L6_FOLLOW: at({0:F2},{1:F2},{2:F2}) offset=({3:F2},{4:F2},{5:F2}); at({6:F2},{7:F2},{8:F2}) offset=({9:F2},{10:F2},{11:F2}); drift={12:F3}" -f `
            $a[3], $a[4], $a[5], $a[0], $a[1], $a[2], $b[3], $b[4], $b[5], $b[0], $b[1], $b[2], $drift)
    $results['L6'] = ($null -ne $drift) -and ($drift -lt 0.2)
} else {
    Write-Host 'L6_FOLLOW: rig or player missing from the snapshot'
    $results['L6'] = $false
}
Write-Host ("L6_{0}" -f $(if ($results['L6']) { 'PASS' } else { 'FAIL' }))
Stop-Game

# --- summary -------------------------------------------------------------------
[IO.File]::WriteAllText((Join-Path $OutDir 't11t1-live-summary.txt'), `
        "L1=$($results['L1']) L2=$($results['L2']) L3=$($results['L3']) L4=$($results['L4']) L5=$($results['L5']) L6=$($results['L6']) clearLog=$clearLog`n")
Write-Host ("VERDICT: L1={0} L2={1} L3={2} L4={3} L5={4} L6={5}" -f `
        $results['L1'], $results['L2'], $results['L3'], $results['L4'], $results['L5'], $results['L6'])
Write-Host 'T11T1_LIVE_DONE'
