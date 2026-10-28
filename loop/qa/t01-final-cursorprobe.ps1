Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CursorProbe {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
}
"@
$p = New-Object CursorProbe+POINT
[CursorProbe]::GetCursorPos([ref]$p) | Out-Null
Write-Output ("before: {0},{1}" -f $p.X, $p.Y)
$ok = [CursorProbe]::SetCursorPos(700, 500)
$q = New-Object CursorProbe+POINT
[CursorProbe]::GetCursorPos([ref]$q) | Out-Null
Write-Output ("SetCursorPos(700,500) ret={0} after: {1},{2}" -f $ok, $q.X, $q.Y)
