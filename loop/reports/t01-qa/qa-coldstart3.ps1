# QA 冷启动探针 v3（D5#1 直接判据，进程内注入为主、OS RMB 为辅）：
# 通道事实（本 QA 会话）：OS 相对移动死 -> winit cursor_position 无源 -> 零点击 hover 门无法用 OS 开。
# 方案：input.pointer(action=press button=right) 自带 Emit::Cursor（进程内 CursorMoved+RMB 按下，
# 走真实 bevy 输入管线），L2 enabled 用 world.get_components 按相机实体读（drive 脚本同款）。
# 判据（旧代码 text_focused=is_some() 恒真 下全部相反）：
#   A. 零点击 + InputFocus=Some(window) 稳态下 fly 激活（B1=true）
#   B. 同态 L2 enabled=True（旧码 False —— D5#1 核心判据）
#   C. 按下零跳变；W（input.key）零点击会话前进（旧码 enabled=False -> 不动）
#   D. release 后 fly=false
# CSV: loop/reports/t01-qa/coldstart3.csv
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15713,
    [string]$DpiScale = 1.5
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\qa\brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot '..\..\qa\input.ps1')
$csv = Join-Path $PSScriptRoot 'coldstart3.csv'
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
function Op([string]$Id, $Params) {
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params }) | Out-Null
}
function Get-CamEnabledByEntity([string]$Entity) {
    $path = 'jackdaw_camera::JackdawCameraSettings'
    $r = Brp-Result (Brp-Call 'world.get_components' @{ entity = $Entity; components = @($path) })
    return [bool]$r.components.$path.enabled
}
function Get-AllCursors {
    $r = Brp-Result (Brp-Call 'world.query' @{
        data   = @{ components = @('bevy_window::window::Window') }
        filter = @{ with = @('bevy_window::window::Window') }
    })
    $out = @()
    foreach ($row in $r) {
        $out += ("e{0}:cur={1}" -f $row.entity, ($row.components.'bevy_window::window::Window'.cursor_position | ConvertTo-Json -Compress))
    }
    return ($out -join ' | ')
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
    $r2 = New-Object JdInput+RECT
    [JdInput]::GetWindowRect($hwnd, [ref]$r2) | Out-Null
    $cx = [Math]::Round((($r2.R - $r2.L) / $DpiScale) * 0.5)
    $cy = [Math]::Round((($r2.B - $r2.T) / $DpiScale) * 0.5)

    # [零点击] 稳态
    $focus = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_input_focus::InputFocus' })
    $cf = $focus.value.current_focus
    if ($null -eq $cf) { $cf = ($focus | ConvertTo-Json -Compress -Depth 6) }
    Log-Q 'COLD3' 'inputfocus_no_click' $cf 'non-null(window)' ($null -ne $focus.value.current_focus)
    Log-Q 'COLD3' 'cursor_rows_no_click' (Get-AllCursors) 'all null' $true
    $cam = Get-FlyCamera
    Log-Q 'COLD3' 'camera_entity' $cam.Entity 'non-null' ($null -ne $cam.Entity)
    $enBefore = Get-CamEnabledByEntity $cam.Entity
    $fly0 = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'
    Log-Q 'COLD3' 'state_no_click' "enabled=$enBefore fly=$fly0" 'enabled=F fly=F' (($enBefore -eq $false) -and ($fly0 -eq $false))

    # ---- 通道 1：进程内 move 开 hover 门 -> OS RMB（保持 OS 级按钮注入）----
    Op 'input.pointer' @{ x = $cx; y = $cy; action = 'move' }
    Frames 5
    Log-Q 'COLD3' 'cursor_rows_after_inproc_move' (Get-AllCursors) 'primary non-null' $true
    $null = Set-CursorToWindowPoint $hwnd 0.5 0.5
    $camA = Get-FlyCamera
    [JdInput]::RmbDown(); Frames 5
    $flyOs = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'
    [JdInput]::RmbUp(); Frames 3
    Log-Q 'COLD3' 'os_rmb_after_inproc_move' $flyOs 'True(若OS按钮可达)' $true

    # ---- 通道 2（主判据）：进程内 press(right) —— CursorMoved + RMB 按下一体 ----
    $cam0 = Get-FlyCamera
    Op 'input.pointer' @{ x = $cx; y = $cy; action = 'press'; button = 'right' }
    Frames 6
    $fly1 = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'
    $en1 = Get-CamEnabledByEntity $cam.Entity
    $cam1 = Get-FlyCamera
    Start-Sleep -Milliseconds 400; Frames 3
    $cam2 = Get-FlyCamera
    Log-Q 'COLD3' 'A_fly_on_rmb_noclick' $fly1 'True' ($fly1 -eq $true)
    Log-Q 'COLD3' 'B_enabled_windowfocus' $en1 'True (D5#1 core)' ($en1 -eq $true)
    $dyaw = [Math]::Abs($cam1.Yaw - $cam0.Yaw); $dpit = [Math]::Abs($cam1.Pitch - $cam0.Pitch)
    $p1 = [Math]::Sqrt([Math]::Pow($cam1.Position['x']-$cam0.Position['x'],2)+[Math]::Pow($cam1.Position['y']-$cam0.Position['y'],2)+[Math]::Pow($cam1.Position['z']-$cam0.Position['z'],2))
    $p2 = [Math]::Sqrt([Math]::Pow($cam2.Position['x']-$cam0.Position['x'],2)+[Math]::Pow($cam2.Position['y']-$cam0.Position['y'],2)+[Math]::Pow($cam2.Position['z']-$cam0.Position['z'],2))
    Log-Q 'COLD3' 'C1_zero_jump_press' ("dyaw={0:N4} dpitch={1:N4} posPress={2:N4} posHold={3:N4}" -f $dyaw,$dpit,$p1,$p2) '<0.005/<0.01' (($dyaw -lt 0.005) -and ($dpit -lt 0.005) -and ($p1 -lt 0.01) -and ($p2 -lt 0.01))

    # C2：零点击会话 WASD 前进（input.key 按住 ~25 帧；key 名须为 KeybindDialog 拼写 KeyW）
    Op 'input.key' @{ key = 'KeyW'; action = 'press' }
    Frames 25
    Op 'input.key' @{ key = 'KeyW'; action = 'release' }
    Frames 3
    $camW = Get-FlyCamera
    $dW = [Math]::Sqrt([Math]::Pow($camW.Position['x']-$cam2.Position['x'],2)+[Math]::Pow($camW.Position['y']-$cam2.Position['y'],2)+[Math]::Pow($camW.Position['z']-$cam2.Position['z'],2))
    Log-Q 'COLD3' 'C2_wasd_forward_noclick' ("len={0:N2}" -f $dW) '>0.5 (旧码=0)' ($dW -gt 0.5)

    # D：释放（轮询插桩：多轮读 fly，观察 just_released 是否落帧）
    Op 'input.pointer' @{ x = $cx; y = $cy; action = 'release'; button = 'right' }
    $polls = @()
    foreach ($p in 1..6) {
        Frames 5
        $fp = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'
        $polls += "p${p}=$fp"
        if ($fp -eq $false) { break }
    }
    Log-Q 'COLD3' 'D_fly_after_release' ($polls -join ' ') 'some poll=False' (($polls | Where-Object { $_ -match 'False' }).Count -gt 0)
    exit 0
}
finally {
    if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}
