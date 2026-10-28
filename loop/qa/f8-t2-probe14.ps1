# Inspect jackdaw/scene_tree response for scene entity ids.
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = 'C:\Users\linbo.zhang\Projects\my-game'; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath (Join-Path $Repo 'target\debug\jackdaw.exe') -WorkingDirectory (Join-Path $Repo 'target\debug') -PassThru
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    $r = Brp-Call 'jackdaw/scene_tree' @{}
    Write-Host '--- scene_tree raw (first 1500 chars):'
    ($r | ConvertTo-Json -Depth 8 -Compress).Substring(0, 1500) | Write-Host
    $m = [regex]::Matches(($r | ConvertTo-Json -Depth 8 -Compress), '"entity"\s*:\s*"[^"]+"')
    Write-Host ("entity refs: " + (($m | Select-Object -First 6 | ForEach-Object { $_.Value }) -join ' '))
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
