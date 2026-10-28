# QA 冷启动探针 v2（D5#1 直接判据版）：
# 本会话 OS 相对移动注入死（t01-qa probe P2 FAIL）→ winit cursor_position 无人更新 →
# hover 门关 → 零点击 RMB 无法置 fly（环境性，与 D5#1 无关）。
# 判据改用 BRP 进程内 input.pointer(move)（产生 winit CursorMoved，逻辑坐标，不经 OS 前台）：
#   零点击 + InputFocus=Some(window) 稳态 + hover 门开 ->
#   L2 JackdawCameraSettings.enabled == True  （旧代码 text_focused=is_some() 恒 true -> enabled=False）
#   -> OS RMB 激活 fly + 按下零跳变 -> W 前进（零点击会话端到端）。
# CSV: loop/reports/t01-qa/coldstart2.csv
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15713,
    [string]$DpiScale = 1.5
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\qa\brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot '..\..\qa\input.ps1')
$csv = Join-Path $PSScriptRoot 'coldstart2.csv'
"probe,item,value,expected,ok" | Set-Content -Path $csv -Encoding UTF8
function Log-Q {
    param([string]$P, [string]$I, $V, [string]$E, [bool]$Ok)
    $line = "$P,$I,$V,$E,$Ok"
    Add-Content -Path $csv -Encoding UTF8 -Value $line
    Write-Host $line
}
function Frames([int]$n) { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } | Out-Null }
function Get-BoolRes([string]$Path) {
    $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = $Path })
    $v = $r.value
    if ($v -is [bool]) { return $v }
    if ($v -is [System.Array]) { return [bool]$v[0] }
    $first = $v.PSObject.Properties | Select-Object -First 1
    if ($first) { return [bool]$first.Value }
    throw "shape: $($v | ConvertTo-Json -Compress)"
}
function Get-CamEnabled {
    $r = Brp-Result (Brp-Call 'world.query' @{
        data   = @{ components = @('jackdaw_camera::JackdawCameraSettings') }
        filter = @{ with = @('jackdaw_camera::JackdawCameraSettings') }
    })
    $vals = @()
    foreach ($row in $r) { $vals += [bool]$row.components.'jackdaw_camera::JackdawCameraSettings'.enabled }
    return $vals
}
function Get-CursorPos {
    $r = Brp-Result (Brp-Call 'world.query' @{
        data   = @{ components = @('bevy_window::window::Window') }
        filter = @{ with = @('bevy_window::window::Window') }
    })
    foreach ($row in $r) { return $row.components.'bevy_window::window::Window'.cursor_position }
    return $null
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
}
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
    $hwnd = Get-JackdawHwnd
    $r = New-Object JdInput+RECT
    [JdInput]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $logicalW = ($r.R - $r.L) / $DpiScale
    $logicalH = ($r.B - $r.T) / $DpiScale
    $cx = [Math]::Round($logicalW * 0.5); $cy = [Math]::Round($logicalH * 0.5)

    # [零点击] 稳态：InputFocus=Some(window)（D5#1 污染前提）；hover 未开 -> enabled 应 false
    $focus = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_input_focus::InputFocus' })
    $cf = $focus.value.current_focus
    Log-Q 'COLD2' 'inputfocus_no_click' $cf 'non-null(window)' ($null -ne $cf -and $cf -ne '')
    $cur0 = Get-CursorPos
    $en0 = Get-CamEnabled
    Log-Q 'COLD2' 'cursor_before_brp_move' ($null -ne $cur0) 'False(null)' ($null -eq $cur0)
    Log-Q 'COLD2' 'enabled_before_hover' ($en0 -join '/') 'all False' (($en0 | Where-Object { $_ }).Count -eq 0)

    # BRP 进程内 move（CursorMoved；InputFocus 不受影响——无点击）
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $cx; y = $cy; action = 'move' } }) | Out-Null
    Frames 5
    $cur1 = Get-CursorPos
    Log-Q 'COLD2' 'cursor_after_brp_move' ($cur1 | ConvertTo-Json -Compress) 'non-null' ($null -ne $cur1)

    # D5#1 直接判据：零点击 + 窗口焦点稳态 + hover 开 -> enabled 必须 True（旧码为 False）
    $en1 = Get-CamEnabled
    Log-Q 'COLD2' 'enabled_hover_windowfocus' ($en1 -join '/') 'all True (D5#1 fix)' (($en1 | Where-Object { -not $_ }).Count -eq 0)
    $fly0 = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'
    Log-Q 'COLD2' 'fly_before_rmb' $fly0 'False' ($fly0 -eq $false)

    # OS RMB：激活 + 按下零跳变
    $null = Set-CursorToWindowPoint $hwnd 0.5 0.5
    $cam0 = Get-FlyCamera
    [JdInput]::RmbDown(); Frames 5
    $fly1 = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'
    $cam1 = Get-FlyCamera
    Start-Sleep -Milliseconds 400; Frames 3
    $cam2 = Get-FlyCamera
    Log-Q 'COLD2' 'fly_on_rmb_noclick' $fly1 'True' ($fly1 -eq $true)
    $dyaw = [Math]::Abs($cam1.Yaw - $cam0.Yaw); $dpit = [Math]::Abs($cam1.Pitch - $cam0.Pitch)
    $p1 = [Math]::Sqrt([Math]::Pow($cam1.Position['x']-$cam0.Position['x'],2)+[Math]::Pow($cam1.Position['y']-$cam0.Position['y'],2)+[Math]::Pow($cam1.Position['z']-$cam0.Position['z'],2))
    $p2 = [Math]::Sqrt([Math]::Pow($cam2.Position['x']-$cam0.Position['x'],2)+[Math]::Pow($cam2.Position['y']-$cam0.Position['y'],2)+[Math]::Pow($cam2.Position['z']-$cam0.Position['z'],2))
    Log-Q 'COLD2' 'zero_jump_press' ("dyaw={0:N4} dpitch={1:N4} posPress={2:N4} posHold={3:N4}" -f $dyaw,$dpit,$p1,$p2) '<0.005/<0.01' (($dyaw -lt 0.005) -and ($dpit -lt 0.005) -and ($p1 -lt 0.01) -and ($p2 -lt 0.01))

    # 零点击会话 WASD 端到端：W 前进
    Send-KeyHold 'W' 400
    Frames 3
    $camW = Get-FlyCamera
    $dW = [Math]::Sqrt([Math]::Pow($camW.Position['x']-$cam2.Position['x'],2)+[Math]::Pow($camW.Position['y']-$cam2.Position['y'],2)+[Math]::Pow($camW.Position['z']-$cam2.Position['z'],2))
    Log-Q 'COLD2' 'wasd_forward_noclick' ("len={0:N2}" -f $dW) '>0.5' ($dW -gt 0.5)

    [JdInput]::RmbUp(); Frames 5
    $fly2 = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'
    Log-Q 'COLD2' 'fly_after_release' $fly2 'False' ($fly2 -eq $false)
    exit 0
}
finally {
    if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}
