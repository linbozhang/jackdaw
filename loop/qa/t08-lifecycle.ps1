# T08-T2 live: authored-asset lifecycle protection on my-game.
#   Leg A (N10 prior-freeze zone): dirty scene (Save semantics) + dirty
#     asset card + pie.play_current -> editor alive, asset value saved
#     to disk by the launch chain, play runs, stop returns.
#   Leg B (T07 export chain): dirty asset card + game.export ->
#     jackdaw/export ready + the asset on disk (and so in the staged
#     package) carries the card's value.
#   Leg C (T1 leftover): scene_snapshot over the editor port during a
#     play session -> projected entities move (the method is now
#     registered editor-side).
# Usage: powershell -NoProfile -File loop\qa\t08-lifecycle.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15703
$OutDir  = Join-Path $Repo 'loop\t08-t2-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')

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

# The asset under test: a compiled material kind every project has.
# The file the editor creates is named after the asset's name (no
# .material segment).
$assetPath = Join-Path $Project 'assets\t08-lifecycle.bsn'

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir 'editor-stdout.log') `
    -RedirectStandardError (Join-Path $OutDir 'editor-stderr.log') -PassThru
$proc.Id | Set-Content (Join-Path $OutDir 'editor.pid')
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died while booting' }
}
if (-not $ready) { throw 'editor BRP never answered' }
Wait-Until 'idle' 1800
Write-Host 'editor ready'

# -- A dirty asset card, the way a user makes one ----------------------
Op 'asset.new' @{ type = 'material'; name = 't08-lifecycle' } | Out-Null
Start-Sleep -Seconds 1
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.75' } | Out-Null
Start-Sleep -Seconds 1
# Card is dirty and unsaved here: the disk copy has no 0.75 yet.
$beforePlay = if (Test-Path $assetPath) { Get-Content $assetPath -Raw } else { '' }
Write-Host ("card dirty; disk has 0.75: " + ($beforePlay -match '0\.75'))

# -- Leg A: N10 zone - named dirty-capable scene + dirty card + Play.
# A named scene (untitled runs the copy path, whose save chain is the
# scene-only branch): open the project's own scene, save it clean, then
# play — the launch-save chain (scenes AND asset cards) runs first.
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Op 'scene.save' @{} | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' @{} | Out-Null
Wait-Until 'pie_running' 900
Write-Host 'play running (N10 zone: no freeze)'
Start-Sleep -Seconds 4
$aliveDuringPlay = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
if (-not $aliveDuringPlay) { throw 'LEG A FAIL: editor froze/died during the N10-zone play' }

# Leg C rides the same session: the editor port now answers
# scene_snapshot; some projected entity should be moving.
$tkey = 'bevy_transform::components::transform::Transform'
$a = (Brp-Try 'jackdaw/scene_snapshot' @{} ).result
Start-Sleep -Seconds 2
$b = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
$moved = $false; $snapshotCount = 0
if ($b) {
    $snapshotCount = @($b).Count
    foreach ($eb in @($b)) {
        foreach ($ea in @($a)) {
            if ($ea.entity -eq $eb.entity) {
                $ta = $ea.components[$tkey]; $tb = $eb.components[$tkey]
                if ($ta -and $tb -and [double]$tb.translation.y -ne [double]$ta.translation.y) { $moved = $true; break }
            }
        }
        if ($moved) { break }
    }
}
Write-Host ("LEG C scene_snapshot: count=$snapshotCount moved=$moved")

Op 'pie.stop' @{} | Out-Null
Wait-Until 'idle' 120
$aliveAfter = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
$afterPlay = Get-Content $assetPath -Raw -ErrorAction SilentlyContinue
$savedByChain = ($afterPlay -match '0\.75')
if ($aliveAfter -and $savedByChain) {
    Write-Host 'LEG A PASS: N10-zone play survived; the launch chain saved the dirty card'
} else {
    Write-Host ("LEG A FAIL: alive={0} saved={1}" -f $aliveAfter, $savedByChain)
}

# -- Leg B: dirty card + export = the staged package carries the card's value
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.9' } | Out-Null
Start-Sleep -Seconds 1
Op 'game.export' @{} | Out-Null
Wait-Until 'idle' 1800
$face = Brp-Try 'jackdaw/export' @{}
$dist = "$($face.result.dist_dir)"
$stagedAsset = if ($dist) { Join-Path $dist 'assets\t08-lifecycle.bsn' } else { $null }
$stagedHas = if ($stagedAsset -and (Test-Path $stagedAsset)) { (Get-Content $stagedAsset -Raw) -match '0\.9' } else { $false }
if ($face.result.state -eq 'ready' -and $stagedHas) {
    Write-Host 'LEG B PASS: export ready; staged package carries the card value (0.9)'
} else {
    Write-Host ("LEG B FAIL: state={0} stagedHas={1} dist={2}" -f $face.result.state, $stagedHas, $dist)
}

$alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($alive) {
    $alive.Refresh()
    Save-WindowScreenshot $alive.MainWindowHandle (Join-Path $OutDir 't08t2.png') | Out-Null
    Stop-Process -Id $proc.Id -Force
}
Write-Output 'T08_T2_LIFECYCLE_DONE'
