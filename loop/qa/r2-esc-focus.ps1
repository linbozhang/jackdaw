# Focus probe: is SendInput Esc landing on the editor at all?
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@

function Get-ModalReport {
    $r = Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30
    return $r.modal
}
function Call-Op {
    param([string]$Id, $OpParams = @{})
    $p = @{ id = $Id; history = $false }
    if ($OpParams.Count -gt 0) { $p.params = $OpParams }
    Brp-Result (Brp-Call 'jackdaw/call_operator' $p) | Out-Null
}
function Frames([int]$n) { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } | Out-Null }

Wait-EditorReady -TimeoutSec 90
Frames 5
$hwnd = Get-JackdawHwnd
Write-Host ("hwnd = " + $hwnd)

# F1: bare Focus-Jackdaw -> is foreground actually the editor?
Focus-Jackdaw $hwnd
$fg = [Fg]::GetForegroundWindow()
Write-Host ("F1 after Focus-Jackdaw: foreground = $fg  editor = $hwnd  match = " + ($fg -eq $hwnd))

# F2: click viewport centre -> foreground now?
Reset-Modal; Frames 5
Call-Op 'tools.measure_distance'
Frames 5
Write-Host ("F2 measure active: '$(Get-ModalReport)'")
$null = Set-CursorToWindowPoint $hwnd 0.5 0.5
Start-Sleep -Milliseconds 150
Send-LmbDown; Start-Sleep -Milliseconds 60; Send-LmbUp
Start-Sleep -Milliseconds 300
$fg = [Fg]::GetForegroundWindow()
Write-Host ("F2 after LMB click: foreground = $fg  match = " + ($fg -eq $hwnd))

# F3: Esc now?
Send-Esc
Frames 15
Write-Host ("F3 after click+Esc: modal = '$(Get-ModalReport)'")

# F4: fresh measure, no click, Esc (control for the focus theory)
Reset-Modal; Frames 5
Call-Op 'tools.measure_distance'
Frames 5
Start-Sleep -Milliseconds 200
$fg = [Fg]::GetForegroundWindow()
Write-Host ("F4 before bare Esc: foreground = $fg  match = " + ($fg -eq $hwnd))
Send-Esc
Frames 15
Write-Host ("F4 after bare Esc: modal = '$(Get-ModalReport)'")
Reset-Modal
Write-Host "focus probe done"
