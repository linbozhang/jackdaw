# R1b QA: snap_toggle 中键点击语义真机验证（按钮注入路径）
# 前提：plain debug exe（dylib 构建在部分会话启动挂死）。
# 步骤：切 Translate 工具 → 读 SnapSettings → 中键静止点击(0px) → 读(期望翻转)
#       → 再点一次(期望翻回) → 相机 Transform 原始 JSON 亲查 → 截图。
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot '..\reports\r1b-qa-snap' }
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')
. (Join-Path $PSScriptRoot 'screenshot.ps1')

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
$fail = @()
try {
    Wait-EditorReady -TimeoutSec 120
    foreach ($try in 1..6) {
        try { Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null; break }
        catch { Start-Sleep -Seconds 2 }
    }

    # 切到 Translate 工具（snap_toggle 对 Select 工具是 no-op）
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'tool.translate'; history = $false })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null

    function Get-Snap {
        $r = Brp-Call 'world.get_resources' @{ resource = 'jackdaw::snapping::SnapSettings' }
        return ($r | ConvertTo-Json -Depth 12 -Compress)
    }

    $s0 = Get-Snap
    Write-Host "SNAP_BEFORE: $s0"
    $snap0 = ($r = $null)

    # 前台化（照 r1b-press 模式：中键注入需要编辑器前台）
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Fg2 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
    $hwnd = Get-JackdawHwnd
    [Fg2]::ShowWindow($hwnd, 6) | Out-Null; Start-Sleep -Milliseconds 250
    [Fg2]::ShowWindow($hwnd, 9) | Out-Null; Start-Sleep -Milliseconds 450
    $null = Set-CursorToWindowPoint $hwnd 0.5 0.5
    Start-Sleep -Milliseconds 200

    # 中键静止点击 #1：不移动（0px 行程）
    Send-MmbDown; Start-Sleep -Milliseconds 120; Send-MmbUp
    Start-Sleep -Milliseconds 400
    $s1 = Get-Snap
    Write-Host "SNAP_AFTER_CLICK1: $s1"

    # 中键静止点击 #2：应翻回
    Send-MmbDown; Start-Sleep -Milliseconds 120; Send-MmbUp
    Start-Sleep -Milliseconds 400
    $s2 = Get-Snap
    Write-Host "SNAP_AFTER_CLICK2: $s2"

    # 中键长按 700ms 不动再释放：仍是点击（行程 0），也应翻转
    Send-MmbDown; Start-Sleep -Milliseconds 700; Send-MmbUp
    Start-Sleep -Milliseconds 400
    $s3 = Get-Snap
    Write-Host "SNAP_AFTER_HOLD: $s3"

    # 相机 Transform 原始 JSON 亲查
    $camParams = @{
        data   = @{ components = @( 'bevy_transform::components::transform::Transform', 'bevy_camera::camera::Camera' ) }
        filter = @{ with = @( 'bevy_camera::camera::Camera' ) }
    }
    $rawCam = Brp-Call 'world.query' $camParams
    $camJson = $rawCam | ConvertTo-Json -Depth 12
    Write-Host "CAMERA_RAW_BEGIN"
    Write-Host $camJson
    Write-Host "CAMERA_RAW_END"
    $camJson | Set-Content (Join-Path $OutDir 'camera-raw.json') -Encoding UTF8

    Save-WindowScreenshot $hwnd (Join-Path $OutDir 'qa-snap.png') | Out-Null
    Write-Host "shot -> $OutDir\qa-snap.png"

    if ($s0 -eq $s1) { $fail += 'click1 did not toggle snap' }
    if ($s1 -ne $s2) { if ($s0 -ne $s2) { $fail += 'click2 did not toggle back' } }
    if ($s2 -eq $s3) { $fail += 'hold-click did not toggle' }

    if ($fail.Count -eq 0) { Write-Host 'SNAP_RESULT: PASS'; exit 0 }
    else { Write-Host "SNAP_RESULT: FAIL ($fail)"; exit 1 }
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
