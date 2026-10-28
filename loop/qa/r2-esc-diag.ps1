# R2 Esc diagnosis: why does SendInput Esc cancel draw_brush but not measure?
param(
    [int]$Port = 15703
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

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
Write-Host "editor ready"
Frames 5
$hwnd = Get-JackdawHwnd

# ---- probe A: measure, single Esc tap ----
Reset-Modal; Frames 5
Call-Op 'tools.measure_distance'
Frames 5
$m = Get-ModalReport
Write-Host ("A measure active: '$m'")
Focus-Jackdaw $hwnd
Send-Esc
Frames 15
Write-Host ("A after 1 tap : '$(Get-ModalReport)'")

# ---- probe B: same modal still running, a second and third tap ----
if ((Get-ModalReport)) {
    Focus-Jackdaw $hwnd
    Send-Esc
    Frames 15
    Write-Host ("B after 2nd tap: '$(Get-ModalReport)'")
}
if ((Get-ModalReport)) {
    Focus-Jackdaw $hwnd
    Send-Esc
    Frames 15
    Write-Host ("B after 3rd tap: '$(Get-ModalReport)'")
}

# ---- probe C: fresh measure, Esc held 300ms ----
Reset-Modal; Frames 5
Call-Op 'tools.measure_distance'
Frames 5
Write-Host ("C measure active: '$(Get-ModalReport)'")
Focus-Jackdaw $hwnd
[JdInput]::KeyDown(0x1B); Start-Sleep -Milliseconds 300; [JdInput]::KeyUp(0x1B)
Frames 15
Write-Host ("C after hold  : '$(Get-ModalReport)'")

# ---- probe D: control, draw brush Add, single tap ----
Reset-Modal; Frames 5
Call-Op 'viewport.draw_brush_modal' @{ mode = 'Add' }
Frames 5
Write-Host ("D drawAdd active: '$(Get-ModalReport)'")
Focus-Jackdaw $hwnd
Send-Esc
Frames 15
Write-Host ("D after tap    : '$(Get-ModalReport)'")

# ---- probe E: fresh measure, then synthetic in-process input.key Escape (BRP) ----
Reset-Modal; Frames 5
Call-Op 'tools.measure_distance'
Frames 5
Write-Host ("E measure active: '$(Get-ModalReport)'")
Call-Op 'input.key' @{ key = 'Escape'; action = 'tap' }
Frames 15
Write-Host ("E after BRP synthetic Esc: '$(Get-ModalReport)'")
Reset-Modal
Write-Host "diag done"
