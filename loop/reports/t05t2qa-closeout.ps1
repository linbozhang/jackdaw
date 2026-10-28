# T05-T2 QA closeout: Close-button control, scale probe, then the full rebind chain.
$ErrorActionPreference = 'Stop'
$Port = 15823
function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try { $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15 }
        catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout $Method"
}
function Wait-Idle([int]$T = 90) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 40 } 30).result.nodes }
function Find-All($nodes, [string]$text) {
    $found = @()
    foreach ($n in $nodes) {
        if ($n.text -and $n.text -like "*$text*") { $found += $n }
        if ($n.children) { $found += Find-All $n.children $text }
    }
    return $found
}
$out = 'E:\Project\rust\jackdaw\loop\reports\t05t2-rebind-qa'
function Fail([string]$What) { Write-Output "FAIL: $What"; exit 1 }
function Pass([string]$What) { Write-Output "PASS: $What" }

Wait-Idle 120
$audit = (Brp-Call 'jackdaw/audit' @{} 60).result
Write-Output ("audit before: " + $audit.summary)

# --- open the list and locate the buttons ---
Op 'asset.missing_list' @{} | Out-Null
Wait-Idle
$tree = Get-Tree
function Find-Container($nodes, [string]$label) {
    foreach ($n in $nodes) {
        if ($n.children -and ($n.children | Where-Object { $_.text -eq $label })) { return $n }
        if ($n.children) { $hit = Find-Container $n.children $label; if ($hit) { return $hit } }
    }
    return $null
}
$btn = Find-Container $tree 'Rebind'
if (-not $btn) { Fail 'no Rebind container in the list' }
$close = Find-Container $tree 'Close'
Write-Output ("Rebind container: kind=$($btn.kind) rect=" + ($btn.rect -join ','))
if ($close) { Write-Output ("Close container: kind=$($close.kind) rect=" + ($close.rect -join ',')) } else { Write-Output 'Close container not found' }

# --- control: does ui_click on Close dismiss the list? ---
if ($close) { Brp-Call 'jackdaw/ui_click' @{ entity = $close.entity } 30 | Out-Null }
Wait-Idle
Start-Sleep -Milliseconds 400
$t2 = Get-Tree
$stillOpen = Find-All $t2 'Missing References'
if ($stillOpen.Count -eq 0) { Write-Output 'CONTROL: ui_click Close dismisses the list - synthetic clicks reach the modal buttons' }
else {
    Write-Output 'CONTROL: ui_click Close did NOT dismiss the list - synthetic clicks do not reach the modal'
    # try input.pointer on Close as the fallback control
    $ccx = [double]$close.rect[0] + [double]$close.rect[2] / 2
    $ccy = [double]$close.rect[1] + [double]$close.rect[3] / 2
    Op 'input.pointer' @{ x = [Math]::Round($ccx / 2.25); y = [Math]::Round($ccy / 2.25); action = 'click' } | Out-Null
    Wait-Idle; Start-Sleep -Milliseconds 400
    $t3 = Get-Tree
    if ((Find-All $t3 'Missing References').Count -eq 0) { Write-Output 'CONTROL-B: input.pointer(2.25) Close works' } else { Write-Output 'CONTROL-B: input.pointer(2.25) Close does not work either' }
}

# --- reopen the list and probe scales for Rebind ---
Op 'asset.missing_list' @{} | Out-Null
Wait-Idle
$cx = [double]$btn.rect[0] + [double]$btn.rect[2] / 2
$cy = [double]$btn.rect[1] + [double]$btn.rect[3] / 2
$working = $null
foreach ($div in @(2.25, 1.5, 1.0)) {
    $lx = [Math]::Round($cx / $div); $ly = [Math]::Round($cy / $div)
    Write-Output ("probe input.pointer at ($lx,$ly) [scale $div]")
    Op 'input.pointer' @{ x = $lx; y = $ly; action = 'click' } | Out-Null
    Wait-Idle; Start-Sleep -Milliseconds 500
    $tp = Get-Tree
    $tp | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 (Join-Path $out ("probe-scale-$($div.ToString().Replace('.','-')).json"))
    $pick = Find-All $tp 'keeper'
    $title = Find-All $tp 'Rebind reference'
    if ($pick.Count -gt 0 -or $title.Count -gt 0) { Write-Output ("PICKER OPEN at scale $div"); $working = $div; break }
    Write-Output "  no picker at scale $div"
}
if (-not $working) {
    # last resort: ui_click the Rebind container once more (fresh list state)
    $treeF = Get-Tree
    $btnF = (Find-All $treeF 'Rebind' | Where-Object { $_.kind -eq 'node' }) | Select-Object -First 1
    if ($btnF) {
        Brp-Call 'jackdaw/ui_click' @{ entity = $btnF.entity } 30 | Out-Null
        Wait-Idle; Start-Sleep -Milliseconds 500
        $tf = Get-Tree
        if ((Find-All $tf 'keeper').Count -gt 0) { Write-Output 'PICKER OPEN via ui_click after fresh list'; $working = 'ui_click' }
    }
}
if (-not $working) { Fail 'the rebind picker cannot be opened by any synthetic-click channel (recorded as the blocking point)' }

# --- pick keeper ---
$tp = Get-Tree
$keep = Find-All $tp 'keeper' | Select-Object -First 1
if (-not $keep) { Fail 'picker open but keeper item not found' }
$kx = [double]$keep.rect[0] + [double]$keep.rect[2] / 2
$ky = [double]$keep.rect[1] + [double]$keep.rect[3] / 2
if ($working -eq 'ui_click') { Brp-Call 'jackdaw/ui_click' @{ entity = $keep.entity } 30 | Out-Null }
else { Op 'input.pointer' @{ x = [Math]::Round($kx / $working); y = [Math]::Round($ky / $working); action = 'click' } | Out-Null }
Wait-Idle; Start-Sleep -Milliseconds 500
$bsn = (Brp-Call 'jackdaw/scene_bsn' @{} 30).result
$text = $bsn | ConvertTo-Json -Depth 10
$bsn | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $out 'phase4-scene-bsn.json')
if ($text -notlike '*keeper*') { Fail 'the authored bsn does not name the held prefab' }
if ($text -like '*victim*') { Fail 'the authored bsn still names the gone prefab' }
Pass "rebind wrote the tab's document (victim -> keeper, channel=$working)"

# --- save ---
Op 'scene.save' @{} | Out-Null
Wait-Idle
$saved = [System.IO.File]::ReadAllText('C:\Users\linbo.zhang\Projects\my-game\assets\scene.bsn')
if ($saved -notlike '*keeper*') { Fail 'the file on disk does not name the held prefab' }
if ($saved -like '*victim*') { Fail 'the file on disk still names the gone prefab' }
Pass 'scene.save wrote the new reference to disk'

# --- reopen and audit clean ---
Op 'scene.new' @{} | Out-Null; Wait-Idle
Op 'scene.switch' @{ tab = 0 } | Out-Null; Wait-Idle
Op 'scene.close' @{} | Out-Null; Wait-Idle
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Wait-Idle 120
$audit2 = (Brp-Call 'jackdaw/audit' @{} 60).result
$audit2 | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $out 'phase6-audit2.json')
Write-Output ("audit after reopen: " + $audit2.summary + " ; count=" + $audit2.count)
$victimLeft = @($audit2.findings) | Where-Object { $_.reference -like '*victim*' }
if (@($victimLeft).Count -gt 0) { Write-Output ('NOTE: victim still reported: ' + ($victimLeft | ConvertTo-Json -Compress)) }
$keeperMachines = @($audit2.findings) | Where-Object { $_.reference -like '*keeper*' }
if (@($keeperMachines).Count -gt 0) { Write-Output ('NOTE: healthy keeper reported after reopen: ' + ($keeperMachines | ConvertTo-Json -Compress)) }
if ($audit2.count -eq 0) { Pass 'the reopened scene audits clean' }
else { Write-Output 'NOTE: reopened audit is not empty (recorded above)' }
Brp-Call 'jackdaw/screenshot' @{ kind = 'window'; path = (Join-Path $out 'final-window.png') } 30 | Out-Null
Write-Output 'CLOSEOUT DONE'
