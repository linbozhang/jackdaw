# T01 task 2 supplement: leftover matrix cells via the synthetic-input channel.
# Phases (one editor session, run in order): T34 (T3/T4 entry + T1-failure
# diagnosis) -> T9 (face-drag Esc restore; modal-transform-G documented
# disabled-by-design in code) -> V8 (text focus semantics, R-1) -> T10 (snap
# middle-click semantics via toolbar ButtonVariant).
# CSV: loop/reports/t01-t2-supplement/<Label>/metrics.csv  case,iter,result,detail
# ASCII-only on purpose (PowerShell 5 reads BOM-less files as ANSI).
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [string]$Label = 's1',
    [double]$DpiScale = 1.5,
    [string]$Phase = 'All',   # All | T34 | T9 | V8 | T10
    [switch]$NoStart,
    [switch]$LeaveRunning
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot "..\reports\t01-t2-supplement\$Label"
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

# VK codes the shared table lacks (replicating the T1 Tools-phase driver).
$script:Vk['Digit1'] = 0x31; $script:Vk['Digit3'] = 0x33; $script:Vk['Digit4'] = 0x34
$script:Vk['K'] = 0x4B; $script:Vk['G'] = 0x47

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

# Synthetic input (BRP operators in test_input.rs). x/y are window logical px.
function Syn-Pointer($Params) { Call-Op 'input.pointer' $Params }
function Syn-ClickAt([double]$X, [double]$Y, [string]$Button = 'primary') {
    Syn-Pointer @{ x = $X; y = $Y; action = 'click'; button = $Button }
    Frames 8; Start-Sleep -Milliseconds 300
}
function Syn-Key([string]$Key) {
    Call-Op 'input.key' @{ key = $Key }
    Frames 6; Start-Sleep -Milliseconds 150
}
function Get-Fly { Get-BoolResource 'jackdaw::viewport::CameraFlyActive' }
function Get-Pan { Get-BoolResource 'jackdaw::viewport::CameraPanActive' }
function Get-BoolResource {
    param([Parameter(Mandatory = $true)][string]$Path)
    $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = $Path })
    $v = $r.value
    if ($v -is [bool]) { return $v }
    if ($v -is [System.Array]) { return [bool]$v[0] }
    $first = $v.PSObject.Properties | Select-Object -First 1
    if ($first) { return [bool]$first.Value }
    throw "unrecognized value shape for ${Path}: $($v | ConvertTo-Json -Compress)"
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
function Get-SceneBsn {
    $r = (Brp-Call 'jackdaw/scene_bsn' @{}).result
    if ($r -is [string]) { return $r }
    return [string]$r.bsn
}

# ---- foreground helpers (r2-style AttachThreadInput; no minimize/restore) --
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
# OS-level viewport click (replicates the T1 Tools-phase driver exactly).
function Os-ClickViewport {
    Keep-Foreground $script:Hwnd | Out-Null
    $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
    Start-Sleep -Milliseconds 150
    [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
    Start-Sleep -Milliseconds 250
}
# Window center in logical px (input.pointer coordinates).
function Get-WinCenter {
    $r = New-Object JdInput+RECT
    [JdInput]::GetWindowRect($script:Hwnd, [ref]$r) | Out-Null
    $cx = [double](($r.L + $r.R) / 2); $cy = [double](($r.T + $r.B) / 2)
    return @{ X = [Math]::Floor($cx / $DpiScale); Y = [Math]::Floor($cy / $DpiScale) }
}

# ---- UI queries ------------------------------------------------------------
$UiTextPath = 'bevy_ui::widget::text::Text'
$UiNodePath = 'bevy_ui::ui_node::ComputedNode'
$UiGtPath = 'bevy_ui::ui_transform::UiGlobalTransform'
# Find focusable text inputs (EditableText holders) with their on-screen
# centers, in physical UI px. Tries known reflect paths.
function Get-TextInputRows {
    $editablePaths = @('bevy_text::EditableText', 'bevy_text::editing::EditableText', 'bevy::text::EditableText')
    $editable = $null
    foreach ($p in $editablePaths) {
        try {
            $null = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($p) }; filter = @{ with = @($p) } })
            $editable = $p; break
        } catch { }
    }
    if (-not $editable) { return $null }
    $params = @{ data = @{ components = @($editable, $UiNodePath, $UiGtPath) }; filter = @{ with = @($editable) } }
    $rows = Brp-Result (Brp-Call 'world.query' $params)
    $out = @()
    foreach ($row in $rows) {
        $c = $row.components
        if ($null -eq $c.$UiGtPath) { continue }
        $size = $c.$UiNodePath.size
        if ([double]$size[0] -le 0 -or [double]$size[1] -le 0) { continue }
        $a = $c.$UiGtPath
        $out += [pscustomobject]@{
            entity = $row.entity
            cx = [double]$a[4]; cy = [double]$a[5]
            w = [double]$size[0]; h = [double]$size[1]
        }
    }
    return ,$out
}

# Toolbar ButtonVariant snapshot: map entity -> variant string for every
# entity carrying the feathers ButtonVariant component.
$VariantPaths = @(
    'bevy_feathers::controls::ButtonVariant',
    'bevy_feathers::controls::button::ButtonVariant'
)
function Get-VariantPath {
    foreach ($p in $script:VariantPaths) {
        try {
            $null = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($p) }; filter = @{ with = @($p) } })
            return $p
        } catch { }
    }
    throw 'ButtonVariant not queryable under known paths'
}
function Get-ToolVariants([string]$Path) {
    $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($Path) }; filter = @{ with = @($Path) } })
    $map = @{}
    foreach ($row in $rows) {
        $v = $row.components.$Path
        $text = if ($v -is [string]) { $v } else { [string]($v | ConvertTo-Json -Compress) }
        $map[[string]$row.entity] = $text
    }
    return $map
}
function Diff-Variants($a, $b) {
    $diff = @()
    foreach ($k in $a.Keys) {
        if ($b.ContainsKey($k) -and $a[$k] -ne $b[$k]) { $diff += $k }
    }
    return ,$diff
}

# ---- start editor ----------------------------------------------------------
$proc = $null
if (-not $NoStart) {
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
    }
    Start-Sleep -Milliseconds 500
    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT = "$Port"
    $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
}
try {
    Wait-EditorReady -TimeoutSec 180
    foreach ($try in 1..6) {
        try { Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null; break }
        catch { Start-Sleep -Seconds 2 }
    }
    Frames 10
    $script:Hwnd = Get-JackdawHwnd
    Keep-Foreground $script:Hwnd | Out-Null
    $VC = Get-WinCenter
    Log-Case 'setup' 'window' 'INFO' ("hwnd={0} logical center=({1},{2})" -f $script:Hwnd, $VC.X, $VC.Y)

    # =========================================================================
    if ($Phase -eq 'All' -or $Phase -eq 'T34') {
        # ---- fixture: brush selected, Object mode, hover over the cube ------
        Os-ClickViewport; Frames 5
        $em0 = Get-EditModeRaw
        Log-Case 'T34' 'setup' 'INFO' "after viewport click: mode=$em0 focus=$(Get-FocusEntity)"

        # Enter Vertex via the real key (proves the brush is selectable here).
        Syn-Key 'Digit1'; Frames 5
        $emV = Get-EditModeRaw
        $fixtureOk = ($emV -match 'Vertex')
        Log-Case 'T34' 'fixture' 'INFO' "Digit1 -> $emV"

        # ---- DIAGNOSIS: replicate the T1 failure (OS channel, T2 sequence) --
        if ($fixtureOk) {
            Syn-Key 'Escape'; Frames 5      # back to Object
            # exact T1 Tools-phase replay: OS click + OS Digit1 + OS Esc x2
            Os-ClickViewport; Frames 3
            [JdInput]::KeyDown($script:Vk['Digit1']); Start-Sleep -Milliseconds 60; [JdInput]::KeyUp($script:Vk['Digit1'])
            Start-Sleep -Milliseconds 300; Frames 5
            $dEm1 = Get-EditModeRaw
            [JdInput]::KeyDown($script:Vk.Esc); Start-Sleep -Milliseconds 30; [JdInput]::KeyUp($script:Vk.Esc)
            Start-Sleep -Milliseconds 300
            [JdInput]::KeyDown($script:Vk.Esc); Start-Sleep -Milliseconds 30; [JdInput]::KeyUp($script:Vk.Esc)
            Start-Sleep -Milliseconds 300; Frames 5
            $dFocus = Get-FocusEntity
            [JdInput]::KeyDown($script:Vk['Digit4']); Start-Sleep -Milliseconds 60; [JdInput]::KeyUp($script:Vk['Digit4'])
            Start-Sleep -Milliseconds 300; Frames 5
            $dEm2 = Get-EditModeRaw
            $diag = "d1=$dEm1 escFocus=$dFocus d4=$dEm2"
            if ($dEm2 -match 'Clip') { Log-Case 'T34' 'diag' 'INFO' "T1 sequence now enters Clip ($diag)" }
            else { Log-Case 'T34' 'diag' 'INFO' "T1 sequence reproduced the failure ($diag)" }
        }

        # ---- T3: Clip via Digit4, Esc exits --------------------------------
        Reset-Modal; Frames 3
        if ($fixtureOk -and (Get-EditModeRaw) -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
        Syn-ClickAt $VC.X $VC.Y                  # viewport click: hover + focus clear
        $preFocus = Get-FocusEntity
        Syn-Key 'Digit4'; Frames 5
        $em1 = Get-EditModeRaw
        $inClip = ($em1 -match 'Clip')
        Syn-Key 'Escape'; Frames 5
        $em2 = Get-EditModeRaw
        $ok3 = $inClip -and ($em2 -match 'Object')
        if ($inClip) { Log-Case 'T3' 1 ($(if ($ok3) { 'PASS' } else { 'FAIL' })) "d4=$em1 esc=$em2 preFocus=$preFocus" }
        else { Log-Case 'T3' 1 'BLOCKED' "Digit4 did not enter Clip (mode=$em1 preFocus=$preFocus)" }
        # jackdaw/cancel path from Clip (matrix: EditMode + jackdaw/cancel reset)
        if ($inClip) {
            Syn-Key 'Digit4'; Frames 5
            $em1c = Get-EditModeRaw
            Reset-Modal; Frames 5
            $em2c = Get-EditModeRaw
            Log-Case 'T3' 'cancel-op' 'INFO' "reenter=$em1c jackdaw/cancel->$em2c"
            if ($em2c -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
        }

        # ---- T4: Knife via KeyK; click places a path point; Esc clears path,
        #         second Esc leaves Knife -> Object ---------------------------
        Syn-ClickAt $VC.X $VC.Y
        Syn-Key 'KeyK'; Frames 5
        $em1 = Get-EditModeRaw
        $inKnife = ($em1 -match 'Knife')
        if ($inKnife) {
            Syn-ClickAt $VC.X $VC.Y              # place one knife path point on the cube
            Frames 5
            Syn-Key 'Escape'; Frames 5       # should clear the path, stay Knife
            $emPath = Get-EditModeRaw
            Syn-Key 'Escape'; Frames 5       # should now exit to Object
            $emExit = Get-EditModeRaw
            $ok4 = ($emPath -match 'Knife') -and ($emExit -match 'Object')
            Log-Case 'T4' 1 ($(if ($ok4) { 'PASS' } else { 'FAIL' })) "k=$em1 escPath=$emPath escExit=$emExit"
        } else {
            Log-Case 'T4' 1 'BLOCKED' "KeyK did not enter Knife (mode=$em1)"
        }
    }

    # =========================================================================
    if ($Phase -eq 'All' -or $Phase -eq 'T9') {
        # T9 part A: modal transform via G is disabled by design. Evidence:
        # modal_transform.rs plugin comment (G/R/S are TrenchBroom chords);
        # plain G is unbound, Alt+G is transform.reset_position. Live check:
        # press G with a selection; no modal may start.
        Reset-Modal; Frames 3
        if ((Get-EditModeRaw) -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
        Syn-ClickAt $VC.X $VC.Y
        $m0 = Get-Modal
        Syn-Key 'KeyG'; Frames 5
        $m1 = Get-Modal
        $ok9a = ($null -eq $m0) -and ($null -eq $m1)
        Log-Case 'T9' 'modal-G' ($(if ($ok9a) { 'PASS' } else { 'FAIL' })) "modal: $m0 -> $m1 (G starts no modal; systems disabled by design)"

        # T9 part B: face drag mid-flight Esc restores geometry.
        # Enter Face mode, press on the cube -> brush.face.drag modal starts.
        Syn-Key 'Digit3'; Frames 5
        $emF = Get-EditModeRaw
        if ($emF -notmatch 'Face') {
            Log-Case 'T9' 'face-drag' 'BLOCKED' "Digit3 did not enter Face (mode=$emF)"
        } else {
            $bsn0 = Get-SceneBsn
            # control: drag + release (no Esc) commits a geometry change.
            # 400px total travel so grid snapping cannot quantize it to zero.
            Syn-Pointer @{ x = $VC.X; y = $VC.Y; action = 'press' }
            Frames 5
            $mDrag = Get-Modal
            Syn-Pointer @{ x = ($VC.X + 200); y = $VC.Y; action = 'move' }
            Frames 3
            Syn-Pointer @{ x = ($VC.X + 400); y = $VC.Y; action = 'release' }
            Frames 8; Start-Sleep -Milliseconds 300
            $bsn1 = Get-SceneBsn
            $ctrlMoved = ($bsn1 -ne $bsn0)
            Log-Case 'T9' 'face-commit' ($(if ($ctrlMoved) { 'PASS' } else { 'FAIL' })) "modal=$mDrag geometryChanged=$ctrlMoved (control drag commits)"
            if (-not $ctrlMoved) {
                Log-Case 'T9' 'face-esc' 'BLOCKED' 'control drag changed nothing; face drag never started'
            } else {
                # undo the control drag so the restore compare is clean.
                Call-Op 'history.undo'; Frames 8; Start-Sleep -Milliseconds 200
                $bsn0b = Get-SceneBsn
                $restored = ($bsn0b -eq $bsn0)
                Log-Case 'T9' 'face-undo' 'INFO' "after history.undo geometryRestored=$restored"
                # the real cell: press, drag, Esc mid-flight, release -> restored.
                Syn-Pointer @{ x = $VC.X; y = $VC.Y; action = 'press' }
                Frames 5
                $mDrag2 = Get-Modal
                Syn-Pointer @{ x = ($VC.X + 200); y = $VC.Y; action = 'move' }
                Frames 3
                Syn-Key 'Escape'
                Frames 8
                Syn-Pointer @{ x = ($VC.X + 400); y = $VC.Y; action = 'release' }
                Frames 8; Start-Sleep -Milliseconds 300
                $bsn2 = Get-SceneBsn
                $mAfter = Get-Modal
                $ok9 = ($bsn2 -eq $bsn0) -and ($null -eq $mAfter)
                Log-Case 'T9' 'face-esc' ($(if ($ok9) { 'PASS' } else { 'FAIL' })) "modal=$mDrag2 -> $mAfter geometryRestored=$($bsn2 -eq $bsn0)"
            }
            # leave Object mode for the later phases.
            Syn-Key 'Escape'; Frames 3
            if ((Get-EditModeRaw) -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
        }
    }

    # =========================================================================
    if ($Phase -eq 'All' -or $Phase -eq 'V8') {
        Reset-Modal; Frames 3
        if ((Get-EditModeRaw) -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
        # fixture: an entity selected so the Inspector shows fields.
        Syn-ClickAt $VC.X $VC.Y
        $rows = Get-TextInputRows
        if (-not $rows) {
            Log-Case 'V8' 'fixture' 'BLOCKED' 'no EditableText rows queryable (reflect path missing)'
        } else {
            # pick a row in the right-hand Inspector region (x > 55% of the
            # widest row set), lowest y first (topmost field).
            $maxX = ($rows | Measure-Object cx -Maximum).Maximum
            $cand = $rows | Where-Object { $_.cx -gt ($maxX * 0.55) } | Sort-Object cy
            if (-not $cand -or @($cand).Count -eq 0) { $cand = $rows | Sort-Object cy }
            $field = @($cand)[0]
            $fx = [double]$field.cx / $DpiScale
            $fy = [double]$field.cy / $DpiScale
            Log-Case 'V8' 'fixture' 'INFO' ("text fields found: {0}; clicking ({1:N0},{2:N0}) logical" -f @($rows).Count, $fx, $fy)

            # click the field; typing lands in it only if focused.
            Syn-ClickAt $fx $fy
            $focus1 = Get-FocusEntity
            $focused = ($focus1 -ne 'null' -and $focus1 -ne 'unavailable' -and $null -ne $focus1)
            if (-not $focused) {
                Log-Case 'V8' 'focus' 'BLOCKED' "field click did not focus (focus=$focus1)"
            } else {
                Log-Case 'V8' 'focus' 'PASS' "field focused: $focus1"
                # Hover the viewport WITHOUT clicking: a bare move does not
                # change focus, so the camera gate below is exercised with
                # hovered=true and the typing gate as the only blocker.
                Syn-Pointer @{ x = $VC.X; y = $VC.Y; action = 'move' }
                Frames 5
                $enabled = Get-FlyCamEnabled
                Log-Case 'V8' 'cam-gate' ($(if (-not $enabled) { 'PASS' } else { 'FAIL' })) "JackdawCameraSettings.enabled=$enabled while typing+hover (expect False)"

                # RMB over the viewport must not enter fly.
                Syn-Pointer @{ x = $VC.X; y = $VC.Y; action = 'press'; button = 'secondary' }
                Frames 5
                $flyRmb = Get-Fly
                Syn-Pointer @{ x = $VC.X; y = $VC.Y; action = 'release'; button = 'secondary' }
                Frames 3
                Log-Case 'V8' 'rmb' ($(if (-not $flyRmb) { 'PASS' } else { 'FAIL' })) "fly=$flyRmb while typing (expect False)"

                # WASD must not move the camera.
                $cam0 = Get-Cam
                Call-Op 'input.key' @{ key = 'KeyW'; action = 'press' }
                Frames 30
                Call-Op 'input.key' @{ key = 'KeyW'; action = 'release' }
                Frames 5
                $cam1 = Get-Cam
                $moved = Cam-Dist $cam0 $cam1
                Log-Case 'V8' 'wasd' ($(if ($moved -lt 0.005) { 'PASS' } else { 'FAIL' })) ("W moved={0:N4} while typing (expect 0)" -f $moved)

                # wheel must not dolly.
                $cam0 = Get-Cam
                Syn-Pointer @{ x = $VC.X; y = $VC.Y; action = 'scroll'; lines = 3 }
                Frames 8
                $cam1 = Get-Cam
                $moved = Cam-Dist $cam0 $cam1
                Log-Case 'V8' 'wheel' ($(if ($moved -lt 0.005) { 'PASS' } else { 'FAIL' })) ("wheel moved={0:N4} while typing (expect 0)" -f $moved)

                # R-1: real user flow -- tool active FIRST, then click into the
                # field. First Esc leaves the field (modal survives = one layer
                # at a time), second Esc cancels the modal.
                Reset-Modal; Frames 3
                $camBlur = Get-FocusEntity          # may be 'null' after the RMB probe
                Call-Op 'tools.measure_distance'; Frames 8
                $mStart = Get-Modal
                Syn-ClickAt $fx $fy
                $focusTyping = Get-FocusEntity
                $typing = ($focusTyping -eq $focus1)
                if (-not $typing) {
                    Log-Case 'V8' 'r1-esc' 'BLOCKED' "modal=$mStart; field click while modal active did not refocus (focus=$focusTyping)"
                } else {
                    Syn-Key 'Escape'; Frames 5
                    $focusAfterEsc1 = Get-FocusEntity
                    $mEsc1 = Get-Modal
                    Syn-Key 'Escape'; Frames 5
                    $mEsc2 = Get-Modal
                    $blurred = ($focusAfterEsc1 -ne $focus1)
                    $okR1 = ($mStart -eq 'tools.measure_distance') -and $typing -and $blurred `
                        -and ($mEsc1 -ne $null) -and ($null -eq $mEsc2)
                    Log-Case 'V8' 'r1-esc' ($(if ($okR1) { 'PASS' } else { 'FAIL' })) "modal: $mStart typing focus=$focusTyping esc1->modal=$mEsc1 focus=$focusAfterEsc1 esc2->modal=$mEsc2"
                }
                Reset-Modal; Frames 3

                # activation proof for the negatives above: with focus gone,
                # RMB must enter fly again.
                Syn-Pointer @{ x = $VC.X; y = $VC.Y; action = 'press'; button = 'secondary' }
                Frames 5
                $flyAfter = Get-Fly
                Syn-Pointer @{ x = $VC.X; y = $VC.Y; action = 'release'; button = 'secondary' }
                Frames 3
                Log-Case 'V8' 'rmb-after-blur' ($(if ($flyAfter) { 'PASS' } else { 'FAIL' })) "fly=$flyAfter after blur (expect True; probe for the negatives)"
            }
        }
    }

    # =========================================================================
    if ($Phase -eq 'All' -or $Phase -eq 'T10') {
        Reset-Modal; Frames 3
        Call-Op 'tool.translate'; Frames 5
        try {
            $vpath = Get-VariantPath
            # calibrate: snap.toggle via BRP flips exactly the magnet button.
            $va = Get-ToolVariants $vpath
            Call-Op 'snap.toggle'; Frames 8; Start-Sleep -Milliseconds 200
            $vb = Get-ToolVariants $vpath
            $changed = Diff-Variants $va $vb
            if (@($changed).Count -ne 1) {
                Log-Case 'T10' 'calib' 'BLOCKED' ("snap.toggle changed {0} button variants (expected 1): {1}" -f @($changed).Count, ($changed -join ' '))
            } else {
                $magnet = $changed[0]
                Log-Case 'T10' 'calib' 'INFO' "magnet button = $magnet ($($va[$magnet]) -> $($vb[$magnet]))"

                # stationary middle click (OS) flips snap once.
                Keep-Foreground $script:Hwnd | Out-Null
                $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
                Start-Sleep -Milliseconds 200
                [JdInput]::MmbDown(); Start-Sleep -Milliseconds 120; [JdInput]::MmbUp()
                Start-Sleep -Milliseconds 400; Frames 5
                $vc = Get-ToolVariants $vpath
                $clickFlipped = ($vc[$magnet] -ne $vb[$magnet])
                Log-Case 'T10' 'mm-click' ($(if ($clickFlipped) { 'PASS' } else { 'FAIL' })) "stationary MMB click: $($vb[$magnet]) -> $($vc[$magnet]) (expect flip)"

                # middle drag pans and must NOT flip on release.
                $cam0 = Get-Cam
                [JdInput]::MmbDown(); Start-Sleep -Milliseconds 120
                $panDuring = $false
                foreach ($i in 1..20) {
                    Send-MoveRel 15 0; Start-Sleep -Milliseconds 16
                    if ($i -eq 10) { $panDuring = Get-Pan; $flyDuring = Get-Fly }
                }
                $cam1 = Get-Cam
                [JdInput]::MmbUp(); Start-Sleep -Milliseconds 400; Frames 5
                $vd = Get-ToolVariants $vpath
                $panLen = Cam-Dist $cam0 $cam1
                $dragNoFlip = ($vd[$magnet] -eq $vc[$magnet])
                $okDrag = $dragNoFlip -and $panDuring -and ($panLen -gt 0.1) -and (-not $flyDuring)
                Log-Case 'T10' 'mm-drag' ($(if ($okDrag) { 'PASS' } else { 'FAIL' })) ("drag: pan=$panDuring fly=$flyDuring moved={0:N2} variant {1} -> {2} (expect unchanged)" -f $panLen, $vc[$magnet], $vd[$magnet])

                # second stationary click flips back.
                [JdInput]::MmbDown(); Start-Sleep -Milliseconds 120; [JdInput]::MmbUp()
                Start-Sleep -Milliseconds 400; Frames 5
                $ve = Get-ToolVariants $vpath
                $flipBack = ($ve[$magnet] -eq $vb[$magnet])
                Log-Case 'T10' 'mm-click2' ($(if ($flipBack) { 'PASS' } else { 'FAIL' })) "second click: $($vc[$magnet]) -> $($ve[$magnet]) (expect back to pre-click)"
            }
        } catch {
            Log-Case 'T10' 1 'BLOCKED' $_.Exception.Message
        }
    }

    Write-Host "SUPPLEMENT DONE -> $csv"
}
finally {
    if ($proc -and -not $LeaveRunning) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}

