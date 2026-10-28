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
function Wait-Idle([int]$T = 60) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }
$out = 'E:\Project\rust\jackdaw\loop\reports\t05t2-rebind-qa'
function Find-All($nodes, [string]$text) {
    $found = @()
    foreach ($n in $nodes) {
        if ($n.text -and $n.text -like "*$text*") { $found += $n }
        if ($n.children) { $found += Find-All $n.children $text }
    }
    return $found
}
Wait-Idle
# fresh list
Op 'asset.missing_list' @{} | Out-Null
Wait-Idle
$nodes = (Brp-Call 'jackdaw/ui_tree' @{ depth = 40 } 30).result.nodes
$btns = Find-All $nodes 'Rebind'
$btn = $btns | Where-Object { $_.kind -eq 'node' } | Select-Object -First 1
if (-not $btn) { $btn = $btns | Select-Object -First 1 }
Write-Output ("Rebind rect: " + ($btn.rect -join ','))
$cx = [double]$btn.rect[0] + [double]$btn.rect[2] / 2
$cy = [double]$btn.rect[1] + [double]$btn.rect[3] / 2
Write-Output ("center (physical-ish ui units): $cx , $cy")
# window roots: 4320 wide physically; logical window is 1920 -> divide by 2.25
foreach ($div in @(2.25)) {
    $lx = [Math]::Round($cx / $div); $ly = [Math]::Round($cy / $div)
    Write-Output ("trying input.pointer click at logical ($lx,$ly) [scale $div]")
    Op 'input.pointer' @{ x = $lx; y = $ly; action = 'click' } | Out-Null
    Wait-Idle
    Start-Sleep -Milliseconds 400
    $t2 = (Brp-Call 'jackdaw/ui_tree' @{ depth = 40 } 30).result.nodes
    $t2 | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 (Join-Path $out ("diag-pointer-click-$($div.ToString().Replace('.','-')).json"))
    $pick = Find-All $t2 'keeper'
    $title = Find-All $t2 'Rebind reference'
    if ($pick -or $title) { Write-Output ("PICKER OPEN (scale $div): " + (($title | Select-Object -First 1).text) + ' / items: ' + @($pick).Count); break }
    else { Write-Output "picker not open at scale $div" }
}
