# R2 QA verification driver (final): r2-cancel.ps1 cases with deterministic focus.
# OS keyboard injection needs the editor to actually be foreground; Windows
# denies SetForegroundWindow from a background process, so we click the window
# (a real user focusing the editor) before every key, and assert the foreground
# handle each time. Mouse-only cases keep the original flow.
param(
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [int]$Repeat = 2,
    [string]$Label = 'qa-final',
    [double]$XFactor = 0.5,
    [double]$YFactor = 0.5,
    [switch]$LeaveRunning
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot "..\reports\r2-cancel\$Label"
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
}
"@

$csv = Join-Path $OutDir 'metrics.csv'
"case,iter,modal_before,modal_after,active_tool_after,foreground_ok,ok" | Set-Content -Path $csv -Encoding UTF8
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
    Brp-Result (Brp-Call 'jackdaw/call_operator' $p) | Out-Null
}
function Frames([int]$n) { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } | Out-Null }
function Shot {
    param([string]$Name)
    try {
        Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = "loop/reports/r2-cancel/$Label/$Name.png" } -TimeoutSec 15 | Out-Null
    } catch { Write-Host "screenshot $Name failed: $_" }
}

# Bring the editor to the foreground deterministically. Windows denies
# SetForegroundWindow from a background process and a plain click lands on
# whatever overlaps the editor, so: minimize + restore (the system activates
# a window it restores), fall back to AttachThreadInput, then click the
# viewport (real user focus) and verify the foreground handle.
function Focus-ByClick {
    param([IntPtr]$Hwnd)
    [Fg]::ShowWindow($Hwnd, 6) | Out-Null   # SW_MINIMIZE
    Start-Sleep -Milliseconds 250
    [Fg]::ShowWindow($Hwnd, 9) | Out-Null   # SW_RESTORE
    Start-Sleep -Milliseconds 450
    $fg = [Fg]::GetForegroundWindow()
    if ($fg -ne $Hwnd) {
        # AttachThreadInput fallback to earn the foreground right.
        $fgPid = 0
        $fgThread = [Fg]::GetWindowThreadProcessId($fg, [ref]$fgPid)
        $thisThread = [Fg]::GetCurrentThreadId()
        [Fg]::AttachThreadInput($thisThread, $fgThread, $true) | Out-Null
        [Fg]::SetForegroundWindow($Hwnd) | Out-Null
        [Fg]::AttachThreadInput($thisThread, $fgThread, $false) | Out-Null
        Start-Sleep -Milliseconds 350
        $fg = [Fg]::GetForegroundWindow()
    }
    $null = Set-CursorToWindowPoint $Hwnd $XFactor $YFactor
    Start-Sleep -Milliseconds 150
    [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
    Start-Sleep -Milliseconds 350
    $fg = [Fg]::GetForegroundWindow()
    if ($fg -ne $Hwnd) {
        # One more restore attempt; the desktop may be contended.
        [Fg]::ShowWindow($Hwnd, 6) | Out-Null
        Start-Sleep -Milliseconds 250
        [Fg]::ShowWindow($Hwnd, 9) | Out-Null
        Start-Sleep -Milliseconds 450
        $fg = [Fg]::GetForegroundWindow()
    }
    if ($fg -ne $Hwnd) { throw "focus-by-click failed: foreground=$fg editor=$Hwnd" }
    return $true
}

Wait-EditorReady -TimeoutSec 90
Write-Host "editor ready on port $Port"
foreach ($try in 1..6) {
    try { Frames 30; break } catch { Start-Sleep -Seconds 2 }
}
Frames 5
$hwnd = Get-JackdawHwnd
$failures = @()

# ---------- case 1: ruler Escape (click-to-focus first) ----------
for ($i = 1; $i -le $Repeat; $i++) {
    Reset-Modal; Frames 5
    $before = Get-ModalReport
    if ($null -ne $before) { throw "iter ${i}: stale modal '$before' before ruler" }
    Call-Op 'tools.measure_distance'
    Frames 5
    $modal_before = Get-ModalReport
    if ($i -eq 1) { Shot "ruler-active-$i" }
    $fg_ok = Focus-ByClick $hwnd
    Send-Esc
    Frames 15
    $modal_after = Get-ModalReport
    $tool_after = Get-ActiveTool
    $ok = ($modal_before -eq 'tools.measure_distance') -and ($null -eq $modal_after) -and ($tool_after -match 'Select') -and $fg_ok
    Log-Metric "ruler-Esc,$i,$modal_before,$modal_after,$tool_after,$fg_ok,$ok"
    if (-not $ok) { $failures += "ruler-Esc iter $i" }
}

# ---------- case 2: ruler RMB ----------
for ($i = 1; $i -le $Repeat; $i++) {
    Reset-Modal; Frames 5
    Call-Op 'tools.measure_distance'
    Frames 5
    $modal_before = Get-ModalReport
    $null = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
    Start-Sleep -Milliseconds 150
    Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
    Start-Sleep -Milliseconds 100
    Send-RmbDown
    Start-Sleep -Milliseconds 200
    Send-RmbUp
    Frames 15
    $modal_after = Get-ModalReport
    $tool_after = Get-ActiveTool
    $ok = ($modal_before -eq 'tools.measure_distance') -and ($null -eq $modal_after) -and ($tool_after -match 'Select')
    Log-Metric "ruler-RMB,$i,$modal_before,$modal_after,$tool_after,,ok=$ok"
    if (-not $ok) { $failures += "ruler-RMB iter $i" }
}

# ---------- case 3: draw brush Add, Escape (the fixed dead path) ----------
Reset-Modal; Frames 5
Call-Op 'viewport.draw_brush_modal' @{ mode = 'Add' }
Frames 5
$modal_before = Get-ModalReport
$fg_ok = Focus-ByClick $hwnd
Send-Esc
Frames 15
$modal_after = Get-ModalReport
$ok = ($modal_before -eq 'viewport.draw_brush_modal') -and ($null -eq $modal_after) -and $fg_ok
Log-Metric "drawAdd-Esc,1,$modal_before,$modal_after,,$fg_ok,$ok"
if (-not $ok) { $failures += "drawAdd-Esc" }

# ---------- case 4: draw brush Cut, RMB (regression) ----------
Reset-Modal; Frames 5
Call-Op 'viewport.draw_brush_modal' @{ mode = 'Cut' }
Frames 5
$modal_before = Get-ModalReport
$null = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
Start-Sleep -Milliseconds 150
Send-RmbDown; Start-Sleep -Milliseconds 200; Send-RmbUp
Frames 15
$modal_after = Get-ModalReport
$ok = ($modal_before -eq 'viewport.draw_brush_modal') -and ($null -eq $modal_after)
Log-Metric "drawCut-RMB,1,$modal_before,$modal_after,,,ok=$ok"
if (-not $ok) { $failures += "drawCut-RMB" }

# ---------- case 5: no modal, Esc is a no-op; ActiveTool over BRP ----------
Reset-Modal; Frames 5
Call-Op 'tool.rotate'
Frames 5
$tool_rotate = Get-ActiveTool
$fg_ok = Focus-ByClick $hwnd
Send-Esc
Frames 15
$modal_after_esc = Get-ModalReport
$tool_after_esc = Get-ActiveTool
Call-Op 'tool.select'
Frames 5
$tool_select = Get-ActiveTool
$ok = ($tool_rotate -match 'Rotate') -and ($null -eq $modal_after_esc) `
    -and ($tool_after_esc -match 'Rotate') -and ($tool_select -match 'Select') -and $fg_ok
Log-Metric "toolState,1,null,$modal_after_esc,$tool_after_esc,$fg_ok,ok=$ok"
if (-not $ok) { $failures += "toolState" }
Shot "final"

if ($failures.Count -gt 0) { throw "QA failures: $($failures -join '; ')" }
Write-Host "ALL QA CASES PASS"
if (-not $LeaveRunning) {
    Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
}
