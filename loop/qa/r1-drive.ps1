# R1 真机验证驱动脚本（feature-05 T1 契约验收）
# 流程：启动编辑器（JACKDAW_OPEN_PROJECT）→ 就绪 → 每轮：
#   1) BRP 读相机基线  2) 视口中心 RMB 按下（不动）500ms  3) 再读相机断言旋转未跳变
#   4) 按住拖动 20x(15,0) 断言环视生效  5) W 按住断言位移  6) 松开 RMB  7) 截图留档
# 用法示例：
#   powershell -File r1-drive.ps1 -Exe E:\Project\rust\jackdaw\target\debug\jackdaw.exe `
#     -Repeat 10 -Label fixed -Drive Full
#   powershell -File r1-drive.ps1 -Drive Press -Repeat 5 -GrabEnv confined -Label confined
#   -Drive Press       仅「按下不动→松开」（判别实验用，配合 -GrabEnv）
#   -Drive PressMoving 「移动中按下」：模拟用户真实手势（RMB 落下瞬间手还在动，
#                      候选 1「驱动在 ClipCursor 收紧瞬间合成 raw delta」的复现形态）
#   -Drive Full        完整契约验收（press 断言 + 环视 + W 位移）
# 判别构建支持：-GrabEnv locked/confined/none 写入 JACKDAW_FLY_GRAB（仅判别版二进制读取）。
# 实测注意：SetCursorPos 的 WM_MOUSEMOVE 不被 winit 记账（cursor_position 保持 null），
# hover 注册必须靠 SendInput 相对移动（真实 WM_INPUT/WM_MOUSEMOVE）；脚本在按下前
# 固定做一次 ±2px jiggle。
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [string]$GrabEnv = 'locked',
    [int]$Repeat = 10,
    [ValidateSet('Press', 'PressMoving', 'Full')][string]$Drive = 'Full',
    [string]$Label = 'run',
    [string]$OutDir = '',
    [double]$XFactor = 0.5,
    [double]$YFactor = 0.5,
    [switch]$NoStart,          # 附加到已运行的编辑器（不自启）
    [switch]$LeaveRunning
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "..\reports\r1-$Label" }
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')
. (Join-Path $PSScriptRoot 'screenshot.ps1')

$csv = Join-Path $OutDir 'metrics.csv'
"log,iter,phase,yaw0,pitch0,x0,y0,z0,yaw1,pitch1,dyaw_press,dpitch_press,press_ok,dyaw_look,dpitch_look,look_ok,dist_move,move_ok" | Set-Content -Path $csv -Encoding UTF8
function Log-Metric {
    param([string]$Line)
    Add-Content -Path $csv -Encoding UTF8 -Value $Line
    Write-Host $Line
}

$proc = $null
if (-not $NoStart) {
    # 清理旧实例（手册 §5.6 前置 + 风险 6：多实例端口冲突）
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
    }
    Start-Sleep -Milliseconds 500

    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT = "$Port"
    if ($GrabEnv) { $env:JACKDAW_FLY_GRAB = $GrabEnv } else { Remove-Item Env:JACKDAW_FLY_GRAB -ErrorAction SilentlyContinue }
    $stdout = Join-Path $OutDir 'editor-stdout.log'
    $stderr = Join-Path $OutDir 'editor-stderr.log'
    Write-Host "starting editor: $Exe  port=$Port grab=$GrabEnv"
    $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    Write-Host "editor pid=$($proc.Id), stdout -> $stdout"
}

try {
    Wait-EditorReady -TimeoutSec 90
    Write-Host "editor ready on port $Port"
    # 资产管线就绪（编辑器忙时首个请求可能超时，容错重试）
    $idle = $false
    foreach ($try in 1..6) {
        try {
            Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null
            $idle = $true
            break
        } catch { Write-Host "idle wait retry $try"; Start-Sleep -Seconds 2 }
    }
    if (-not $idle) { throw 'editor never reached idle' }

    $failures = @()
    for ($i = 1; $i -le $Repeat; $i++) {
        Reset-Modal
        Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null

        # 1) 基线
        $c0 = Get-FlyCamera
        # 2) 聚焦 + 光标到视口中心 + jiggle（保证 winit 收到真实相对移动、hover 注册）
        $hwnd = Get-JackdawHwnd
        Focus-Jackdaw $hwnd
        $pt = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
        Start-Sleep -Milliseconds 150
        Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
        Start-Sleep -Milliseconds 100

        if ($Drive -eq 'PressMoving') {
            # 移动流进行到一半时按下 RMB，继续 4 个移动后停住 → 读相机 → 松开。
            # 按下与移动之间不能插 BRP 读（会清掉在途运动），基线取 jiggle 后的 c0。
            # 期望：7×15px 的正常环视 ≈ 0.315 rad；用户症状形态 = 单帧尖峰导致
            # 数 rad 级跳变（dyaw>1.0 或 dpitch>0.5 记为 JUMP）。
            1..3 | ForEach-Object { Send-MoveRel 15 0; Start-Sleep -Milliseconds 30 }
            Send-RmbDown
            1..4 | ForEach-Object { Send-MoveRel 15 0; Start-Sleep -Milliseconds 30 }
            Start-Sleep -Milliseconds 400
            $c1 = Get-FlyCamera
            Send-RmbUp
            Start-Sleep -Milliseconds 200
            $dyawM = $c1.Yaw - $c0.Yaw; $dpitchM = $c1.Pitch - $c0.Pitch
            $jump = ([Math]::Abs($dyawM) -gt 1.0) -or ([Math]::Abs($dpitchM) -gt 0.5)
            Log-Metric ("{0},{1},pressmoving,{2:F6},{3:F6},,,,{4:F6},{5:F6},{6:F6},{7:F6},{8},,,,," -f `
                    $Label, $i, $c0.Yaw, $c0.Pitch, $c1.Yaw, $c1.Pitch, [Math]::Abs($dyawM), [Math]::Abs($dpitchM), (-not $jump))
            if ($jump) { $failures += "iter${i}:JUMP(dyaw=$('{0:F4}' -f $dyawM),dpitch=$('{0:F4}' -f $dpitchM))" }
            Save-WindowScreenshot $hwnd (Join-Path $OutDir ("pm-{0:D2}.png" -f $i)) | Out-Null
            Start-Sleep -Milliseconds 400
            continue
        }

        Send-RmbDown
        Start-Sleep -Milliseconds 500
        # 3) 按下瞬间断言（容差 0.005 rad，见 feature-05 方案 §7 T1 第 2 条）
        $c1 = Get-FlyCamera
        $dyawP = [Math]::Abs($c1.Yaw - $c0.Yaw); $dpitchP = [Math]::Abs($c1.Pitch - $c0.Pitch)
        $pressOk = ($dyawP -lt 0.005) -and ($dpitchP -lt 0.005)

        if ($Drive -eq 'Press') {
            Send-RmbUp
            Start-Sleep -Milliseconds 200
            Log-Metric ("{0},{1},press,{2:F6},{3:F6},,,,{4:F6},{5:F6},{6:F6},{7:F6},{8},,,,," -f `
                    $Label, $i, $c0.Yaw, $c0.Pitch, $c1.Yaw, $c1.Pitch, $dyawP, $dpitchP, $pressOk)
            if (-not $pressOk) { $failures += "iter${i}:press(dyaw=$('{0:F4}' -f $dyawP),dpitch=$('{0:F4}' -f $dpitchP))" }
            Save-WindowScreenshot $hwnd (Join-Path $OutDir ("press-{0:D2}.png" -f $i)) | Out-Null
            Start-Sleep -Milliseconds 400
            continue
        }

        # 4) 环视：按住拖 20x(15,0)
        1..20 | ForEach-Object { Send-MoveRel 15 0; Start-Sleep -Milliseconds 16 }
        Start-Sleep -Milliseconds 300
        $c2 = Get-FlyCamera
        $dyawL = [Math]::Abs($c2.Yaw - $c1.Yaw); $dpitchL = [Math]::Abs($c2.Pitch - $c1.Pitch)
        # 期望 yaw 明显变化（20*15px*0.003 ≈ 0.9 rad，下限 0.1），pitch 基本不动（纯水平移动，上限 0.02）
        $lookOk = ($dyawL -gt 0.1) -and ($dpitchL -lt 0.02)

        # 5) W 按住 400ms：位移（speed 10 → ~4 单位，下限 0.5）
        Send-KeyHold 'W' -Ms 400
        Start-Sleep -Milliseconds 300
        $c3 = Get-FlyCamera
        $dist = [Math]::Sqrt(
            [Math]::Pow($c3.Position.x - $c2.Position.x, 2) +
            [Math]::Pow($c3.Position.y - $c2.Position.y, 2) +
            [Math]::Pow($c3.Position.z - $c2.Position.z, 2))
        $moveOk = $dist -gt 0.5

        # 6) 松开
        Send-RmbUp
        Start-Sleep -Milliseconds 200

        Log-Metric ("{0},{1},full,{2:F6},{3:F6},{4:F3},{5:F3},{6:F3},{7:F6},{8:F6},{9:F6},{10:F6},{11},{12:F6},{13:F6},{14},{15:F3},{16}" -f `
                $Label, $i, $c0.Yaw, $c0.Pitch, $c0.Position.x, $c0.Position.y, $c0.Position.z,
                $c1.Yaw, $c1.Pitch, $dyawP, $dpitchP, $pressOk, $dyawL, $dpitchL, $lookOk, $dist, $moveOk)
        if (-not $pressOk) { $failures += "iter${i}:press(dyaw=$('{0:F4}' -f $dyawP),dpitch=$('{0:F4}' -f $dpitchP))" }
        if (-not $lookOk) { $failures += "iter${i}:look(dyaw=$('{0:F4}' -f $dyawL))" }
        if (-not $moveOk) { $failures += "iter${i}:move(dist=$('{0:F3}' -f $dist))" }

        # 7) 截图留档
        Save-WindowScreenshot $hwnd (Join-Path $OutDir ("full-{0:D2}.png" -f $i)) | Out-Null
        Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null
    }

    Write-Host ''
    Write-Host "==== summary [$Label] drive=$Drive repeat=$Repeat grab=$GrabEnv ===="
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
