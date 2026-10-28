# Phase v2: fresh editor, select Sun, click the category-strip button whose
# tooltip titles 'Transform' (the Object category), then dump panel texts.
param([int]$Port = 15807)
$ErrorActionPreference = 'Stop'
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
    throw "timeout waiting for $Method $Params"
}
function Wait-Idle([int]$T = 90) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes }

$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) { Start-Sleep -Seconds 4; if (netstat -ano | Select-String ':15807\s.*LISTENING') { break } }
Wait-Idle 120
Start-Sleep -Seconds 2

# select Sun
$script:rows = @()
function Walk($n) {
    if (@($n.children | Where-Object { $_.text -eq 'Sun' }).Count -gt 0) { $script:rows += $n }
    foreach ($c in @($n.children)) { Walk $c }
}
foreach ($n in (Get-Tree)) { Walk $n }
$row = @($script:rows | Where-Object { $_.rect[0] -lt 300 -and $_.rect[2] -gt 0 })[0]
$r = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$row.entity }
Write-Output ('[select] ' + ($r.result | ConvertTo-Json -Compress))
Wait-Idle; Start-Sleep -Milliseconds 600

# strip buttons: nodes whose subtree carries a text child of a known category
# name ('Transform', 'Components', 'Mesh', 'Object', 'Material'); click the
# one titled Transform (Object category). Never touch y<40 nodes (window
# controls shrink the window - lesson from two sessions).
$script:cands = @()
function FindStrip($n, $title) {
    if (@($n.children | Where-Object { $_.text -eq $title }).Count -gt 0) { $script:cands += @{ n = $n; t = $title } }
    foreach ($c in @($n.children)) { FindStrip $c $title }
}
foreach ($title in 'Transform', 'Components') {
    $script:cands = @()
    foreach ($n in (Get-Tree)) { FindStrip $n $title }
    foreach ($c in $script:cands) {
        Write-Output ('strip? title=' + $c.t + ' e=' + $c.n.entity + ' rect=[' + ($c.n.rect -join ',') + ']')
    }
    if ($title -eq 'Transform' -and $script:cands.Count -ge 1) {
        $target = @($script:cands | Where-Object { $_.n.rect[1] -gt 100 } | Sort-Object { $_.n.rect[2] })[0]
        if ($target) {
            $c2 = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$target.n.entity }
            Write-Output ('[click Transform strip] ' + ($c2 | ConvertTo-Json -Depth 4 -Compress))
        } else { Write-Output 'no Transform strip button below y=100' }
    }
}
Wait-Idle; Start-Sleep -Milliseconds 800

$script:hits = @()
function TW($n) {
    if ($n.kind -eq 'text' -and $n.rect -and $n.rect[2] -gt 0 -and $n.rect[0] -gt 1000 -and $n.rect[1] -gt 30 -and $n.rect[1] -lt 500) { $script:hits += $n }
    foreach ($c in @($n.children)) { TW $c }
}
foreach ($n in (Get-Tree)) { TW $n }
Write-Output '--- panel texts:'
$script:hits | Sort-Object { $_.rect[1] } | ForEach-Object {
    Write-Output ('t=[' + $_.text + '] e=' + $_.entity + ' x=' + $_.rect[0] + ' y=' + $_.rect[1] + ' w=' + $_.rect[2] + ' h=' + $_.rect[3])
}
