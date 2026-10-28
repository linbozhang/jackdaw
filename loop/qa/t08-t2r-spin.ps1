# T08-T2 rework QA spin leg: new template (no SpinningCube on the falling
# cube) should spin at exactly 1.0 * move_speed. Sampled AFTER an 8s
# warm-up so the cold-start window (the rework report's archived 0.42
# first-sample) cannot bite. JSON captured raw and analyzed locally.
$ErrorActionPreference = 'Stop'
$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'E:\Project\rust\jackdaw\loop\qa-fixture\t08t2r-fixture'
$Port    = 15703
$OutDir  = Join-Path $Repo 'loop\t08-t2-qa-live'

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
Wait-Until 'idle' 1800
Start-Sleep -Seconds 25
Write-Host 'editor ready (schema settled)'

$configPath = Join-Path $Project 'assets\game-config.bsn'
$created = Op 'asset.new' @{ type = 'game_config'; name = 'game-config' }
$okNew = "$($created.result.result)" -eq 'finished' -and -not $created.result.warnings
Write-Host ("asset.new ok: " + $okNew)
if (-not $okNew) { throw 'asset.new failed' }
Op 'asset.set' @{ field = 'move_speed'; value = '2.5' } | Out-Null
Op 'asset.set' @{ field = 'gravity'; value = '-9.81' } | Out-Null
Op 'asset.save' | Out-Null
Start-Sleep -Seconds 1
$onDisk = Get-Content $configPath -Raw -Encoding UTF8
if ($onDisk -notmatch '2\.5') { throw "2.5 did not reach the file" }
Write-Host 'config: move_speed 2.5 on disk'

Op 'scene.new' | Out-Null
Op 'scene.save' | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' | Out-Null
Wait-Until 'pie_running' 900
Write-Host 'play running; warming 8s past the cold-start window'
Start-Sleep -Seconds 8

$body = '{"jsonrpc":"2.0","id":7,"method":"jackdaw/scene_snapshot","params":{}}'
$r1 = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -TimeoutSec 30 -Body $body
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Seconds 2
$r2 = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -TimeoutSec 30 -Body $body
$elapsed = $sw.Elapsed.TotalSeconds
$r1.Content | Out-File -Encoding ascii (Join-Path $OutDir 'spinr1.json')
$r2.Content | Out-File -Encoding ascii (Join-Path $OutDir 'spinr2.json')
Write-Host ("snaps saved (window " + [Math]::Round($elapsed,2) + "s)")

Op 'pie.stop' | Out-Null
Wait-Until 'idle' 120
Stop-Process -Id $proc.Id -Force
Write-Output 'SPIN_LEG_DONE'
