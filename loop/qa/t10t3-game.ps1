# T10-T3 matrix, game legs (direct run, game-side BRP on 15702):
#   -Gravity -9.81 -Drive : grid 3 (settle sampling), grid 5 (the player
#       alone collects; a settling cube must NOT), grid 6 (three pickups
#       => "Level clear!" in the game log), plus the baseline fall-time
#       samples for grid 4.
#   -Gravity -19.62       : grid 4 doubled-gravity leg (fall time shrinks
#       ~1/sqrt(2); settle y unchanged).
# The config file is rewritten per run (pure ASCII, byte-safe .NET IO).
# Boot is detached: cmd start /B (QA-proven; Start-Process from a piped
# host has died 0xc0000005 in this environment).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t10t3-game.ps1 [-Gravity -9.81] [-Drive]
param(
    [string]$Project = 'H:\workspace_AI\t10-phys\phys-game',
    [double]$Gravity = -9.81,
    [switch]$Drive
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$OutDir = Join-Path $Repo 'loop\t10t3-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$GamePort = 15702
$Exe = Join-Path $Project 'target\debug\phys-game.exe'

# --- write the config ------------------------------------------------------
$cfgPath = Join-Path $Project 'assets\game-config.bsn'
$cfg = "// jackdaw 0.21.0-dev | bevy main`n// jackdaw asset phys_game::GameConfig`n#`"game-config`"`nphys_game::GameConfig {`n    gravity: $Gravity,`n}`n"
[IO.File]::WriteAllText($cfgPath, $cfg)
Write-Host ("GRAVITY_SET: {0}" -f $Gravity)

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
function Find-At([object]$snap, [double]$x, [double]$yLo, [double]$yHi, [double]$band) {
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if ($t) {
            $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
            if ([Math]::Abs($ex - $x) -lt $band -and $ey -ge $yLo -and $ey -le $yHi) { return $ey }
        }
    }
    return $null
}
# The lowest y near x inside the band: the settled cube (0.3) under the
# pickup that also sits at x=0 (0.5) -- Find-At returns whichever entity
# serializes first, this one picks the floor-dweller.
function Find-MinY([object]$snap, [double]$x, [double]$yLo, [double]$yHi, [double]$band) {
    $best = $null
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if ($t) {
            $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
            if ([Math]::Abs($ex - $x) -lt $band -and $ey -ge $yLo -and $ey -le $yHi) {
                if ($null -eq $best -or $ey -lt $best) { $best = $ey }
            }
        }
    }
    return $best
}
function Pickup-Count([object]$snap) {
    foreach ($e in @($snap)) {
        $props = if ($e.components -is [System.Management.Automation.PSObject]) {
            $e.components.PSObject.Properties
        } else { $e.components }
        foreach ($prop in $props) {
            if ("$($prop.Name)" -like '*PickupCount') {
                $j = $prop.Value | ConvertTo-Json -Compress
                if ("$j" -match '(\d+)') { return [int]$Matches[1] }
            }
        }
    }
    return -1
}

# --- boot -------------------------------------------------------------------
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process jackdaw    -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$deps = Join-Path $Project 'target\debug\deps'
$env:PATH = "$deps;$env:PATH"
$tag = if ($Drive) { 'run1' } else { 'run2' }
$gameLog = Join-Path $OutDir "t10t3-game-$tag-stdout.log"
cmd /c "start /B /D `"$Project`" cmd /c `"`"$Exe`" > `"$OutDir\t10t3-game-$tag-stdout.log`" 2>`&1`""
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 250
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process phys-game -ErrorAction SilentlyContinue)) { break }
}
if (-not $ready) { Write-Host 'GAME_BOOT_FAIL'; exit 1 }
Write-Host ("GAME_READY at {0} ms after start" -f $sw.ElapsedMilliseconds)

# --- fall-time samples (grid 4 raw data; best effort -- BRP answers after
# the renderer is up, which can outlast the fall itself) ---------------------
$ys = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt 46; $i++) {
    $t0 = $sw.ElapsedMilliseconds
    $y = Find-MinY (Snap) 0.0 0.05 6.0 0.45
    $ys.Add(("{0},{1}" -f $t0, $y))
    if ($null -ne $y -and $y -lt 0.36 -and $i -gt 2) { break }
    Start-Sleep -Milliseconds 150
}
[IO.File]::WriteAllLines((Join-Path $OutDir "t10t3-game-$tag-fall.csv"), $ys)

# --- grid 4 resource leg: the engine's Gravity resource carries the file's
# number (apply_gravity_from_config). Raw response kept for the report.
$gravResp = Brp 'world.get_resources' @{ resource = 'avian3d::math::Gravity' }
$gravJson = $gravResp | ConvertTo-Json -Depth 8 -Compress
Write-Host ("GRID4_GRAVITY_RESOURCE: {0}" -f $gravJson)
[IO.File]::WriteAllText((Join-Path $OutDir "t10t3-game-$tag-gravity.json"), $gravJson)

# --- grid 3: the cube settles (three samples, 2 s apart) --------------------
Start-Sleep -Seconds 4
$y1 = Find-MinY (Snap) 0.0 0.05 3.0 0.45
Start-Sleep -Seconds 2
$y2 = Find-MinY (Snap) 0.0 0.05 3.0 0.45
Start-Sleep -Seconds 2
$y3 = Find-MinY (Snap) 0.0 0.05 3.0 0.45
Write-Host ("GRID3_CUBE: y1={0} y2={1} y3={2}" -f $y1, $y2, $y3)
if ($null -ne $y1 -and $null -ne $y2 -and $null -ne $y3) {
    $d12 = [Math]::Abs([double]$y2 - [double]$y1); $d23 = [Math]::Abs([double]$y3 - [double]$y2)
    Write-Host ("GRID3_DELTA: d12={0:E1} d23={1:E1}" -f $d12, $d23)
    if ($d12 -lt 0.001 -and $d23 -lt 0.001 -and $y3 -ge 0.25 -and $y3 -le 0.35) { Write-Host 'GRID3_PASS' }
    else { Write-Host 'GRID3_FAIL' }
} else { Write-Host 'GRID3_FAIL (missing entity)' }

if ($Drive) {
    # --- grid 5a: the settled cube did NOT collect the pickup it lands on --
    # (the T10-T3 fix: only the player's touch counts; T10-T2's cube DID
    # collect x=0 -- that behavior is the regression this asserts against)
    $snap = Snap
    $mid = Find-At $snap 0.0 0.3 0.7 0.4
    $cnt = Pickup-Count $snap
    Write-Host ("GRID5A_CUBE_NOCOLLECT: midPickupPresent={0} count={1}" -f ($null -ne $mid), $cnt)
    if ($null -ne $mid -and $cnt -eq 0) { Write-Host 'GRID5A_PASS' } else { Write-Host 'GRID5A_FAIL' }

    # --- grid 5b/6: real keyboard D walks the player through all three ----
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class JdKey {
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
"@
    $game = Get-Process phys-game -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $game) { Write-Host 'GRID5B_FAIL (no game process)'; exit 1 }
    $hwnd = $game.MainWindowHandle
    # Keyboard by window message: PostMessage WM_KEYDOWN/UP straight to the
    # game's window. Both SetForegroundWindow (even with AttachThreadInput)
    # and a synthesized click were refused activation from this background
    # session; winit reads keyboard from its message queue, so posted
    # messages reach the game regardless of foreground state. A focus/activate
    # pair rides along first: winit's input path tracks them.
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class JdPost {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wParam, IntPtr lParam);
}
"@
    $WM_ACTIVATE = 0x0006; $WM_SETFOCUS = 0x0007
    $WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101
    $VK_D = [IntPtr]0x44
    [void][JdPost]::PostMessage($hwnd, $WM_ACTIVATE, [IntPtr]1, [IntPtr]0)
    [void][JdPost]::PostMessage($hwnd, $WM_SETFOCUS, [IntPtr]0, [IntPtr]0)
    Start-Sleep -Milliseconds 600
    Write-Host ("GRID5B_FOREGROUND: hwnd={0} (posted activate+focus)" -f $hwnd)
    $VK_D = [IntPtr]0x44; $WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101
    [void][JdPost]::PostMessage($hwnd, $WM_KEYDOWN, $VK_D, [IntPtr]0)
    $seq = New-Object System.Collections.Generic.List[string]
    $finalCount = -1; $playerX = $null
    for ($i = 0; $i -lt 14; $i++) {
        Start-Sleep -Milliseconds 500
        $s = Snap
        $c = Pickup-Count $s
        $px = $null
        foreach ($e in @($s)) {
            $t = Get-T $e
            if ($t) {
                $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
                $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
                $isPlayer = $false
                foreach ($prop in $props) { if ("$($prop.Name)" -like '*PickupCount') { $isPlayer = $true } }
                if ($isPlayer) { $px = $ex }
            }
        }
        $seq.Add(("{0}:{1}" -f $c, $px))
        $finalCount = $c; $playerX = $px
        if ($c -ge 3) { break }
    }
    [void][JdPost]::PostMessage($hwnd, $WM_KEYUP, $VK_D, [IntPtr]0)
    Write-Host ("GRID5B_SEQ: {0}" -f ($seq -join ' '))
    Write-Host ("GRID5B_FINAL: count={0} playerX={1}" -f $finalCount, $playerX)
    if ($finalCount -ge 3) { Write-Host 'GRID5B_PASS' } else { Write-Host 'GRID5B_FAIL' }

    # --- grid 6: pickups all gone + the clear line in the game's own log ----
    Start-Sleep -Seconds 1
    $s6 = Snap
    $pL = Find-At $s6 -1.0 0.3 0.7 0.4; $pM = Find-At $s6 0.0 0.3 0.7 0.4; $pR = Find-At $s6 1.0 0.3 0.7 0.4
    Write-Host ("GRID6_PICKUPS_LEFT: L={0} M={1} R={2}" -f ($null -ne $pL), ($null -ne $pM), ($null -ne $pR))
    # The log file stays locked by the child until it exits; stop it, then read.
    Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Seconds 2
    $gameLogText = ''
    if (Test-Path $gameLog) { $gameLogText = [IO.File]::ReadAllText($gameLog) }
    $clear = $gameLogText -match 'Level clear'
    Write-Host ("GRID6_CLEAR_LOG: {0}" -f $clear)
    if ($null -eq $pL -and $null -eq $pM -and $null -eq $pR -and $clear -and $finalCount -ge 3) { Write-Host 'GRID6_PASS' }
    else { Write-Host 'GRID6_FAIL' }
    Write-Host 'T10T3_GAME_DONE'
    exit 0
}

# --- settle for the doubled-gravity leg: same resting y ----------------------
if (-not $Drive) {
    Write-Host ("RUN2_SETTLE_Y: {0}" -f $y3)
}

# --- cleanup -----------------------------------------------------------------
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
Write-Host 'T10T3_GAME_DONE'
