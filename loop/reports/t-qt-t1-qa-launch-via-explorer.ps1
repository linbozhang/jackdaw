# Launch the editor through the interactive shell (explorer) so it gets a
# real desktop: this QA harness cannot spawn windowed children directly.
param(
    [string]$Project = "C:\Users\linbo.zhang\AppData\Local\Temp\t-qt-diag-1662138129",
    [int]$Port = 15807
)
Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$bat = Join-Path $env:TEMP "jd-qa-launch.cmd"
$lines = @(
    "set JACKDAW_OPEN_PROJECT=$Project",
    "set JACKDAW_REMOTE_PORT=$Port",
    "set JACKDAW_SKIP_SETUP_CHECK=1",
    "cd /d E:\Project\rust\jackdaw",
    "start `"`" /B target\debug\jackdaw.exe",
    "exit"
)
[System.IO.File]::WriteAllLines($bat, $lines)
Write-Output "launcher: $bat"

# ShellExecute serviced by the interactive shell process (explorer), so the
# child lands on the console session's desktop with working stdio.
$shell = New-Object -ComObject Shell.Application
$shell.ShellExecute("open", "`"$bat`"", "", "open", 0) | Out-Null

$deadline = (Get-Date).AddSeconds(180)
$ok = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 4
    $hit = netstat -ano | Select-String ":$Port\s.*LISTENING"
    if ($hit) { $ok = $true; break }
}
Write-Output "LISTENING=$ok"
if ($ok) {
    Get-Process jackdaw -ErrorAction SilentlyContinue | Select-Object Id, CPU, MainWindowTitle | Format-List
    $s = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType "application/json" `
        -Body '{"jsonrpc":"2.0","id":1,"method":"jackdaw/status","params":{}}' -TimeoutSec 10
    Write-Output ("STATUS=" + ($s | ConvertTo-Json -Compress -Depth 4))
}
