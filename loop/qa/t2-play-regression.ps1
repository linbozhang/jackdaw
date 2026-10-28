# T2-B4: editor Play(dev) regression smoke — boot the plain editor on
# my-game, Play via the pie.play operator, wait pie_running, screenshot,
# Stop, verify stopped. Reuses loop/qa/brp.ps1 + screenshot.ps1.
# Usage: powershell -NoProfile -File loop\qa\t2-play-regression.ps1
$ErrorActionPreference = 'Stop'

$Repo   = 'E:\Project\rust\jackdaw'
$Exe    = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port   = 15703
$OutDir = Join-Path $Repo 'loop\t2-b4'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
}
Start-Sleep -Milliseconds 500

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
# Iron rule: the editor's dlls live in deps\; prefix PATH.
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir 'editor-stdout.log') `
    -RedirectStandardError (Join-Path $OutDir 'editor-stderr.log') -PassThru
Write-Host "editor pid=$($proc.Id)"
$proc.Id | Set-Content (Join-Path $OutDir 'editor.pid')

Wait-EditorReady -TimeoutSec 120
Write-Host 'editor ready'
Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 120 | Out-Null
Write-Host 'editor idle (prebuild done)'

# The game.export operator must be present (task 2 wiring).
$ops = Brp-Result (Brp-Call 'jackdaw/operators' @{})
$flat = @()
if ($ops -is [array]) { $flat = $ops } else { $flat = @($ops.PSObject.Properties | ForEach-Object { $_.Value }) }
$text = $flat | ConvertTo-Json -Depth 6 -Compress
if ($text -notmatch [regex]::Escape('game.export')) { throw 'operator game.export missing' }
Write-Host 'operators OK: game.export present'

# Play (dev) — the operator the Play button dispatches.
Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'pie.play' }) | Out-Null
$r = Wait-BrpResult 'jackdaw/wait' @{ until = 'pie_running' } -TimeoutSec 900
Write-Host ("pie_running: " + ($r | ConvertTo-Json -Depth 6 -Compress))

Start-Sleep -Seconds 3
$alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if (-not $alive) { throw 'editor died during play' }
$alive.Refresh()
Save-WindowScreenshot $alive.MainWindowHandle (Join-Path $OutDir 'b4-playing.png') | Out-Null
Write-Host 'shot saved: playing'

# Stop and verify the return to authoring.
Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'pie.stop' }) | Out-Null
Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 60 | Out-Null
Start-Sleep -Seconds 2
$alive2 = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if (-not $alive2) { throw 'editor died on stop' }
Save-WindowScreenshot $alive2.MainWindowHandle (Join-Path $OutDir 'b4-stopped.png') | Out-Null
Write-Host 'shot saved: stopped — editor alive after stop'

Write-Output 'B4_PLAY_REGRESSION_PASS'
Stop-Process -Id $proc.Id -Force
Write-Host "editor killed pid=$($proc.Id)"
