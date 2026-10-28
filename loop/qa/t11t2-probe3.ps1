# direct run probe: is the windowed direct-run form still alive?
$proj = 'H:\workspace_AI\t11-live\t11t1-game'
$exe = Join-Path $proj 'target\debug\t11t1-game.exe'
Get-Process t11t1-game -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
$env:PATH = "$proj\target\debug\deps;$env:PATH"
cmd /c "start /B /D `"$proj`" cmd /c `"`"$exe`" > H:\workspace_AI\t11-live\direct-probe.log 2>&1`""
Start-Sleep -Seconds 12
try {
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:15702/' -Method Post -ContentType 'application/json' -TimeoutSec 8 -Body '{"jsonrpc":"2.0","id":1,"method":"jackdaw/status"}'
    Write-Host ('DIRECT_RUN_15702: ' + ($r | ConvertTo-Json -Depth 3 -Compress))
} catch {
    Write-Host ('DIRECT_RUN_15702_FAIL: ' + $_.Exception.Message)
}
$p = Get-Process t11t1-game -ErrorAction SilentlyContinue
Write-Host ('ALIVE: ' + ($null -ne $p))
Get-Process t11t1-game -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'PROBE3_DONE'
