# T2 supplement, attempt 6 (final, focused): warm the brush caches with a
# Vertex->Face pass first (s5's cold Face entry never started the face-drag
# modal; s4's warm session did), then T9 Esc-restore, V8 with click variants
# on the Filter input, T10 behavioral probe on the warmed state.
# CSV: loop/reports/t01-t2-supplement/<Label>/metrics.csv
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [string]$Label = 's6',
    [double]$DpiScale = 1.5
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot "..\reports\t01-t2-supplement\$Label"
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')
$script:Vk['Digit1'] = 0x31; $script:Vk['Digit3'] = 0x33

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
function Get-Fly { Get-BoolResource 'jackdaw::viewport::CameraFlyActive' }
function Get-Pan { Get-BoolResource 'jackdaw::viewport::CameraPanActive' }
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
function Get-Cam {
    $c = Get-FlyCamera
    [PSCustomObject]@{
        Entity = $c.Entity
        X = [double]$c.Position['x']; Y = [double]$c.Position['y']; Z = [double]$c.Position['z']
        Yaw = [double]$c.Yaw; Pitch = [double]$c.Pitch
    }
}
function Cam-Dist($a, $b) {
    [Math]::Sqrt([Math]::Pow($a.X - $b.X, 2) + [Math]::Pow($a.Y - $b.Y, 2) + [Math]::Pow($a.Z - $b.Z, 2))
}
function Get-FlyCamEnabled {
    $cam = Get-Cam
    $path = 'jackdaw_camera::JackdawCameraSettings'
    $r = Brp-Result (Brp-Call 'world.get_components' @{ entity = $cam.Entity; components = @($path) })
    return [bool]$r.components.$path.enabled
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
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
"@
function Take-Foreground {
    param([Parameter(Mandatory = $true)][IntPtr]$Hwnd)
    foreach ($attempt in 1..3) {
        $fg = [Fg]::GetForegroundWindow()
        if ($fg -eq $Hwnd) { return $true }
        $fgPid = 0
        $fgThread = [Fg]::GetWindowThreadProcessId($fg, [ref]$fgPid)
        $thisThread = [Fg]::GetCurrentThreadId()
        [Fg]::AttachThreadInput($thisThread, $fgThread, $true) | Out-Null
        [Fg]::SetForegroundWindow($Hwnd) | Out-Null
        [Fg]::AttachThreadInput($thisThread, $fgThread, $false) | Out-Null
        Start-Sleep -Milliseconds 300
        if ([Fg]::GetForegroundWindow() -eq $Hwnd) { return $true }
        $null = Set-CursorToWindowPoint $Hwnd 0.5 0.01
        Start-Sleep -Milliseconds 150
        [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
        Start-Sleep -Milliseconds 500
        if ([Fg]::GetForegroundWindow() -eq $Hwnd) { return $true }
    }
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
    [Fg]::ShowWindow($script:Hwnd, 3) | Out-Null
    Start-Sleep -Milliseconds 800
    $fgOk = Take-Foreground $script:Hwnd
    $r = New-Object JdInput+RECT
    [JdInput]::GetWindowRect($script:Hwnd, [ref]$r) | Out-Null
    $physW = [double]($r.R - $r.L); $physH = [double]($r.B - $r.T)
    $cx = [Math]::Floor($physW / 2 / $DpiScale)
    $cy = [Math]::Floor($physH / 2 / $DpiScale)
    $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
    Start-Sleep -Milliseconds 300
    Log-Case 'setup' 'window' 'INFO' ("hwnd={0} fg={1} center=({2},{3})" -f $script:Hwnd, $fgOk, $cx, $cy)

    # ---- warm-up: Vertex pass (builds brush caches), then Face --------------
    Syn-ClickAt $cx $cy
    Syn-Key 'Digit1'; Frames 30; Start-Sleep -Milliseconds 1200     # Vertex, caches build
    $emWarm = Get-EditModeRaw
    Syn-Key 'Escape'; Frames 5                                        # exit (+deselect)
    Syn-ClickAt $cx $cy
    Syn-Key 'Digit3'; Frames 30; Start-Sleep -Milliseconds 1200     # Face, warm
    $emF = Get-EditModeRaw
    Log-Case 'setup' 'warm' 'INFO' "vertex=$emWarm face=$emF"

    # helper: press-and-verify-modal with two candidate points
    function Try-Press([double]$X, [double]$Y) {
        Syn-Pointer @{ x = $X; y = $Y; action = 'press' }
        Frames 5; Start-Sleep -Milliseconds 150
        return (Get-Modal)
    }

    # ---- T9: Esc mid-flight restore -----------------------------------------
    $bsn0 = Get-SceneBsn
    $mD = Try-Press $cx $cy
    if (-not $mD) { $mD = Try-Press ($cx + 60) ($cy + 40) }
    if (-not $mD) { $mD = Try-Press ($cx - 60) ($cy - 40) }
    if (-not $mD) {
        Log-Case 'T9' 'face-esc' 'BLOCKED' "face drag modal never started (warm=$emF)"
    } else {
        Syn-Pointer @{ x = ($cx + 300); y = $cy; action = 'move' }
        Frames 8
        $bsnMid = Get-SceneBsn
        $mutating = ($bsnMid -ne $bsn0)
        Log-Case 'T9' 'mid' 'INFO' "modal='$mD' mutatingMidDrag=$mutating"
        if (-not $mutating) {
            Syn-Pointer @{ x = ($cx + 600); y = $cy; action = 'move' }
            Frames 8
            $mutating = ((Get-SceneBsn) -ne $bsn0)
            Log-Case 'T9' 'mid' 'INFO' "after +600: mutating=$mutating"
        }
        if ($mutating) {
            Syn-Key 'Escape'
            Frames 10
            Syn-Pointer @{ x = ($cx + 600); y = $cy; action = 'release' }
            Frames 10; Start-Sleep -Milliseconds 400
            $bsn2 = Get-SceneBsn
            $mAfter = Get-Modal
            $ok9 = ($bsn2 -eq $bsn0) -and ($null -eq $mAfter)
            Log-Case 'T9' 'face-esc' ($(if ($ok9) { 'PASS' } else { 'FAIL' })) "mutating mid-drag; after Esc: restored=$($bsn2 -eq $bsn0) modal='$mAfter'"
        } else {
            Syn-Pointer @{ x = $cx; y = $cy; action = 'release' }
            Frames 8
            Log-Case 'T9' 'face-esc' 'BLOCKED' 'drag never mutated (modal started but promotion refused)'
        }
        Reset-Modal; Frames 3
    }

    # ---- V8: Filter input with click variants -------------------------------
    if ((Get-EditModeRaw) -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
    Syn-ClickAt $cx $cy
    Frames 20; Start-Sleep -Milliseconds 500
    $UiTextPath = 'bevy_ui::widget::text::Text'
    $UiNodePath = 'bevy_ui::ui_node::ComputedNode'
    $UiGtPath = 'bevy_ui::ui_transform::UiGlobalTransform'
    $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($UiTextPath, $UiNodePath, $UiGtPath) } })
    $filter = $null
    foreach ($row in $rows) {
        $c = $row.components
        if ($null -eq $c.$UiGtPath) { continue }
        $size = $c.$UiNodePath.size
        if ([double]$size[0] -le 0) { continue }
        if ([string]$c.$UiTextPath -match 'Filter') {
            $filter = [pscustomobject]@{ cx = [double]$c.$UiGtPath[4]; cy = [double]$c.$UiGtPath[5]; w = [double]$size[0]; h = [double]$size[1] }
            break
        }
    }
    if (-not $filter) {
        Log-Case 'V8' 'target' 'BLOCKED' 'Filter row not found'
    } else {
        Log-Case 'V8' 'target' 'INFO' ("Filter at ({0:N0},{1:N0}) {2:N0}x{3:N0} physical" -f $filter.cx, $filter.cy, $filter.w, $filter.h)
        $focus1 = $null
        foreach ($variant in @('mid', 'right', 'dbl')) {
            if ($variant -eq 'mid') { $vx = $filter.cx / $DpiScale; $vy = $filter.cy / $DpiScale; Syn-ClickAt $vx $vy }
            elseif ($variant -eq 'right') { $vx = ($filter.cx + 80) / $DpiScale; $vy = $filter.cy / $DpiScale; Syn-ClickAt $vx $vy }
            else { $vx = ($filter.cx + 40) / $DpiScale; $vy = $filter.cy / $DpiScale; Syn-Pointer @{ x = $vx; y = $vy; action = 'dblclick' }; Frames 10; Start-Sleep -Milliseconds 300 }
            $f = Get-FocusEntity
            Log-Case 'V8' 'variant' 'INFO' ("{0} at ({1:N0},{2:N0}): focus={3}" -f $variant, $vx, $vy, $f)
            if ($f -ne 'null' -and $f -ne 'unavailable' -and $null -ne $f) {
                Syn-Pointer @{ x = $cx; y = $cy; action = 'move' }
                Frames 5
                $en = Get-FlyCamEnabled
                Log-Case 'V8' 'oracle' 'INFO' "focused; camera enabled after viewport hover=$en"
                if (-not $en) { $focus1 = $f; break }
            }
        }
        if (-not $focus1) {
            Log-Case 'V8' 'focus' 'BLOCKED' 'no variant focused a keyboard-holding field'
        } else {
            Log-Case 'V8' 'focus' 'PASS' "field focused and typing gates the camera"
            Syn-Pointer @{ x = $cx; y = $cy; action = 'press'; button = 'secondary' }
            Frames 5
            $flyRmb = Get-Fly
            Syn-Pointer @{ x = $cx; y = $cy; action = 'release'; button = 'secondary' }
            Frames 3
            Log-Case 'V8' 'rmb' ($(if (-not $flyRmb) { 'PASS' } else { 'FAIL' })) "fly=$flyRmb while typing"
            $cam0 = Get-Cam
            Call-Op 'input.key' @{ key = 'KeyW'; action = 'press' }
            Frames 30
            Call-Op 'input.key' @{ key = 'KeyW'; action = 'release' }
            Frames 5
            $moved = Cam-Dist $cam0 (Get-Cam)
            Log-Case 'V8' 'wasd' ($(if ($moved -lt 0.005) { 'PASS' } else { 'FAIL' })) ("W moved={0:N4} while typing" -f $moved)
            $cam0 = Get-Cam
            Syn-Pointer @{ x = $cx; y = $cy; action = 'scroll'; lines = 3 }
            Frames 8
            $moved = Cam-Dist $cam0 (Get-Cam)
            Log-Case 'V8' 'wheel' ($(if ($moved -lt 0.005) { 'PASS' } else { 'FAIL' })) ("wheel moved={0:N4} while typing" -f $moved)
            Reset-Modal; Frames 3
            Syn-ClickAt $cx $cy        # blur via viewport click
            Call-Op 'tools.measure_distance'; Frames 8
            $mStart = Get-Modal
            $win = $null
            if ($variant -eq 'mid') { $win = 'mid' } elseif ($variant -eq 'right') { $win = 'right' } else { $win = 'dbl' }
            if ($win -eq 'mid') { Syn-ClickAt ($filter.cx / $DpiScale) ($filter.cy / $DpiScale) }
            elseif ($win -eq 'right') { Syn-ClickAt (($filter.cx + 80) / $DpiScale) ($filter.cy / $DpiScale) }
            else { Syn-ClickAt (($filter.cx + 40) / $DpiScale) ($filter.cy / $DpiScale) }
            $fTyping = Get-FocusEntity
            if ($fTyping -ne $focus1) {
                Log-Case 'V8' 'r1' 'BLOCKED' ("modal='{0}'; refocus gave {1}" -f $mStart, $fTyping)
            } else {
                Syn-Key 'Escape'; Frames 5
                $fEsc1 = Get-FocusEntity
                $mEsc1 = Get-Modal
                Syn-Key 'Escape'; Frames 5
                $mEsc2 = Get-Modal
                $okR1 = ($mStart -eq 'tools.measure_distance') -and ($mEsc1 -ne $null) -and ($null -eq $mEsc2) -and ($fEsc1 -ne $focus1)
                Log-Case 'V8' 'r1' ($(if ($okR1) { 'PASS' } else { 'FAIL' })) ("modal='{0}' esc1: modal='{1}' focus={2} esc2: modal='{3}'" -f $mStart, $mEsc1, $fEsc1, $mEsc2)
                Reset-Modal; Frames 3
            }
            Syn-Pointer @{ x = $cx; y = $cy; action = 'press'; button = 'secondary' }
            Frames 5
            $flyAfter = Get-Fly
            Syn-Pointer @{ x = $cx; y = $cy; action = 'release'; button = 'secondary' }
            Frames 3
            Log-Case 'V8' 'probe' ($(if ($flyAfter) { 'PASS' } else { 'FAIL' })) "fly=$flyAfter after blur"
        }
    }

    # ---- T10: behavioral probe on the warmed state ---------------------------
    Reset-Modal; Frames 3
    Call-Op 'tool.translate'; Frames 5
    if ((Get-EditModeRaw) -notmatch 'Face') {
        Syn-ClickAt $cx $cy
        Syn-Key 'Digit3'; Frames 30; Start-Sleep -Milliseconds 1200
    }
    $emF2 = Get-EditModeRaw
    $px = $cx + 60; $py = $cy + 40
    $mProbe = Try-Press $px $py
    if (-not $mProbe) { $px = $cx; $py = $cy; $mProbe = Try-Press $px $py }
    if (-not $mProbe) {
        Log-Case 'T10' 'fixture' 'BLOCKED' ("face drag unavailable for the probe (mode=$emF2)")
    } else {
        Syn-Pointer @{ x = $px; y = $py; action = 'release' }
        Frames 5
        function Probe-Drag {
            $base = Get-SceneBsn
            Syn-Pointer @{ x = $px; y = $py; action = 'press' }
            Frames 5
            Syn-Pointer @{ x = ($px + 80); y = $py; action = 'move' }
            Frames 8
            Syn-Pointer @{ x = ($px + 90); y = $py; action = 'release' }
            Frames 10; Start-Sleep -Milliseconds 300
            $changed = ((Get-SceneBsn) -ne $base)
            if ($changed) { Call-Op 'history.undo'; Frames 10; Start-Sleep -Milliseconds 300 }
            return $changed
        }
        $q0 = Probe-Drag
        Log-Case 'T10' 'baseline' 'INFO' "sub-quantum drag changed=$q0"
        Syn-Pointer @{ x = $cx; y = $cy; action = 'click'; button = 'middle' }
        Frames 10; Start-Sleep -Milliseconds 400
        $q1 = Probe-Drag
        Log-Case 'T10' 'mm-click' ($(if ($q1 -ne $q0) { 'PASS' } else { 'FAIL' })) "readout $q0 -> $q1 (stationary MMB must toggle)"
        $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
        Start-Sleep -Milliseconds 200
        $cam0 = Get-Cam
        [JdInput]::MmbDown(); Start-Sleep -Milliseconds 150
        $panDuring = $false; $flyDuring = $false
        for ($i = 1; $i -le 20; $i++) {
            Send-MoveRel 15 0; Start-Sleep -Milliseconds 16
            if ($i -eq 10) { $panDuring = Get-Pan; $flyDuring = Get-Fly }
        }
        $cam1 = Get-Cam
        [JdInput]::MmbUp(); Start-Sleep -Milliseconds 400; Frames 5
        $panLen = Cam-Dist $cam0 $cam1
        $q2 = Probe-Drag
        $readoutStable = ($q2 -eq $q1)
        $osOk = $panDuring -and (-not $flyDuring) -and ($panLen -gt 0.1)
        Log-Case 'T10' 'mm-drag' ($(if ($readoutStable -and $osOk) { 'PASS' } else { 'FAIL' })) ("pan={0} fly={1} moved={2:N2} readout {3} -> {4}" -f $panDuring, $flyDuring, $panLen, $q1, $q2)
        Syn-Pointer @{ x = $cx; y = $cy; action = 'click'; button = 'middle' }
        Frames 10; Start-Sleep -Milliseconds 400
        $q3 = Probe-Drag
        Log-Case 'T10' 'mm-click2' ($(if ($q3 -eq $q0) { 'PASS' } else { 'FAIL' })) "readout $q1 -> $q3 (expect baseline $q0)"
    }

    Write-Host "SUPPLEMENT6 DONE -> $csv"
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
