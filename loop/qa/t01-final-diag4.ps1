param(
    [int]$Port = 15717
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FgD3 {
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
    [FgD3]::ShowWindow($hwnd, 3) | Out-Null
    Start-Sleep -Milliseconds 500
    $parked = Set-CursorToWindowPoint $hwnd 0.5 0.5
    Start-Sleep -Milliseconds 400
    $r = $parked.Rect
    $wx = [int](($r.R - $r.L) / 2); $wy = [int](($r.B - $r.T) / 2)
    Write-Output ("parked=({0},{1}) window-local center=({2},{3})" -f $parked.X, $parked.Y, $wx, $wy)

    function Get-Modal { (Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30).modal }
    function Syn($Params) {
        $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = $Params })
    }

    # 1) measure tool via operator, then synthetic RMB click must cancel it (T5/R-3)
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'tools.measure_distance'; history = $false })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null; Start-Sleep -Milliseconds 400
    Write-Output ("modal: '{0}'" -f (Get-Modal))
    Syn @{ x = $wx; y = $wy; action = 'press'; button = 'secondary'; frames = 1 }
    Wait-BrpResult 'jackdaw/wait' @{ frames = 8 } | Out-Null
    $midHold = Get-Modal
    Syn @{ x = ($wx + 5); y = $wy; action = 'release'; button = 'secondary'; frames = 1 }
    Wait-BrpResult 'jackdaw/wait' @{ frames = 8 } | Out-Null; Start-Sleep -Milliseconds 400
    Write-Output ("modal after synthetic RMB press(hold='{0}')+release: '{1}'" -f $midHold, (Get-Modal))

    # 2) fly probe right after: synthetic RMB press with the modal gone
    Syn @{ x = $wx; y = $wy; action = 'press'; button = 'secondary'; frames = 1 }
    Wait-BrpResult 'jackdaw/wait' @{ frames = 6 } | Out-Null
    $fly = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'jackdaw::viewport::CameraFlyActive' })
    $pan = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'jackdaw::viewport::CameraPanActive' })
    Write-Output ("fly='{0}' pan='{1}' during RMB hold" -f ($fly.value | ConvertTo-Json -Compress), ($pan.value | ConvertTo-Json -Compress))
    # middle button press: pan should engage (hover-gated too)
    Syn @{ x = $wx; y = $wy; action = 'press'; button = 'middle'; frames = 1 }
    Wait-BrpResult 'jackdaw/wait' @{ frames = 6 } | Out-Null
    $pan2 = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'jackdaw::viewport::CameraPanActive' })
    $fly2 = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'jackdaw::viewport::CameraFlyActive' })
    Write-Output ("after MMB press too: pan='{0}' fly='{1}'" -f ($pan2.value | ConvertTo-Json -Compress), ($fly2.value | ConvertTo-Json -Compress))
    Syn @{ x = ($wx + 5); y = $wy; action = 'release'; button = 'middle'; frames = 1 }
    Syn @{ x = ($wx + 6); y = $wy; action = 'release'; button = 'secondary'; frames = 1 }
    Wait-BrpResult 'jackdaw/wait' @{ frames = 8 } | Out-Null
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
