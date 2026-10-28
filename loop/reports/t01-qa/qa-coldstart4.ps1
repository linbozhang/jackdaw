# QA 冷启动探针 v4（通道隔离版）：全程零 OS 鼠标输入，纯进程内注入。
# 目的：隔离 v3 中 C2(W 前进=0)/D(release 不清位) 的疑点——v3 的通道1 OS RmbDown/RmbUp
# 可能残留 ButtonInput.pressed(Right)（若 RmbUp 丢失）导致 NavFly action 与 KeyW 解读受扰。
# 流程：冷启动 -> [零点击] InputFocus 稳态 -> in-proc press(right) 轮询 fly ->
#       KeyW press -> 轮询位移 -> KeyW release -> in-proc release(right) 轮询 fly。
# CSV: loop/reports/t01-qa/coldstart4.csv
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15713,
    [string]$DpiScale = '1.5'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\qa\brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot '..\..\qa\input.ps1')
$csv = Join-Path $PSScriptRoot 'coldstart4.csv'
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
function Pos3($c) { "{0:N3},{1:N3},{2:N3}" -f $c.Position['x'], $c.Position['y'], $c.Position['z'] }

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
    $r2 = New-Object JdInput+RECT
    [JdInput]::GetWindowRect((Get-JackdawHwnd), [ref]$r2) | Out-Null
    $cx = [Math]::Round((($r2.R - $r2.L) / $DpiScale) * 0.5)
    $cy = [Math]::Round((($r2.B - $r2.T) / $DpiScale) * 0.5)

    $focus = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_input_focus::InputFocus' })
    Log-Q 'COLD4' 'inputfocus_no_click' ($focus.value | ConvertTo-Json -Compress -Depth 6) 'current_focus non-null' ($null -ne $focus.value.current_focus)
    $cam = Get-FlyCamera
    Log-Q 'COLD4' 'cam_pos_start' (Pos3 $cam) 'baseline' $true

    # A/B：in-proc press(right) —— 零点击激活 + enabled（D5#1 核心）
    Op 'input.pointer' @{ x = $cx; y = $cy; action = 'press'; button = 'right' }
    $engaged = $false
    foreach ($p in 1..6) {
        Frames 3
        if (Get-BoolRes 'jackdaw::viewport::CameraFlyActive') { $engaged = $true; break }
    }
    Log-Q 'COLD4' 'A_fly_engaged_poll' $engaged 'True (<=18f)' ($engaged -eq $true)
    $path = 'jackdaw_camera::JackdawCameraSettings'
    $rc = Brp-Result (Brp-Call 'world.get_components' @{ entity = $cam.Entity; components = @($path) })
    Log-Q 'COLD4' 'B_enabled_windowfocus' ([bool]$rc.components.$path.enabled) 'True (D5#1 core)' ([bool]$rc.components.$path.enabled)

    # C2：KeyW 按住 -> 轮询位移
    $cam0 = Get-FlyCamera
    Op 'input.key' @{ key = 'KeyW'; action = 'press' }
    $moved = $false; $maxd = 0.0
    foreach ($p in 1..6) {
        Frames 5
        $c = Get-FlyCamera
        $d = [Math]::Sqrt([Math]::Pow($c.Position['x']-$cam0.Position['x'],2)+[Math]::Pow($c.Position['y']-$cam0.Position['y'],2)+[Math]::Pow($c.Position['z']-$cam0.Position['z'],2))
        if ($d -gt $maxd) { $maxd = $d }
        if ($d -gt 0.5) { $moved = $true; break }
    }
    Op 'input.key' @{ key = 'KeyW'; action = 'release' }
    Frames 3
    Log-Q 'COLD4' 'C2_wasd_forward_poll' ("maxLen={0:N2}" -f $maxd) '>0.5' ($moved -eq $true)

    # D：in-proc release(right) —— 轮询清位
    Op 'input.pointer' @{ x = $cx; y = $cy; action = 'release'; button = 'right' }
    $cleared = $false
    foreach ($p in 1..6) {
        Frames 3
        if (-not (Get-BoolRes 'jackdaw::viewport::CameraFlyActive')) { $cleared = $true; break }
    }
    Log-Q 'COLD4' 'D_fly_released_poll' $cleared 'True (<=18f)' ($cleared -eq $true)

    # 兜底：OS RmbUp（若 in-proc release 未清，真实 OS 事件应清）
    if (-not $cleared) {
        . (Join-Path $PSScriptRoot '..\..\qa\input.ps1')
        [JdInput]::RmbUp(); Frames 5
        $flyOsUp = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'
        Log-Q 'COLD4' 'D2_os_rmbup_fallback' $flyOsUp 'False' ($flyOsUp -eq $false)
    }
    exit 0
}
finally {
    if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}
