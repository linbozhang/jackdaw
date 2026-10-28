# T2 supplement diagnostics: pin the Esc-then-digit reentry failure, the
# face-drag motion channel, the text-field focus channel and the toolbar
# variant channel. One session, four sections, heavy per-step logging.
# CSV: loop/reports/t01-t2-supplement/<Label>/metrics.csv
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [string]$Label = 's2',
    [double]$DpiScale = 1.5
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot "..\reports\t01-t2-supplement\$Label"
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')
$script:Vk['Digit3'] = 0x33; $script:Vk['Digit4'] = 0x34; $script:Vk['M'] = 0x4D

$csv = Join-Path $OutDir 'metrics.csv'
"case,iter,result,detail" | Set-Content -Path $csv -Encoding UTF8
function Log-Case {
    param([string]$Case, [string]$Iter, [string]$Result, [string]$Detail)
    $line = "$Case,$Iter,$Result,`"$Detail`""
    Add-Content -Path $csv -Encoding UTF8 -Value $line
    Write-Host $line
}
function Frames([int]$n) { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } | Out-Null }
function Call-Op {
    param([string]$Id, $OpParams = @{})
    $p = @{ id = $Id; history = $false }
    if ($OpParams.Count -gt 0) { $p.params = $OpParams }
    Brp-Result (Brp-Call 'jackdaw/call_operator' $p) | Out-Null
}
function Get-Modal { (Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30).modal }
function Reset-Modal { try { Brp-Result (Brp-Call 'jackdaw/cancel' @{}) | Out-Null } catch { } }
function Syn-Pointer($Params) { Call-Op 'input.pointer' $Params }
function Syn-ClickAt([double]$X, [double]$Y) {
    Syn-Pointer @{ x = $X; y = $Y; action = 'click' }
    Frames 8; Start-Sleep -Milliseconds 300
}
function Syn-Key([string]$Key) {
    Call-Op 'input.key' @{ key = $Key }
    Frames 6; Start-Sleep -Milliseconds 150
}
function Get-EditModeRaw {
    $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'jackdaw::brush::EditMode' })
    return ($r.value | ConvertTo-Json -Compress -Depth 8)
}
function Get-FocusEntity {
    try {
        $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_input_focus::InputFocus' })
        $v = $r.value
        if ($null -eq $v) { return $null }
        $p = $v.PSObject.Properties['current_focus']
        if ($p -and $null -ne $p.Value) { return ([string]($p.Value | ConvertTo-Json -Compress)) }
        return 'null'
    } catch { return 'unavailable' }
}
function Get-SceneBsn {
    $r = (Brp-Call 'jackdaw/scene_bsn' @{}).result
    if ($r -is [string]) { return $r }
    return [string]$r.bsn
}
function Get-BoolResource {
    param([Parameter(Mandatory = $true)][string]$Path)
    $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = $Path })
    $v = $r.value
    if ($v -is [bool]) { return $v }
    if ($v -is [System.Array]) { return [bool]$v[0] }
    $first = $v.PSObject.Properties | Select-Object -First 1
    if ($first) { return [bool]$first.Value }
    throw "unrecognized value shape for ${Path}"
}
function Get-Pan { Get-BoolResource 'jackdaw::viewport::CameraPanActive' }
# Window cursor position (logical px) via the Window component.
$WinPath = 'bevy_window::window::Window'
function Get-CursorPos {
    $r = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($WinPath) }; filter = @{ with = @($WinPath) } })
    foreach ($row in $r) { return $row.components.$WinPath.cursor_position }
    return $null
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
}
"@
function Keep-Foreground {
    param([Parameter(Mandatory = $true)][IntPtr]$Hwnd)
    $fg = [Fg]::GetForegroundWindow()
    if ($fg -eq $Hwnd) { return $true }
    $fgPid = 0
    $fgThread = [Fg]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    $thisThread = [Fg]::GetCurrentThreadId()
    [Fg]::AttachThreadInput($thisThread, $fgThread, $true) | Out-Null
    [Fg]::SetForegroundWindow($Hwnd) | Out-Null
    [Fg]::AttachThreadInput($thisThread, $fgThread, $false) | Out-Null
    Start-Sleep -Milliseconds 250
    return ([Fg]::GetForegroundWindow() -eq $Hwnd)
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
try {
    Wait-EditorReady -TimeoutSec 180
    foreach ($try in 1..6) {
        try { Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null; break }
        catch { Start-Sleep -Seconds 2 }
    }
    Frames 10
    Start-Sleep -Seconds 3
    $script:Hwnd = Get-JackdawHwnd
    Keep-Foreground $script:Hwnd | Out-Null
    $r = New-Object JdInput+RECT
    [JdInput]::GetWindowRect($script:Hwnd, [ref]$r) | Out-Null
    $cx = [Math]::Floor([double](($r.L + $r.R) / 2) / $DpiScale)
    $cy = [Math]::Floor([double](($r.T + $r.B) / 2) / $DpiScale)
    Log-Case 'setup' 'window' 'INFO' ("hwnd={0} rect=({1},{2},{3},{4}) logical center=({5},{6}) fg={7}" -f $script:Hwnd, $r.L, $r.T, $r.R, $r.B, $cx, $cy, ([Fg]::GetForegroundWindow() -eq $script:Hwnd))

    # ---- A: Esc-then-digit reentry mechanism --------------------------------
    Log-Case 'A' 'focus0' 'INFO' "startup focus=$(Get-FocusEntity) cursor=$(Get-CursorPos | ConvertTo-Json -Compress)"
    Syn-ClickAt $cx $cy
    Log-Case 'A' 'click' 'INFO' "focus after viewport click=$(Get-FocusEntity) cursor=$(Get-CursorPos | ConvertTo-Json -Compress)"
    Syn-Key 'Digit4'; Frames 3
    $em1 = Get-EditModeRaw
    Log-Case 'A' 'd4' 'INFO' "mode=$em1 focus=$(Get-FocusEntity)"
    Syn-Key 'Escape'; Frames 3
    $em2 = Get-EditModeRaw
    $f2 = Get-FocusEntity
    Log-Case 'A' 'esc' 'INFO' "mode=$em2 focus=$f2  <-- KEY DATUM"
    Syn-Key 'Digit4'; Frames 3
    $em3 = Get-EditModeRaw
    Log-Case 'A' 'd4-again' 'INFO' "mode=$em3 focus=$(Get-FocusEntity)"
    Start-Sleep -Seconds 1
    Syn-Key 'Digit4'; Frames 3
    $em4 = Get-EditModeRaw
    Log-Case 'A' 'd4-late' 'INFO' "mode=$em4 focus=$(Get-FocusEntity)"
    Reset-Modal; Frames 3
    Syn-Key 'Digit4'; Frames 3
    $em5 = Get-EditModeRaw
    Log-Case 'A' 'd4-cancel' 'INFO' "mode=$em5 focus=$(Get-FocusEntity)"
    Syn-ClickAt $cx $cy
    Syn-Key 'Digit4'; Frames 3
    $em6 = Get-EditModeRaw
    Log-Case 'A' 'd4-click' 'INFO' "mode=$em6 focus=$(Get-FocusEntity)"
    if ($em6 -match 'Clip') { Syn-Key 'Escape'; Frames 3 }

    # ---- B: face drag motion channel ----------------------------------------
    Syn-ClickAt $cx $cy
    Syn-Key 'Digit3'; Frames 5
    $emF = Get-EditModeRaw
    if ($emF -notmatch 'Face') {
        Log-Case 'B' 'enter' 'BLOCKED' "Digit3 -> $emF"
    } else {
        $bsn0 = Get-SceneBsn
        Syn-Pointer @{ x = $cx; y = $cy; action = 'press' }
        Frames 5
        $mD = Get-Modal
        $cur1 = Get-CursorPos
        Syn-Pointer @{ x = ($cx + 200); y = $cy; action = 'move' }
        Frames 5
        $cur2 = Get-CursorPos
        $bsnMid = Get-SceneBsn
        Syn-Pointer @{ x = ($cx + 300); y = $cy; action = 'release' }
        Frames 8; Start-Sleep -Milliseconds 400
        $bsn1 = Get-SceneBsn
        Log-Case 'B' 'syn-drag' 'INFO' ("modal={0} cursor {1} -> {2} bsnChangedMid={3} bsnChanged={4}" -f $mD, ($cur1 | ConvertTo-Json -Compress), ($cur2 | ConvertTo-Json -Compress), ($bsnMid -ne $bsn0), ($bsn1 -ne $bsn0))
        # OS relative moves during a held press: does the cursor move at all?
        Syn-Pointer @{ x = $cx; y = $cy; action = 'press' }
        Frames 5
        $mD2 = Get-Modal
        $cur3 = Get-CursorPos
        foreach ($i in 1..20) { Send-MoveRel 15 0; Start-Sleep -Milliseconds 16 }
        Frames 3
        $cur4 = Get-CursorPos
        $bsnMid2 = Get-SceneBsn
        [JdInput]::LmbUp()
        Frames 8; Start-Sleep -Milliseconds 400
        $bsn2 = Get-SceneBsn
        Log-Case 'B' 'os-drag' 'INFO' ("modal={0} cursor {1} -> {2} bsnChangedMid={3} bsnChanged={4}" -f $mD2, ($cur3 | ConvertTo-Json -Compress), ($cur4 | ConvertTo-Json -Compress), ($bsnMid2 -ne $bsn1), ($bsn2 -ne $bsn1))
        Syn-Key 'Escape'; Frames 3
        if ((Get-EditModeRaw) -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
    }

    # ---- C: text field focus channel ----------------------------------------
    Syn-ClickAt $cx $cy
    $UiTextPath = 'bevy_ui::widget::text::Text'
    $UiNodePath = 'bevy_ui::ui_node::ComputedNode'
    $UiGtPath = 'bevy_ui::ui_transform::UiGlobalTransform'
    $params = @{ data = @{ components = @($UiTextPath, $UiNodePath, $UiGtPath) } }
    $rows = Brp-Result (Brp-Call 'world.query' $params)
    $maxX = 0.0
    $uiRows = @()
    foreach ($row in $rows) {
        $c = $row.components
        if ($null -eq $c.$UiGtPath) { continue }
        $size = $c.$UiNodePath.size
        if ([double]$size[0] -le 0 -or [double]$size[1] -le 0) { continue }
        $a = $c.$UiGtPath
        $t = [string]$c.$UiTextPath
        $uiRows += [pscustomobject]@{
            cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$size[0]; h = [double]$size[1]
            text = $t
        }
        if ([double]$a[4] -gt $maxX) { $maxX = [double]$a[4] }
    }
    Log-Case 'C' 'rows' 'INFO' ("text rows: {0}; maxX={1:N0}" -f @($uiRows).Count, $maxX)
    $right = $uiRows | Where-Object { $_.cx -gt ($maxX * 0.55) } | Sort-Object cy
    foreach ($row in @($right)) {
        $t = $row.text; if ($t.Length -gt 24) { $t = $t.Substring(0, 24) }
        Log-Case 'C' 'right-row' 'INFO' ("({0:N0},{1:N0}) {2}x{3} '{4}'" -f $row.cx, $row.cy, $row.w, $row.h, $t)
    }
    $focused = $false
    $fx = 0.0; $fy = 0.0
    foreach ($row in @($right) | Select-Object -First 4) {
        $fx = [double]$row.cx / $DpiScale; $fy = [double]$row.cy / $DpiScale
        Syn-ClickAt $fx $fy
        $f = Get-FocusEntity
        Log-Case 'C' 'click' 'INFO' ("click ({0:N0},{1:N0}) '{2}' -> focus={3}" -f $fx, $fy, $row.text, $f)
        if ($f -ne 'null' -and $f -ne 'unavailable' -and $null -ne $f) { $focused = $true; break }
        # try a double click too (scrubber focuses on release; entry may need dbl)
        Syn-Pointer @{ x = $fx; y = $fy; action = 'dblclick' }
        Frames 8; Start-Sleep -Milliseconds 300
        $f = Get-FocusEntity
        Log-Case 'C' 'dblclick' 'INFO' ("dblclick ({0:N0},{1:N0}) -> focus={2}" -f $fx, $fy, $f)
        if ($f -ne 'null' -and $f -ne 'unavailable' -and $null -ne $f) { $focused = $true; break }
    }
    Log-Case 'C' 'result' ($(if ($focused) { 'PASS' } else { 'BLOCKED' })) "text field focusable=$focused"

    # ---- D: toolbar variant channel -----------------------------------------
    Reset-Modal; Frames 3
    Call-Op 'tool.translate'; Frames 5
    $VariantPaths = @('bevy_feathers::controls::ButtonVariant', 'bevy_feathers::controls::button::ButtonVariant')
    $vpath = $null
    foreach ($p in $VariantPaths) {
        try {
            $null = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($p) }; filter = @{ with = @($p) } })
            $vpath = $p; break
        } catch { }
    }
    if (-not $vpath) {
        Log-Case 'D' 'path' 'BLOCKED' 'ButtonVariant not queryable'
    } else {
        function Get-Variants {
            $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($vpath) }; filter = @{ with = @($vpath) } })
            $map = @{}
            foreach ($row in $rows) {
                $v = $row.components.$vpath
                $text = if ($v -is [string]) { $v } else { [string]($v | ConvertTo-Json -Compress) }
                $map[[string]$row.entity] = $text
            }
            return $map
        }
        $va = Get-Variants
        Log-Case 'D' 'snapshot' 'INFO' ("path={0} entities={1}" -f $vpath, $va.Count)
        # KeyM keybind dispatch (announces through the action layer)
        Syn-Key 'KeyM'; Frames 10; Start-Sleep -Milliseconds 400
        $vb = Get-Variants
        $changed = @()
        foreach ($k in $va.Keys) { if ($vb.ContainsKey($k) -and $va[$k] -ne $vb[$k]) { $changed += ('{0}:{1}->{2}' -f $k, $va[$k], $vb[$k]) } }
        Log-Case 'D' 'keym' 'INFO' ("KeyM changed {0}: {1}" -f @($changed).Count, ($changed -join ' | '))
        # call_operator path
        Call-Op 'snap.toggle'; Frames 10; Start-Sleep -Milliseconds 400
        $vc = Get-Variants
        $changed2 = @()
        foreach ($k in $vb.Keys) { if ($vc.ContainsKey($k) -and $vb[$k] -ne $vc[$k]) { $changed2 += ('{0}:{1}->{2}' -f $k, $vb[$k], $vc[$k]) } }
        Log-Case 'D' 'op' 'INFO' ("snap.toggle changed {0}: {1}" -f @($changed2).Count, ($changed2 -join ' | '))
        # OS channel aliveness: MMB click at viewport center
        Keep-Foreground $script:Hwnd | Out-Null
        $cur5 = Get-CursorPos
        $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
        Start-Sleep -Milliseconds 200
        foreach ($i in 1..5) { Send-MoveRel 10 0; Start-Sleep -Milliseconds 16 }
        Frames 3
        $cur6 = Get-CursorPos
        Log-Case 'D' 'os-move' 'INFO' ("OS MoveRel cursor {0} -> {1}" -f ($cur5 | ConvertTo-Json -Compress), ($cur6 | ConvertTo-Json -Compress))
        # MMB stationary click -> variant flip?
        $vd0 = Get-Variants
        [JdInput]::MmbDown(); Start-Sleep -Milliseconds 120; [JdInput]::MmbUp()
        Start-Sleep -Milliseconds 400; Frames 5
        $vd1 = Get-Variants
        $changed3 = @()
        foreach ($k in $vd0.Keys) { if ($vd1.ContainsKey($k) -and $vd0[$k] -ne $vd1[$k]) { $changed3 += ('{0}:{1}->{2}' -f $k, $vd0[$k], $vd1[$k]) } }
        Log-Case 'D' 'os-mmb-click' 'INFO' ("stationary MMB changed {0}: {1}" -f @($changed3).Count, ($changed3 -join ' | '))
    }

    Write-Host "DIAG DONE -> $csv"
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}

