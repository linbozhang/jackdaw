param(
    [int]$Port = 15715
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = 'C:\Users\linbo.zhang\Projects\my-game'
$env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe' -WorkingDirectory 'E:\Project\rust\jackdaw\target\debug' -PassThru
try {
    Wait-EditorReady -TimeoutSec 240
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 60 | Out-Null
    Wait-BrpResult 'jackdaw/wait' @{ frames = 30 } | Out-Null
    Start-Sleep -Seconds 2

    function Get-Modal { (Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30).modal }
    Write-Output ("modal at boot: '{0}'" -f (Get-Modal))

    # start the measure tool via the OPERATOR path (no input dependency)
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'tools.measure_distance'; history = $false })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 10 } | Out-Null
    Start-Sleep -Milliseconds 400
    $m1 = Get-Modal
    Write-Output ("modal after operator start: '{0}'" -f $m1)

    # synthetic Escape via the input.key path
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.key'; history = $false; params = @{ key = 'Escape'; frames = 1 } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 12 } | Out-Null
    Start-Sleep -Milliseconds 400
    $m2 = Get-Modal
    Write-Output ("modal after synthetic Escape: '{0}'" -f $m2)

    # jackdaw/cancel as a control (operator path cancel)
    if ($null -ne $m2) {
        $null = Brp-Result (Brp-Call 'jackdaw/cancel' @{ })
        Wait-BrpResult 'jackdaw/wait' @{ frames = 6 } | Out-Null
        Write-Output ("modal after operator cancel: '{0}'" -f (Get-Modal))
    }
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
