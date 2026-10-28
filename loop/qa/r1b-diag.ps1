# R1b 启动诊断：Start-Process 启动编辑器，轮询 BRP + 进程状态
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [int]$TimeoutSec = 90
)
$ErrorActionPreference = 'Continue'
Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$out = "$env:TEMP\jd-diag-stdout.log"
$err = "$env:TEMP\jd-diag-stderr.log"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
Write-Host "pid=$($proc.Id)"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$ok = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $p = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if (-not $p) {
        $proc.WaitForExit()
        Write-Host ("process EXITED code={0}" -f $proc.ExitCode)
        break
    }
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
            -ContentType 'application/json' `
            -Body '{"jsonrpc":"2.0","id":1,"method":"jackdaw/status","params":{}}' -TimeoutSec 3
        Write-Host "BRP READY: $($r.result | ConvertTo-Json -Depth 2 -Compress)"
        $ok = $true
        break
    } catch {
        Write-Host ("alive: cpu={0:N1}s hwnd={1} wait" -f $p.CPU, $p.MainWindowHandle)
    }
}
if (-not $ok) {
    Write-Host '--- stdout tail ---'; Get-Content $out -Tail 20 -ErrorAction SilentlyContinue
    Write-Host '--- stderr tail ---'; Get-Content $err -Tail 20 -ErrorAction SilentlyContinue
    Write-Host '--- project .jackdaw ---'
    Get-ChildItem (Join-Path $Project '.jackdaw') -ErrorAction SilentlyContinue | Select-Object Name, LastWriteTime
}
Get-Process -Id $proc.Id -ErrorAction SilentlyContinue | Stop-Process -Force
