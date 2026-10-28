# T01 final QA spot-check (lightweight, contract: real machine)
# 1) coldstart: no clicks -> RMB engages fly + camera turns (D5#1 core behavior)
# 2) middle-drag pan one round (pan=True, fly=False, yaw/pitch frozen)
# 3) tool Esc exit (Digit4->Clip->Esc->Object; KeyK->Knife->Esc#1 path/esc#2 exit)
# 4) magnet visibility probe at this resolution (toolbar right cluster vs window width)
# CSV: loop/reports/t01-final-qa-session/metrics.csv  + window screenshot png
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15709,
    [string]$Label = 'final',
    [double]$DpiScale = 1.5
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot "..\reports\t01-final-qa-session"
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')
. (Join-Path $PSScriptRoot 'screenshot.ps1')

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
        # real-click fallback; OS SendInput may be denied in this session (error 5) -
        # non-fatal, synthetic BRP channel carries the assertions instead.
        try {
            $null = Set-CursorToWindowPoint $Hwnd 0.5 0.01
            Start-Sleep -Milliseconds 150
            [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
            Start-Sleep -Milliseconds 500
        } catch { }
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
    Log-Case 'setup' 'window' 'INFO' ("hwnd={0} fg={1} phys={2:N0}x{3:N0} center=({4},{5}) dpi={6}" -f $script:Hwnd, $fgOk, $physW, $physH, $cx, $cy, $DpiScale)

    # ---- 1) coldstart: ZERO clicks, hover via synthetic move, RMB engages ----
    $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
    Start-Sleep -Milliseconds 200
    Syn-Pointer @{ x = $cx; y = $cy; action = 'move' }
    Frames 5
    $en0 = Get-FlyCamEnabled
    $cam0 = Get-Cam
    Syn-Pointer @{ x = $cx; y = $cy; action = 'press'; button = 'secondary' }
    Frames 5
    $fly1 = Get-Fly
    for ($i = 1; $i -le 10; $i++) {
        Syn-Pointer @{ x = ($cx + 15 * $i); y = $cy; action = 'move' }
        Frames 2
    }
    Frames 5
    $cam1 = Get-Cam
    $dyaw = [Math]::Abs($cam1.Yaw - $cam0.Yaw)
    Syn-Pointer @{ x = ($cx + 150); y = $cy; action = 'release'; button = 'secondary' }
    Frames 5
    $fly0 = Get-Fly
    $ok1 = $fly1 -and (-not $fly0) -and ($dyaw -gt 0.1) -and $en0
    Log-Case 'coldstart' 'rmb-orbit' ($(if ($ok1) { 'PASS' } else { 'FAIL' })) ("zero-click: enabled={0} fly(press)={1} fly(release)={2} dyaw={3:N3}" -f $en0, $fly1, $fly0, $dyaw)

    # ---- 2) middle-drag pan one round (OS channel; falls back to synthetic --
    $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
    Start-Sleep -Milliseconds 200
    $cam0 = Get-Cam
    $panDuring = $false; $flyDuring = $false; $osOk = $true
    try {
        [JdInput]::MmbDown(); Start-Sleep -Milliseconds 150
        for ($i = 1; $i -le 20; $i++) {
            Send-MoveRel 15 0; Start-Sleep -Milliseconds 16
            if ($i -eq 10) { $panDuring = Get-Pan; $flyDuring = Get-Fly }
        }
        [JdInput]::MmbUp(); Start-Sleep -Milliseconds 400
    } catch { $osOk = $false }
    if (-not $osOk) {
        Frames 3
        Syn-Pointer @{ x = $cx; y = $cy; action = 'press'; button = 'middle' }
        Frames 3
        for ($i = 1; $i -le 10; $i++) {
            Syn-Pointer @{ x = ($cx + 20 * $i); y = ($cy + 8 * $i); action = 'move' }
            Frames 2
            if ($i -eq 5) { $panDuring = Get-Pan; $flyDuring = Get-Fly }
        }
        Syn-Pointer @{ x = ($cx + 200); y = ($cy + 80); action = 'release'; button = 'middle' }
        Frames 5
    }
    $cam1 = Get-Cam
    Frames 5
    $panLen = Cam-Dist $cam0 $cam1
    $dYaw = [Math]::Abs($cam1.Yaw - $cam0.Yaw); $dPitch = [Math]::Abs($cam1.Pitch - $cam0.Pitch)
    $ok2 = $panDuring -and (-not $flyDuring) -and ($panLen -gt 0.1) -and ($dYaw -lt 0.005) -and ($dPitch -lt 0.005)
    Log-Case 'pan' 'mmb-drag' ($(if ($ok2) { 'PASS' } else { 'FAIL' })) ("os={0} pan={1} fly={2} moved={3:N2} dyaw={4:N4} dpitch={5:N4}" -f $osOk, $panDuring, $flyDuring, $panLen, $dYaw, $dPitch)

    # ---- 3) tool Esc exit: Digit4->Clip->Esc; KeyK->Knife->Esc#1/Esc#2 -----
    Reset-Modal; Frames 3
    Syn-ClickAt $cx $cy
    Syn-Key 'Digit4'; Frames 5
    $emClip = Get-EditModeRaw
    Syn-Key 'Escape'; Frames 5
    $emAfterClip = Get-EditModeRaw
    $ok3a = ($emClip -match 'Clip') -and ($emAfterClip -match 'Object' -and $emAfterClip -notmatch 'BrushEdit')
    Log-Case 'esc-tool' 'clip' ($(if ($ok3a) { 'PASS' } else { 'FAIL' })) ("d4={0} esc={1}" -f $emClip, $emAfterClip)
    # re-click entity (Esc also deselects), then Knife
    Syn-ClickAt $cx $cy
    Syn-Key 'KeyK'; Frames 5
    $emK = Get-EditModeRaw
    Syn-Key 'Escape'; Frames 5
    $emK1 = Get-EditModeRaw
    Syn-Key 'Escape'; Frames 5
    $emK2 = Get-EditModeRaw
    $ok3b = ($emK -match 'Knife') -and ($emK1 -match 'Knife') -and ($emK2 -match 'object' -or $emK2 -match 'Object')
    Log-Case 'esc-tool' 'knife' ($(if ($ok3b) { 'PASS' } else { 'FAIL' })) ("k={0} esc1={1} esc2={2}" -f $emK, $emK1, $emK2)

    # ---- 4) magnet visibility at this resolution ----------------------------
    # toolbar band = top strip (physical y < 120). Any interactive/text row whose
    # physical x center exceeds the window width is clipped off-screen.
    $UiTextPath = 'bevy_ui::widget::text::Text'
    $UiNodePath = 'bevy_ui::ui_node::ComputedNode'
    $UiGtPath = 'bevy_ui::ui_transform::UiGlobalTransform'
    $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($UiTextPath, $UiNodePath, $UiGtPath) } })
    $band = @()
    foreach ($row in $rows) {
        $c = $row.components
        if ($null -eq $c.$UiGtPath) { continue }
        $size = $c.$UiNodePath.size
        if ([double]$size[0] -le 0 -or [double]$size[1] -le 0) { continue }
        $a = $c.$UiGtPath
        $px = [double]$a[4]; $py = [double]$a[5]
        if ($py -lt 120) {
            $band += [pscustomobject]@{ x = $px; y = $py; w = [double]$size[0]; text = [string]$c.$UiTextPath }
        }
    }
    $clipped = @($band | Where-Object { $_.x -gt $physW })
    $maxX = ($band | Measure-Object -Property x -Maximum).Maximum
    $shot = Join-Path $OutDir 'toolbar-maximized.png'
    Save-WindowScreenshot $script:Hwnd $shot | Out-Null
    Log-Case 'magnet' 'toolbar' 'INFO' ("toolbarBand rows={0} maxX={1:N0} windowW={2:N0} clippedRows={3} shot={4}" -f @($band).Count, $maxX, $physW, @($clipped).Count, (Split-Path -Leaf $shot))
    foreach ($c3 in ($clipped | Select-Object -First 6)) {
        Log-Case 'magnet' 'clipped' 'INFO' ("off-screen row text='{0}' x={1:N0} y={2:N0} w={3:N0}" -f $c3.text, $c3.x, $c3.y, $c3.w)
    }

    Write-Host "FINAL-QA DONE -> $csv"
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
