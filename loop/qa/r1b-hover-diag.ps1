# R1b hover gate diag: does winit's Window.cursor_position update from injected moves,
# and does the window center land on the 3D viewport?
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

function Get-WindowState {
    $path = 'bevy_window::window::Window'
    $r = Brp-Result (Brp-Call 'world.query' @{
        data   = @{ components = @($path) }
        filter = @{ with = @($path) }
    })
    foreach ($row in $r) {
        $w = $row.components.$path
        return @{ cursor = $w.cursor_position; focused = [bool]$w.focused; mode = [string]$w.mode }
    }
    throw 'no Window row'
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
    [JdInput]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    $pt = Set-CursorToWindowPoint $hwnd 0.5 0.5
    Start-Sleep -Milliseconds 200
    $w0 = Get-WindowState
    Write-Host ("after SetCursorPos only: cursor={0} focused={1}" -f ($w0.cursor | ConvertTo-Json -Compress), $w0.focused)

    Send-MoveRel 2 0; Start-Sleep -Milliseconds 60; Send-MoveRel -2 0
    Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null
    $w1 = Get-WindowState
    Write-Host ("after SendInput jiggle:   cursor={0} focused={1}" -f ($w1.cursor | ConvertTo-Json -Compress), $w1.focused)

    try {
        Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = 'loop/reports/r1b-hover-diag/window.png' } -TimeoutSec 15 | Out-Null
        Write-Host 'screenshot: loop/reports/r1b-hover-diag/window.png'
    } catch { Write-Host "screenshot failed: $_" }
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
