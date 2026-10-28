# T2 bonus: drive the NEW game.export operator end-to-end in the real
# editor via BRP. Marks the dist dir before, calls the operator, polls
# until the staging directory is rebuilt (cleared+rewritten by staging),
# then reports. The release cargo cache is warm from the CLI export.
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Dist    = Join-Path $Project '.jackdaw\dist\release'
$Port    = 15703
$OutDir  = Join-Path $Repo 'loop\t2-b5'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
}
Start-Sleep -Milliseconds 500

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
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

# Mark the current dist so the rebuild is detectable.
$before = (Get-Item $Dist).LastWriteTime
Write-Host "dist mtime before: $before"

Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'game.export' }) | Out-Null
Write-Host 'game.export dispatched'

$deadline = (Get-Date).AddMinutes(12)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if (-not $alive) { throw 'editor died during export' }
    $now = (Get-Item $Dist -ErrorAction SilentlyContinue).LastWriteTime
    if ($now -and $now -gt $before) {
        Write-Host "dist rebuilt at $now"
        break
    }
}
if (-not ($now -and $now -gt $before)) { throw 'dist was not rebuilt within 12min' }

# Settling: the exe is copied last, so once the dir mtime moved the exe
# should be complete one moment later.
Start-Sleep -Seconds 5
$exe = Join-Path $Dist 'my-game.exe'
$len = (Get-Item $exe).Length
Write-Output ("STAGED_EXE_MB=" + [math]::Round($len/1MB, 1))

Start-Sleep -Seconds 3
$alive2 = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if (-not $alive2) { throw 'editor died after export' }
$alive2.Refresh()
Save-WindowScreenshot $alive2.MainWindowHandle (Join-Path $OutDir 'b5-exported.png') | Out-Null
Write-Host 'shot saved: editor after export'

Write-Output 'B5_EDITOR_EXPORT_PASS'
Stop-Process -Id $proc.Id -Force
Write-Host "editor killed pid=$($proc.Id)"
