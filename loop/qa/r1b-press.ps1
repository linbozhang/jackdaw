# R1b 真机驱动脚本（复发取证 + Unity 导航契约验收）
# -Drive Press：连续 N 次「RMB 按下-不动-释放」，每次间隔 >1s（默认 1.5s），
#   BRP 每次按下前/后读相机 Transform，定位第几次起跳变与量级（复发取证）。
# -Drive Full：完整契约：
#   1) 10 连按零跳变（含第 4~10 次 = 复发场景）
#   2) RMB 按住拖拽环视正常
#   3) MMB 按住拖拽平移（方向断言：水平拖 → 相机沿 -right；垂直拖 → 相机沿 +up）
#   4) 滚轮缩放（perspective dolly 沿 forward）
#   5) RMB+W 位移回归
# 用法：
#   powershell -ExecutionPolicy Bypass -File r1b-press.ps1 -Drive Press -Repeat 10 -Label repro
#   powershell -ExecutionPolicy Bypass -File r1b-press.ps1 -Drive Full -Repeat 10 -Label fixed
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [int]$Repeat = 10,
    [ValidateSet('Press', 'Full')][string]$Drive = 'Press',
    [string]$Label = 'run',
    [string]$OutDir = '',
    [int]$HoldMs = 500,        # RMB 按下后不动的保持时长
    [int]$GapMs = 1500,        # 每轮间隔（>1s，模拟用户真实节奏）
    [double]$XFactor = 0.5,
    [double]$YFactor = 0.5,
    [switch]$NoStart,
    [switch]$LeaveRunning
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "..\reports\r1b-$Label" }
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')
. (Join-Path $PSScriptRoot 'screenshot.ps1')

# 前台化基建（照 r2-cancel-qa.ps1）：后台进程的 SetForegroundWindow 会被
# Windows 拒绝，手势（RMB fly / MMB pan / motion）将路由到别处——必须
# AttachThreadInput + 最小化/还原真正取得前台。
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

function Assert-Foreground {
    param([Parameter(Mandatory = $true)][IntPtr]$Hwnd)
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
    if ($fg -ne $Hwnd) {
        # Real-user focus: click the viewport (r2-cancel-qa.ps1 pattern).
        $null = Set-CursorToWindowPoint $Hwnd 0.5 0.5
        Start-Sleep -Milliseconds 150
        [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
        Start-Sleep -Milliseconds 350
        $fg = [Fg]::GetForegroundWindow()
    }
    if ($fg -ne $Hwnd) {
        # One more restore attempt; the desktop may be contended.
        [Fg]::ShowWindow($Hwnd, 6) | Out-Null
        Start-Sleep -Milliseconds 250
        [Fg]::ShowWindow($Hwnd, 9) | Out-Null
        Start-Sleep -Milliseconds 450
        $fg = [Fg]::GetForegroundWindow()
    }
    if ($fg -ne $Hwnd) { throw "foreground failed: fg=$fg editor=$Hwnd" }
}

$csv = Join-Path $OutDir 'metrics.csv'
"log,iter,phase,yaw0,pitch0,yaw1,pitch1,dyaw_hold,dpitch_hold,hold_ok,dyaw_release,dpitch_release,pos_move_len,pan_dir_right,pan_dir_up,pan_len,wheel_dolly,wheel_dolly_fwd,ok" |
    Set-Content -Path $csv -Encoding UTF8
function Log-Metric {
    param([string]$Line)
    Add-Content -Path $csv -Encoding UTF8 -Value $Line
    Write-Host $Line
}
function Frames([int]$n) { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } | Out-Null }
function Cam-Dist($a, $b) {
    [Math]::Sqrt([Math]::Pow($a.x - $b.x, 2) + [Math]::Pow($a.y - $b.y, 2) + [Math]::Pow($a.z - $b.z, 2))
}
# 四元数 [x,y,z,w] → right/up/forward 世界轴（camera_system 无 roll，YXZ）
function Quat-Axes($q) {
    $x = [double]$q[0]; $y = [double]$q[1]; $z = [double]$q[2]; $w = [double]$q[3]
    return @{
        right  = @((1 - 2 * ($y * $y + $z * $z)), (2 * ($x * $y + $w * $z)), (2 * ($x * $z - $w * $y)))
        up     = @((2 * ($x * $y - $w * $z)), (1 - 2 * ($x * $x + $z * $z)), (2 * ($y * $z + $w * $x)))
        fwd    = @((2 * ($x * $z + $w * $y)), (2 * ($y * $z - $w * $x)), (1 - 2 * ($x * $x + $y * $y)))
    }
}
function Dot3($a, $b) { $a[0] * $b[0] + $a[1] * $b[1] + $a[2] * $b[2] }

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

try {
    Wait-EditorReady -TimeoutSec 180
    Write-Host "editor ready on port $Port"
    $idle = $false
    foreach ($try in 1..6) {
        try { Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null; $idle = $true; break }
        catch { Write-Host "idle wait retry $try"; Start-Sleep -Seconds 2 }
    }
    if (-not $idle) { throw 'editor never reached idle' }

    $failures = @()
    $hwnd = Get-JackdawHwnd

    # ---- 第 1 段：连续 RMB 按下-不动-释放（取证 + 契约 1）----
    for ($i = 1; $i -le $Repeat; $i++) {
        Reset-Modal; Frames 10
        $c0 = Get-FlyCamera
        Assert-Foreground $hwnd
        $pt = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 150
        Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
        Start-Sleep -Milliseconds 100

        Send-RmbDown
        Start-Sleep -Milliseconds $HoldMs
        $c1 = Get-FlyCamera
        Send-RmbUp
        Start-Sleep -Milliseconds 300
        $c2 = Get-FlyCamera

        $dyawH = [Math]::Abs($c1.Yaw - $c0.Yaw); $dpitchH = [Math]::Abs($c1.Pitch - $c0.Pitch)
        $dyawR = [Math]::Abs($c2.Yaw - $c0.Yaw); $dpitchR = [Math]::Abs($c2.Pitch - $c0.Pitch)
        $holdOk = ($dyawH -lt 0.005) -and ($dpitchH -lt 0.005)
        $releaseOk = ($dyawR -lt 0.005) -and ($dpitchR -lt 0.005)
        $posMove = Cam-Dist $c0.Position $c2.Position
        if (-not $holdOk) { $failures += "press${i}:HOLD_JUMP(dyaw=$('{0:F4}' -f $dyawH),dpitch=$('{0:F4}' -f $dpitchH))" }
        if (-not $releaseOk) { $failures += "press${i}:RELEASE_JUMP(dyaw=$('{0:F4}' -f $dyawR),dpitch=$('{0:F4}' -f $dpitchR))" }
        if ($posMove -gt 0.01) { $failures += "press${i}:POS_MOVE($('{0:F3}' -f $posMove))" }
        Log-Metric ("{0},{1},press,{2:F6},{3:F6},{4:F6},{5:F6},{6:F6},{7:F6},{8},{9:F6},{10:F6},{11:F3},,,,," -f `
                $Label, $i, $c0.Yaw, $c0.Pitch, $c1.Yaw, $c1.Pitch, $dyawH, $dpitchH, $holdOk, $dyawR, $dpitchR, $posMove)
        Start-Sleep -Milliseconds $GapMs
    }
    Save-WindowScreenshot $hwnd (Join-Path $OutDir 'after-press-series.png') | Out-Null

    if ($Drive -eq 'Full') {
        # ---- 第 2 段：RMB 按住拖拽环视 ----
        Reset-Modal; Frames 10
        $c0 = Get-FlyCamera
        Assert-Foreground $hwnd
        $pt = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 150
        Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
        Start-Sleep -Milliseconds 100
        Send-RmbDown
        Start-Sleep -Milliseconds 500
        1..20 | ForEach-Object { Send-MoveRel 15 0; Start-Sleep -Milliseconds 16 }
        Start-Sleep -Milliseconds 300
        $c1 = Get-FlyCamera
        Send-RmbUp
        Frames 10
        $dyawL = [Math]::Abs($c1.Yaw - $c0.Yaw); $dpitchL = [Math]::Abs($c1.Pitch - $c0.Pitch)
        $lookOk = ($dyawL -gt 0.1) -and ($dpitchL -lt 0.02)
        if (-not $lookOk) { $failures += "look(dyaw=$('{0:F4}' -f $dyawL),dpitch=$('{0:F4}' -f $dpitchL))" }
        Log-Metric ("{0},1,look,{1:F6},{2:F6},{3:F6},{4:F6},{5:F6},{6:F6},{7},,,,,,,," -f `
                $Label, $c0.Yaw, $c0.Pitch, $c1.Yaw, $c1.Pitch, $dyawL, $dpitchL, $lookOk)

        # ---- 第 3 段：MMB 平移（水平拖 → 相机 -right；垂直拖 → 相机 +up）----
        Reset-Modal; Frames 10
        $m0 = Get-FlyCamera
        Write-Host ("panX m0: type={0} pos.x={1} rot={2}" -f $m0.GetType().Name, $m0.Position.x, ($m0.Rotation -join '/'))
        $axes = Quat-Axes $m0.Rotation
        Assert-Foreground $hwnd
        $pt = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 150
        Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
        Start-Sleep -Milliseconds 100
        Send-MmbDown
        Start-Sleep -Milliseconds 300
        1..20 | ForEach-Object { Send-MoveRel 20 0; Start-Sleep -Milliseconds 16 }
        Start-Sleep -Milliseconds 300
        $m1 = Get-FlyCamera
        Write-Host ("panX m1: type={0} pos.x={1}" -f $m1.GetType().Name, $m1.Position.x)
        Send-MmbUp
        Frames 10
        # PowerShell 逗号数组优先级高于减法（a - b, c 解析为 a - (b,c)），
        # 必须逐个赋值再组数组。
        $dx = [double]$m1.Position.x - [double]$m0.Position.x
        $dy = [double]$m1.Position.y - [double]$m0.Position.y
        $dz = [double]$m1.Position.z - [double]$m0.Position.z
        $d = @($dx, $dy, $dz)
        $panLen = [Math]::Sqrt($d[0] * $d[0] + $d[1] * $d[1] + $d[2] * $d[2])
        $dotRight = Dot3 $d $axes.right   # 期望为负（相机向 -right）
        $panRotOk = ([Math]::Abs($m1.Yaw - $m0.Yaw) -lt 0.005) -and ([Math]::Abs($m1.Pitch - $m0.Pitch) -lt 0.005)
        $panOkX = ($panLen -gt 0.5) -and ($dotRight -lt -0.5 * $panLen) -and $panRotOk
        if (-not $panOkX) { $failures += "panX(len=$('{0:F3}' -f $panLen),dotRight=$('{0:F3}' -f $dotRight),rotOk=$panRotOk)" }
        Log-Metric ("{0},1,panX,,,,,,,rot_ok={1},,,,,{2:F3},{3:F3},,," -f $Label, $panRotOk, ($dotRight / $panLen), $panLen)

        # 垂直拖：相机 +up
        Reset-Modal; Frames 10
        $v0 = Get-FlyCamera
        $axesV = Quat-Axes $v0.Rotation
        Assert-Foreground $hwnd
        $pt = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 150
        Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
        Start-Sleep -Milliseconds 100
        Send-MmbDown
        Start-Sleep -Milliseconds 300
        1..15 | ForEach-Object { Send-MoveRel 0 20; Start-Sleep -Milliseconds 16 }
        Start-Sleep -Milliseconds 300
        $v1 = Get-FlyCamera
        Send-MmbUp
        Frames 10
        $dvx = [double]$v1.Position.x - [double]$v0.Position.x
        $dvy = [double]$v1.Position.y - [double]$v0.Position.y
        $dvz = [double]$v1.Position.z - [double]$v0.Position.z
        $dv = @($dvx, $dvy, $dvz)
        $panLenV = [Math]::Sqrt($dv[0] * $dv[0] + $dv[1] * $dv[1] + $dv[2] * $dv[2])
        $dotUp = Dot3 $dv $axesV.up      # 期望为正（光标下移 → 内容下移 → 相机 +up）
        $panOkY = ($panLenV -gt 0.5) -and ($dotUp -gt 0.5 * $panLenV)
        if (-not $panOkY) { $failures += "panY(len=$('{0:F3}' -f $panLenV),dotUp=$('{0:F3}' -f $dotUp))" }
        Log-Metric ("{0},1,panY,,,,rot_ok=1,,,,,,{1:F3},,{2:F3},,," -f $Label, ($dotUp / $panLenV), $panLenV)

        # ---- 第 4 段：滚轮缩放（perspective dolly 沿 forward）----
        Reset-Modal; Frames 10
        $w0 = Get-FlyCamera
        $axesW = Quat-Axes $w0.Rotation
        Assert-Foreground $hwnd
        $pt = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 150
        Send-Wheel 3
        Start-Sleep -Milliseconds 400
        $w1 = Get-FlyCamera
        Frames 10
        $dwx = [double]$w1.Position.x - [double]$w0.Position.x
        $dwy = [double]$w1.Position.y - [double]$w0.Position.y
        $dwz = [double]$w1.Position.z - [double]$w0.Position.z
        $dw = @($dwx, $dwy, $dwz)
        $wheelLen = [Math]::Sqrt($dw[0] * $dw[0] + $dw[1] * $dw[1] + $dw[2] * $dw[2])
        $dotFwd = Dot3 $dw $axesW.fwd     # 向前滚 = zoom in = +forward
        $wheelOk = ($wheelLen -gt 0.5) -and ($dotFwd -gt 0.5 * $wheelLen)
        if (-not $wheelOk) { $failures += "wheel(len=$('{0:F3}' -f $wheelLen),dotFwd=$('{0:F3}' -f $dotFwd))" }
        Log-Metric ("{0},1,wheel,,,,rot_ok=1,,,,,,,,{1:F3},{2:F3}," -f $Label, $wheelLen, ($dotFwd / $wheelLen))

        # ---- 第 5 段：RMB+W 位移回归 ----
        Reset-Modal; Frames 10
        $p0 = Get-FlyCamera
        Assert-Foreground $hwnd
        $pt = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 150
        Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
        Start-Sleep -Milliseconds 100
        Send-RmbDown
        Start-Sleep -Milliseconds 200
        Send-KeyHold 'W' -Ms 400
        Start-Sleep -Milliseconds 300
        $p1 = Get-FlyCamera
        Send-RmbUp
        Frames 10
        $moveLen = Cam-Dist $p0.Position $p1.Position
        $moveOk = $moveLen -gt 0.5
        if (-not $moveOk) { $failures += "wasd(dist=$('{0:F3}' -f $moveLen))" }
        Log-Metric ("{0},1,wasd,,,,,,,,,,,move_len={1:F3},move_ok={2},,," -f $Label, $moveLen, $moveOk)

        Save-WindowScreenshot $hwnd (Join-Path $OutDir 'full-final.png') | Out-Null
    }

    Write-Host ''
    Write-Host "==== summary [$Label] drive=$Drive repeat=$Repeat hold=${HoldMs}ms gap=${GapMs}ms ===="
    Write-Host "metrics -> $csv"
    if ($failures.Count -eq 0) {
        Write-Host 'RESULT: PASS (all assertions held)'
        $code = 0
    } else {
        Write-Host "RESULT: FAIL ($($failures.Count) failures)"
        $failures | ForEach-Object { Write-Host "  - $_" }
        $code = 1
    }
    exit $code
}
finally {
    if ($proc -and -not $LeaveRunning) {
        Write-Host "stopping editor pid=$($proc.Id)"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
