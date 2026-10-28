# Verify SendInput actually enters the system input stream via GetAsyncKeyState.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Ks {
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int k);
}
"@
. (Join-Path $PSScriptRoot 'input.ps1')
$before = [Ks]::GetAsyncKeyState(0x02)
Write-Host ('before inject: 0x{0:X4}' -f ($before -band 0xFFFF))
Send-RmbDown
Start-Sleep -Milliseconds 80
$after = [Ks]::GetAsyncKeyState(0x02)
Write-Host ('after RmbDown: 0x{0:X4} (high bit set = injected press is live)' -f ($after -band 0xFFFF))
Send-RmbUp
Start-Sleep -Milliseconds 80
$up = [Ks]::GetAsyncKeyState(0x02)
Write-Host ('after RmbUp:   0x{0:X4}' -f ($up -band 0xFFFF))
