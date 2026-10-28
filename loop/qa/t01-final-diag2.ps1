param(
    [int]$Port = 15713
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FgD2 {
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
    [FgD2]::ShowWindow($hwnd, 3) | Out-Null
    Start-Sleep -Milliseconds 500
    $parked = Set-CursorToWindowPoint $hwnd 0.5 0.5
    Start-Sleep -Milliseconds 400
    Write-Output ("parked at ({0},{1})" -f $parked.X, $parked.Y)

    function Dump-Window([string]$Tag) {
        $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @('bevy_window::window::Window') } })
        foreach ($row in $rows) {
            $w = $row.components.'bevy_window::window::Window'
            if ($w) {
                $phys = $w.internal.physical_cursor_position
                Write-Output ("{0}: internal.phys_cursor={1} scale={2}" -f $Tag, ($phys | ConvertTo-Json -Compress), $w.resolution.scale_factor)
            }
        }
    }
    Dump-Window 'before'

    $lx = [Math]::Floor($parked.Rect.R - ($parked.Rect.R - $parked.Rect.L) / 2)
    $ly = [Math]::Floor($parked.Rect.B - ($parked.Rect.B - $parked.Rect.T) / 2)
    # logical = physical (scale 1.0 observed); use window-local coords
    $wx = $lx - $parked.Rect.L; $wy = $ly - $parked.Rect.T
    Write-Output ("synthetic move to window-local ({0},{1})" -f $wx, $wy)
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = $wx; y = $wy; action = 'move'; frames = 1 } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 6 } | Out-Null
    Start-Sleep -Milliseconds 400
    Dump-Window 'after-move'

    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = $wx; y = $wy; action = 'press'; button = 'secondary'; frames = 1 } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 6 } | Out-Null
    $fly = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'jackdaw::viewport::CameraFlyActive' })
    Write-Output ("fly after press: " + ($fly.value | ConvertTo-Json -Compress))
    for ($i = 1; $i -le 10; $i++) {
        $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = ($wx + 15 * $i); y = $wy; action = 'move'; frames = 1 } })
        Wait-BrpResult 'jackdaw/wait' @{ frames = 2 } | Out-Null
    }
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    $cam = Get-FlyCamera
    Write-Output ("cam: yaw=" + $cam.Yaw + " pitch=" + $cam.Pitch)
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = ($wx + 150); y = $wy; action = 'release'; button = 'secondary' } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 6 } | Out-Null
    $fly2 = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'jackdaw::viewport::CameraFlyActive' })
    Write-Output ("fly after release: " + ($fly2.value | ConvertTo-Json -Compress))
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
