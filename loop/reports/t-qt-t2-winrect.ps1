Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WR {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    public struct RECT { public int L, T, R, B; }
}
"@
$p = Get-Process jackdaw -ErrorAction SilentlyContinue
if ($p) {
    foreach ($proc in $p) {
        $r = New-Object WR+RECT
        [WR]::GetWindowRect($proc.MainWindowHandle, [ref]$r) | Out-Null
        Write-Output ("pid=" + $proc.Id + " hwnd=" + $proc.MainWindowHandle + " iconic=" + [WR]::IsIconic($proc.MainWindowHandle) +
            " rect L=" + $r.L + " T=" + $r.T + " R=" + $r.R + " B=" + $r.B + " w=" + ($r.R - $r.L) + " h=" + ($r.B - $r.T))
    }
} else { 'no jackdaw process' }
