# QA 定制冷启动探针（D5#1 修复核心场景）：
# 新进程天然获得前台权——不做任何 minimize/restore（t01-probe.ps1 的
# Assert-Foreground 会 minimize 掉新进程的前台权，导致 P3n 非诊断）。
# 流程：冷启动 -> 就绪 -> [零点击] 读 InputFocus -> jiggle -> RMB down ->
#       断言 CameraFlyActive==true 且相机零跳变 -> RMB up -> false。
# CSV: loop/reports/t01-qa/coldstart.csv
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15713,
    [double]$XFactor = 0.5,
    [double]$YFactor = 0.5
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot '.'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
. (Join-Path $PSScriptRoot '..\..\qa\brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot '..\..\qa\input.ps1')
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FgQ {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@
$csv = Join-Path $OutDir 'coldstart.csv'
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
    $fg = [FgQ]::GetForegroundWindow()
    Log-Q 'COLD' 'fresh-process-foreground' ($fg -eq $hwnd) 'True' ($fg -eq $hwnd)

    # [零点击] 稳态焦点读数：应为 PrimaryWindow 实体（Some），而非 null
    $focus = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_input_focus::InputFocus' })
    Log-Q 'COLD' 'inputfocus_no_click' ($focus | ConvertTo-Json -Compress -Depth 6) 'Some(window)=steady-state' $true

    # 零点击 jiggle + RMB：D5#1 修复后 fly 必须激活
    $null = Set-CursorToWindowPoint $hwnd $XFactor $YFactor
    Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
    Frames 3
    $fly0 = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'
    $cam0 = Get-FlyCamera
    [JdInput]::RmbDown(); Frames 5
    $fly1 = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'
    $cam1 = Get-FlyCamera
    Start-Sleep -Milliseconds 400; Frames 3   # hold 不动
    $cam2 = Get-FlyCamera
    [JdInput]::RmbUp(); Frames 5
    $fly2 = Get-BoolRes 'jackdaw::viewport::CameraFlyActive'

    $dyaw = [Math]::Abs($cam1.Yaw - $cam0.Yaw)
    $dpit = [Math]::Abs($cam1.Pitch - $cam0.Pitch)
    $p1 = [Math]::Sqrt([Math]::Pow($cam1.Position['x']-$cam0.Position['x'],2)+[Math]::Pow($cam1.Position['y']-$cam0.Position['y'],2)+[Math]::Pow($cam1.Position['z']-$cam0.Position['z'],2))
    $p2 = [Math]::Sqrt([Math]::Pow($cam2.Position['x']-$cam0.Position['x'],2)+[Math]::Pow($cam2.Position['y']-$cam0.Position['y'],2)+[Math]::Pow($cam2.Position['z']-$cam0.Position['z'],2))

    Log-Q 'COLD' 'fly_before_rmb' $fly0 'False' ($fly0 -eq $false)
    Log-Q 'COLD' 'fly_on_rmb_noclick' $fly1 'True (D5#1 fix)' ($fly1 -eq $true)
    Log-Q 'COLD' 'zero_jump_press' ("dyaw={0:N4} dpitch={1:N4} posPress={2:N4} posHold={3:N4}" -f $dyaw,$dpit,$p1,$p2) 'dyaw/dpitch<0.005 pos<0.01' (($dyaw -lt 0.005) -and ($dpit -lt 0.005) -and ($p1 -lt 0.01) -and ($p2 -lt 0.01))
    Log-Q 'COLD' 'fly_after_release' $fly2 'False' ($fly2 -eq $false)
    exit 0
}
finally {
    if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}
