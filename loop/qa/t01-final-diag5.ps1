param(
    [int]$Port = 15719
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FgD4 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
"@

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = 'C:\Users\linbo.zhang\Projects\my-game'
$env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe' -WorkingDirectory 'E:\Project\rust\jackdaw\target\debug' -PassThru
try {
    Wait-EditorReady -TimeoutSec 240
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 60 | Out-Null
    Wait-BrpResult 'jackdaw/wait' @{ frames = 30 } | Out-Null
    Start-Sleep -Seconds 2
    $hwnd = Get-JackdawHwnd
    [FgD4]::ShowWindow($hwnd, 3) | Out-Null
    Start-Sleep -Milliseconds 500
    $parked = Set-CursorToWindowPoint $hwnd 0.5 0.5
    Start-Sleep -Milliseconds 400
    $r = $parked.Rect
    $wx = [int](($r.R - $r.L) / 2); $wy = [int](($r.B - $r.T) / 2)

    # move synthetic cursor to center first
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = $wx; y = $wy; action = 'move'; frames = 1 } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 6 } | Out-Null
    Start-Sleep -Milliseconds 300

    # read the live cursor back
    $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @('bevy_window::window::Window') } })
    foreach ($row in $rows) {
        $w = $row.components.'bevy_window::window::Window'
        if ($w) { Write-Output ("live phys_cursor=" + ($w.internal.physical_cursor_position | ConvertTo-Json -Compress) + " scale=" + $w.resolution.scale_factor) }
    }

    # query SceneViewport nodes and run node_contains math locally
    $SceneVp = 'jackdaw_api_internal::viewport::SceneViewport'
    $UiNodePath = 'bevy_ui::ui_node::ComputedNode'
    $UiGtPath = 'bevy_ui::ui_transform::UiGlobalTransform'
    $vpRows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($SceneVp, $UiNodePath, $UiGtPath) } })
    $i = 0
    foreach ($row in $vpRows) {
        $c = $row.components
        if ($null -eq $c.$UiGtPath -or $null -eq $c.$UiNodePath) { continue }
        $i++
        $a = $c.$UiGtPath
        $tx = [double]$a[4]; $ty = [double]$a[5]
        $size = $c.$UiNodePath.size
        $sw = [double]$size[0]; $sh = [double]$size[1]
        $inv = $c.$UiNodePath.inverse_scale_factor
        if (-not $inv) { $inv = 1.0 } else { $inv = [double]$inv }
        # node_contains: centre = translation * inv; half = size * inv / 2 (cursor in ui-logical)
        $cx2 = $tx * $inv; $cy2 = $ty * $inv
        $hw = $sw * $inv / 2.0; $hh = $sh * $inv / 2.0
        $inside = ($wx -ge ($cx2 - $hw)) -and ($wx -le ($cx2 + $hw)) -and ($wy -ge ($cy2 - $hh)) -and ($wy -le ($cy2 + $hh))
        Write-Output ("viewport#{0} entity={1} centre=({2:N0},{3:N0}) half=({4:N0},{5:N0}) inv={6:N3} cursorInside={7}" -f $i, $row.entity, $cx2, $cy2, $hw, $hh, $inv, $inside)
    }
    # also dump UiScale resource if reflected
    try {
        $uis = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_ui::UiScale' })
        Write-Output ("UiScale: " + ($uis.value | ConvertTo-Json -Compress))
    } catch { Write-Output "UiScale: unreadable" }
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
