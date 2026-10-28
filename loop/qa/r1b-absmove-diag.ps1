# R1b absolute-move injection diag: does MOUSEEVENTF_ABSOLUTE produce winit CursorMoved?
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
public class AbsMove {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll", SetLastError = true)]
  public static extern uint SendInput(uint n, INPUT[] i, int size);
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT { public uint type; public MK u; }
  [StructLayout(LayoutKind.Explicit)]
  public struct MK { [FieldOffset(0)] public MOUSE mo; }
  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSE { public int dx; public int dy; public uint data; public uint flags; public uint time; public IntPtr extra; }
  public static void AbsTo(int x, int y, int screenW, int screenH) {
    // Normalize to 0..65535 across the virtual screen.
    int nx = (int)((x * 65535.0) / (screenW - 1));
    int ny = (int)((y * 65535.0) / (screenH - 1));
    INPUT i = new INPUT(); i.type = 0;
    i.u.mo = new MOUSE();
    i.u.mo.dx = nx; i.u.mo.dy = ny;
    i.u.mo.flags = 0x8001; // ABSOLUTE | MOVE
    uint sent = SendInput(1, new INPUT[] { i }, Marshal.SizeOf(typeof(INPUT)));
    if (sent != 1) throw new Exception("SendInput abs failed: " + Marshal.GetLastWin32Error());
  }
}
"@

function Get-CursorPosRes {
    $path = 'bevy_window::window::Window'
    $r = Brp-Result (Brp-Call 'world.query' @{
        data   = @{ components = @($path) }
        filter = @{ with = @($path) }
    })
    foreach ($row in $r) { return $row.components.$path.cursor_position }
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
    Write-Host ("cursor after SetCursorPos: {0}" -f ((Get-CursorPosRes) | ConvertTo-Json -Compress))

    # Physical-pixel cursor pos now; inject an ABSOLUTE move 30px right.
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Scr {
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
}
"@
    $w = [Scr]::GetSystemMetrics(0); $h = [Scr]::GetSystemMetrics(1)
    [AbsMove]::AbsTo($pt.X + 30, $pt.Y, $w, $h)
    Start-Sleep -Milliseconds 150
    $cp = New-Object AbsMove+POINT
    [AbsMove]::GetCursorPos([ref]$cp) | Out-Null
    Write-Host ("os cursor after abs move: ({0},{1})" -f $cp.X, $cp.Y)
    Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null
    Write-Host ("winit cursor after abs move: {0}" -f ((Get-CursorPosRes) | ConvertTo-Json -Compress))
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
