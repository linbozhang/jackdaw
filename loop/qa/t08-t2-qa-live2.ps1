# T08-T2 QA live v2: export save leg + quit-dialog asset leg, no play
# (the first run showed PIE stop closes open asset cards, which starved
# the later legs of a dirty card - asset.set answered "no asset is open").
# Usage: powershell -NoProfile -File loop\qa\t08-t2-qa-live2.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15703
$OutDir  = Join-Path $Repo 'loop\t08-t2-qa-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

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
        }
        Start-Sleep -Seconds 2
    }
    throw "wait($until) timed out after ${TimeoutSec}s"
}

$assetPath = Join-Path $Project 'assets\t08qa3.bsn'
$scenePath = Join-Path $Project 'assets\scene.bsn'
$sceneShaBefore = (Get-FileHash $scenePath -Algorithm SHA256).Hash

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32Qa2 {
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
    -RedirectStandardOutput (Join-Path $OutDir 'editor2-stdout.log') `
    -RedirectStandardError (Join-Path $OutDir 'editor2-stderr.log') -PassThru
$proc.Id | Set-Content (Join-Path $OutDir 'editor2.pid')
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died while booting' }
}
if (-not $ready) { throw 'editor BRP never answered' }
Wait-Until 'idle' 1800
Write-Host 'editor ready'

# Dirty card, fresh session (no play in between).
Op 'asset.new' @{ type = 'material'; name = 't08qa3' } | Out-Null
Start-Sleep -Seconds 1
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.75' } | Out-Null
Start-Sleep -Seconds 1
$before = if (Test-Path $assetPath) { Get-Content $assetPath -Raw } else { '' }
Write-Host ("P0 card dirty; disk has 0.75: " + ($before -match '0\.75'))

# --- Export save leg: game.export writes the dirty card before building.
Op 'game.export' @{} | Out-Null
Start-Sleep -Seconds 5
$afterExport = Get-Content $assetPath -Raw -ErrorAction SilentlyContinue
$savedExport = ($afterExport -match '0\.75')
Write-Host ("LEGB sync save: disk has 0.75 right after game.export: " + $savedExport)
$dist = Join-Path $Project '.jackdaw\dist\release'
$stagedAsset = Join-Path $dist 'assets\t08qa3.bsn'
$distSaw = $false
$state = 'unknown'
$deadline = (Get-Date).AddSeconds(240)
while ((Get-Date) -lt $deadline) {
    if ((Test-Path $stagedAsset) -and ((Get-Content $stagedAsset -Raw) -match '0\.75')) { $distSaw = $true }
    $face = Brp-Try 'jackdaw/export' @{} 1
    if ($face) { $state = "$($face.result.state)" }
    if ($distSaw -and $state -eq 'ready') { break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Seconds 5
}
Write-Host ("LEGB state={0} distHas075={1}" -f $state, $distSaw)
if ($savedExport -and $distSaw) { Write-Host 'LEGB PASS: export saved the dirty card and the staged package carries it' }
elseif ($savedExport) { Write-Host 'LEGB PARTIAL: sync save passed; dist not ready in window (T3 matrix cell 7 decides)' }
else { Write-Host 'LEGB FAIL: card value did not reach disk' }

# --- Quit dialog asset leg ----------------------------------------------
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.9' } | Out-Null
Start-Sleep -Seconds 1
$hwnd = (Get-Process -Id $proc.Id).MainWindowHandle
[Win32Qa2]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
Start-Sleep -Seconds 2
$flat = Brp-Try 'jackdaw/ui_tree' @{ text = 'Unsaved assets' } 1
$flatJson = if ($flat -and $flat.result.nodes) { ($flat.result.nodes | ConvertTo-Json -Depth 8 -Compress) } else { 'not found' }
$dlg = Brp-Try 'jackdaw/ui_tree' @{ kind = 'dialog' } 1
$dlgJson = if ($dlg -and $dlg.result.nodes) { ($dlg.result.nodes | ConvertTo-Json -Depth 6 -Compress) } else { 'no dialog node' }
Write-Host ("QUIT1 dialog: " + $dlgJson)
Write-Host ("QUIT1 names asset: " + $flatJson)
$aliveMid = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
$cancel = Brp-Try 'jackdaw/ui_click' @{ text = 'Cancel' } 3
Start-Sleep -Seconds 2
$aliveCancel = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
$diskAfterCancel = (Get-Content $assetPath -Raw -ErrorAction SilentlyContinue) -match '0\.9'
Write-Host ("QUIT1 Cancel: dialogWasUp=" + ($flatJson -ne 'not found') + " alive=" + $aliveCancel + " diskHas09=" + $diskAfterCancel)
if (($flatJson -ne 'not found') -and $aliveCancel -and -not $diskAfterCancel) { Write-Host 'QUIT1 PASS: dialog named the asset; Cancel stayed with 0.9 unsaved' }
else { Write-Host 'QUIT1 FAIL' }

# Save All writes 0.9 and the editor exits.
$hwnd = (Get-Process -Id $proc.Id).MainWindowHandle
[Win32Qa2]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
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

$alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($alive) { Stop-Process -Id $proc.Id -Force }
$sceneShaAfter = (Get-FileHash $scenePath -Algorithm SHA256).Hash
Write-Host ("scene.bsn SHA unchanged: " + ($sceneShaBefore -eq $sceneShaAfter))
Write-Output 'T08_T2_QA_LIVE2_DONE'
