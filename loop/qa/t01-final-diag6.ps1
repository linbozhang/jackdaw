param(
    [int]$Port = 15721
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FgD5 {
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
    [FgD5]::ShowWindow($hwnd, 3) | Out-Null
    Start-Sleep -Milliseconds 500
    $parked = Set-CursorToWindowPoint $hwnd 0.5 0.5
    Start-Sleep -Milliseconds 400
    $r = $parked.Rect
    $wx = [int](($r.R - $r.L) / 2); $wy = [int](($r.B - $r.T) / 2)

    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = $wx; y = $wy; action = 'move'; frames = 1 } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 6 } | Out-Null
    Start-Sleep -Milliseconds 300

    $UiNodePath = 'bevy_ui::ui_node::ComputedNode'
    $UiGtPath = 'bevy_ui::ui_transform::UiGlobalTransform'
    $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($UiNodePath, $UiGtPath) } })
    $nodes = @()
    foreach ($row in $rows) {
        $c = $row.components
        if ($null -eq $c.$UiGtPath -or $null -eq $c.$UiNodePath) { continue }
        $a = $c.$UiGtPath
        $tx = [double]$a[4]; $ty = [double]$a[5]
        $size = $c.$UiNodePath.size
        $sw = [double]$size[0]; $sh = [double]$size[1]
        if ($sw -le 0 -or $sh -le 0) { continue }
        $inv = $c.$UiNodePath.inverse_scale_factor
        if (-not $inv) { $inv = 1.0 } else { $inv = [double]$inv }
        $cx2 = $tx * $inv; $cy2 = $ty * $inv
        $hw = $sw * $inv / 2.0; $hh = $sh * $inv / 2.0
        $inside = ($wx -ge ($cx2 - $hw)) -and ($wx -le ($cx2 + $hw)) -and ($wy -ge ($cy2 - $hh)) -and ($wy -le ($cy2 + $hh))
        $nodes += [pscustomobject]@{
            e = $row.entity; area = $sw * $sh; cx = $cx2; cy = $cy2; hw = $hw; hh = $hh; inv = $inv; inside = $inside
        }
    }
    Write-Output ("total ui nodes with rect: " + @($nodes).Count)
    $big = $nodes | Sort-Object -Property area -Descending | Select-Object -First 8
    foreach ($n in $big) {
        Write-Output ("node {0} area={1:N0} centre=({2:N0},{3:N0}) half=({4:N0},{5:N0}) inv={6:N3} cursorInside={7}" -f $n.e, $n.area, $n.cx, $n.cy, $n.hw, $n.hh, $n.inv, $n.inside)
    }
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
