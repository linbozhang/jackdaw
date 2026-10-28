param(
    [int]$Port = 15711
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FgD {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
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
    Wait-BrpResult 'jackdaw/wait' @{ frames = 20 } | Out-Null
    Start-Sleep -Seconds 2
    $hwnd = Get-JackdawHwnd
    [FgD]::ShowWindow($hwnd, 3) | Out-Null
    Start-Sleep -Milliseconds 500
    [FgD]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    $fg = [FgD]::GetForegroundWindow() -eq $hwnd
    # park the REAL cursor at the window center (T2 methodology: synthetic hover
    # only survives while the real cursor sits over the viewport)
    $parked = Set-CursorToWindowPoint $hwnd 0.5 0.5
    Start-Sleep -Milliseconds 400
    Write-Output ("fg={0} parked at ({1},{2})" -f $fg, $parked.X, $parked.Y)

    # compute logical center from the live window component
    $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @('bevy_window::window::Window') } })
    $scale = 1.5; $pw = 1280; $ph = 720
    foreach ($row in $rows) {
        $w = $row.components.'bevy_window::window::Window'
        if ($w) {
            $pw = [double]$w.resolution.physical_width
            $ph = [double]$w.resolution.physical_height
            if ($w.resolution.scale_factor) { $scale = [double]$w.resolution.scale_factor }
        }
    }
    $lx = [Math]::Floor($pw / 2 / $scale); $ly = [Math]::Floor($ph / 2 / $scale)
    Write-Output ("window phys={0}x{1} scale={2} logicalCenter=({3},{4})" -f $pw, $ph, $scale, $lx, $ly)

    function Read-Resource([string]$Path) {
        try {
            $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = $Path })
            return ($r.value | ConvertTo-Json -Compress -Depth 6)
        } catch { return "ERR: $($_.Exception.Message)" }
    }
    Write-Output ("focus: " + (Read-Resource 'bevy_input_focus::InputFocus'))

    # synthetic move into the viewport area
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = $lx; y = $ly; action = 'move' } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    Start-Sleep -Milliseconds 300
    Write-Output '--- after synthetic move ---'

    # synthetic RMB press
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = $lx; y = $ly; action = 'press'; button = 'secondary' } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    Write-Output '--- after synthetic RMB press ---'
    Write-Output ("fly: " + (Read-Resource 'jackdaw::viewport::CameraFlyActive'))
    # a small look move while held
    for ($i = 1; $i -le 10; $i++) {
        $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = ($lx + 15 * $i); y = $ly; action = 'move' } })
        Wait-BrpResult 'jackdaw/wait' @{ frames = 2 } | Out-Null
    }
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    $cam = Get-FlyCamera
    Write-Output ("cam after look moves: yaw=" + $cam.Yaw + " pitch=" + $cam.Pitch)
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = ($lx + 150); y = $ly; action = 'release'; button = 'secondary' } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    Write-Output ("fly after release: " + (Read-Resource 'jackdaw::viewport::CameraFlyActive'))
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
