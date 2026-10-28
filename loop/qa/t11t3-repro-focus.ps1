# T11-T3 minimal repro: does the PLACED scene (two active cameras) take
# injected keys while focused? One boot, focus asserted, W held, z sampled.
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$GamePort = 15702
)
$OutDir = 'E:\Project\rust\jackdaw\loop\t11t3-live'
$Exe = Join-Path $Project 'target\debug\t11t1-game.exe'
$Scene = Join-Path $Project 'target\debug\assets\scene.bsn'
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
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class JdWin {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@
$TKEY = 'bevy_transform::components::transform::Transform'
function Get-T($e) {
    foreach ($prop in $e.components.PSObject.Properties) { if ("$($prop.Name)" -eq $TKEY) { return $prop.Value } }
    return $null
}
function Has-Comp([object]$e, [string]$suffix) {
    if (-not $e) { return $false }
    foreach ($prop in $e.components.PSObject.Properties) { if ("$($prop.Name)" -like "*$suffix") { return $true } }
    return $false
}
function Snap { (GameBrp 'jackdaw/scene_snapshot' @{} 2).result }

Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 2500
Copy-Item "$Project\assets\t11t3-place.bsn" $Scene -Force
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Exe; $psi.WorkingDirectory = $Project
$psi.UseShellExecute = $true; $psi.WindowStyle = 'Minimized'
$null = [System.Diagnostics.Process]::Start($psi)
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Milliseconds 250
    if (GameBrp 'jackdaw/scene_snapshot' @{} 1) { break }
}
Start-Sleep -Seconds 3
$game = Get-Process t11t1-game -ErrorAction SilentlyContinue | Select-Object -First 1
$hwnd = $game.MainWindowHandle
"window handle: $hwnd"
[void][JdWin]::ShowWindow($hwnd, 9)
[void][JdWin]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 600
$fg = [JdWin]::GetForegroundWindow()
"foreground == game window: $($fg -eq $hwnd) (fg=$fg)"
# retry focus a few times
for ($k = 0; $k -lt 3 -and $fg -ne $hwnd; $k++) {
    [void][JdWin]::ShowWindow($hwnd, 9); [void][JdWin]::SetForegroundWindow($hwnd)
    Start-Sleep -Milliseconds 500
    $fg = [JdWin]::GetForegroundWindow()
    "retry $k foreground match: $($fg -eq $hwnd)"
}
# find the placed player (no PickupCount)
function Find-Placed($snap) {
    foreach ($e in @($snap)) {
        if ((Has-Comp $e 'PlayerMarker') -and -not (Has-Comp $e 'PickupCount')) { return $e }
    }
    return $null
}
$z0 = (Get-T (Find-Placed (Snap))).translation[2]
"z before: $z0"
[JdWin]::PostMessage($hwnd, 0x0100, [IntPtr]0x57, [IntPtr]0) | Out-Null
Start-Sleep -Milliseconds 1200
[JdWin]::PostMessage($hwnd, 0x0101, [IntPtr]0x57, [IntPtr]0) | Out-Null
Start-Sleep -Milliseconds 300
$z1 = (Get-T (Find-Placed (Snap))).translation[2]
"z after : $z1"
"MOVED: $([Math]::Abs([double]$z1 - [double]$z0) -gt 0.3)"
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
