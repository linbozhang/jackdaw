# Fine-grained probe: wall stop from spawn (x=-2 inside the wall span),
# then the pickup walk with 60 ms sampling to see what the third pickup
# does (cube interference?).
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$GamePort = 15702
)
$OutDir = 'E:\Project\rust\jackdaw\loop\t11t1-live'
$Exe = Join-Path $Project 'target\debug\t11t1-game.exe'
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
function Find-Player([object]$snap) {
    foreach ($e in @($snap)) {
        $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
        foreach ($prop in $props) { if ("$($prop.Name)" -like '*PickupCount') { return $e } }
    }
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
function State([object]$snap) {
    $p = Find-Player $snap
    if (-not $p) { return 'no-player' }
    $t = Get-T $p
    return ('{0:F3},{1:F3},{2:F3},c{3}' -f [double]$t.translation[0], [double]$t.translation[1], [double]$t.translation[2], (Pickup-Count $snap))
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
function Tap([IntPtr]$hwnd, [byte]$vk) {
    [void][JdPost]::PostMessage($hwnd, $WM_KEYDOWN, [IntPtr]$vk, [IntPtr]0)
    Start-Sleep -Milliseconds 60
    [void][JdPost]::PostMessage($hwnd, $WM_KEYUP, [IntPtr]$vk, [IntPtr]0)
}

Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$deps = Join-Path $Project 'target\debug\deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"$Project`" cmd /c `"`"$Exe`" > `"$OutDir\probe2-stdout.log`" 2>`&1`""
$ready = $false
for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 250
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process t11t1-game -ErrorAction SilentlyContinue)) { Write-Host 'BOOT_FAIL'; exit 1 }
}
if (-not $ready) { Write-Host 'BOOT_FAIL'; exit 1 }
Start-Sleep -Seconds 3
$game = Get-Process t11t1-game -ErrorAction SilentlyContinue | Select-Object -First 1
$hwnd = $game.MainWindowHandle
[void][JdPost]::PostMessage($hwnd, $WM_ACTIVATE, [IntPtr]1, [IntPtr]0)
[void][JdPost]::PostMessage($hwnd, $WM_SETFOCUS, [IntPtr]0, [IntPtr]0)
Start-Sleep -Milliseconds 600
$VK_D = 0x44; $VK_W = 0x57; $VK_S = 0x53; $VK_SPACE = 0x20

Write-Host ("START: {0}" -f (State (Snap)))

# Leg A: wall stop from spawn (x=-2 is inside the wall span).
[void][JdPost]::PostMessage($hwnd, $WM_KEYDOWN, [IntPtr]$VK_W, [IntPtr]0)
$series = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 120
    $series.Add((State (Snap)))
}
[void][JdPost]::PostMessage($hwnd, $WM_KEYUP, [IntPtr]$VK_W, [IntPtr]0)
Write-Host ("WALL_WALK: {0}" -f ($series -join ' | '))

# Walk back south, then east to the pickup lane approach.
[void][JdPost]::PostMessage($hwnd, $WM_KEYDOWN, [IntPtr]$VK_S, [IntPtr]0)
Start-Sleep -Milliseconds 900
[void][JdPost]::PostMessage($hwnd, $WM_KEYUP, [IntPtr]$VK_S, [IntPtr]0)
Write-Host ("AFTER_S: {0}" -f (State (Snap)))

# Leg B: pickup walk, fine sampling; tap Space to hop the cube at x~-0.6.
[void][JdPost]::PostMessage($hwnd, $WM_KEYDOWN, [IntPtr]$VK_D, [IntPtr]0)
$hopped = $false
$series2 = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt 70; $i++) {
    Start-Sleep -Milliseconds 60
    $s = Snap
    $st = State $s
    $series2.Add($st)
    $x = [double]($st -replace '^(-?[0-9.]+),.*$', '$1')
    if (-not $hopped -and $x -gt -0.75) { Tap $hwnd $VK_SPACE; $hopped = $true }
    if ((Pickup-Count $s) -ge 3) { break }
}
[void][JdPost]::PostMessage($hwnd, $WM_KEYUP, [IntPtr]$VK_D, [IntPtr]0)
Write-Host ("PICKUP_WALK: {0}" -f ($series2 -join ' | '))
Write-Host ("FINAL: {0}" -f (State (Snap)))

Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 2
$logText = ''
$gameLog = Join-Path $OutDir 'probe2-stdout.log'
if (Test-Path $gameLog) { $logText = [IO.File]::ReadAllText($gameLog) }
Write-Host ("CLEAR_LOG: {0}" -f ($logText -match 'Level clear'))
Write-Host 'PROBE2_DONE'
