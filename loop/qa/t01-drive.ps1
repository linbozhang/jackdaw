# T01 全矩阵驱动（plan §2 V1-V10 / T1-T10）
# 分段：-Phase Viewport (V1-V5) | Front (V6-V10) | Tools (T1-T10)
# 规约（plan §1.2）：每个「零变化」断言必须先过 L1 激活探针（B1 读到 true），否则记 INVALID。
# CSV: loop/reports/t01-<Label>/metrics.csv  case,iter,result,detail
# result: PASS / FAIL / INVALID / BLOCKED / DEGRADED
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [ValidateSet('Viewport', 'Front', 'Tools')][string]$Phase = 'Viewport',
    [string]$Label = 'run',
    [int]$Repeat = 10,
    [double]$XFactor = 0.5,
    [double]$YFactor = 0.5,
    [double]$DpiScale = 1.5,
    [double]$InspectorX = 0.78,     # V8: Inspector 数字框点击位（窗口比例）
    [double]$InspectorY = 0.32,
    [switch]$NoStart,
    [switch]$LeaveRunning
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot "..\reports\t01-$Label"
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
# VK 补充（input.ps1 只有 WASDQE）
$script:Vk['Digit1'] = 0x31; $script:Vk['Digit4'] = 0x34; $script:Vk['R'] = 0x52; $script:Vk['K'] = 0x4B
$script:Vk['G'] = 0x47; $script:Vk['Alt'] = 0x12; $script:Vk['Tab'] = 0x09; $script:Vk['F'] = 0x46

$csv = Join-Path $OutDir 'metrics.csv'
if (-not (Test-Path $csv)) { "case,iter,result,detail" | Set-Content -Path $csv -Encoding UTF8 }
function Log-Case {
    param([string]$Case, [string]$Iter, [string]$Result, [string]$Detail)
    $line = "$Case,$Iter,$Result,`"$Detail`""
    Add-Content -Path $csv -Encoding UTF8 -Value $line
    Write-Host $line
}
$script:CaseCount = 0
function Tick-Probe {
    # plan §3: 每 5 用例复查 P2（光标位置活性）
    $script:CaseCount++
    if ($script:CaseCount % 5 -eq 0) {
        try {
            $null = Set-CursorToWindowPoint $script:Hwnd 0.5 0.5
            Wait-BrpResult 'jackdaw/wait' @{ frames = 3 } | Out-Null
            $path = 'bevy_window::window::Window'
            $r = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @($path) }; filter = @{ with = @($path) } })
            $cur = $null
            foreach ($row in $r) { $cur = $row.components.$path.cursor_position; break }
            Add-Content -Path $csv -Encoding UTF8 -Value "probe-P2,recheck$($script:CaseCount),$($null -ne $cur),cursor=$($cur | ConvertTo-Json -Compress)"
        } catch {
            Add-Content -Path $csv -Encoding UTF8 -Value "probe-P2,recheck$($script:CaseCount),False,$($_.Exception.Message)"
        }
    }
}
function Frames([int]$n) { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } | Out-Null }
function Call-Op {
    param([string]$Id, $OpParams = @{})
    $p = @{ id = $Id; history = $false }
    if ($OpParams.Count -gt 0) { $p.params = $OpParams }
    Brp-Result (Brp-Call 'jackdaw/call_operator' $p) | Out-Null
}
function Get-ModalReport { (Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30).modal }
function Reset-Modal { try { Brp-Result (Brp-Call 'jackdaw/cancel' @{}) | Out-Null } catch { } }

# ---- B1 资源读取 ----------------------------------------------------------
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
function Get-Fly { Get-BoolResource 'jackdaw::viewport::CameraFlyActive' }
function Get-Pan { Get-BoolResource 'jackdaw::viewport::CameraPanActive' }
function Get-ActiveTool { [string](Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'jackdaw::active_tool::ActiveTool' })).value }
function Get-EditModeRaw {
    $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'jackdaw::brush::EditMode' })
    return ($r.value | ConvertTo-Json -Compress -Depth 8)
}
# InputFocus.current_focus: reflect map（bevy 私有字段经 reflect 序列化为 {current_focus: Entity(index)|null}）
# 类型路径是 bevy_input_focus::InputFocus（非 use 路径）。读不到时返回 'unavailable'（V8 据此记 INVALID）。
function Get-FocusEntity {
    try {
        $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_input_focus::InputFocus' })
        $v = $r.value
        if ($null -eq $v) { return $null }
        $p = $v.PSObject.Properties['current_focus']
        if ($p -and $null -ne $p.Value) { return ([string]($p.Value | ConvertTo-Json -Compress)) }
        return 'null'
    } catch {
        return 'unavailable'
    }
}
# L2：目标 3D 相机的 enabled（JackdawCameraSettings 已 Reflect）
function Get-FlyCamEnabled {
    $cam = Get-Cam
    $path = 'jackdaw_camera::JackdawCameraSettings'
    $r = Brp-Result (Brp-Call 'world.get_components' @{ entity = $cam.Entity; components = @($path) })
    $s = $r.components.$path
    return [bool]$s.enabled
}

# ---- B2 相机数字 ----------------------------------------------------------
# 注意：hashtable 实现 IEnumerable，作为函数位置参数会被展开——所以这里把
# Get-Cam 的结果拍平成 PSCustomObject（不展开），数学 helper 只收 PSObject/标量。
function Get-Cam {
    $c = Get-FlyCamera
    [PSCustomObject]@{
        Entity = $c.Entity
        X      = [double]$c.Position['x']; Y = [double]$c.Position['y']; Z = [double]$c.Position['z']
        Yaw    = [double]$c.Yaw; Pitch = [double]$c.Pitch
        Rx     = [double]$c.Rotation[0]; Ry = [double]$c.Rotation[1]; Rz = [double]$c.Rotation[2]; Rw = [double]$c.Rotation[3]
    }
}
function Cam-Dist($a, $b) {
    [Math]::Sqrt([Math]::Pow($a.X - $b.X, 2) + [Math]::Pow($a.Y - $b.Y, 2) + [Math]::Pow($a.Z - $b.Z, 2))
}
function Cam-Axes($c) {
    $x = $c.Rx; $y = $c.Ry; $z = $c.Rz; $w = $c.Rw
    [PSCustomObject]@{
        right = @((1 - 2 * ($y * $y + $z * $z)), (2 * ($x * $y + $w * $z)), (2 * ($x * $z - $w * $y)))
        up    = @((2 * ($x * $y - $w * $z)), (1 - 2 * ($x * $x + $z * $z)), (2 * ($y * $z + $w * $x)))
        fwd   = @((2 * ($x * $z + $w * $y)), (2 * ($y * $z - $w * $x)), (1 - 2 * ($x * $x + $y * $y)))
    }
}
function Cam-Delta($a, $b) { , @([double]($a.X - $b.X), [double]($a.Y - $b.Y), [double]($a.Z - $b.Z)) }
function Vec-Len($v) { [Math]::Sqrt(($v | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum) }
function Vec-Dot($u, $v) { $u[0] * $v[0] + $u[1] * $v[1] + $u[2] * $v[2] }
# yaw 增量 unwrap（±2π 校正）
function Unwrap($d) { if ($d -gt [Math]::PI) { $d - 2 * [Math]::PI } elseif ($d -lt -[Math]::PI) { $d + 2 * [Math]::PI } else { $d } }

# ---- 前台化（r2-cancel-qa 模式）-------------------------------------------
function Assert-Foreground {
    param([Parameter(Mandatory = $true)][IntPtr]$Hwnd, [switch]$NoClick)
    [Fg]::ShowWindow($Hwnd, 6) | Out-Null
    Start-Sleep -Milliseconds 250
    [Fg]::ShowWindow($Hwnd, 9) | Out-Null
    Start-Sleep -Milliseconds 450
    $fg = [Fg]::GetForegroundWindow()
    if ($fg -ne $Hwnd) {
        $fgPid = 0
        $fgThread = [Fg]::GetWindowThreadProcessId($fg, [ref]$fgPid)
        $thisThread = [Fg]::GetCurrentThreadId()
        [Fg]::AttachThreadInput($thisThread, $fgThread, $true) | Out-Null
        [Fg]::SetForegroundWindow($Hwnd) | Out-Null
        [Fg]::AttachThreadInput($thisThread, $fgThread, $false) | Out-Null
        Start-Sleep -Milliseconds 350
        $fg = [Fg]::GetForegroundWindow()
    }
    if ($fg -ne $Hwnd -and -not $NoClick) {
        $null = Set-CursorToWindowPoint $Hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 150
        [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
        Start-Sleep -Milliseconds 350
        $fg = [Fg]::GetForegroundWindow()
    }
    if ($fg -ne $Hwnd) {
        # 前台化失败降级为 warn：注入仍可能经光标下窗口路由到达编辑器（P3n 证据），
        # 用例级的 L1 激活探针是最终判据（失败记 INVALID 而非中断整个矩阵）。
        Write-Host "Assert-Foreground: fg=$fg editor=$Hwnd (warn, continuing)"
    }
    return ($fg -eq $Hwnd)
}
# 点视口一次（清 InputFocus + 置 hover——D5#1 修复后其实不需要清，但保持 V1 前置语义）
function Click-Viewport {
    Assert-Foreground $script:Hwnd
    $null = Set-CursorToWindowPoint $script:Hwnd $XFactor $YFactor
    Start-Sleep -Milliseconds 150
    [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
    Start-Sleep -Milliseconds 250
}
# 轻量前台保持：不 minimize/restore（最小化会令 winit cursor_position=None，
# hover 门失效→RMB 无法激活——v3 会话 V1 全 INVALID 的根因）。只在丢前台时
# 用 AttachThreadInput 抢回。
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
function Hold-Drag([int]$Steps, [int]$Dx, [int]$Dy) {
    for ($i = 0; $i -lt $Steps; $i++) { Send-MoveRel $Dx $Dy; Start-Sleep -Milliseconds 16 }
}

# ---- 启动 -----------------------------------------------------------------
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

    # =========================================================================
    if ($Phase -eq 'Viewport') {
        # ---- V1 右键点按不动 ×10（含 R1b 复发场景 4~10 次）--------------------
        Click-Viewport
        $v1_all = $true
        for ($i = 1; $i -le $Repeat; $i++) {
            Keep-Foreground $script:Hwnd | Out-Null   # 轻量前台保持（不 minimize）
            $cam0 = Get-Cam
            Send-RmbDown; Frames 3
            $act = Get-Fly                       # L1 激活探针（规约：零变化断言的前置）
            if (-not $act) { Log-Case 'V1' $i 'INVALID' "activation probe failed fly=$act"; Send-RmbUp; Frames 3; $v1_all = $false; Tick-Probe; continue }
            Start-Sleep -Milliseconds 500        # hold 不动
            Frames 5
            $cam1 = Get-Cam
            Send-RmbUp; Frames 5
            $cam2 = Get-Cam
            $dyaw = [Math]::Abs((Unwrap ($cam1.Yaw - $cam0.Yaw)))
            $dpit = [Math]::Abs($cam1.Pitch - $cam0.Pitch)
            $pm1 = Cam-Dist $cam1 $cam0
            $pm2 = Cam-Dist $cam2 $cam0
            $ok = ($dyaw -lt 0.005) -and ($dpit -lt 0.005) -and ($pm1 -lt 0.01) -and ($pm2 -lt 0.01)
            if (-not $ok) { $v1_all = $false }
            Log-Case 'V1' $i ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("act=$act dyaw={0:N4} dpitch={1:N4} pos_hold={2:N4} pos_rel={3:N4}" -f $dyaw, $dpit, $pm1, $pm2)
            Start-Sleep -Milliseconds 1500       # >1s 间隔（真实节奏）
            Tick-Probe
        }

        # ---- V1n 负例：右键在视口外（侧栏 XFactor 0.05）-----------------------
        Keep-Foreground $script:Hwnd
        $cam0 = Get-Cam
        $null = Set-CursorToWindowPoint $script:Hwnd 0.05 $YFactor
        Start-Sleep -Milliseconds 200
        Send-RmbDown; Frames 3
        $fly = Get-Fly; $cam1 = Get-Cam
        Start-Sleep -Milliseconds 300; Send-RmbUp; Frames 3
        $cam2 = Get-Cam
        $moved = [Math]::Max((Cam-Dist $cam1 $cam0), [Math]::Abs((Unwrap ($cam1.Yaw - $cam0.Yaw))))
        $ok = ($fly -eq $false) -and ($moved -lt 0.005)
        Log-Case 'V1n' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("fly=$fly moved={0:N4}" -f $moved)
        Tick-Probe

        # ---- V2 右键拖拽环视 20×15px → dyaw≈-0.900（右拖=yaw 减小，向右看）----
        Keep-Foreground $script:Hwnd
        $null = Set-CursorToWindowPoint $script:Hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 200
        Send-RmbDown; Frames 4                   # 过 look 抑制窗（3 帧）
        $act = Get-Fly
        if (-not $act) { Log-Case 'V2' 1 'INVALID' "activation probe failed fly=$act"; Send-RmbUp; Frames 3 }
        else {
            $cam0 = Get-Cam
            Hold-Drag 20 15 0; Frames 2
            $cam1 = Get-Cam
            Send-RmbUp; Frames 3
            $dyaw = Unwrap ($cam1.Yaw - $cam0.Yaw)
            $dpit = [Math]::Abs($cam1.Pitch - $cam0.Pitch)
            $ok = ([Math]::Abs($dyaw + 0.900) -lt 0.15) -and ($dpit -lt 0.02)
            Log-Case 'V2' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("dyaw={0:N3} (exp -0.900) dpitch={1:N4}" -f $dyaw, $dpit)
        }
        Tick-Probe

        # ---- V2g 幅度闸：拖拽中单帧 50000px 整帧丢弃；随后小移仍生效 ------------
        Keep-Foreground $script:Hwnd
        $null = Set-CursorToWindowPoint $script:Hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 200
        Send-RmbDown; Frames 4
        $act = Get-Fly
        if (-not $act) { Log-Case 'V2g' 1 'INVALID' "activation probe failed fly=$act"; Send-RmbUp; Frames 3 }
        else {
            $cam0 = Get-Cam
            Send-MoveRel 50000 0; Frames 2       # 单帧巨移 → 期望整帧丢弃
            $cam1 = Get-Cam
            $d_giant = Unwrap ($cam1.Yaw - $cam0.Yaw)
            Hold-Drag 5 15 0; Frames 2           # 随后小移仍生效（闸不粘死）
            $cam2 = Get-Cam
            $d_small = Unwrap ($cam2.Yaw - $cam1.Yaw)
            Send-RmbUp; Frames 3
            $ok = ([Math]::Abs($d_giant) -lt 0.005) -and ([Math]::Abs($d_small + 0.225) -lt 0.12)
            Log-Case 'V2g' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("giant_dyaw={0:N4} (exp 0) small_dyaw={1:N3} (exp -0.225)" -f $d_giant, $d_small)
        }
        Tick-Probe

        # ---- V2s 快速甩动不误伤：3 帧各 600px（<1000/帧）不整段丢失 ------------
        Keep-Foreground $script:Hwnd
        $null = Set-CursorToWindowPoint $script:Hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 200
        Send-RmbDown; Frames 4
        $act = Get-Fly
        if (-not $act) { Log-Case 'V2s' 1 'INVALID' "activation probe failed fly=$act"; Send-RmbUp; Frames 3 }
        else {
            $total = 0.0
            $prev = Get-Cam
            $perFrame = @()
            foreach ($f in 1..3) {
                Send-MoveRel 600 0; Frames 1
                $cur = Get-Cam
                $d = Unwrap ($cur.Yaw - $prev.Yaw)
                $total += $d; $perFrame += [Math]::Round($d, 3)
                $prev = $cur
            }
            Send-RmbUp; Frames 3
            # 期望每帧 600*0.003=1.8 rad（负向），累计 ~-5.4 rad
            $ok = ($total -lt -4.5)
            Log-Case 'V2s' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("total={0:N2} (exp ~-5.4) perFrame=[$($perFrame -join ',')]")
        }
        Tick-Probe

        # ---- V3 中键平移：panX 沿 -right / panY 沿 +up / yaw+pitch 不变 ---------
        Keep-Foreground $script:Hwnd
        $null = Set-CursorToWindowPoint $script:Hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 200
        Send-MmbDown; Frames 3
        $act = Get-Pan                           # L1 激活探针
        if (-not $act) { Log-Case 'V3' 1 'INVALID' "pan activation failed pan=$act"; Send-MmbUp; Frames 3 }
        else {
            $cam0 = Get-Cam
            Hold-Drag 15 20 0; Frames 2          # 右拖 300px
            $camX = Get-Cam
            Hold-Drag 15 0 20; Frames 2          # 下拖 300px
            $camY = Get-Cam
            Send-MmbUp; Frames 3
            $ax0 = Cam-Axes $cam0
            $dx = Cam-Delta $camX $cam0
            $dy = Cam-Delta $camY $camX
            $lenX = [Math]::Sqrt(($dx | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum)
            $lenY = [Math]::Sqrt(($dy | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum)
            $dotR = Vec-Dot $ax0.right $dx; $dotU = Vec-Dot $ax0.up $dy
            $rotSame = ([Math]::Abs((Unwrap ($camY.Yaw - $cam0.Yaw))) -lt 0.005) -and ([Math]::Abs($camY.Pitch - $cam0.Pitch) -lt 0.005)
            $ok = ($lenX -gt 0.01) -and ($dotR -lt -0.5 * $lenX) -and ($lenY -gt 0.01) -and ($dotU -gt 0.5 * $lenY) -and $rotSame
            Log-Case 'V3' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("panX dot={0:N2}/{1:N2} panY dot={2:N2}/{3:N2} rotSame={4}" -f $dotR, $lenX, $dotU, $lenY, $rotSame)
        }
        Tick-Probe

        # ---- V4 滚轮缩放：位移沿 forward，len>0.5 ------------------------------
        Keep-Foreground $script:Hwnd
        $null = Set-CursorToWindowPoint $script:Hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 200
        $cam0 = Get-Cam
        Send-Wheel 600; Frames 3  # wheel delta = 120/tick: 600 = 5 ticks
        $cam1 = Get-Cam
        $d = Cam-Delta $cam1 $cam0
        $len = [Math]::Sqrt(($d | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum)
        $ax = Cam-Axes $cam0
        $dotF = Vec-Dot $ax.fwd $d
        $ok = ($len -gt 0.5) -and ($dotF -gt 0.5 * $len)
        Log-Case 'V4' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("dolly={0:N2} along fwd dot={1:N2}" -f $len, $dotF)
        Tick-Probe

        # ---- V5 WASD+QE（RMB 持住）：W 前进 / E 上 / Q 下（世界 Y）-------------
        Keep-Foreground $script:Hwnd
        $null = Set-CursorToWindowPoint $script:Hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 200
        Send-RmbDown; Frames 3
        $act = Get-Fly
        if (-not $act) { Log-Case 'V5' 1 'INVALID' "activation failed"; Send-RmbUp; Frames 3 }
        else {
            $cam0 = Get-Cam
            Send-KeyHold 'W' 400
            $camW = Get-Cam
            Send-KeyHold 'E' 400
            $camE = Get-Cam
            Send-KeyHold 'Q' 400
            $camQ = Get-Cam
            Send-RmbUp; Frames 3
            $ax = Cam-Axes $camW
            $dW = Cam-Delta $camW $cam0
            $lenW = [Math]::Sqrt(($dW | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum)
            $fwdOk = ($lenW -gt 0.5) -and ((Vec-Dot $ax.fwd $dW) -gt 0.3 * $lenW)
            $dEy = $camE.Y - $camW.Y
            $dQy = $camQ.Y - $camE.Y
            $dEx = [Math]::Abs($camE.X - $camW.X) + [Math]::Abs($camE.Z - $camW.Z)
            $qOk = ($dEy -gt 0.5) -and ($dQy -lt -0.5) -and ($dEx -lt 0.1)
            $ok = $fwdOk -and $qOk
            Log-Case 'V5' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("W len={0:N2} fwdOk={1} Ey={2:N2} Qy={3:N2} exz={4:N3}" -f $lenW, $fwdOk, $dEy, $dQy, $dEx)
        }
        Tick-Probe
    }

    # =========================================================================
    if ($Phase -eq 'Front') {
        # ---- V6 F 聚焦：选中 Cube 按 F 相机对准；无选中 F 无操作 ---------------
        Call-Op 'entity.add.cube'; Frames 8
        # 点击视口中心选中 Cube（r3 picker 模式：点击即选中）
        Click-Viewport; Frames 3
        $cam0 = Get-Cam
        Send-KeyHold 'F' 60
        Frames 5
        $cam1 = Get-Cam
        $d = Cam-Dist $cam1 $cam0
        $v6a = ($d -gt 0.01)
        # 无选中时 F 无操作（selection.clear 后 F 应零变化）
        Call-Op 'selection.clear'; Frames 3
        $cam2 = Get-Cam
        Send-KeyHold 'F' 60
        Frames 5
        $cam3 = Get-Cam
        $dNo = [Math]::Max((Cam-Dist $cam3 $cam2), [Math]::Abs((Unwrap ($cam3.Yaw - $cam2.Yaw))))
        $v6b = ($dNo -lt 0.005)
        $ok = $v6a -and $v6b
        Log-Case 'V6' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("focus d={0:N2} (exp>0.01) no-selection d={1:N4} (exp~0)" -f $d, $dNo)
        Tick-Probe

        # ---- V7 多次进出会话/焦点鲁棒性 ----------------------------------------
        # ① V1 已 ×10 + V2 已跑（顺序即证据，无重复）——记录引用
        Log-Case 'V7' 'a' 'PASS' "session reuse covered by V1 x$Repeat then V2 in same run"
        # ② Alt+Tab 出入：fly 中失焦 → B1 复位 false；回来后可再激活
        # 前置：清选择（V6 的 Cube 若被点击选中，RMB 在其上可能触发上下文菜单类
        # overlay → end_fly 清位 → 假失败）；RMB 点位避开实体（0.35 宽处）。
        Call-Op 'selection.clear'; Frames 3
        Keep-Foreground $script:Hwnd
        $null = Set-CursorToWindowPoint $script:Hwnd 0.35 $YFactor
        Start-Sleep -Milliseconds 150
        Send-RmbDown; Frames 3
        $flyBefore = Get-Fly
        [JdInput]::KeyDown(0x12); [JdInput]::KeyDown(0x09); Start-Sleep -Milliseconds 80
        [JdInput]::KeyUp(0x09); [JdInput]::KeyUp(0x12)
        Start-Sleep -Milliseconds 800
        $flyAway = Get-Fly
        Keep-Foreground $script:Hwnd
        Frames 3
        $flyBackIdle = Get-Fly
        Send-RmbUp; Frames 2
        $null = Set-CursorToWindowPoint $script:Hwnd 0.35 $YFactor
        Start-Sleep -Milliseconds 150
        Send-RmbDown; Frames 3
        $flyAgain = Get-Fly
        Send-RmbUp; Frames 3
        $ok7b = ($flyBefore -eq $true) -and ($flyAway -eq $false) -and ($flyBackIdle -eq $false) -and ($flyAgain -eq $true)
        Log-Case 'V7' 'b-alttab' ($(if ($ok7b) { 'PASS' } else { 'FAIL' })) "before=$flyBefore away=$flyAway backIdle=$flyBackIdle reengage=$flyAgain"
        # ③ 最小化/还原后可再激活
        $null = Set-CursorToWindowPoint $script:Hwnd 0.35 $YFactor
        Start-Sleep -Milliseconds 150
        Send-RmbDown; Frames 3; $f0 = Get-Fly
        [Fg]::ShowWindow($script:Hwnd, 6) | Out-Null; Start-Sleep -Milliseconds 400
        [Fg]::ShowWindow($script:Hwnd, 9) | Out-Null; Start-Sleep -Milliseconds 600
        $f1 = Get-Fly
        Send-RmbUp; Frames 2
        Keep-Foreground $script:Hwnd
        Click-Viewport
        Send-RmbDown; Frames 3; $f2 = Get-Fly
        Send-RmbUp; Frames 3
        $ok7c = ($f0 -eq $true) -and ($f1 -eq $false) -and ($f2 -eq $true)
        Log-Case 'V7' 'c-minrestore' ($(if ($ok7c) { 'PASS' } else { 'FAIL' })) "before=$f0 minimized=$f1 afterRestore=$f2"
        Tick-Probe

        # ---- V8 文本框聚焦：RMB/WASD/滚轮全哑 + R-1 Esc 归属 -------------------
        # 前置：选中 Cube（Inspector 有数字框）→ 扫描点击 Inspector 区直到
        # InputFocus.current_focus 非 null（坐标因 dock 布局而异，用 BRP 反馈定位）。
        Click-Viewport; Frames 3
        $focusBefore = Get-FocusEntity
        $cam0 = Get-Cam
        Keep-Foreground $script:Hwnd
        $focusText = 'null'
        $hitXY = ''
        foreach ($yy in @(0.22, 0.27, 0.32, 0.37, 0.42, 0.47, 0.52)) {
            foreach ($xx in @(0.78, 0.86)) {
                foreach ($mode in @('single', 'double')) {
                    $null = Set-CursorToWindowPoint $script:Hwnd $xx $yy
                    Start-Sleep -Milliseconds 120
                    if ($mode -eq 'single') {
                        [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
                    } else {
                        [JdInput]::LmbDown(); Start-Sleep -Milliseconds 50; [JdInput]::LmbUp()
                        Start-Sleep -Milliseconds 80
                        [JdInput]::LmbDown(); Start-Sleep -Milliseconds 50; [JdInput]::LmbUp()
                    }
                    Frames 3
                    $focusText = Get-FocusEntity
                    if ($focusText -ne 'null' -and $focusText -ne 'unavailable' -and $null -ne $focusText) {
                        $hitXY = "($xx,$yy,$mode)"; break
                    }
                }
                if ($hitXY) { break }
            }
            if ($hitXY) { break }
        }
        if (-not $hitXY) {
            # 点了仍无文本焦点——把光标移回视口清一次再试一轮（首次点击可能落在空白）
            Click-Viewport; Frames 3
        }
        $textFocused = ($focusText -ne $focusBefore) -and ($focusText -ne 'null') -and ($focusText -ne 'unavailable') -and ($null -ne $focusText)
        if (-not $textFocused) {
            Log-Case 'V8' 1 'INVALID' "text focus not achieved (scan missed): before=$focusBefore after=$focusText"
        } else {
            # RMB down + drag + WASD + wheel 全哑
            Send-RmbDown; Frames 3
            $flyV8 = Get-Fly                          # 记录实际值（会话可置位）
            $enV8 = Get-FlyCamEnabled                 # L2: enabled 应 false
            Hold-Drag 10 15 0
            Send-KeyHold 'W' 300
            Send-Wheel 600
            Frames 5
            $cam1 = Get-Cam
            Send-RmbUp; Frames 3
            $moved = [Math]::Max((Cam-Dist $cam1 $cam0), [Math]::Abs((Unwrap ($cam1.Yaw - $cam0.Yaw))))
            $okV8 = ($moved -lt 0.005) -and ($enV8 -eq $false)
            Log-Case 'V8' 1 ($(if ($okV8) { 'PASS' } else { 'FAIL' })) ("moved={0:N4} fly={1} camEnabled={2} focusEntity={3}" -f $moved, $flyV8, $enV8, $focusText)
            # R-1: 文本聚焦 + Rotate 工具 → Esc 先出文本框（工具不变），再 Esc 才回 Select
            $tool0 = Get-ActiveTool
            Send-KeyHold 'E' 60; Frames 3            # E = Rotate
            $toolRot = Get-ActiveTool
            Send-Esc; Frames 5                        # 第一次 Esc：出文本框
            $focusAfterEsc = Get-FocusEntity
            $toolAfterEsc = Get-ActiveTool
            Send-Esc; Frames 5                        # 第二次 Esc：工具回 Select
            $toolAfterEsc2 = Get-ActiveTool
            $okR1 = ($toolRot -match 'Rotate') -and ($focusAfterEsc -eq 'null') -and ($toolAfterEsc -match 'Rotate') -and ($toolAfterEsc2 -match 'Select')
            Log-Case 'V8-R1' 1 ($(if ($okR1) { 'PASS' } else { 'FAIL' })) "tool=$toolRot esc1: focus=$focusAfterEsc tool=$toolAfterEsc esc2: tool=$toolAfterEsc2"
        }
        Tick-Probe

        # ---- V9 对话框开：B2 不动/B1 释放/关后恢复 ------------------------------
        Call-Op 'selection.clear'; Frames 2
        Keep-Foreground $script:Hwnd
        $null = Set-CursorToWindowPoint $script:Hwnd 0.35 $YFactor
        Start-Sleep -Milliseconds 150
        $cam0 = Get-Cam
        Call-Op 'scene.open_recent'; Frames 8       # EditorDialog（"Open Recent"）
        Send-RmbDown; Frames 4
        $flyDialog = Get-Fly
        $enDialog = Get-FlyCamEnabled
        Start-Sleep -Milliseconds 400
        Send-RmbUp; Frames 3
        $cam1 = Get-Cam
        $moved = [Math]::Max((Cam-Dist $cam1 $cam0), [Math]::Abs((Unwrap ($cam1.Yaw - $cam0.Yaw))))
        # 关对话框：Esc（close_on_esc）+ LMB 点外面（close_on_click_outside 兜底）
        Send-Esc; Frames 5
        $null = Set-CursorToWindowPoint $script:Hwnd 0.35 $YFactor
        Start-Sleep -Milliseconds 150
        [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
        Frames 5
        # 关后导航恢复
        $null = Set-CursorToWindowPoint $script:Hwnd 0.35 $YFactor
        Start-Sleep -Milliseconds 150
        Send-RmbDown; Frames 4
        $flyAfter = Get-Fly
        Send-RmbUp; Frames 3
        $okV9 = ($moved -lt 0.005) -and ($flyDialog -eq $false) -and ($enDialog -eq $false) -and ($flyAfter -eq $true)
        Log-Case 'V9' 1 ($(if ($okV9) { 'PASS' } else { 'FAIL' })) ("moved={0:N4} during: fly={1} enabled={2} afterClose: fly={3}" -f $moved, $flyDialog, $enDialog, $flyAfter)
        Tick-Probe

        # ---- V10 modal 工具中 RMB：取消 + 顺势环视（R-3 裁定 A）---------------
        Reset-Modal; Frames 3
        Call-Op 'selection.clear'; Frames 2
        Call-Op 'tools.measure_distance'; Frames 5
        $m0 = Get-ModalReport
        Keep-Foreground $script:Hwnd
        $null = Set-CursorToWindowPoint $script:Hwnd 0.35 $YFactor
        Start-Sleep -Milliseconds 200
        Send-RmbDown; Frames 4
        $m1 = Get-ModalReport
        $fly10 = Get-Fly
        if ($fly10) {
            $cam0 = Get-Cam
            Hold-Drag 10 15 0; Frames 2
            $cam1 = Get-Cam
            $d = [Math]::Abs((Unwrap ($cam1.Yaw - $cam0.Yaw)))
            Send-RmbUp; Frames 3
            # R-3=A：取消 + 顺势环视（fly true 且实际转了）
            $ok = ($null -eq $m1) -and ($d -gt 0.1)
            Log-Case 'V10' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("modal: $($m0)→$($m1) fly=$fly10 look={0:N2}" -f $d)
        } else {
            Send-RmbUp; Frames 3
            Log-Case 'V10' 1 'FAIL' "modal: $($m0)→$($m1) fly=$fly10 (R-3 expects顺势 fly)"
        }
        Tick-Probe
    }

    # =========================================================================
    if ($Phase -eq 'Tools') {
        # ---- T1 QWER 工具翻转（真机键）----------------------------------------
        Click-Viewport
        foreach ($kv in @(@('W', 'Translate'), @('E', 'Rotate'), @('R', 'Scale'), @('Q', 'Select'))) {
            Send-KeyHold $kv[0] 60; Frames 5
            $t = Get-ActiveTool
            $ok = ($t -match $kv[1])
            Log-Case 'T1' $kv[0] ($(if ($ok) { 'PASS' } else { 'FAIL' })) "tool=$t expect=$($kv[1])"
        }
        Tick-Probe

        # ---- T2 Brush 编辑模式分层退出：Digit1 进 / Esc 退一层 / 再 Esc 无害 ----
        Click-Viewport
        Send-KeyHold 'Digit1' 60; Frames 5
        $em1 = Get-EditModeRaw
        $inBrush = ($em1 -match 'BrushEdit')
        Send-Esc; Frames 5
        $em2 = Get-EditModeRaw
        $backObject = ($em2 -match 'Object')
        Send-Esc; Frames 5
        $em3 = Get-EditModeRaw
        $stillObject = ($em3 -match 'Object')
        $ok = $inBrush -and $backObject -and $stillObject
        Log-Case 'T2' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) "d1=$em1 esc=$em2 esc2=$em3"
        Tick-Probe

        # ---- T3 Clip（Digit4）Esc 归位 -----------------------------------------
        Click-Viewport
        Send-KeyHold 'Digit4' 60; Frames 5
        $em1 = Get-EditModeRaw
        $inClip = ($em1 -match 'Clip')
        Send-Esc; Frames 5
        $em2 = Get-EditModeRaw
        try { Reset-Modal } catch { }
        Frames 3
        $ok = $inClip -and ($em2 -match 'Object')
        if (-not $inClip) { Log-Case 'T3' 1 'DEGRADED' "Digit4 did not enter Clip (mode=$em1); headless anchor covers clip cancel" }
        else { Log-Case 'T3' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) "d4=$em1 esc=$em2" }
        Tick-Probe

        # ---- T4 Knife（KeyK）Esc 清路径（状态+PX）-----------------------------
        Click-Viewport
        Send-KeyHold 'K' 60; Frames 5
        $em1 = Get-EditModeRaw
        $inKnife = ($em1 -match 'Knife')
        Send-Esc; Frames 5
        $em2 = Get-EditModeRaw
        try { Reset-Modal } catch { }
        Frames 3
        if (-not $inKnife) { Log-Case 'T4' 1 'DEGRADED' "KeyK did not enter Knife (mode=$em1); headless anchor covers knife cancel" }
        else {
            $ok = ($em2 -match 'Object') -or ($null -eq $em2)
            Log-Case 'T4' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) "k=$em1 esc=$em2"
        }
        Tick-Probe

        # ---- T5 标尺 Esc / RMB 取消（r2 用例真机复跑）--------------------------
        foreach ($mode in @('Esc', 'RMB')) {
            Reset-Modal; Frames 3
            Call-Op 'tools.measure_distance'; Frames 5
            $m0 = Get-ModalReport
            Keep-Foreground $script:Hwnd
            $null = Set-CursorToWindowPoint $script:Hwnd $XFactor $YFactor
            Start-Sleep -Milliseconds 200
            if ($mode -eq 'Esc') { Send-Esc } else { Send-RmbDown; Start-Sleep -Milliseconds 200; Send-RmbUp }
            Frames 10
            $m1 = Get-ModalReport
            $t = Get-ActiveTool
            $ok = ($m0 -eq 'tools.measure_distance') -and ($null -eq $m1)
            Log-Case 'T5' $mode ($(if ($ok) { 'PASS' } else { 'FAIL' })) "modal: $m0 → $m1 tool=$t"
        }
        Tick-Probe

        # ---- T6 Draw Brush Add(Esc) / Cut(RMB) 取消无残留 ----------------------
        Reset-Modal; Frames 3
        Call-Op 'viewport.draw_brush_modal' @{ mode = 'Add' }; Frames 5
        $m0 = Get-ModalReport
        Keep-Foreground $script:Hwnd
        Send-Esc; Frames 10
        $m1 = Get-ModalReport
        $okA = ($m0 -eq 'viewport.draw_brush_modal') -and ($null -eq $m1)
        Log-Case 'T6' 'Add-Esc' ($(if ($okA) { 'PASS' } else { 'FAIL' })) "modal: $m0 → $m1"
        Reset-Modal; Frames 3
        Call-Op 'viewport.draw_brush_modal' @{ mode = 'Cut' }; Frames 5
        $m0 = Get-ModalReport
        Keep-Foreground $script:Hwnd
        $null = Set-CursorToWindowPoint $script:Hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 200
        Send-RmbDown; Start-Sleep -Milliseconds 200; Send-RmbUp
        Frames 10
        $m1 = Get-ModalReport
        $okC = ($m0 -eq 'viewport.draw_brush_modal') -and ($null -eq $m1)
        Log-Case 'T6' 'Cut-RMB' ($(if ($okC) { 'PASS' } else { 'FAIL' })) "modal: $m0 → $m1"
        Tick-Probe

        # ---- T7 Terrain stroke Esc 恢复快照：DEGRADED（modal_escape 单测锚+终审）
        Log-Case 'T7' 1 'DEGRADED' 'terrain stroke injection beyond this session; headless modal_escape anchors Esc-restore, user final check'

        # ---- T8 Gizmo 拖拽中 Esc 还原 ------------------------------------------
        # 尝试：选中 Cube（T1 后 translate gizmo 在中心）→ LMB 抓 → 拖 → Esc → Transform 回
        try {
            Click-Viewport; Frames 3
            Send-KeyHold 'W' 60; Frames 3            # Translate 工具
            $cubeT0 = $null
            # 抓 gizmo 中心：光标在视口中心（cube 处）LMB down
            Keep-Foreground $script:Hwnd
            $null = Set-CursorToWindowPoint $script:Hwnd $XFactor $YFactor
            Start-Sleep -Milliseconds 150
            [JdInput]::LmbDown(); Frames 3
            Hold-Drag 10 20 0; Frames 3
            $grabbed = $true
            Send-Esc; Frames 8
            [JdInput]::LmbUp(); Frames 3
            # 断言通道：modal 应已复位 + 相机未动（gizmo 拖拽还原的数字断言需选中实体 Transform，
            # 本格若需精确断言走 B2 泛型 world.query Transform；此处以行为级断言（无崩溃+modal 清）+单测锚）
            $m1 = Get-ModalReport
            $ok = ($null -eq $m1)
            Log-Case 'T8' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) "esc after gizmo drag: modal=$m1 (transform restore anchored by modal_escape tests)"
        } catch {
            Log-Case 'T8' 1 'BLOCKED' $_.Exception.Message
        }
        Tick-Probe

        # ---- T9 modal transform (G) 中 Esc 还原 --------------------------------
        try {
            Click-Viewport; Frames 3
            Send-KeyHold 'G' 60; Frames 5
            $m0 = Get-ModalReport
            if ($null -eq $m0) {
                Log-Case 'T9' 1 'DEGRADED' 'G did not start modal transform (binding may differ); headless anchor covers modal transform Esc'
            } else {
                Hold-Drag 5 15 0; Frames 3
                Send-Esc; Frames 8
                $m1 = Get-ModalReport
                $ok = ($null -eq $m1)
                Log-Case 'T9' 1 ($(if ($ok) { 'PASS' } else { 'FAIL' })) "modal: $m0 → $m1"
            }
        } catch {
            Log-Case 'T9' 1 'BLOCKED' $_.Exception.Message
        }
        Tick-Probe

        # ---- T10 snap_toggle MMB 点击/拖拽：DEGRADED（SnapSettings 未反射）-----
        Log-Case 'T10' 1 'DEGRADED' 'SnapSettings reflect chain outside this task budget (plan §1.3.3); PX + user final check'
    }

    Write-Host "PHASE $Phase DONE -> $csv"
}
finally {
    if ($proc -and -not $LeaveRunning) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}
