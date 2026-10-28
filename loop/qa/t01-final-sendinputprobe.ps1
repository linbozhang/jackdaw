. (Join-Path $PSScriptRoot 'input.ps1')
try {
    [JdInput]::MoveRel(0, 0)
    Write-Output 'SendInput MoveRel: OK'
} catch { Write-Output ("SendInput MoveRel FAILED: {0}" -f $_.Exception.Message) }
try {
    [JdInput]::KeyDown(0x11); [JdInput]::KeyUp(0x11)
    Write-Output 'SendInput key: OK'
} catch { Write-Output ("SendInput key FAILED: {0}" -f $_.Exception.Message) }
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FgP {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
"@
$h = [FgP]::GetForegroundWindow()
$pid2 = 0
$t = [FgP]::GetWindowThreadProcessId($h, [ref]$pid2)
$proc = Get-Process -Id $pid2 -ErrorAction SilentlyContinue
Write-Output ("foreground: pid={0} name={1}" -f $pid2, $(if ($proc) { $proc.ProcessName } else { '?' }))
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent()
Write-Output ("me: user={0} elevated={1} type={2}" -f $me.Name, $(New-Object System.Security.Principal.WindowsPrincipal($me)).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator), $me.ImpersonationLevel)

