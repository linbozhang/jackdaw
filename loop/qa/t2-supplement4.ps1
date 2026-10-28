# T2 supplement, attempt 4 (targeted): T9 face-drag with a long drag and
# mid-drag probes, V8 via the on-screen hierarchy Filter field, T10 via the
# positionally-identified magnet (rightmost toolbar icon) and call_operator.
# CSV: loop/reports/t01-t2-supplement/<Label>/metrics.csv
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [string]$Label = 's4',
    [double]$DpiScale = 1.5
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot "..\reports\t01-t2-supplement\$Label"
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')
$script:Vk['Digit3'] = 0x33

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
    Log-Case 'setup' 'window' 'INFO' ("hwnd={0} fg={1} phys=({2:N0}x{3:N0}) center=({4},{5}) cursor={6}" -f $script:Hwnd, $fgOk, $physW, $physH, $cx, $cy, (Get-CursorPos | ConvertTo-Json -Compress))

    $UiTextPath = 'bevy_ui::widget::text::Text'
    $UiNodePath = 'bevy_ui::ui_node::ComputedNode'
    $UiGtPath = 'bevy_ui::ui_transform::UiGlobalTransform'
    function Get-TextRows {
        $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($UiTextPath, $UiNodePath, $UiGtPath) } })
        $out = @()
        foreach ($row in $rows) {
            $c = $row.components
            if ($null -eq $c.$UiGtPath) { continue }
            $size = $c.$UiNodePath.size
            if ([double]$size[0] -le 0 -or [double]$size[1] -le 0) { continue }
            $a = $c.$UiGtPath
            $out += [pscustomobject]@{
                entity = [string]$row.entity
                cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$size[0]; h = [double]$size[1]
                text = [string]$c.$UiTextPath
            }
        }
        return ,$out
    }

    # ---- T9 face drag, long drag + mid-drag probes ---------------------------
    Syn-ClickAt $cx $cy
    Syn-Key 'Digit3'; Frames 5
    $emF = Get-EditModeRaw
    if ($emF -notmatch 'Face') {
        Log-Case 'T9' 'face' 'BLOCKED' "Digit3 -> $emF"
    } else {
        $bsn0 = Get-SceneBsn
        Syn-Pointer @{ x = $cx; y = $cy; action = 'press' }
        Frames 5
        $mD = Get-Modal
        # three staged moves with a bsn probe after each: activation should
        # show a live geometry change mid-drag (before any release).
        $stages = @(100, 300, 700)
        $mid = @()
        foreach ($dx in $stages) {
            Syn-Pointer @{ x = ($cx + $dx); y = $cy; action = 'move' }
            Frames 8
            $mid += ($bsnMid = Get-SceneBsn) -ne $bsn0
            Log-Case 'T9' 'probe' 'INFO' ("after +{0}px: modal still? cursor={1} bsnChanged={2}" -f $dx, (Get-CursorPos | ConvertTo-Json -Compress), ($bsnMid -ne $bsn0))
        }
        Syn-Pointer @{ x = ($cx + 900); y = ($cy + 100); action = 'release' }
        Frames 10; Start-Sleep -Milliseconds 400
        $bsn1 = Get-SceneBsn
        $mRel = Get-Modal
        Log-Case 'T9' 'face-commit' ($(if ($bsn1 -ne $bsn0) { 'PASS' } else { 'FAIL' })) "modal=$mD rel='$mRel' midChanged=[$($mid -join ',')] committed=$($bsn1 -ne $bsn0)"
        if ($bsn1 -ne $bsn0) {
            Call-Op 'history.undo'; Frames 10; Start-Sleep -Milliseconds 300
            Log-Case 'T9' 'face-undo' 'INFO' "undo restored=$((Get-SceneBsn) -eq $bsn0)"
            # the cell: Esc mid-flight restores
            Syn-Pointer @{ x = $cx; y = $cy; action = 'press' }
            Frames 5
            $mD2 = Get-Modal
            Syn-Pointer @{ x = ($cx + 300); y = $cy; action = 'move' }
            Frames 8
            Syn-Key 'Escape'
            Frames 10
            Syn-Pointer @{ x = ($cx + 600); y = $cy; action = 'release' }
            Frames 10; Start-Sleep -Milliseconds 400
            $bsn2 = Get-SceneBsn
            $mAfter = Get-Modal
            $ok9 = ($bsn2 -eq $bsn0) -and ($null -eq $mAfter)
            Log-Case 'T9' 'face-esc' ($(if ($ok9) { 'PASS' } else { 'FAIL' })) "modal='$mD2'->'$mAfter' geometryRestored=$($bsn2 -eq $bsn0)"
        } else {
            Log-Case 'T9' 'face-esc' 'BLOCKED' 'control drag changed nothing (snap quantization or promotion refused)'
        }
        Syn-Key 'Escape'; Frames 3
        if ((Get-EditModeRaw) -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
    }

    # ---- V8: the on-screen hierarchy Filter field ----------------------------
    Reset-Modal; Frames 3
    if ((Get-EditModeRaw) -notmatch 'Object') { Syn-Key 'Escape'; Frames 3 }
    Syn-ClickAt $cx $cy
    Frames 20; Start-Sleep -Milliseconds 500
    $rows = Get-TextRows
    $onScreen = $rows | Where-Object { $_.cx -lt $physW -and $_.cy -lt $physH }
    Log-Case 'V8' 'rows' 'INFO' ("rows total={0} onScreen={1}" -f @($rows).Count, @($onScreen).Count)
    $filter = $onScreen | Where-Object { $_.text -match 'Filter' } | Select-Object -First 1
    $target = $null
    if ($filter) { $target = $filter; Log-Case 'V8' 'target' 'INFO' ("Filter field at ({0:N0},{1:N0})" -f $filter.cx, $filter.cy) }
    else {
        # dump the on-screen rows nearest the left panel for the record
        foreach ($row in @($onScreen | Sort-Object cx | Select-Object -First 10)) {
            $t = $row.text; if ($t.Length -gt 20) { $t = $t.Substring(0, 20) }
            Log-Case 'V8' 'left-row' 'INFO' ("({0:N0},{1:N0}) '{2}'" -f $row.cx, $row.cy, $t)
        }
        # fallback: the topmost small on-screen row left of center
        $target = $onScreen | Where-Object { $_.cx -lt ($physW / 2) -and $_.h -le 30 } | Sort-Object cy | Select-Object -First 1
    }
    if (-not $target) {
        Log-Case 'V8' 'focus' 'BLOCKED' 'no on-screen text field found'
    } else {
        $fx = [double]$target.cx / $DpiScale; $fy = [double]$target.cy / $DpiScale
        Syn-ClickAt $fx $fy
        $focus1 = Get-FocusEntity
        Syn-Pointer @{ x = $cx; y = $cy; action = 'move' }
        Frames 5
        $en = Get-FlyCamEnabled
        $typing = ($focus1 -ne 'null' -and $focus1 -ne 'unavailable' -and $null -ne $focus1) -and (-not $en)
        Log-Case 'V8' 'focus' ($(if ($typing) { 'PASS' } else { 'BLOCKED' })) "click ({0:N0},{1:N0}) focus={2} enabledAfterHover={3}" -f $fx, $fy, $focus1, $en
        if ($typing) {
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
            # R-1: tool first, then the field; Esc peels one layer at a time
            Reset-Modal; Frames 3
            Call-Op 'tools.measure_distance'; Frames 8
            $mStart = Get-Modal
            Syn-ClickAt $fx $fy
            $fTyping = Get-FocusEntity
            if ($fTyping -ne $focus1) {
                Log-Case 'V8' 'r1' 'BLOCKED' "modal='$mStart'; field click while modal gave focus=$fTyping"
            } else {
                Syn-Key 'Escape'; Frames 5
                $fEsc1 = Get-FocusEntity
                $mEsc1 = Get-Modal
                Syn-Key 'Escape'; Frames 5
                $mEsc2 = Get-Modal
                $okR1 = ($mStart -eq 'tools.measure_distance') -and ($mEsc1 -ne $null) -and ($null -eq $mEsc2) -and ($fEsc1 -ne $focus1)
                Log-Case 'V8' 'r1' ($(if ($okR1) { 'PASS' } else { 'FAIL' })) "modal='$mStart' esc1: modal='$mEsc1' focus=$fEsc1 esc2: modal='$mEsc2'"
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

    # ---- T10: magnet = rightmost toolbar icon; call_operator + OS gestures ----
    Reset-Modal; Frames 3
    Call-Op 'tool.translate'; Frames 5
    $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
    Start-Sleep -Milliseconds 200
    $rows = Get-TextRows
    $band = $rows | Where-Object { ([double]$_.cy / $DpiScale) -lt 40 }
    $magnetRow = $band | Sort-Object cx -Descending | Select-Object -First 1
    if (-not $magnetRow) {
        Log-Case 'T10' 'locate' 'BLOCKED' 'no toolbar-band text rows'
    } else {
        Log-Case 'T10' 'locate' 'INFO' ("magnet candidate: ({0:N0},{1:N0}) '{2}' w={3:N0}" -f $magnetRow.cx, $magnetRow.cy, $magnetRow.text, $magnetRow.w)
        $BgPath = 'bevy_ui::ui_node::BackgroundColor'
        function Get-EntityBg([string]$Entity) {
            $res = Brp-Result (Brp-Call 'world.get_components' @{ entity = $Entity; components = @($BgPath) })
            if ($null -eq $res.components.$BgPath) { return $null }
            return [string]($res.components.$BgPath | ConvertTo-Json -Compress)
        }
        $bg0 = Get-EntityBg $magnetRow.entity
        Log-Case 'T10' 'bg0' 'INFO' "magnet row entity=$($magnetRow.entity) bg=$bg0"
        # the icon Text node may not carry BackgroundColor; if null, query the
        # whole band and take the entity nearest the icon center.
        if ($null -eq $bg0) {
            $bRows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($BgPath, $UiGtPath) } })
            $best = $null; $bestD = 1e9
            foreach ($row in $bRows) {
                $a = $row.components.$UiGtPath
                if ($null -eq $a) { continue }
                $d = [Math]::Pow([double]$a[4] - $magnetRow.cx, 2) + [Math]::Pow([double]$a[5] - $magnetRow.cy, 2)
                if ($d -lt $bestD) { $bestD = $d; $best = [string]$row.entity }
            }
            $magnetRow = $null
            $magnetEnt = $best
            $bg0 = Get-EntityBg $magnetEnt
            Log-Case 'T10' 'bg0' 'INFO' "nearest bg entity=$magnetEnt dist={0:N0} bg=$bg0" -f [Math]::Sqrt($bestD)
        } else {
            $magnetEnt = $magnetRow.entity
        }
        # calibrate with the operator directly
        Call-Op 'snap.toggle'; Frames 10; Start-Sleep -Milliseconds 400
        $bg1 = Get-EntityBg $magnetEnt
        Log-Case 'T10' 'calib' 'INFO' "snap.toggle: bg=$bg0 -> $bg1 (changed=$($bg1 -ne $bg0))"
        if ($bg1 -eq $bg0) {
            Log-Case 'T10' 1 'BLOCKED' 'snap.toggle did not change the magnet background (identification failed)'
        } else {
            # synthetic stationary middle click flips once
            Syn-Pointer @{ x = $cx; y = $cy; action = 'click'; button = 'middle' }
            Frames 10; Start-Sleep -Milliseconds 400
            $bg2 = Get-EntityBg $magnetEnt
            Log-Case 'T10' 'mm-click' ($(if ($bg2 -ne $bg1) { 'PASS' } else { 'FAIL' })) "stationary MMB click: bg=$bg1 -> $bg2"
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
            $bg3 = Get-EntityBg $magnetEnt
            $panLen = Cam-Dist $cam0 $cam1
            $noFlip = ($bg3 -eq $bg2)
            $okDrag = $noFlip -and $panDuring -and (-not $flyDuring) -and ($panLen -gt 0.1)
            Log-Case 'T10' 'mm-drag' ($(if ($okDrag) { 'PASS' } else { 'FAIL' })) ("drag: pan=$panDuring fly=$flyDuring moved={0:N2} magnetUnchanged=$noFlip" -f $panLen)
            # second stationary click flips back
            Syn-Pointer @{ x = $cx; y = $cy; action = 'click'; button = 'middle' }
            Frames 10; Start-Sleep -Milliseconds 400
            $bg4 = Get-EntityBg $magnetEnt
            Log-Case 'T10' 'mm-click2' ($(if ($bg4 -eq $bg1) { 'PASS' } else { 'FAIL' })) "second click: bg=$bg4 (expect initial $bg1)"
        }
    }

    Write-Host "SUPPLEMENT4 DONE -> $csv"
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
