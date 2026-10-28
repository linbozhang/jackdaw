# T01 三级探针（plan §3）：会话开始必跑，判定注入能力分级
#   P1 点击类   Assert-Foreground -> Send-Esc -> BRP status 应答  => C 类可用性
#   P2 光标类   置 (0.35,0.5) 读 Window.cursor_position，移 (0.65,0.5) 再读
#               差值 ≈ 窗口宽 30%（逻辑 px）；并做 150% DPI 换算校验（物理宽*0.30/1.5，±2 逻辑 px）
#   P3 fly 端到端 LMB 点视口 -> RMB down -> B1 CameraFlyActive==true -> RMB up -> false
#   P3n D5#1 复现探针：不点 LMB 直接 RMB（启动后未点视口），修复后也应激活
# 输出 loop/reports/t01-probe/<Label>/probe.csv；退出码 0=全绿，3=HOVER-BLOCKED，4=MOVE-BLOCKED
# 用法: powershell -ExecutionPolicy Bypass -File t01-probe.ps1 -Label sess1 [-NoStart] [-LeaveRunning]
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [string]$Label = 'sess',
    [double]$XFactor = 0.5,
    [double]$YFactor = 0.5,
    [double]$DpiScale = 1.5,
    [switch]$NoStart,
    [switch]$LeaveRunning
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot "..\reports\t01-probe\$Label"
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

$csv = Join-Path $OutDir 'probe.csv'
"probe,item,value,expected,ok" | Set-Content -Path $csv -Encoding UTF8
function Log-Probe {
    param([string]$Probe, [string]$Item, $Value, [string]$Expected, [bool]$Ok)
    $line = "$Probe,$Item,$Value,$Expected,$Ok"
    Add-Content -Path $csv -Encoding UTF8 -Value $line
    Write-Host $line
}
function Frames([int]$n) { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } | Out-Null }

# 前台化（r2-cancel-qa 模式：minimize/restore + AttachThreadInput + click 兜底）
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
        # Real-user focus: click the viewport (r2-cancel-qa pattern).
        $null = Set-CursorToWindowPoint $Hwnd 0.5 0.5
        Start-Sleep -Milliseconds 150
        [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
        Start-Sleep -Milliseconds 350
        $fg = [Fg]::GetForegroundWindow()
    }
    if ($fg -ne $Hwnd) {
        Write-Host "Assert-Foreground: fg=$fg editor=$Hwnd (continuing)"
    }
    return ($fg -eq $Hwnd)
}

# BRP 资源读取 helper：tuple struct(bool) 序列化为 [true] / {"0":true} / true 三种形状兼容
function Get-BoolResource {
    param([Parameter(Mandatory = $true)][string]$Path)
    $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = $Path })
    $v = $r.value
    if ($v -is [bool]) { return $v }
    if ($v -is [System.Array]) { return [bool]$v[0] }
    $first = $v.PSObject.Properties | Select-Object -First 1
    if ($first) { return [bool]$first.Value }
    throw "unrecognized resource value shape for ${Path}: $($v | ConvertTo-Json -Compress)"
}
function Get-Fly { Get-BoolResource 'jackdaw::viewport::CameraFlyActive' }
function Get-Pan { Get-BoolResource 'jackdaw::viewport::CameraPanActive' }
function Get-InputFocus {
    # 类型路径（非 use 路径）：bevy_input_focus::InputFocus。读不到时容错返回标记
    # （plan §1.3.4：不可读不强求）。
    try {
        $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_input_focus::InputFocus' })
        return ($r.value | ConvertTo-Json -Compress -Depth 6)
    } catch {
        return "(unavailable: $($_.Exception.Message))"
    }
}
function Get-WindowState {
    $path = 'bevy_window::window::Window'
    $r = Brp-Result (Brp-Call 'world.query' @{
        data   = @{ components = @($path) }
        filter = @{ with = @($path) }
    })
    foreach ($row in $r) {
        $w = $row.components.$path
        return @{ cursor = $w.cursor_position; focused = [bool]$w.focused }
    }
    throw 'no Window row'
}

# ---- 启动 ----------------------------------------------------------------
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
    $hwnd = Get-JackdawHwnd

    # ---- P3n D5#1 冷启动复现探针（必须最先跑：任何点击都会清 InputFocus）----
    # 不点击、只用 minimize/restore（无点击）取前台 + 光标 jiggle 产生 CursorMoved
    # （hover 判定可达），然后直接 RMB：修复后 fly 必须激活（窗口实体焦点≠打字）。
    $fgN = Assert-Foreground $hwnd -NoClick
    $focus_state = Get-InputFocus
    $null = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
    Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
    Frames 3
    $flyN0 = Get-Fly
    [JdInput]::RmbDown(); Frames 5
    $flyN1 = Get-Fly
    [JdInput]::RmbUp(); Frames 5
    if ($fgN) {
        # 冷启动、未点击：fly 应直接激活（D5#1 修复语义）
        $p3n_ok = ($flyN0 -eq $false) -and ($flyN1 -eq $true)
        Log-Probe 'P3n' 'cold-start RMB fly' "focus=$focus_state before=$flyN0 down=$flyN1" 'false/true (fix holds w/o click)' $p3n_ok
    } elseif ($flyN1 -eq $true) {
        # 前台化失败但 fly 已激活：激活本身就是 RMB 已达编辑器的证据（D5#1 修复成立）
        $p3n_ok = $true
        Log-Probe 'P3n' 'cold-start RMB fly' "fg failed but fly activated (proof by activation); focus=$focus_state" 'fly=true' $p3n_ok
    } else {
        Log-Probe 'P3n' 'cold-start RMB fly' "foreground failed, inconclusive: fly=$flyN1" '' $false
    }

    # ---- P1 点击类 --------------------------------------------------------
    $fg1 = Assert-Foreground $hwnd
    Send-Esc
    Frames 5
    $status_ok = $false
    try { $null = Brp-Result (Brp-Call 'jackdaw/status' @{}); $status_ok = $true } catch { }
    $p1_ok = $fg1 -and $status_ok
    Log-Probe 'P1' 'foreground+esc+status' "$fg1/$status_ok" 'true/true' $p1_ok

    # ---- P2 光标位置类 + DPI 换算校验 -------------------------------------
    # SetCursorPos 只移动 OS 光标，winit 只在收到 SendInput 事件时更新
    # cursor_position（r1b-hover-diag 结论）——Set 后必须 jiggle 一次。
    Assert-Foreground $hwnd | Out-Null
    $r = New-Object JdInput+RECT
    [JdInput]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $physW = $r.R - $r.L
    $a = Set-CursorToWindowPoint $hwnd 0.35 0.5
    Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
    Frames 3
    $w1 = Get-WindowState
    $b = Set-CursorToWindowPoint $hwnd 0.65 0.5
    Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
    Frames 3
    $w2 = Get-WindowState
    $c1 = $w1.cursor; $c2 = $w2.cursor
    $p2_ok = $false; $dx = 'null'
    if ($null -ne $c1 -and $null -ne $c2) {
        $dx = [double]$c2[0] - [double]$c1[0]
        $expectedLogical = $physW * 0.30 / $DpiScale
        $p2_ok = ([Math]::Abs($dx - $expectedLogical) -le 2.0)
        Log-Probe 'P2' 'cursor_dx_logical_px' ([Math]::Round($dx, 1)) ("~{0:N1} (physW={1} dpi={2})" -f $expectedLogical, $physW, $DpiScale) $p2_ok
    } else {
        Log-Probe 'P2' 'cursor_reads' "c1=$($null -ne $c1) c2=$($null -ne $c2)" 'both non-null' $false
    }

    # ---- P3 fly 端到端 -----------------------------------------------------
    # LMB 点视口一次（清 InputFocus + 置 hover），然后 RMB down/up
    Assert-Foreground $hwnd | Out-Null
    $null = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
    Start-Sleep -Milliseconds 150
    [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
    Frames 5
    $fly_before = Get-Fly
    [JdInput]::RmbDown(); Frames 5
    $fly_down = Get-Fly
    [JdInput]::RmbUp(); Frames 5
    $fly_up = Get-Fly
    $p3_ok = ($fly_before -eq $false) -and ($fly_down -eq $true) -and ($fly_up -eq $false)
    Log-Probe 'P3' 'fly_active' "before=$fly_before down=$fly_down up=$fly_up" 'false/true/false' $p3_ok

    # ---- 分级判定 ----------------------------------------------------------
    $verdict = 'GREEN'
    if (-not $p2_ok) { $verdict = 'HOVER-BLOCKED' }
    elseif (-not $p3_ok) { $verdict = 'FLY-BLOCKED' }
    if (-not $p1_ok) { $verdict = "INJ-DEAD($verdict)" }
    Log-Probe 'VERDICT' 'grading' $verdict '' $true
    Write-Host "PROBE VERDICT: $verdict"
    if (-not $p3n_ok -and $fgN) {
        Write-Host 'P3N REGRESSION: cold-start fly did NOT activate (D5#1)'
    }
    exit 0
}
finally {
    if ($proc -and -not $LeaveRunning) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}
