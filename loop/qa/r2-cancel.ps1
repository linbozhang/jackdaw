# R2 real-machine verification driver (feature-05 T2): Escape / RMB cancel semantics.
# Flow: start editor (JACKDAW_OPEN_PROJECT) -> ready -> per case:
#   ruler-Esc   : BRP activate measure -> assert modal running -> SendInput Esc
#                 -> assert modal cleared + ActiveTool still Select
#   ruler-RMB   : BRP activate measure -> SendInput RMB down/up at viewport centre
#                 -> assert modal cleared + ActiveTool still Select
#   drawAdd-Esc : BRP activate draw brush Add mode -> SendInput Esc -> assert cleared
#   drawCut-RMB : BRP activate draw brush Cut mode -> SendInput RMB -> assert cleared
#   toolState   : BRP call tool.rotate -> world.get_resources ActiveTool == Rotate
#                 -> Esc (no modal: no-op) -> ActiveTool still Rotate -> tool.select
# Every case leaves a screenshot in loop/reports/r2-cancel/<Label>/.
# Usage:
#   powershell -ExecutionPolicy Bypass -File r2-cancel.ps1 -Label run
#   powershell -ExecutionPolicy Bypass -File r2-cancel.ps1 -NoStart -Label rerun   # attach to running editor
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [int]$Repeat = 3,
    [string]$Label = 'run',
    [string]$OutDir = '',
    [double]$XFactor = 0.5,
    [double]$YFactor = 0.5,
    [switch]$NoStart,
    [switch]$LeaveRunning
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "..\reports\r2-cancel\$Label" }
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')
. (Join-Path $PSScriptRoot 'screenshot.ps1')

$csv = Join-Path $OutDir 'metrics.csv'
"case,iter,modal_before,modal_after,active_tool_before,active_tool_after,ok" | Set-Content -Path $csv -Encoding UTF8
function Log-Metric {
    param([string]$Line)
    Add-Content -Path $csv -Encoding UTF8 -Value $Line
    Write-Host $Line
}

$ActiveToolPath = 'jackdaw::active_tool::ActiveTool'

function Get-ActiveTool {
    $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = $ActiveToolPath })
    return [string]$r.value
}

function Get-ModalReport {
    $r = Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30
    return $r.modal
}

function Call-Op {
    param([string]$Id, $OpParams = @{})
    $p = @{ id = $Id; history = $false }
    if ($OpParams.Count -gt 0) { $p.params = $OpParams }
    $r = Brp-Result (Brp-Call 'jackdaw/call_operator' $p)
    return $r
}

function Shot {
    param([string]$Name)
    try {
        Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = "loop/reports/r2-cancel/$Label/$Name.png" } -TimeoutSec 15 | Out-Null
    } catch { Write-Host "screenshot $Name failed: $_" }
}

function Assert-True {
    param([bool]$Cond, [string]$What)
    if (-not $Cond) { throw "ASSERT FAILED: $What" }
    Write-Host "  ok: $What"
}

$proc = $null
if (-not $NoStart) {
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
    }
    Start-Sleep -Milliseconds 500
    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT = "$Port"
    $stdout = Join-Path $OutDir 'editor-stdout.log'
    $stderr = Join-Path $OutDir 'editor-stderr.log'
    Write-Host "starting editor: $Exe  port=$Port"
    $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    Write-Host "editor pid=$($proc.Id)"
}

$failures = @()
try {
    Wait-EditorReady -TimeoutSec 90
    Write-Host "editor ready on port $Port"
    foreach ($try in 1..6) {
        try { Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null; break }
        catch { Write-Host "idle wait retry $try"; Start-Sleep -Seconds 2 }
    }

    $hwnd = Get-JackdawHwnd

    # ---------- case 1: ruler Escape ----------
    for ($i = 1; $i -le $Repeat; $i++) {
        Reset-Modal
        Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
        $before = Get-ModalReport
        Assert-True ($null -eq $before) "iter ${i}: no stale modal before activating ruler (was '$before')"
        Call-Op 'tools.measure_distance' | Out-Null
        Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
        $modal_before = Get-ModalReport
        $ok_before = ($modal_before -eq 'tools.measure_distance')
        if ($i -eq 1) { Shot "ruler-active-$i" }
        Focus-Jackdaw $hwnd
        Send-Esc
        Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null
        $modal_after = Get-ModalReport
        $tool_after = Get-ActiveTool
        $ok = $ok_before -and ($modal_after -eq $null) -and ($tool_after -match 'Select')
        Log-Metric "ruler-Esc,$i,$modal_before,$modal_after,,$tool_after,$ok"
        if (-not $ok) { $failures += "ruler-Esc iter $i" }
    }

    # ---------- case 2: ruler RMB ----------
    for ($i = 1; $i -le $Repeat; $i++) {
        Reset-Modal
        Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
        Call-Op 'tools.measure_distance' | Out-Null
        Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
        $modal_before = Get-ModalReport
        Focus-Jackdaw $hwnd
        $pt = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 150
        Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
        Start-Sleep -Milliseconds 100
        Send-RmbDown
        Start-Sleep -Milliseconds 200
        Send-RmbUp
        Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null
        $modal_after = Get-ModalReport
        $tool_after = Get-ActiveTool
        $ok = ($modal_before -eq 'tools.measure_distance') -and ($modal_after -eq $null) -and ($tool_after -match 'Select')
        Log-Metric "ruler-RMB,$i,$modal_before,$modal_after,,$tool_after,$ok"
        if (-not $ok) { $failures += "ruler-RMB iter $i" }
    }

    # ---------- case 3: draw brush Add mode, Escape (previously a dead path) ----------
    Reset-Modal
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    Call-Op 'viewport.draw_brush_modal' @{ mode = 'Add' } | Out-Null
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    $modal_before = Get-ModalReport
    Focus-Jackdaw $hwnd
    Send-Esc
    Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null
    $modal_after = Get-ModalReport
    $ok = ($modal_before -eq 'viewport.draw_brush_modal') -and ($modal_after -eq $null)
    Log-Metric "drawAdd-Esc,1,$modal_before,$modal_after,,,$ok"
    if (-not $ok) { $failures += "drawAdd-Esc" }

    # ---------- case 4: draw brush Cut mode, RMB (regression: existing binding) ----------
    Reset-Modal
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    Call-Op 'viewport.draw_brush_modal' @{ mode = 'Cut' } | Out-Null
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    $modal_before = Get-ModalReport
    Focus-Jackdaw $hwnd
    $pt = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
    Start-Sleep -Milliseconds 150
    Send-RmbDown
    Start-Sleep -Milliseconds 200
    Send-RmbUp
    Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null
    $modal_after = Get-ModalReport
    $ok = ($modal_before -eq 'viewport.draw_brush_modal') -and ($modal_after -eq $null)
    Log-Metric "drawCut-RMB,1,$modal_before,$modal_after,,,$ok"
    if (-not $ok) { $failures += "drawCut-RMB" }

    # ---------- case 5: ActiveTool readable over BRP; Esc with no modal is a no-op ----------
    Reset-Modal
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    Call-Op 'tool.rotate' | Out-Null
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    $tool_rotate = Get-ActiveTool
    Focus-Jackdaw $hwnd
    Send-Esc
    Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null
    $modal_after_esc = Get-ModalReport
    $tool_after_esc = Get-ActiveTool
    Call-Op 'tool.select' | Out-Null
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    $tool_select = Get-ActiveTool
    $ok = ($tool_rotate -match 'Rotate') -and ($modal_after_esc -eq $null) `
        -and ($tool_after_esc -match 'Rotate') -and ($tool_select -match 'Select')
    Log-Metric "toolState,1,null,$modal_after_esc,$tool_rotate,$tool_select,$ok"
    if (-not $ok) { $failures += "toolState" }
    Shot "final"

    if ($failures.Count -gt 0) {
        Write-Host "FAILURES: $($failures -join '; ')"
        throw "r2-cancel verification failed"
    }
    Write-Host "ALL CASES PASS"
}
finally {
    if ($proc -and -not $LeaveRunning) {
        Write-Host "stopping editor pid=$($proc.Id)"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
