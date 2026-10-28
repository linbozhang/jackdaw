# T11-T3 acceptance matrix, direct-run leg (cells 1/2-behavior/5/6/7/9).
# PIE is dead this window (leg A: 3/3 exited 0xc0000005 before connecting,
# T10b driver state); the same binary the editor would play carries the
# behavior cells -- T10/T2 precedent channel.
#   Round 1 (t11t3-place.bsn, the operator-placed five-piece player with
#            authored move_speed 2.0 / jump_speed 6.0 / distance 5.0 /
#            sensitivity 0.008):
#     C1 settle, C2 wall stop, C3 jump apex (6.0^2/2g), C4 wall slide,
#     C5 follow at distance 5 (offset + lenDrift), C6 half-speed.
#     NOTE: no bsn text injection this time -- leg A placed PlayerVelocity
#     through the operator (the C10-fixed chain, taken literally).
#   Round 2 (template scene.bsn, the out-of-box chain, cell 1):
#     template player visible (mesh) + moves + jumps + rig follows +
#     FallingCube pushed (kinematic->dynamic, cell 6).
#   Round 3 (t11t3-fast.bsn, move_speed 8.0): W into the wall at double
#     speed -- no penetration (cell 6).
#   Round 4 (t11t3-fp.bsn, FirstPerson): rig local offset collapses to
#     the eye-height form (cell 7's mode leg).
# Boot is detached: cmd start /B only. No WGPU_BACKEND.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t3-matrix-c.ps1
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$GamePort = 15702
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$OutDir = Join-Path $Repo 'loop\t11t3-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Exe = Join-Path $Project 'target\debug\t11t1-game.exe'
if (-not (Test-Path $Exe)) { Write-Host 'EXE_MISSING'; exit 1 }
$GameAssets = Join-Path $Project 'target\debug\assets'
New-Item -ItemType Directory -Force -Path $GameAssets | Out-Null
$Scene = Join-Path $GameAssets 'scene.bsn'

function GameBrp([string]$method, $params, [int]$retries = 3) {
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
function Props($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) { return $e.components.PSObject.Properties }
    return $e.components
}
function Get-T($e) {
    foreach ($prop in (Props $e)) { if ("$($prop.Name)" -eq $TKEY) { return $prop.Value } }
    return $null
}
function Has-Comp([object]$e, [string]$suffix) {
    if (-not $e) { return $false }
    foreach ($prop in (Props $e)) { if ("$($prop.Name)" -like "*$suffix") { return $true } }
    return $false
}
function Snap { (GameBrp 'jackdaw/scene_snapshot' @{} 2).result }
function Num($v) {
    $s = "$v"
    $x = 0.0
    if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$x)) { return $x }
    return $null
}
function Find-Player([object]$snap, [bool]$placed) {
    $wantX = -2.0; $wantZ = 0.0
    if ($placed) { $wantX = 2.0; $wantZ = 2.0 }
    $best = $null; $bestD = 1e9
    foreach ($e in @($snap)) {
        if (-not (Has-Comp $e 'PlayerMarker')) { continue }
        $hasPickup = Has-Comp $e 'PickupCount'
        if ($placed -eq $hasPickup) { continue }
        $t = Get-T $e
        if (-not $t) { continue }
        $d = [Math]::Abs((Num $t.translation[0]) - $wantX) + [Math]::Abs((Num $t.translation[2]) - $wantZ)
        if ($d -lt $bestD) { $bestD = $d; $best = $e }
    }
    if ($bestD -lt 14.0) { return $best }
    return $null
}
function Find-Rig-For([object]$snap, [object]$player) {
    if (-not $player) { return $null }
    $pt = Get-T $player
    if (-not $pt) { return $null }
    $px = Num $pt.translation[0]; $pz = Num $pt.translation[2]
    $best = $null; $bestD = 1e9
    foreach ($e in @($snap)) {
        if (-not (Has-Comp $e 'CameraRig')) { continue }
        $t = Get-T $e
        if (-not $t) { continue }
        $d = [Math]::Abs((Num $t.translation[0]) - $px) + [Math]::Abs((Num $t.translation[2]) - $pz)
        if ($d -lt $bestD) { $bestD = $d; $best = $e }
    }
    if ($bestD -lt 22.0) { return $best }
    return $null
}
function Rig-Local([object]$snap, [bool]$placed) {
    $p = Find-Player $snap $placed
    $r = Find-Rig-For $snap $p
    if (-not $r) { return $null }
    $t = Get-T $r
    if (-not $t) { return $null }
    return @((Num $t.translation[0]), (Num $t.translation[1]), (Num $t.translation[2]))
}
$results = @{}
$ProgressLog = Join-Path $OutDir 't11t3-c-progress.log'
[IO.File]::WriteAllText($ProgressLog, '')
function Leg([string]$name, [bool]$ok) {
    $results[$name] = $ok
    $line = ("{0}_{1}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }))
    Write-Host $line
    [IO.File]::AppendAllText($ProgressLog, "$line`r`n")
}
function Log([string]$line) {
    Write-Host $line
    [IO.File]::AppendAllText($ProgressLog, "$line`r`n")
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class JdPost {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
$SW_RESTORE = 9
$WM_ACTIVATE = 0x0006; $WM_SETFOCUS = 0x0007
$WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101
$VK_W = 0x57; $VK_A = 0x41; $VK_D = 0x44; $VK_S = 0x53; $VK_SPACE = 0x20
$script:hwnd = [IntPtr]::Zero
function Down([byte]$vk) { [void][JdPost]::PostMessage($script:hwnd, $WM_KEYDOWN, [IntPtr]$vk, [IntPtr]0) }
function Up([byte]$vk) { [void][JdPost]::PostMessage($script:hwnd, $WM_KEYUP, [IntPtr]$vk, [IntPtr]0) }
function Tap([byte]$vk) { Down $vk; Start-Sleep -Milliseconds 60; Up $vk }

function Stop-Game {
    Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Milliseconds 2500
}
function Boot-Game([string]$srcScene) {
    Stop-Game
    if ($srcScene -and (Test-Path $srcScene)) { Copy-Item $srcScene $Scene -Force }
    $deps = Join-Path $Project 'target\debug\deps'
    $env:PATH = "$deps;$env:PATH"
    # .NET Process API instead of `cmd start /B`: in this shell chain the
    # start /B form leaves the game running but unreachable through BRP
    # (found live; the same exe started via Process API answers in ~12s).
    # Boot minimized (a Normal window dies within seconds in this desktop
    # state -- winit "No windows are open, exiting", no WER; found live),
    # then RESTORE the window right before injecting keys: restored, it
    # takes focus and winit dispatches the posted keyboard messages.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.WorkingDirectory = $Project
    $psi.UseShellExecute = $true
    $psi.WindowStyle = 'Minimized'
    $null = [System.Diagnostics.Process]::Start($psi)
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Milliseconds 250
        $r = GameBrp 'jackdaw/scene_snapshot' @{} 1
        if ($r) { break }
        if (-not (Get-Process t11t1-game -ErrorAction SilentlyContinue)) {
            Log 'GAME_BOOT_FAIL'; return $false
        }
    }
    Start-Sleep -Seconds 3
    $game = Get-Process t11t1-game -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $game) { Log 'GAME_GONE_EARLY'; return $false }
    $script:hwnd = $game.MainWindowHandle
    # No restore, no focus chase: posted keyboard messages reach a
    # minimized winit window fine (repro t11t3-repro-focus.ps1: z moved
    # with foreground elsewhere), while SW_RESTORE in this desktop state
    # destabilizes the window and kills input instead.
    Start-Sleep -Milliseconds 600
    return $true
}

# =================== Round 1: the placed scene, authored tuning ===================
if (-not (Boot-Game "$Project\assets\t11t3-place.bsn")) { exit 1 }
Start-Sleep -Seconds 2
$s = Snap
$pl = Find-Player $s $true
$tpl = Find-Player $s $false
$plRig = Find-Rig-For $s $pl
$plMat = $false; $plAct = $false
if ($plRig) { $plMat = Has-Comp $plRig 'Projection'; $plAct = Has-Comp $plRig 'ActiveCameraRig' }
$pyBase = Num ((Get-T $pl).translation[1])
Log ("R1C1 placed y={0:F3} tplPlayer={1} placedRig materialized={2} active={3}" -f $pyBase, ($null -ne $tpl), $plMat, $plAct)
Leg 'R1_C1_SETTLE' (($null -ne $pl) -and ($null -ne $tpl) -and $plMat -and $plAct -and ($pyBase -gt 0.7) -and ($pyBase -lt 1.05))

# walk to the wall
Start-Sleep -Seconds 1
Down $VK_W
$zEnd = 0.0; $n = 0
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 120
    $e = Find-Player (Snap) $true
    if ($e) { $zEnd = Num ((Get-T $e).translation[2]); $n++ }
    if ($i -gt 10) {
        $e2 = Find-Player (Snap) $true
        $zPrev = Num ((Get-T (Find-Player (Snap) $true)).translation[2])
        if ([Math]::Abs($zEnd - $zPrev) -lt 0.005 -and $zEnd -lt -2.2) { break }
    }
}
Up $VK_W
Log ("R1C2 walk zEnd={0:F3} (samples {1})" -f $zEnd, $n)
Leg 'R1_C2_WALLSTOP' (($n -ge 4) -and ($zEnd -gt -2.60) -and ($zEnd -lt -2.0))

# follow at the authored distance 5 across a turn
$oa = Rig-Local (Snap) $true
Down $VK_D
Start-Sleep -Milliseconds 1500
Up $VK_D
Start-Sleep -Milliseconds 400
$ob = Rig-Local (Snap) $true
$drift = 9.9
if ($oa -and $ob -and ($null -notin $oa) -and ($null -notin $ob)) {
    $na = [Math]::Sqrt($oa[0] * $oa[0] + $oa[1] * $oa[1] + $oa[2] * $oa[2])
    $nb = [Math]::Sqrt($ob[0] * $ob[0] + $ob[1] * $ob[1] + $ob[2] * $ob[2])
    $drift = [Math]::Abs($na - $nb)
    Log ("R1C5 local=({0:F2},{1:F2},{2:F2}) |.|={3:F3} -> ({4:F2},{5:F2},{6:F2}) |.|={7:F3} drift={8:F3} (distance-5 expectation (0,3.15,4.61), |.|~5.578)" -f $oa[0], $oa[1], $oa[2], $na, $ob[0], $ob[1], $ob[2], $nb, $drift)
}
Leg 'R1_C5_FOLLOW' (($drift -lt 0.15) -and ($null -ne $oa) -and ([Math]::Abs($oa[1] - 3.147) -lt 0.3) -and ([Math]::Abs($oa[2] - 4.605) -lt 0.4))

# jump at the authored jump_speed 6.0: apex = rest + 36/19.62
$e = Find-Player (Snap) $true
$yBase = Num ((Get-T $e).translation[1])
Tap $VK_SPACE
$apex = $yBase
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 60
    $e2 = Find-Player (Snap) $true
    if ($e2) {
        $y = Num ((Get-T $e2).translation[1])
        if ($y -gt $apex) { $apex = $y }
    }
}
$expected = 0.86 + 6.0 * 6.0 / (2.0 * 9.81)
Log ("R1C3 jump apex={0:F3} expected~{1:F3} (jump_speed 6.0 authored)" -f $apex, $expected)
Leg 'R1_C3_JUMP' (([Math]::Abs($apex - $expected)) -lt 0.35)

# slide: back west, then W+D along the wall
Down $VK_A
Start-Sleep -Milliseconds 1300
Up $VK_A
Start-Sleep -Milliseconds 300
$x0 = Num ((Get-T (Find-Player (Snap) $true)).translation[0])
Down $VK_W; Down $VK_D
for ($i = 0; $i -lt 8; $i++) { Start-Sleep -Milliseconds 120; $null = Snap }
Up $VK_W; Up $VK_D
Start-Sleep -Milliseconds 300
$t3 = Get-T (Find-Player (Snap) $true)
$x1 = Num $t3.translation[0]
$zSlide = Num $t3.translation[2]
Log ("R1C4 slide x {0:F2} -> {1:F2}, z={2:F3}" -f $x0, $x1, $zSlide)
Leg 'R1_C4_SLIDE' ((($x1 - $x0) -gt 0.8) -and ($zSlide -gt -2.70) -and ($zSlide -lt -2.15))

# half-speed: placed 2.0 vs template 4.0 in one window
Down $VK_A
Start-Sleep -Milliseconds 1600
Up $VK_A
Start-Sleep -Milliseconds 400
$a = Snap
$plA = Find-Player $a $true; $tpA = Find-Player $a $false
$t0 = Get-Date
Down $VK_D
Start-Sleep -Milliseconds 1400
Up $VK_D
Start-Sleep -Milliseconds 250
$b = Snap
$plB = Find-Player $b $true; $tpB = Find-Player $b $false
$dt = ((Get-Date) - $t0).TotalSeconds
$vPl = $null; $vTp = $null
if ($plA -and $plB) {
    $ta = Get-T $plA; $tb = Get-T $plB
    $dx = (Num $ta.translation[0]) - (Num $tb.translation[0]); $dz = (Num $ta.translation[2]) - (Num $tb.translation[2])
    $vPl = [Math]::Sqrt($dx * $dx + $dz * $dz) / $dt
}
if ($tpA -and $tpB) {
    $ta = Get-T $tpA; $tb = Get-T $tpB
    $dx = (Num $ta.translation[0]) - (Num $tb.translation[0]); $dz = (Num $ta.translation[2]) - (Num $tb.translation[2])
    $vTp = [Math]::Sqrt($dx * $dx + $dz * $dz) / $dt
}
Log ("R1C6 placed={0} m/s (authored 2.0) template={1} m/s (4.0)" -f ('{0:F2}' -f $vPl), ('{0:F2}' -f $vTp))
Leg 'R1_C6_HALFSPEED' (($null -ne $vPl) -and ($null -ne $vTp) -and ($vPl -gt 1.2) -and ($vPl -lt 2.8) -and ($vTp -gt 2.8))
Stop-Game

# =================== Round 2: the template scene, out-of-box chain (cell 1) =======
if (-not (Boot-Game "$Project\assets\scene.bsn")) { exit 1 }
Start-Sleep -Seconds 3
$s2 = Snap
$tpl2 = Find-Player $s2 $false
$visible = $false
if ($tpl2) { $visible = Has-Comp $tpl2 'Mesh3d' }
$z0 = 0.0
if ($tpl2) { $z0 = Num ((Get-T $tpl2).translation[2]) }
# walk
Down $VK_W
Start-Sleep -Milliseconds 900
Up $VK_W
Start-Sleep -Milliseconds 300
$z1 = Num ((Get-T (Find-Player (Snap) $false)).translation[2])
# jump
$y0 = Num ((Get-T (Find-Player (Snap) $false)).translation[1])
Tap $VK_SPACE
$apex2 = $y0
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 60
    $e = Find-Player (Snap) $false
    if ($e) { $y = Num ((Get-T $e).translation[1]); if ($y -gt $apex2) { $apex2 = $y } }
}
# follow: template rig local offset length across a side-step
$fa = Rig-Local (Snap) $false
Down $VK_D
Start-Sleep -Milliseconds 700
Up $VK_D
Start-Sleep -Milliseconds 300
$fb = Rig-Local (Snap) $false
$fDrift = 9.9
if ($fa -and $fb -and ($null -notin $fa) -and ($null -notin $fb)) {
    $na = [Math]::Sqrt($fa[0] * $fa[0] + $fa[1] * $fa[1] + $fa[2] * $fa[2])
    $nb = [Math]::Sqrt($fb[0] * $fb[0] + $fb[1] * $fb[1] + $fb[2] * $fb[2])
    $fDrift = [Math]::Abs($na - $nb)
}
# FallingCube push (cell 6 kinematic->dynamic): the cube settles near
# (0, ., 0); walk the template player east into it and the cube moves.
$cubeBefore = $null
foreach ($e in @($s2)) {
    if ((Has-Comp $e 'FallingCube') -and (Get-T $e)) { $cubeBefore = Get-T $e; break }
}
$pushed = $false; $cubeDx = 0.0
if ($cubeBefore) {
    $cx0 = Num $cubeBefore.translation[0]
    Down $VK_D
    Start-Sleep -Milliseconds 2600
    Up $VK_D
    Start-Sleep -Milliseconds 400
    foreach ($e in @((Snap))) {
        if ((Has-Comp $e 'FallingCube') -and (Get-T $e)) {
            $cubeDx = [Math]::Abs((Num (Get-T $e).translation[0]) - $cx0)
            if ($cubeDx -gt 0.3) { $pushed = $true }
            break
        }
    }
}
Log ("R2 tpl visible={0} walk dz={1:F2} jumpApex={2:F3} followDrift={3:F3} cubePushed={4} (dx={5:F2})" -f $visible, ($z0 - $z1), $apex2, $fDrift, $pushed, $cubeDx)
Leg 'R2_CELL1_OUTOFBOX' ($visible -and (($z0 - $z1) -gt 0.8) -and (($apex2 - $y0) -gt 0.6) -and ($fDrift -lt 0.2))
Leg 'R2_CELL6_PUSHCUBE' $pushed
Stop-Game

# =================== Round 3: high speed into the wall (cell 6) ===================
if (-not (Boot-Game "$Project\assets\t11t3-fast.bsn")) { exit 1 }
Start-Sleep -Seconds 3
Down $VK_W
Start-Sleep -Milliseconds 2500
Up $VK_W
Start-Sleep -Milliseconds 300
$e = Find-Player (Snap) $true
$zFast = 99.0
if ($e) { $zFast = Num ((Get-T $e).translation[2]) }
Log ("R3 high-speed wall stop z={0:F3} (no-penetration bound: >= -2.45)" -f $zFast)
Leg 'R3_CELL6_NO Penetration' (($zFast -gt -2.50) -and ($zFast -lt -2.0))
Stop-Game

# =================== Round 4: FirstPerson mode (cell 7 mode leg) ==================
if (-not (Boot-Game "$Project\assets\t11t3-fp.bsn")) { exit 1 }
Start-Sleep -Seconds 3
$fp = Rig-Local (Snap) $true
$fpLen = -1.0
if ($fp -and ($null -notin $fp)) {
    $fpLen = [Math]::Sqrt($fp[0] * $fp[0] + $fp[1] * $fp[1] + $fp[2] * $fp[2])
}
Log ("R4 FP rig local=({0:F2},{1:F2},{2:F2}) |.|={3:F3} (eye-height form; measured 1.60 this window, TP form is 5.578)" -f $fp[0], $fp[1], $fp[2], $fpLen)
Leg 'R4_CELL7_FIRSTPERSON' (($fpLen -gt 0.9) -and ($fpLen -lt 1.75))
Stop-Game

Remove-Item $Scene -Force -ErrorAction SilentlyContinue
$summary = ($results.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
[IO.File]::WriteAllText((Join-Path $OutDir 't11t3-c-summary.txt'), "$summary`r`n")
Log ("VERDICT_C: {0}" -f $summary)
Write-Host 'T11T3_C_DONE'
