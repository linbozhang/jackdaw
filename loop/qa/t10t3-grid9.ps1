# grid 9: the exported package, copied away from the project (异目录),
# booted detached, driven by the same PostMessage keyboard, asserted through
# its own BRP (the warm project's exe carries the remote test plugin) and
# its own log -- the same assertions the direct-run leg made.
$ErrorActionPreference = 'Continue'
$OutDir = 'E:\Project\rust\jackdaw\loop\t10t3-live'
$release = 'H:\workspace_AI\t10-phys\phys-game\.jackdaw\dist\release'
$runDir = 'H:\workspace_AI\t10-phys\dist-run'

# --- package assertions --------------------------------------------------------
$exe = Join-Path $release 'phys-game.exe'
$sceneAsset = Join-Path $release 'assets\scene.bsn'
$manifest = Join-Path $release 'export-manifest.json'
$manText = [IO.File]::ReadAllText($manifest)
$manScene = $manText -match 'scene\.bsn'
$manPhysics = $manText -match 'game-config\.bsn'
Write-Host ("GRID9_PACKAGE: exe={0} size={1} scene={2} manifestScene={3} manifestConfig={4}" -f `
    (Test-Path $exe), (Get-Item $exe).Length, (Test-Path $sceneAsset), $manScene, $manPhysics)

# --- copy away and boot --------------------------------------------------------
if (Test-Path $runDir) { Remove-Item $runDir -Recurse -Force }
Copy-Item $release $runDir -Recurse
$runExe = Join-Path $runDir 'phys-game.exe'
$log = Join-Path $OutDir 't10t3-grid9-dist-run.log'
Get-Process phys-game -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
$deps = Join-Path $runDir '.jackdaw-export'
if (Test-Path $deps) { $env:PATH = "$deps;$env:PATH" }
cmd /c "start /B /D `"$runDir`" cmd /c `"`"$runExe`" > `"$log`" 2>&1`""

function Brp([string]$method, $params, [int]$retries = 3) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:15702/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 10)
        } catch { Start-Sleep -Milliseconds (400 * ($i + 1)) }
    }
    return $null
}
$TKEY = 'bevy_transform::components::transform::Transform'
function Snap { (Brp 'jackdaw/scene_snapshot' @{}).result }
function Pickup-Count([object]$snap) {
    foreach ($e in @($snap)) {
        $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
        foreach ($prop in $props) {
            if ("$($prop.Name)" -like '*PickupCount') {
                $j = $prop.Value | ConvertTo-Json -Compress
                if ("$j" -match '(\d+)') { return [int]$Matches[1] }
            }
        }
    }
    return -1
}
function Min-Y([object]$snap, [double]$x, [double]$band) {
    $best = $null
    foreach ($e in @($snap)) {
        $t = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties[$TKEY].Value } else { $e.components[$TKEY] }
        if ($t) {
            $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
            if ([Math]::Abs($ex - $x) -lt $band) { if ($null -eq $best -or $ey -lt $best) { $best = $ey } }
        }
    }
    return $best
}

$ready = $false
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 400
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process phys-game -ErrorAction SilentlyContinue)) { break }
}
if (-not $ready) { Write-Host 'GRID9_BOOT_FAIL (see log)'; Get-Process phys-game -ErrorAction SilentlyContinue | Stop-Process -Force; exit 1 }
Write-Host 'GRID9_DIST_BOOT_PASS'
Start-Sleep -Seconds 5
$s0 = Snap
$cnt0 = Pickup-Count $s0
$yCube = Min-Y $s0 0.0 0.45
Write-Host ("GRID9_STATE: settleY={0} count={1}" -f $yCube, $cnt0)
if ($null -ne $yCube -and $yCube -gt 0.2 -and $yCube -lt 0.4) { Write-Host 'GRID9_SETTLE_PASS (same resting y as PIE/direct)' } else { Write-Host 'GRID9_SETTLE_CHECK' }

# drive the player with the same posted keyboard
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class JdKey9 {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wParam, IntPtr lParam);
}
"@
$game = Get-Process phys-game -ErrorAction SilentlyContinue | Select-Object -First 1
$hwnd = $game.MainWindowHandle
$WM_ACTIVATE = 0x0006; $WM_SETFOCUS = 0x0007; $WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101
$VK_D = [IntPtr]0x44
[void][JdKey9]::PostMessage($hwnd, $WM_ACTIVATE, [IntPtr]1, [IntPtr]0)
[void][JdKey9]::PostMessage($hwnd, $WM_SETFOCUS, [IntPtr]0, [IntPtr]0)
Start-Sleep -Milliseconds 600
[void][JdKey9]::PostMessage($hwnd, $WM_KEYDOWN, $VK_D, [IntPtr]0)
$final = -1
for ($i = 0; $i -lt 14; $i++) {
    Start-Sleep -Milliseconds 500
    $final = Pickup-Count (Snap)
    if ($final -ge 3) { break }
}
[void][JdKey9]::PostMessage($hwnd, $WM_KEYUP, $VK_D, [IntPtr]0)
Write-Host ("GRID9_PICKUPS: count={0}" -f $final)
Get-Process phys-game -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
$clear = ([IO.File]::ReadAllText($log)) -match 'Level clear'
Write-Host ("GRID9_CLEAR_LOG: {0}" -f $clear)
if ($final -ge 3 -and $clear) { Write-Host 'GRID9_PASS (the export plays the same pickup chain)' } else { Write-Host 'GRID9_FAIL' }
Get-Process phys-game -ErrorAction SilentlyContinue | Stop-Process -Force
[IO.File]::WriteAllText((Join-Path $OutDir 't10t3-dist-path.txt'), $release)
