# T08-T2 rework QA live: the two must-fix legs in one my-game session.
#   Leg B (QA-1): saved-clean named scene + asset.set -> history dirty
#                 stays false (the exact path that read true before).
#   Leg A (ruling A): untitled scene in front + dirty card + DEFAULT
#                 Save policy play_current -> the card's value is on
#                 disk after stop (the editor's own archived run logged
#                 False for this; this is the independent re-run).
# Usage: powershell -NoProfile -File loop\qa\t08-t2-rework-qa.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15703
$OutDir  = Join-Path $Repo 'loop\t08-t2-qa-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

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
function History-Dirty {
    $h = (Brp-Try 'jackdaw/history' @{}).result
    if ($h) { return @{ dirty = [bool]$h.dirty; undo = [int]$h.undo_len } }
    return $null
}

$assetPath = Join-Path $Project 'assets\t08rw3.bsn'
$scenePath = Join-Path $Project 'assets\scene.bsn'
$sceneShaBefore = (Get-FileHash $scenePath -Algorithm SHA256).Hash

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir 'reworkqa-stdout.log') `
    -RedirectStandardError (Join-Path $OutDir 'reworkqa-stderr.log') -PassThru
$proc.Id | Set-Content (Join-Path $OutDir 'reworkqa.pid')
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died while booting' }
}
if (-not $ready) { throw 'editor BRP never answered' }
Wait-Until 'idle' 1800
Write-Host 'editor ready'

# A dirty card first (created BEFORE any play, so the card is open).
Op 'asset.new' @{ type = 'material'; name = 't08rw3' } | Out-Null
Start-Sleep -Seconds 2
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.6' } | Out-Null
Start-Sleep -Seconds 2
$noVal = if (Test-Path $assetPath) { (Get-Content $assetPath -Raw) -match '0\.6' } else { $false }
Write-Host ("P0 card dirty, disk has 0.6: " + $noVal + " (expect False)")

# --- Leg B (QA-1): saved-clean named scene + asset edit stays clean ----
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Op 'scene.save' | Out-Null
Start-Sleep -Seconds 2
$before = History-Dirty
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.7' } | Out-Null
Start-Sleep -Seconds 2
$after = History-Dirty
Write-Host ("LEGB saved-scene dirty: before=" + $before.dirty + " after-asset-set=" + $after.dirty + " undo " + $before.undo + "->" + $after.undo + " (expect False/False)")
if (-not $before.dirty -and -not $after.dirty) { Write-Host 'LEGB PASS: the saved tab stays clean across an asset edit (QA-1 closed)' }
else { Write-Host 'LEGB FAIL' }

# --- Leg A (ruling A): untitled front + default Save policy play --------
$st = (Brp-Try 'jackdaw/status' @{}).result
Op 'scene.new' | Out-Null
Start-Sleep -Seconds 2
Op 'pie.play_current' | Out-Null
Wait-Until 'pie_running' 900
Write-Host 'LEGA untitled+Save policy: play running'
Start-Sleep -Seconds 4
$aliveDuring = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
Op 'pie.stop' | Out-Null
Wait-Until 'idle' 120
$aliveAfter = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
$disk = Get-Content $assetPath -Raw -ErrorAction SilentlyContinue
$has07 = $disk -match '0\.7'
$has07full = $disk -match '0\.699999'
Write-Host ("LEGA alive=" + ($aliveDuring -and $aliveAfter) + " card-on-disk-0.7=" + ($has07 -or $has07full))
if ($aliveDuring -and $aliveAfter -and ($has07 -or $has07full)) { Write-Host 'LEGA PASS: the untitled+Save-policy launch chain saved the dirty card' }
else { Write-Host 'LEGA FAIL' }

$alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($alive) { Stop-Process -Id $proc.Id -Force }
$sceneShaAfter = (Get-FileHash $scenePath -Algorithm SHA256).Hash
Write-Host ("scene.bsn SHA unchanged: " + ($sceneShaBefore -eq $sceneShaAfter))
Write-Output 'T08_T2_REWORK_QA_DONE'
