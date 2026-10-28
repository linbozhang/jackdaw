# T08-T2 QA diag7: does an editor config change reach the NEXT play?
# Gravity doubled to -19.62: dy should roughly double (-63) if the file
# is what the next play reads; dy staying -31.7 means the run staging
# (or an asset cache) still serves the old value.
$ErrorActionPreference = 'Stop'
$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'E:\Project\rust\jackdaw\loop\qa-fixture\t08t2qa-fixture'
$Port    = 15703

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
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died' }
}
if (-not $ready) { throw 'BRP never answered' }
Wait-Until 'idle' 600
Start-Sleep -Seconds 15

Op 'asset.open' @{ path = 'game-config.bsn' } | Out-Null
Start-Sleep -Seconds 1
Op 'asset.set' @{ field = 'gravity'; value = '-19.62' } | Out-Null
Op 'asset.save' | Out-Null
Start-Sleep -Seconds 1
$onDisk = Get-Content (Join-Path $Project 'assets\game-config.bsn') -Raw
if ($onDisk -notmatch '19\.62') { throw "gravity did not reach the file: $onDisk" }
Write-Host 'config on disk: gravity -19.62 (dy should be about 2x the -9.81 leg)'

Op 'scene.new' | Out-Null
Op 'scene.save' | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' | Out-Null
Wait-Until 'pie_running' 900
Start-Sleep -Seconds 3

$body = '{"jsonrpc":"2.0","id":7,"method":"jackdaw/scene_snapshot","params":{}}'
$r1 = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -TimeoutSec 30 -Body $body
Start-Sleep -Seconds 3
$r2 = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -TimeoutSec 30 -Body $body
$r1.Content | Out-File -Encoding ascii (Join-Path $Repo 'loop\t08-t2-qa-live\snap5.json')
$r2.Content | Out-File -Encoding ascii (Join-Path $Repo 'loop\t08-t2-qa-live\snap6.json')
Write-Host 'snaps saved'

Op 'pie.stop' | Out-Null
Wait-Until 'idle' 120
Stop-Process -Id $proc.Id -Force
Write-Output 'DIAG7_DONE'
