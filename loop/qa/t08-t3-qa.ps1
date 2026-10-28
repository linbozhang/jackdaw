# T08-T3 QA spot-check: C2 (restart consistency) and C7 (export carries
# the card value + manifest) on the t08lf-qa template project - the two
# matrix cells the task asks QA to re-verify independently. C7 pays a
# first-time release build (cold); that is the cost of an independent leg.
$ErrorActionPreference = 'Stop'

$Repo  = 'E:\Project\rust\jackdaw'
$Exe   = Join-Path $Repo 'target\debug\jackdaw.exe'
$Proj  = 'E:\Project\rust\jackdaw\loop\qa-fixture\t08lf-qa'
$Port  = 15703
$OutDir = Join-Path $Repo 'loop\t08-t2-qa-live'

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
    throw "wait($until) timed out after ${TimeoutSec}s"
}

$configPath = Join-Path $Proj 'assets\game-config.bsn'
if (Test-Path $configPath) { Remove-Item $configPath -Force }

# --- Session 1: create the config with a distinctive value, save. ------
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
Start-Sleep -Seconds 15
$created = Op 'asset.new' @{ type = 'game_config'; name = 'game-config' }
$okNew = "$($created.result.result)" -eq 'finished' -and -not $created.result.warnings
Write-Host ("C2 asset.new ok: " + $okNew)
if (-not $okNew) { throw 'asset.new failed' }
Op 'asset.set' @{ field = 'move_speed'; value = '3.25' } | Out-Null
Op 'asset.set' @{ field = 'gravity'; value = '-9.81' } | Out-Null
Op 'asset.save' | Out-Null
Start-Sleep -Seconds 1
$disk1 = Get-Content $configPath -Raw
Write-Host ("C2 saved on disk has 3.25: " + ($disk1 -match '3\.25'))
Stop-Process -Id $proc.Id -Force

# --- Session 2 (restart): disk value survived; card reopens with it. ---
Start-Sleep -Seconds 2
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
$ready = $false
for ($i = 0; $i -lt 360; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died booting (restart)' }
}
if (-not $ready) { throw 'BRP never answered (restart)' }
Wait-Until 'idle' 900
Start-Sleep -Seconds 5
$disk2 = Get-Content $configPath -Raw
$survived = $disk2 -match '3\.25'
$g = Op 'asset.get' @{ field = 'move_speed' }
$cardVal = "$($g.result.value)$($g.result)"
$cardHas = $cardVal -match '3\.25'
Write-Host ("C2 restart: disk-survived=$survived card-reads=$cardHas")
if ($survived) { Write-Host 'C2 PASS: the value survived an editor restart' } else { Write-Host 'C2 FAIL' }

# --- C7: dirty card 7.5 -> export -> dist carries it + manifest. -------
# The restart session has no card open (a fresh boot opens nothing);
# open the config card first so asset.set reaches it.
Op 'asset.open' @{ path = 'game-config.bsn' } | Out-Null
Start-Sleep -Seconds 2
Op 'asset.set' @{ field = 'move_speed'; value = '7.5' } | Out-Null
Start-Sleep -Seconds 1
$diskPre = (Get-Content $configPath -Raw) -match '7\.5'
Write-Host ("C7 card dirty, disk pre-export has 7.5: " + $diskPre + " (expect False)")
Op 'game.export' | Out-Null
# The export's save leg is synchronous; the release build is not.
Start-Sleep -Seconds 8
$diskSync = (Get-Content $configPath -Raw) -match '7\.5'
Write-Host ("C7 sync save leg wrote 7.5 right after export: " + $diskSync)
$dist = $null
$state = 'unknown'
$deadline = (Get-Date).AddSeconds(2400)
while ((Get-Date) -lt $deadline) {
    $face = Brp-Try 'jackdaw/export' @{} 1
    if ($face) { $state = "$($face.result.state)"; $dist = "$($face.result.dist_dir)" }
    if ($state -eq 'ready') { break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Seconds 10
}
Write-Host ("C7 state=$state dist=$dist")
$distCfg = if ($dist) { Join-Path $dist 'assets\game-config.bsn' } else { $null }
$distHas = $false
if ($distCfg -and (Test-Path $distCfg)) { $distHas = (Get-Content $distCfg -Raw) -match '7\.5' }
$manifest = if ($dist) { Join-Path $dist 'export-manifest.json' } else { $null }
$manifestHas = $false
if ($manifest -and (Test-Path $manifest)) { $manifestHas = (Get-Content $manifest -Raw) -match 'game-config\.bsn' }
Write-Host ("C7 dist carries 7.5: $distHas; manifest lists config: $manifestHas")
if ($distHas -and $manifestHas -and $diskSync) { Write-Host 'C7 PASS: export carries the card value and the receipt names it' }
else { Write-Host 'C7 FAIL' }

Stop-Process -Id $proc.Id -Force
Write-Output 'T08_T3_QA_DONE'
