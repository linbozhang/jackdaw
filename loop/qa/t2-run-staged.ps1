# T2-B2/B3: launch a staged game exe as an independent process (cwd =
# $env:TEMP), wait for boot, screenshot its window, report liveness, kill.
# Usage: powershell -NoProfile -File loop\qa\t2-run-staged.ps1 -Exe <path> -Shot <png> [-WaitSec 10]
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$Shot,
    [int]$WaitSec = 10
)

. (Join-Path $PSScriptRoot 'screenshot.ps1')

$proc = Start-Process -FilePath $Exe -WorkingDirectory $env:TEMP -PassThru
Write-Output ("LAUNCHED pid=" + $proc.Id + " cwd=" + $env:TEMP)
Start-Sleep -Seconds $WaitSec

$alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if (-not $alive) {
    Write-Output ("RESULT=DEAD_BEFORE_SHOT exit-was=" + $proc.ExitCode)
    exit 2
}
# Refresh to pick up the window handle once the surface exists.
$alive.Refresh()
$hwnd = $alive.MainWindowHandle
Write-Output ("ALIVE_AFTER_${WaitSec}s window='" + $alive.MainWindowTitle + "' hwnd=" + $hwnd + " mem=" + [math]::Round($alive.WorkingSet64/1MB) + "MB")
if ($hwnd -eq 0) {
    Write-Output 'RESULT=NO_WINDOW'
    Stop-Process -Id $proc.Id -Force
    exit 3
}

Save-WindowScreenshot $hwnd $Shot | Out-Null
Write-Output ("SHOT_SAVED " + $Shot)

# Still alive after the shot?
Start-Sleep -Seconds 2
$still = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($still) {
    Write-Output 'RESULT=ALIVE_THROUGH_SHOT'
    Stop-Process -Id $proc.Id -Force
    Write-Output ("KILLED pid=" + $proc.Id)
} else {
    Write-Output 'RESULT=EXITED_AFTER_SHOT'
}
