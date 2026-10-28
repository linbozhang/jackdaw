Add-Type @'
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  public struct R { public int L, T, Rt, B; }
}
'@
$p = Get-Process jackdaw -ErrorAction Stop
$r = New-Object W+R
[W]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
Write-Output ('window rect physical: L=' + $r.L + ' T=' + $r.T + ' R=' + $r.Rt + ' B=' + $r.B + '  size=' + ($r.Rt - $r.L) + 'x' + ($r.B - $r.T))
