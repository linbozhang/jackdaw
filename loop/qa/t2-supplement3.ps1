# T2 supplement, attempt 3: the four cells with the channel fixes pinned by
# the s1/s2 diagnostics:
#  - foreground via AttachThreadInput then a title-bar click fallback (OS
#    clicks need the editor foregrounded in this agent session);
#  - the real OS cursor is parked over the viewport so Window.cursor_position
#    stays alive (ViewportCursor / face drag / pan all read it);
#  - T10 signal = BackgroundColor diff calibrated by KeyM (the feathers theme
#    writes it from the ButtonVariant; ButtonVariant itself queried 0 rows);
#  - V8 field identification = click candidate, then the camera gate is the
#    is_typing oracle (focused entity holds the keyboard <=> enabled=false).
# CSV: loop/reports/t01-t2-supplement/<Label>/metrics.csv
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [string]$Label = 's3',
    [double]$DpiScale = 1.5
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot "..\reports\t01-t2-supplement\$Label"
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')
$script:Vk['Digit3'] = 0x33; $script:Vk['Digit4'] = 0x34

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
    # click fallback: a (real) click on the title bar raises the window.
    $null = Set-CursorToWindowPoint $Hwnd 0.5 0.01
    Start-Sleep -Milliseconds 150
    [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
    Start-Sleep -Milliseconds 500
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
    # maximize: the default 1280x720 window clips the right-side panels
    # (s2 measured Inspector text at physical x > 1280). Maximize is not the
    # minimize/restore cycle that kills cursor_position.
    [Fg]::ShowWindow($script:Hwnd, 3) | Out-Null
    Start-Sleep -Milliseconds 800
    $fgOk = Take-Foreground $script:Hwnd
    $r = New-Object JdInput+RECT
    [JdInput]::GetWindowRect($script:Hwnd, [ref]$r) | Out-Null
    $cx = [Math]::Floor([double](($r.L + $r.R) / 2) / $DpiScale)
    $cy = [Math]::Floor([double](($r.T + $r.B) / 2) / $DpiScale)
    # park the real cursor over the viewport for the whole session
    $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
    Start-Sleep -Milliseconds 300
    Log-Case 'setup' 'window' 'INFO' ("hwnd={0} fg={1} rect=({2},{3},{4},{5}) center=({6},{7})" -f $script:Hwnd, $fgOk, $r.L, $r.T, $r.R, $r.B, $cx, $cy)

    # alive probe: synthetic RMB over the viewport must engage fly (hover +
    # camera gate alive). This is also the L1 activation probe rule for the
    # negative cells below.
    Syn-Pointer @{ x = $cx; y = $cy; action = 'press'; button = 'secondary' }
    Frames 5
    $probeFly = Get-Fly
    Syn-Pointer @{ x = $cx; y = $cy; action = 'release'; button = 'secondary' }
    Frames 3
    Log-Case 'setup' 'probe' ($(if ($probeFly) { 'PASS' } else { 'FAIL' })) "synthetic RMB engages fly=$probeFly"
    if (-not $probeFly) {
        Log-Case 'setup' 'probe' 'BLOCKED' 'cursor channel dead; negatives below would be INVALID'
    }

    # ---- T3/T4: real-key entry + Esc semantics (s1 PASS, rerun for record) -
    Syn-ClickAt $cx $cy
    Syn-Key 'Digit4'; Frames 5
    $em1 = Get-EditModeRaw
    Syn-Key 'Escape'; Frames 5
    $em2 = Get-EditModeRaw
    $ok3 = ($em1 -match 'Clip') -and ($em2 -match 'Object')
    Log-Case 'T3' 1 ($(if ($ok3) { 'PASS' } else { 'FAIL' })) "d4=$em1 esc=$em2 (Esc also deselects: next entry needs a click; s2-A evidence)"
    Syn-ClickAt $cx $cy
    Syn-Key 'KeyK'; Frames 5
    $em1 = Get-EditModeRaw
    Syn-ClickAt $cx $cy              # knife path point on the cube
    Frames 5
    Syn-Key 'Escape'; Frames 5
    $emPath = Get-EditModeRaw
    Syn-Key 'Escape'; Frames 5
    $emExit = Get-EditModeRaw
    $ok4 = ($em1 -match 'Knife') -and ($emPath -match 'Knife') -and ($emExit -match 'Object')
    Log-Case 'T4' 1 ($(if ($ok4) { 'PASS' } else { 'FAIL' })) "k=$em1 escPath=$emPath escExit=$emExit"
    # T9 modal-G half (already PASS in s1; cheap re-proof)
    Syn-ClickAt $cx $cy
    $m0 = Get-Modal
    Syn-Key 'KeyG'; Frames 5
    $m1 = Get-Modal
    Log-Case 'T9' 'modal-G' ($(if ($null -eq $m0 -and $null -eq $m1) { 'PASS' } else { 'FAIL' })) "modal: '$m0' -> '$m1' (modal transform disabled by design)"

    # ---- T9: face drag commits, and Esc mid-flight restores ----------------
    Syn-ClickAt $cx $cy
    Syn-Key 'Digit3'; Frames 5
    $emF = Get-EditModeRaw
    if ($emF -notmatch 'Face') {
        Log-Case 'T9' 'face' 'BLOCKED' "Digit3 -> $emF"
    } else {
        $bsn0 = Get-SceneBsn
        # control: press, drag, release commits a change
        Syn-Pointer @{ x = $cx; y = $cy; action = 'press' }
        Frames 5
        $mD = Get-Modal
        Syn-Pointer @{ x = ($cx + 150); y = $cy; action = 'move' }
        Frames 5
        Syn-Pointer @{ x = ($cx + 300); y = $cy; action = 'release' }
        Frames 10; Start-Sleep -Milliseconds 400
        $bsn1 = Get-SceneBsn
        $ctrlMoved = ($bsn1 -ne $bsn0)
        Log-Case 'T9' 'face-commit' ($(if ($ctrlMoved) { 'PASS' } else { 'FAIL' })) "modal=$mD geometryChanged=$ctrlMoved"
        if ($ctrlMoved) {
            Call-Op 'history.undo'; Frames 10; Start-Sleep -Milliseconds 300
            $bsn0b = Get-SceneBsn
            Log-Case 'T9' 'face-undo' 'INFO' "undo restored=$($bsn0b -eq $bsn0)"
            # the cell: Esc mid-flight restores
            Syn-Pointer @{ x = $cx; y = $cy; action = 'press' }
            Frames 5
            $mD2 = Get-Modal
            Syn-Pointer @{ x = ($cx + 150); y = $cy; action = 'move' }
            Frames 5
            Syn-Key 'Escape'
            Frames 10
            Syn-Pointer @{ x = ($cx + 300); y = $cy; action = 'release' }
            Frames 10; Start-Sleep -Milliseconds 400
            $bsn2 = Get-SceneBsn
            $mAfter = Get-Modal
            $ok9 = ($bsn2 -eq $bsn0) -and ($null -eq $mAfter)
            Log-Case 'T9' 'face-esc' ($(if ($ok9) { 'PASS' } else { 'FAIL' })) "modal='$mD2'->'$mAfter' geometryRestored=$($bsn2 -eq $bsn0)"
        } else {
            Log-Case 'T9' 'face-esc' 'BLOCKED' 'control drag changed nothing'
        }
        Syn-Key 'Escape'; Frames 3
        if ((Get-EditModeRaw) -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
    }

    # ---- V8: text focus semantics ------------------------------------------
    Reset-Modal; Frames 3
    if ((Get-EditModeRaw) -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
    Syn-ClickAt $cx $cy           # select the brush; Inspector shows fields
    Frames 20; Start-Sleep -Milliseconds 500
    $UiTextPath = 'bevy_ui::widget::text::Text'
    $UiNodePath = 'bevy_ui::ui_node::ComputedNode'
    $UiGtPath = 'bevy_ui::ui_transform::UiGlobalTransform'
    $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($UiTextPath, $UiNodePath, $UiGtPath) } })
    $maxX = 0.0; $minX = 99999.0
    $uiRows = @()
    foreach ($row in $rows) {
        $c = $row.components
        if ($null -eq $c.$UiGtPath) { continue }
        $size = $c.$UiNodePath.size
        if ([double]$size[0] -le 0 -or [double]$size[1] -le 0) { continue }
        $a = $c.$UiGtPath
        $t = [string]$c.$UiTextPath
        $uiRows += [pscustomobject]@{ cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$size[0]; h = [double]$size[1]; text = $t }
        if ([double]$a[4] -gt $maxX) { $maxX = [double]$a[4] }
        if ([double]$a[4] -lt $minX) { $minX = [double]$a[4] }
    }
    Log-Case 'V8' 'rows' 'INFO' ("text rows: {0} x-range {1:N0}..{2:N0}" -f @($uiRows).Count, $minX, $maxX)
    # candidates: right-panel rows that look like editable values (numeric or
    # short) in the Inspector band; try until the typing oracle fires.
    $right = $uiRows | Where-Object { $_.cx -gt ($maxX - [double](($r.R - $r.L) / 2)) } | Sort-Object cy
    $focused = $false; $fx = 0.0; $fy = 0.0; $focusId = ''
    foreach ($row in @($right) | Select-Object -First 8) {
        $fx = [double]$row.cx / $DpiScale; $fy = [double]$row.cy / $DpiScale
        Syn-ClickAt $fx $fy
        $f = Get-FocusEntity
        if ($f -eq 'null' -or $f -eq 'unavailable' -or $null -eq $f) { continue }
        # typing oracle: with the cursor hovered over the viewport, the camera
        # gate must be disabled iff the focused entity holds the keyboard.
        Syn-Pointer @{ x = $cx; y = $cy; action = 'move' }
        Frames 5
        $en = Get-FlyCamEnabled
        $t = $row.text; if ($t.Length -gt 20) { $t = $t.Substring(0, 20) }
        Log-Case 'V8' 'try' 'INFO' ("click ({0:N0},{1:N0}) '{2}' focus={3} enabled={4}" -f $fx, $fy, $t, $f, $en)
        if (-not $en) { $focused = $true; $focusId = $f; break }
    }
    if (-not $focused) {
        Log-Case 'V8' 'focus' 'BLOCKED' 'no clicked field held the keyboard (camera never gated)'
    } else {
        Log-Case 'V8' 'focus+gate' 'PASS' "field focused ($focusId) and typing gates the camera (enabled=False, hovered)"
        # RMB must not enter fly
        Syn-Pointer @{ x = $cx; y = $cy; action = 'press'; button = 'secondary' }
        Frames 5
        $flyRmb = Get-Fly
        Syn-Pointer @{ x = $cx; y = $cy; action = 'release'; button = 'secondary' }
        Frames 3
        Log-Case 'V8' 'rmb' ($(if (-not $flyRmb) { 'PASS' } else { 'FAIL' })) "fly=$flyRmb while typing"
        # WASD must not move the camera
        $cam0 = Get-Cam
        Call-Op 'input.key' @{ key = 'KeyW'; action = 'press' }
        Frames 30
        Call-Op 'input.key' @{ key = 'KeyW'; action = 'release' }
        Frames 5
        $cam1 = Get-Cam
        $moved = Cam-Dist $cam0 $cam1
        Log-Case 'V8' 'wasd' ($(if ($moved -lt 0.005) { 'PASS' } else { 'FAIL' })) ("W moved={0:N4} while typing" -f $moved)
        # wheel must not dolly
        $cam0 = Get-Cam
        Syn-Pointer @{ x = $cx; y = $cy; action = 'scroll'; lines = 3 }
        Frames 8
        $cam1 = Get-Cam
        $moved = Cam-Dist $cam0 $cam1
        Log-Case 'V8' 'wheel' ($(if ($moved -lt 0.005) { 'PASS' } else { 'FAIL' })) ("wheel moved={0:N4} while typing" -f $moved)
        # R-1: tool active first, then the field; Esc peels one layer at a time
        Reset-Modal; Frames 3
        Call-Op 'tools.measure_distance'; Frames 8
        $mStart = Get-Modal
        Syn-ClickAt $fx $fy
        $fTyping = Get-FocusEntity
        $typing = ($fTyping -eq $focusId)
        if (-not $typing) {
            Log-Case 'V8' 'r1' 'BLOCKED' "modal='$mStart'; field click while modal active lost focus ($fTyping)"
        } else {
            Syn-Key 'Escape'; Frames 5
            $fEsc1 = Get-FocusEntity
            $mEsc1 = Get-Modal
            Syn-Key 'Escape'; Frames 5
            $mEsc2 = Get-Modal
            $okR1 = ($mStart -eq 'tools.measure_distance') -and ($mEsc1 -ne $null) -and ($null -eq $mEsc2) -and ($fEsc1 -ne $focusId)
            Log-Case 'V8' 'r1' ($(if ($okR1) { 'PASS' } else { 'FAIL' })) "modal='$mStart' typing focus=$fTyping esc1: modal='$mEsc1' focus=$fEsc1 esc2: modal='$mEsc2'"
            Reset-Modal; Frames 3
        }
        # activation proof for the negatives: after the blur, RMB flies again
        Syn-Pointer @{ x = $cx; y = $cy; action = 'press'; button = 'secondary' }
        Frames 5
        $flyAfter = Get-Fly
        Syn-Pointer @{ x = $cx; y = $cy; action = 'release'; button = 'secondary' }
        Frames 3
        Log-Case 'V8' 'probe' ($(if ($flyAfter) { 'PASS' } else { 'FAIL' })) "fly=$flyAfter after blur (negatives are valid)"
    }

    # ---- T10: snap middle-click semantics via BackgroundColor --------------
    Reset-Modal; Frames 3
    Call-Op 'tool.translate'; Frames 5
    $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
    Start-Sleep -Milliseconds 200
    $BgPath = 'bevy_ui::ui_node::BackgroundColor'
    $GtPath2 = 'bevy_ui::ui_transform::UiGlobalTransform'
    function Get-ToolbarBgs {
        # background colors of UI entities in the toolbar band (top of window)
        $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($BgPath, $GtPath2) } })
        $map = @{}
        foreach ($row in $rows) {
            $a = $row.components.$GtPath2
            if ($null -eq $a) { continue }
            $py = [double]$a[5] / $DpiScale
            if ($py -gt 40) { continue }        # toolbar band only
            $bg = $row.components.$BgPath
            $map[[string]$row.entity] = [string]($bg | ConvertTo-Json -Compress)
        }
        return $map
    }
    $b0 = Get-ToolbarBgs
    Log-Case 'T10' 'snapshot' 'INFO' ("toolbar-band BackgroundColor entities: {0}" -f $b0.Count)
    # calibrate with the magnet keybind: exactly one entity should change
    Syn-Key 'KeyM'; Frames 10; Start-Sleep -Milliseconds 400
    $b1 = Get-ToolbarBgs
    $diff = @()
    foreach ($k in $b0.Keys) { if ($b1.ContainsKey($k) -and $b0[$k] -ne $b1[$k]) { $diff += $k } }
    Log-Case 'T10' 'calib' 'INFO' ("KeyM changed {0}: {1}" -f @($diff).Count, ($diff -join ','))
    if (@($diff).Count -ne 1) {
        Log-Case 'T10' 1 'BLOCKED' ("calibration found {0} changed entities (expected the magnet only)" -f @($diff).Count)
    } else {
        $magnet = $diff[0]
        # synthetic stationary middle click flips once
        Syn-Pointer @{ x = $cx; y = $cy; action = 'click'; button = 'middle' }
        Frames 10; Start-Sleep -Milliseconds 400
        $b2 = Get-ToolbarBgs
        $flip1 = ($b2[$magnet] -ne $b1[$magnet])
        Log-Case 'T10' 'mm-click' ($(if ($flip1) { 'PASS' } else { 'FAIL' })) "stationary MMB click flipped magnet: $($b1[$magnet]) -> $($b2[$magnet])"
        # OS middle drag pans and must NOT flip
        $cam0 = Get-Cam
        [JdInput]::MmbDown(); Start-Sleep -Milliseconds 150
        $panDuring = $false; $flyDuring = $false
        for ($i = 1; $i -le 20; $i++) {
            Send-MoveRel 15 0; Start-Sleep -Milliseconds 16
            if ($i -eq 10) { $panDuring = Get-Pan; $flyDuring = Get-Fly }
        }
        $cam1 = Get-Cam
        [JdInput]::MmbUp(); Start-Sleep -Milliseconds 400; Frames 5
        $b3 = Get-ToolbarBgs
        $panLen = Cam-Dist $cam0 $cam1
        $noFlip = ($b3[$magnet] -eq $b2[$magnet])
        $okDrag = $noFlip -and $panDuring -and (-not $flyDuring) -and ($panLen -gt 0.1)
        Log-Case 'T10' 'mm-drag' ($(if ($okDrag) { 'PASS' } else { 'FAIL' })) ("drag: pan=$panDuring fly=$flyDuring moved={0:N2} magnetUnchanged=$noFlip" -f $panLen)
        # second stationary click flips back
        Syn-Pointer @{ x = $cx; y = $cy; action = 'click'; button = 'middle' }
        Frames 10; Start-Sleep -Milliseconds 400
        $b4 = Get-ToolbarBgs
        $flipBack = ($b4[$magnet] -eq $b1[$magnet])
        Log-Case 'T10' 'mm-click2' ($(if ($flipBack) { 'PASS' } else { 'FAIL' })) "second click restored magnet: $($b4[$magnet]) eq initial $($b1[$magnet])"
    }

    Write-Host "SUPPLEMENT3 DONE -> $csv"
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
