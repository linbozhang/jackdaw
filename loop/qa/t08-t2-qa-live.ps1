# T08-T2 QA live: independent re-run of the authored-asset lifecycle legs.
#   P5 leg   : a saved-clean named scene + an asset-field edit -> history
#              stays dirty=false (the tab flag no longer follows the shared
#              undo stack), undo_len still grows.
#   Leg A    : N10 prior-freeze zone - dirty card + named scene + Save-mode
#              play_current -> editor alive, card value reaches disk.
#   Leg C    : scene_snapshot over the editor port (count, two-frame diff).
#   Leg B    : game.export -> the synchronous save leg writes the card value
#              to disk immediately; dist watched for a short window.
#   Quit legs: WM_CLOSE with a dirty card -> dialog names the asset; Cancel
#              stays; Save All writes 0.9 and the editor exits.
# Usage: powershell -NoProfile -File loop\qa\t08-t2-qa-live.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15703
$OutDir  = Join-Path $Repo 'loop\t08-t2-qa-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')
. (Join-Path $Repo 'loop\qa\input.ps1')

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

$assetPath = Join-Path $Project 'assets\t08qa2.bsn'
$scenePath = Join-Path $Project 'assets\scene.bsn'
$sceneShaBefore = (Get-FileHash $scenePath -Algorithm SHA256).Hash

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32Qa {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp);
}
"@

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

# A dirty asset card the way a user makes one.
Op 'asset.new' @{ type = 'material'; name = 't08qa2' } | Out-Null
Start-Sleep -Seconds 1
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.75' } | Out-Null
Start-Sleep -Seconds 1
$before = if (Test-Path $assetPath) { Get-Content $assetPath -Raw } else { '' }
Write-Host ("P0 card dirty; disk has 0.75: " + ($before -match '0\.75'))

# --- P5 live leg: a clean named scene + an asset edit ------------------
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Op 'scene.save' @{} | Out-Null
Start-Sleep -Seconds 1
$clean = History-Dirty
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.8' } | Out-Null
Start-Sleep -Seconds 2
$afterEdit = History-Dirty
if ($clean.dirty) { Write-Host 'P5 baseline was dirty (unexpected); noting' } else { Write-Host 'P5 baseline: clean tab' }
Write-Host ("P5 after asset edit: dirty=" + $afterEdit.dirty + " undo_len " + $clean.undo + "->" + $afterEdit.undo)
if (-not $afterEdit.dirty) { Write-Host 'P5 PASS: asset edit left the scene tab clean' }
else { Write-Host 'P5 FAIL: asset edit dirtied the scene tab' }

# --- Leg A: N10 zone, Save-mode play with a dirty card -----------------
Op 'pie.play_current' @{} | Out-Null
Wait-Until 'pie_running' 900
Write-Host 'LEG A: play running (N10 zone)'
Start-Sleep -Seconds 4
$aliveDuring = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
if (-not $aliveDuring) { throw 'LEG A FAIL: editor froze/died during the N10-zone play' }

# --- Leg C: scene_snapshot over the editor port ------------------------
$tkey = 'bevy_transform::components::transform::Transform'
$a = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
Start-Sleep -Seconds 2
$b = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
$moved = $false; $count = 0
if ($b) {
    $count = @($b).Count
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
Write-Host ("LEG C scene_snapshot: count=$count moved=$moved (my-game has no animated entity; moved expected False)")

Op 'pie.stop' @{} | Out-Null
Wait-Until 'idle' 120
$aliveAfter = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
$afterPlay = Get-Content $assetPath -Raw -ErrorAction SilentlyContinue
$savedByChain = ($afterPlay -match '0\.8')
if ($aliveAfter -and $savedByChain) { Write-Host 'LEG A PASS: N10-zone play survived; the launch chain saved the 0.8 card' }
else { Write-Host ("LEG A FAIL: alive={0} saved08={1}" -f $aliveAfter, $savedByChain) }
$stillClean = History-Dirty
Write-Host ("LEG A post-stop tab dirty=" + $stillClean.dirty)

# --- Leg B: export saves the dirty card synchronously ------------------
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.85' } | Out-Null
Start-Sleep -Seconds 1
Op 'game.export' @{} | Out-Null
Start-Sleep -Seconds 5
$afterExport = Get-Content $assetPath -Raw -ErrorAction SilentlyContinue
$savedExport = ($afterExport -match '0\.85')
Write-Host ("LEG B sync save: disk has 0.85 right after game.export: " + $savedExport)
$dist = Join-Path $Project '.jackdaw\dist\release'
$stagedAsset = Join-Path $dist 'assets\t08qa2.bsn'
$distSaw = $false
$deadline = (Get-Date).AddSeconds(150)
while ((Get-Date) -lt $deadline) {
    if ((Test-Path $stagedAsset) -and ((Get-Content $stagedAsset -Raw) -match '0\.85')) { $distSaw = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Seconds 5
}
$face = Brp-Try 'jackdaw/export' @{}
Write-Host ("LEG B state={0} distHas085={1}" -f $face.result.state, $distSaw)
if ($savedExport) { Write-Host 'LEG B PASS (save leg): the export chain wrote the card value before building' }
else { Write-Host 'LEG B FAIL: card value did not reach disk' }

# --- Quit leg 1: dialog appears, names the asset, Cancel stays ---------
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.9' } | Out-Null
Start-Sleep -Seconds 1
$hwnd = (Get-Process -Id $proc.Id).MainWindowHandle
[Win32Qa]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
Start-Sleep -Seconds 2
$tree = Brp-Try 'jackdaw/ui_tree' @{ kind = 'dialog' } 1
$dialogText = if ($tree) { ($tree.result.nodes | ConvertTo-Json -Depth 6 -Compress) } else { 'no dialog node' }
$flat = Brp-Try 'jackdaw/ui_tree' @{ text = 'Unsaved assets' } 1
$flatJson = if ($flat) { ($flat.result.nodes | ConvertTo-Json -Depth 8 -Compress) } else { 'not found' }
Write-Host ("QUIT1 dialog: " + $dialogText)
Write-Host ("QUIT1 names asset: " + $flatJson)
$cancel = Brp-Try 'jackdaw/ui_click' @{ text = 'Cancel' } 3
Start-Sleep -Seconds 2
$aliveCancel = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
$diskAfterCancel = (Get-Content $assetPath -Raw -ErrorAction SilentlyContinue) -match '0\.9'
Write-Host ("QUIT1 Cancel: alive=" + $aliveCancel + " diskHas09=" + $diskAfterCancel)
if ($aliveCancel -and -not $diskAfterCancel) { Write-Host 'QUIT1 PASS: Cancel kept the editor open and the 0.9 unsaved' }
else { Write-Host 'QUIT1 FAIL' }

# --- Quit leg 2: Save All writes 0.9 and the editor exits ---------------
$hwnd = (Get-Process -Id $proc.Id).MainWindowHandle
[Win32Qa]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
Start-Sleep -Seconds 2
$saveAll = Brp-Try 'jackdaw/ui_click' @{ text = 'Save All' } 3
Start-Sleep -Seconds 2
$exited = $false
for ($i = 0; $i -lt 30; $i++) {
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { $exited = $true; break }
    Start-Sleep -Seconds 2
}
$diskAfterSaveAll = (Get-Content $assetPath -Raw -ErrorAction SilentlyContinue) -match '0\.9'
Write-Host ("QUIT2 SaveAll: exited=" + $exited + " diskHas09=" + $diskAfterSaveAll)
if ($exited -and $diskAfterSaveAll) { Write-Host 'QUIT2 PASS: Save All wrote the card and the editor left' }
else { Write-Host 'QUIT2 FAIL' }

# --- Cleanup and integrity ----------------------------------------------
$alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($alive) { Stop-Process -Id $proc.Id -Force }
$sceneShaAfter = (Get-FileHash $scenePath -Algorithm SHA256).Hash
Write-Host ("scene.bsn SHA unchanged: " + ($sceneShaBefore -eq $sceneShaAfter))
Write-Output 'T08_T2_QA_LIVE_DONE'
