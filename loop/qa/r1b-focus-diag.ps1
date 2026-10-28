# R1b 前台三态诊断：RMB 按下后 CursorOptions.visible 是否翻转（fly 激活铁证）
# 三态判别：
#   visible 不变    → RMB 未送达（焦点/路由问题）
#   visible 翻转但 motion 后 dyaw=0 → RMB 送达但 motion 路径断
#   visible 翻转 + dyaw>0 → fly 正常（问题在别处）
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Fg2 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId2(IntPtr h);
}
"@

function Hit-TestCursor {
    $p = New-Object Fg2+POINT
    [Fg2]::GetCursorPos([ref]$p) | Out-Null
    $hit = [Fg2]::WindowFromPoint($p)
    $sb = New-Object System.Text.StringBuilder 256
    [Fg2]::GetWindowText($hit, $sb, 256) | Out-Null
    $pid2 = 0
    [Fg2]::GetWindowThreadProcessId($hit, [ref]$pid2) | Out-Null
    $procName = try { (Get-Process -Id $pid2 -ErrorAction Stop).ProcessName } catch { 'unknown' }
    return @{ x = $p.X; y = $p.Y; hwnd = $hit; title = $sb.ToString(); proc = $procName }
}

$script:CursorPath = $null
function Get-CursorVisible {
    if (-not $script:CursorPath) {
        $candidates = @(
            'bevy_window::window::CursorOptions',
            'bevy::window::window::CursorOptions',
            'bevy::window::cursor_options::CursorOptions',
            'bevy_window::cursor_options::CursorOptions'
        )
        foreach ($path in $candidates) {
            try {
                $r = Brp-Result (Brp-Call 'world.query' @{
                    data   = @{ components = @($path) }
                    filter = @{ with = @($path) }
                })
                if ($r) { $script:CursorPath = $path; break }
            } catch { }
        }
        if (-not $script:CursorPath) { throw 'no CursorOptions candidate path resolved' }
    }
    $r = Brp-Result (Brp-Call 'world.query' @{
        data   = @{ components = @($script:CursorPath) }
        filter = @{ with = @($script:CursorPath) }
    })
    foreach ($row in $r) {
        $c = $row.components.$($script:CursorPath)
        return @{ grab = [string]$c.grab_mode; visible = [bool]$c.visible }
    }
    throw 'no CursorOptions row'
}

Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
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
    $hwnd = Get-JackdawHwnd

    # 前台化（minimize/restore + AttachThreadInput + 点击）
    [Fg2]::ShowWindow($hwnd, 6) | Out-Null; Start-Sleep -Milliseconds 250
    [Fg2]::ShowWindow($hwnd, 9) | Out-Null; Start-Sleep -Milliseconds 450
    $fg = [Fg2]::GetForegroundWindow()
    if ($fg -ne $hwnd) {
        $fgPid = 0
        $fgThread = [Fg2]::GetWindowThreadProcessId($fg, [ref]$fgPid)
        $me = [Fg2]::GetCurrentThreadId()
        [Fg2]::AttachThreadInput($me, $fgThread, $true) | Out-Null
        [Fg2]::SetForegroundWindow($hwnd) | Out-Null
        [Fg2]::AttachThreadInput($me, $fgThread, $false) | Out-Null
        Start-Sleep -Milliseconds 350
        $fg = [Fg2]::GetForegroundWindow()
    }
    if ($fg -ne $hwnd) {
        $null = Set-CursorToWindowPoint $hwnd 0.5 0.5
        Start-Sleep -Milliseconds 150
        [JdInput]::LmbDown(); Start-Sleep -Milliseconds 60; [JdInput]::LmbUp()
        Start-Sleep -Milliseconds 350
        $fg = [Fg2]::GetForegroundWindow()
    }
    Write-Host ("foreground: {0} (editor={1})" -f ($(if ($fg -eq $hwnd) { 'OK' } else { 'FAIL' })), $hwnd)

    $pt = Set-CursorToWindowPoint $hwnd 0.5 0.5
    Start-Sleep -Milliseconds 150
    $hit = Hit-TestCursor
    Write-Host ("cursor at ({0},{1}) hits hwnd={2} proc={3} title='{4}' (editor={5})" -f `
            $hit.x, $hit.y, $hit.hwnd, $hit.proc, $hit.title, $hwnd)
    Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
    Start-Sleep -Milliseconds 100

    $c0 = Get-FlyCamera
    $v0 = Get-CursorVisible
    Write-Host ("baseline: cursor grab={0} visible={1} yaw={2:F6}" -f $v0.grab, $v0.visible, $c0.Yaw)

    Send-RmbDown
    Wait-BrpResult 'jackdaw/wait' @{ frames = 20 } | Out-Null
    $v1 = Get-CursorVisible
    Write-Host ("after RMB down: grab={0} visible={1} (expect Locked/false if fly engaged)" -f $v1.grab, $v1.visible)

    1..20 | ForEach-Object { Send-MoveRel 15 0; Start-Sleep -Milliseconds 16 }
    Wait-BrpResult 'jackdaw/wait' @{ frames = 20 } | Out-Null
    $c1 = Get-FlyCamera
    Write-Host ("after 20x15px drag: dyaw={0:F6}" -f [Math]::Abs($c1.Yaw - $c0.Yaw))

    Send-RmbUp
    Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null
    $v2 = Get-CursorVisible
    Write-Host ("after RMB up: grab={0} visible={1}" -f $v2.grab, $v2.visible)

    if ($v1.visible -eq $true) { Write-Host 'VERDICT: RMB NOT DELIVERED (fly never engaged)' }
    elseif ([Math]::Abs($c1.Yaw - $c0.Yaw) -lt 0.01) { Write-Host 'VERDICT: FLY OK BUT MOTION DEAD' }
    else { Write-Host 'VERDICT: FLY+LOOK OK' }
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
