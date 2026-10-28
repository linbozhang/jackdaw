# Probe world.get_resources response shape for ActiveTool.
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
try {
    Wait-EditorReady -TimeoutSec 90
    foreach ($try in 1..6) {
        try { Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null; break }
        catch { Start-Sleep -Seconds 2 }
    }
    $raw = Brp-Call 'world.get_resources' @{ resource = 'jackdaw::active_tool::ActiveTool' }
    Write-Host "RAW GET_RESOURCES:"
    $raw | ConvertTo-Json -Depth 12
    $raw2 = Brp-Call 'world.get_resources' @{ resource = 'jackdaw::brush::EditMode' }
    Write-Host "RAW EDITMODE:"
    $raw2 | ConvertTo-Json -Depth 12
    # also try the singular method name variant
    try {
        $raw3 = Brp-Call 'world.get_resource' @{ resource = 'jackdaw::active_tool::ActiveTool' }
        Write-Host "RAW SINGULAR:"
        $raw3 | ConvertTo-Json -Depth 12
    } catch { Write-Host "singular method: $_" }
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
