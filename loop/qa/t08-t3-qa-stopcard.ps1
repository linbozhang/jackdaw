# T08 补验②: PIE stop must not close an open asset card (the review-2
# main path). Play -> stop -> asset.set must still reach the open card.
# Reuses the t08lf-qa fixture; run after t08-t3-qa.ps1 finishes (same port).
$ErrorActionPreference = 'Stop'
$Repo  = 'E:\Project\rust\jackdaw'
$Exe   = Join-Path $Repo 'target\debug\jackdaw.exe'
$Proj  = 'E:\Project\rust\jackdaw\loop\qa-fixture\t08lf-qa'
$Port  = 15703

function Brp-Try([string]$method, $params, [int]$retries = 6) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = (Get-Random); method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 8)
        } catch { Start-Sleep -Milliseconds (500 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp-Try 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp-Try 'jackdaw/call_operator' @{ id = $id } }
}
function Wait-Until([string]$until, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp-Try 'jackdaw/wait' @{ until = $until } 1
        if ($r -and $r.result) {
            if ($until -eq 'idle' -and $r.result.idle) { return $true }
            if ($until -eq 'pie_running' -and "$($r.result.pie)" -eq 'running') { return $true }
        }
        Start-Sleep -Seconds 2
    }
    throw "wait($until) timed out"
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Proj
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
$ready = $false
for ($i = 0; $i -lt 360; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died booting' }
}
if (-not $ready) { throw 'BRP never answered' }
Wait-Until 'idle' 900
Start-Sleep -Seconds 20
Write-Host 'editor ready'

# Open a material card (dirty) BEFORE any play.
Op 'asset.new' @{ type = 'material'; name = 't08stop' } | Out-Null
Start-Sleep -Seconds 2
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.6' } | Out-Null
Start-Sleep -Seconds 2
Write-Host 'card open and dirty before play'

# Named scene so the launch-save chain is the full one.
Op 'scene.new' | Out-Null
Op 'scene.save' | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' | Out-Null
Wait-Until 'pie_running' 900
Start-Sleep -Seconds 3
$aliveDuring = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
Op 'pie.stop' | Out-Null
Wait-Until 'idle' 120
$aliveAfter = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
Write-Host ("play/stop survived: " + ($aliveDuring -and $aliveAfter))

# THE probe: after stop, does the open card still take an edit?
$r = Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.8' }
$report = "$($r.result.reports)"
Write-Host ("post-stop asset.set reports: " + $report)
$cardOpen = $report -match 'Set perceptual_roughness'
Write-Host ("STOPCARD PASS: " + ($aliveDuring -and $aliveAfter -and $cardOpen))

$alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($alive) { Stop-Process -Id $proc.Id -Force }
Write-Output 'T08_STOPCARD_DONE'
