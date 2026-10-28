# diag: is the template player settling (physics+move_player alive) and
# does PostMessage input reach it on direct run with the placed scene?
$proj = 'H:\workspace_AI\t11-live\t11t1-game'
$exe = Join-Path $proj 'target\debug\t11t1-game.exe'
$gameAssets = Join-Path $proj 'target\debug\assets'
New-Item -ItemType Directory -Force -Path $gameAssets | Out-Null
Copy-Item (Join-Path $proj 'assets\t11t2-place.bsn') (Join-Path $gameAssets 'scene.bsn') -Force
Get-Process t11t1-game -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
function GBrp([string]$m, $p) {
    try {
        $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $m }
        if ($p) { $body.params = $p }
        return Invoke-RestMethod -Uri 'http://127.0.0.1:15702/' -Method Post -ContentType 'application/json' -TimeoutSec 20 -Body ($body | ConvertTo-Json -Depth 10)
    } catch { return $null }
}
$TKEY = 'bevy_transform::components::transform::Transform'
$env:PATH = "$proj\target\debug\deps;$env:PATH"
cmd /c "start /B /D `"$proj`" cmd /c `"`"$exe`" > H:\workspace_AI\t11-live\diag.log 2>&1`""
for ($i = 0; $i -lt 80; $i++) { Start-Sleep -Milliseconds 250; if (GBrp 'jackdaw/scene_snapshot' @{}) { break } }
Start-Sleep -Seconds 4
$game = Get-Process t11t1-game -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Host ("hwnd: {0}" -f $game.MainWindowHandle)
function Dump-Players($snap) {
    foreach ($e in @($snap)) {
        $comps = @()
        $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
        $t = $null
        foreach ($p in $props) {
            $n = "$($p.Name)" -replace '^.*::', ''
            $comps += $n
            if ("$($p.Name)" -eq $TKEY) { $t = $p.Value }
        }
        if ($comps -contains 'PlayerMarker') {
            Write-Host ("PLAYER [{0}] ({1:F2},{2:F2},{3:F2}): {4}" -f $e.entity, [double]$t.translation[0], [double]$t.translation[1], [double]$t.translation[2], (($comps | Where-Object { $_ -match 'Collider|RigidBody|Velocity|Pickup|Player' }) -join ','))
        }
    }
}
Dump-Players ((GBrp 'jackdaw/scene_snapshot' @{}).result)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class JdPost2 {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wParam, IntPtr lParam);
}
"@
$h = $game.MainWindowHandle
[JdPost2]::PostMessage($h, 0x0006, [IntPtr]1, [IntPtr]0) | Out-Null
[JdPost2]::PostMessage($h, 0x0007, [IntPtr]0, [IntPtr]0) | Out-Null
Start-Sleep -Milliseconds 500
[JdPost2]::PostMessage($h, 0x0100, [IntPtr]0x57, [IntPtr]0) | Out-Null
Start-Sleep -Milliseconds 1200
[JdPost2]::PostMessage($h, 0x0101, [IntPtr]0x57, [IntPtr]0) | Out-Null
Start-Sleep -Milliseconds 300
Dump-Players ((GBrp 'jackdaw/scene_snapshot' @{}).result)
Get-Process t11t1-game -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'DIAG_DONE'
