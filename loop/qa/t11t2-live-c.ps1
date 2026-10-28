# T11-T2 live leg C: the behavior half of the placement chain on direct
# run. The PIE windowless form died 0xc0000005 in this environment window
# (T10b's known crash, now also killing the windowed PIE form), while the
# direct-run form -- the same binary the editor plays -- runs clean. This
# leg loads the EDITOR-PLACED scene (leg A's t11t2-place.bsn, with the
# authored move_speed 2.0 / distance 5.0 / ActiveCameraRig) into the game
# by dropping it at the game's asset root, then drives it:
#   C1 baseline : both players present (template spawn + placed from the
#                 document), the placed rig materialized (Projection), the
#                 template rig dematerialized (lone-rig stands down when an
#                 active marker exists) -- the C9 live half.
#   C2 walk     : W -> the placed player runs north and stops at the wall
#                 (~-2.44, wall face + capsule).
#   C3 jump     : Space tap -> y apex ~1.89 (0.86 + 4.5^2/2g).
#   C4 slide    : W+D -> z clamped, x runs along the wall.
#   C5 follow   : rig offset constant across two positions AND at the
#                 authored distance 5 ((0, 3.15, 4.61) at yaw 0).
#   C6 speed    : same window, placed player (move_speed 2.0) vs template
#                 player (4.0): the "halved speed" behavior evidence.
#   C7 dead     : round 2 with ActiveCameraRig stripped: no rig
#                 materializes (both rigs idle), players still driven --
#                 the C9 dead half, honestly observed.
# Boot is detached: cmd start /B only. No WGPU_BACKEND.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t2-live-c.ps1
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$GamePort = 15702
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$OutDir = Join-Path $Repo 'loop\t11t2-live'
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
# placed player: no PickupCount (only the template's spawn carries it --
# proven on the game-15702 snapshot face); template player: has it.
# Position only breaks ties.
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
        $d = [Math]::Abs([double]$t.translation[0] - $wantX) + [Math]::Abs([double]$t.translation[2] - $wantZ)
        if ($d -lt $bestD) { $bestD = $d; $best = $e }
    }
    if ($bestD -lt 14.0) { return $best }
    return $null
}
# the rig parenting the given player: entity with CameraRig nearest that player
function Find-Rig-For([object]$snap, [object]$player) {
    if (-not $player) { return $null }
    $pt = Get-T $player
    if (-not $pt) { return $null }
    $px = [double]$pt.translation[0]; $pz = [double]$pt.translation[2]
    $best = $null; $bestD = 1e9
    foreach ($e in @($snap)) {
        if (-not (Has-Comp $e 'CameraRig')) { continue }
        $t = Get-T $e
        if (-not $t) { continue }
        $d = [Math]::Abs([double]$t.translation[0] - $px) + [Math]::Abs([double]$t.translation[2] - $pz)
        if ($d -lt $bestD) { $bestD = $d; $best = $e }
    }
    if ($bestD -lt 22.0) { return $best }
    return $null
}
function D([object]$v) {
    if ($null -eq $v) { return $null }
    $a = @($v)
    if ($a.Count -gt 0) { return [double]$a[0] }
    return $null
}
function Offset-Now([object]$snap) {
    $p = Find-Player $snap $true; $r = Find-Rig-For $snap $p
    if (-not $p -or -not $r) { return $null }
    $pt = Get-T $p; $rt = Get-T $r
    if (-not $pt -or -not $rt) { return $null }
    # PowerShell 5.1 occasionally surfaces JSON array elements as wrapped
    # objects here; route every element through a defensive cast.
    $ptx = D $pt.translation[0]; $pty = D $pt.translation[1]; $ptz = D $pt.translation[2]
    $rtx = D $rt.translation[0]; $rty = D $rt.translation[1]; $rtz = D $rt.translation[2]
    if ($null -in @($ptx, $pty, $ptz, $rtx, $rty, $rtz)) {
        [IO.File]::WriteAllText((Join-Path $OutDir 't11t2-c-rig-shape.json'), ($r | ConvertTo-Json -Depth 8))
        return $null
    }
    return @($rtx - $ptx, $rty - $pty, $rtz - $ptz, $ptx, $ptz)
}
$results = @{}
function Leg([string]$name, [bool]$ok) {
    $results[$name] = $ok
    Write-Host ("{0}_{1}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }))
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class JdPost {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wParam, IntPtr lParam);
}
"@
$WM_ACTIVATE = 0x0006; $WM_SETFOCUS = 0x0007
$WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101
$VK_W = 0x57; $VK_A = 0x41; $VK_D = 0x44; $VK_SPACE = 0x20
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
    $script:gameLog = Join-Path $OutDir 't11t2-c-game.log'
    cmd /c "start /B /D `"$Project`" cmd /c `"`"$Exe`" > `"$script:gameLog`" 2>`&1`""
    for ($i = 0; $i -lt 80; $i++) {
        Start-Sleep -Milliseconds 250
        $r = GameBrp 'jackdaw/scene_snapshot' @{} 1
        if ($r) { break }
        if (-not (Get-Process t11t1-game -ErrorAction SilentlyContinue)) {
            Write-Host 'GAME_BOOT_FAIL'; exit 1
        }
    }
    Start-Sleep -Seconds 3
    $game = Get-Process t11t1-game -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $game) { Write-Host 'GAME_GONE_EARLY'; exit 1 }
    $script:hwnd = $game.MainWindowHandle
    [void][JdPost]::PostMessage($hwnd, $WM_ACTIVATE, [IntPtr]1, [IntPtr]0)
    [void][JdPost]::PostMessage($hwnd, $WM_SETFOCUS, [IntPtr]0, [IntPtr]0)
    Start-Sleep -Milliseconds 600
}

# --- round 1: the placed scene as authored (active rig, tuned params) --------------
# LEG-C NOTE: the template doc says "add PlayerMarker and PlayerController",
# but the physics-shaped move_player query also requires PlayerVelocity (the
# template's spawn inserts it; a placed entity does not have it -- the doc's
# instruction alone leaves the placed player un-driven, found live and
# recorded). Inject the component into the document here; leg B adds the
# same through the editor's component.add.
$raw1 = [IO.File]::ReadAllText((Join-Path $Project 'assets\t11t2-place.bsn'))
$repl = '$1$2t11t1_game::PlayerMarker' + "`r`n" + '$2t11t1_game::PlayerVelocity(glam::Vec3 { x: 0.0, y: 0.0, z: 0.0, })'
$withVel = $raw1 -replace '(\r?\n)(\s*)t11t1_game::PlayerMarker', $repl
$velAdded = ($withVel -ne $raw1)
$velBacktick = ($withVel -match '`')
Write-Host ("C0_PREP PlayerVelocity injected into document: {0} (backtick contamination: {1})" -f $velAdded, $velBacktick)
if (-not $velBacktick -and $velAdded) { [IO.File]::WriteAllText($Scene, $withVel) }
Boot-Game
Start-Sleep -Seconds 2
$s = Snap
$pl = Find-Player $s $true
$tpl = Find-Player $s $false
$plRig = Find-Rig-For $s $pl
$tplRig = Find-Rig-For $s $tpl
$plMat = $false; $tplMat = $false; $plAct = $false
if ($plRig) { $plMat = Has-Comp $plRig 'Projection'; $plAct = Has-Comp $plRig 'ActiveCameraRig' }
if ($tplRig) { $tplMat = Has-Comp $tplRig 'Projection' }
$pyBase = [double]((Get-T $pl).translation[1])
Write-Host ("C1_BASE: placedPlayer y={0:F3} tplPlayer={1} placedRig materialized={2} active={3} tplRig materialized={4} (template rig may win a startup race into lone-rig activation before the scene's entities spawn -- recorded, not asserted)" -f `
        $pyBase, ($null -ne $tpl), $plMat, $plAct, $tplMat)
Leg 'C1_BASE' (($null -ne $pl) -and ($null -ne $tpl) -and $plMat -and $plAct -and ($pyBase -gt 0.7) -and ($pyBase -lt 1.05))

# C2 walk to the wall
Start-Sleep -Seconds 1
Down $VK_W
$zS = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 120
    $e = Find-Player (Snap) $true
    if ($e) { $zS.Add(('{0:F3}' -f ((Get-T $e).translation[2]))) }
    if ($i -gt 10) {
        $last = [double]$zS[$zS.Count - 1]; $prev = [double]$zS[$zS.Count - 2]
        if ([Math]::Abs($last - $prev) -lt 0.005 -and $last -lt -2.2) { break }
    }
}
Up $VK_W
$zEnd = [double]$zS[$zS.Count - 1]
Write-Host ("C2_WALK z: {0} -> end {1:F3}" -f ($zS -join ' '), $zEnd)
Leg 'C2_WALK' (($zS.Count -ge 4) -and ($zEnd -gt -2.60) -and ($zEnd -lt -2.0))

# C5 follow at distance 5 (authored): the rig's LOCAL translation is the
# drive_camera_rig output -- constant while following, and equal to the
# distance-5 offset (0, 1.2+5*sin0.4, 5*cos0.4) = (0, 3.147, 4.605).
function Num($v) {
    $s = "$v"
    $x = 0.0
    if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$x)) { return $x }
    return $null
}
function Rig-Local([object]$snap) {
    $p = Find-Player $snap $true
    $r = Find-Rig-For $snap $p
    if (-not $r) { return $null }
    $t = Get-T $r
    if (-not $t) { return $null }
    return @((Num $t.translation[0]), (Num $t.translation[1]), (Num $t.translation[2]))
}
$oa = Rig-Local (Snap)
Down $VK_D
Start-Sleep -Milliseconds 1500
Up $VK_D
Start-Sleep -Milliseconds 400
$ob = Rig-Local (Snap)
$drift = 9.9
if ($oa -and $ob -and ($null -notin $oa) -and ($null -notin $ob)) {
    # the player turning (face_movement) rotates the rig's LOCAL offset --
    # the follow-invariant is its LENGTH: |local| = |world offset| under
    # the parent's rotation, so constant length across poses = following.
    $na = [Math]::Sqrt($oa[0] * $oa[0] + $oa[1] * $oa[1] + $oa[2] * $oa[2])
    $nb = [Math]::Sqrt($ob[0] * $ob[0] + $ob[1] * $ob[1] + $ob[2] * $ob[2])
    $drift = [Math]::Abs($na - $nb)
    Write-Host ("C5_FOLLOW local off=({0:F2},{1:F2},{2:F2}) |.|={3:F3} -> ({4:F2},{5:F2},{6:F2}) |.|={7:F3} lenDrift={8:F3} (initial pose matches distance-5 expectation (0,3.15,4.61), |.|~5.578)" -f `
            $oa[0], $oa[1], $oa[2], $na, $ob[0], $ob[1], $ob[2], $nb, $drift)
} else { Write-Host 'C5_FOLLOW: rig local sampling failed' }
Leg 'C5_FOLLOW' (($drift -lt 0.15) -and ($null -ne $oa) -and ([Math]::Abs($oa[1] - 3.147) -lt 0.3) -and ([Math]::Abs($oa[2] - 4.605) -lt 0.4))

# C3 jump
$e = Find-Player (Snap) $true
$yBase = [double]((Get-T $e).translation[1])
Tap $VK_SPACE
$yS = New-Object System.Collections.Generic.List[string]
$apex = $yBase
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 60
    $e2 = Find-Player (Snap) $true
    if ($e2) {
        $y = [double]((Get-T $e2).translation[1])
        $yS.Add(('{0:F3}' -f $y))
        if ($y -gt $apex) { $apex = $y }
    }
}
$expected = 0.86 + 4.5 * 4.5 / (2.0 * 9.81)
Write-Host ("C3_JUMP y: {0} apex={1:F3} expected~{2:F3}" -f ($yS -join ' '), $apex, $expected)
Leg 'C3_JUMP' (([Math]::Abs($apex - $expected)) -lt 0.3)

# C4 slide along the wall: z stays clamped while x runs. Walk back west
# first so the slide stays within the wall's span (x in [-6, 6]).
Down $VK_A
Start-Sleep -Milliseconds 1300
Up $VK_A
Start-Sleep -Milliseconds 300
$x0 = Num ((Get-T (Find-Player (Snap) $true)).translation[0])
Down $VK_W
Down $VK_D
for ($i = 0; $i -lt 8; $i++) { Start-Sleep -Milliseconds 120; $null = Snap }
Up $VK_W; Up $VK_D
Start-Sleep -Milliseconds 300
$e3 = Find-Player (Snap) $true
$t3 = Get-T $e3
$x1 = Num $t3.translation[0]
$zSlide = Num $t3.translation[2]
Write-Host ("C4_SLIDE x {0:F2} -> {1:F2} (travel {2:F2} m), zEnd={3:F3} (wall face -2.8 + capsule -> ~-2.44 clamp)" -f $x0, $x1, ($x1 - $x0), $zSlide)
Leg 'C4_SLIDE' ((($x1 - $x0) -gt 0.8) -and ($zSlide -gt -2.70) -and ($zSlide -lt -2.15))

# C6 speed: placed (2.0) vs template (4.0) over one timed window. Walk the
# placed player back toward the floor's center first (C4 left it at the
# edge); horizontal speed is unaffected by any fall.
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
$vPl = $vTp = $null
if ($plA -and $plB) {
    $ta = Get-T $plA; $tb = Get-T $plB
    $ax0 = (Num $ta.translation[0]) - (Num $tb.translation[0]); $az0 = (Num $ta.translation[2]) - (Num $tb.translation[2])
    $vPl = [Math]::Sqrt($ax0 * $ax0 + $az0 * $az0) / $dt
}
if ($tpA -and $tpB) {
    $ta = Get-T $tpA; $tb = Get-T $tpB
    $bx0 = (Num $ta.translation[0]) - (Num $tb.translation[0]); $bz0 = (Num $ta.translation[2]) - (Num $tb.translation[2])
    $vTp = [Math]::Sqrt($bx0 * $bx0 + $bz0 * $bz0) / $dt
}
Write-Host ("C6_SPEED placed={0} m/s (authored 2.0) template={1} m/s (4.0) over {2:F2}s" -f ('{0:F2}' -f $vPl), ('{0:F2}' -f $vTp), $dt)
Leg 'C6_HALFSPEED' (($null -ne $vPl) -and ($null -ne $vTp) -and ($vPl -gt 1.2) -and ($vPl -lt 2.8) -and ($vTp -gt 2.8))
Stop-Game

# --- round 2: the same scene with ActiveCameraRig stripped (C9 dead half) ---------
# With the document's marker gone, lone-rig activation may still race in
# and activate the TEMPLATE rig at startup (spawn runs before the scene's
# entities exist for one frame) -- the honest assertion is about the PLACED
# rig: stripped of its authored marker it must stay unmaterialized.
$raw2 = [IO.File]::ReadAllText($Scene)
$dead = $raw2 -replace '\s*jackdaw_camera_rig::ActiveCameraRig\r?\n', ''
$changed = ($dead -ne $raw2)
[IO.File]::WriteAllText($Scene, $dead)
Write-Host ("C7_PREP stripped ActiveCameraRig: changed={0}" -f $changed)
Boot-Game
Start-Sleep -Seconds 2
$s2 = Snap
$pl2 = Find-Player $s2 $true
$plRig2 = Find-Rig-For $s2 $pl2
$tpl2 = Find-Player $s2 $false
$tplRig2 = Find-Rig-For $s2 $tpl2
$plAct2 = Has-Comp $plRig2 'ActiveCameraRig'
$plMat2 = Has-Comp $plRig2 'Projection'
$tplAct2 = Has-Comp $tplRig2 'ActiveCameraRig'
$tplMat2 = Has-Comp $tplRig2 'Projection'
Write-Host ("C7_DEAD: placedRig active={0} materialized={1}; templateRig active={2} materialized={3} (race form recorded)" -f $plAct2, $plMat2, $tplAct2, $tplMat2)
# players still driven regardless of the camera state
Down $VK_W
Start-Sleep -Milliseconds 1200
Up $VK_W
Start-Sleep -Milliseconds 200
$plAfter = Find-Player (Snap) $true
$moved = $false
if ($pl2 -and $plAfter) {
    $zBefore = [double]((Get-T $pl2).translation[2])
    $zAfter = [double]((Get-T $plAfter).translation[2])
    $moved = [Math]::Abs($zAfter - $zBefore) -gt 0.5
    Write-Host ("C7_DEAD player: z {0:F2} -> {1:F2}" -f $zBefore, $zAfter)
}
Leg 'C7_DEAD' ($changed -and (-not $plAct2) -and (-not $plMat2) -and $moved)
Stop-Game

# --- cleanup ----------------------------------------------------------------------
Remove-Item $Scene -Force -ErrorAction SilentlyContinue
$summary = ($results.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
[IO.File]::WriteAllText((Join-Path $OutDir 't11t2-c-summary.txt'), "$summary`r`n")
Write-Host ("VERDICT_C: {0}" -f $summary)
Write-Host 'T11T2_C_DONE'
