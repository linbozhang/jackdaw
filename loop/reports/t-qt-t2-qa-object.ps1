# Phase: on a fresh editor, select Sun, switch inspector to the Object
# category, expand the Transform card if needed, then dump the field texts so
# the switch test can locate the real translation Y input.
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

# category strip icons: nodes ~46x34 in the top-right area; click the LEFTMOST
$script:strip = @()
function Strip($n) {
    if ($n.rect -and $n.rect[2] -gt 30 -and $n.rect[2] -lt 60 -and $n.rect[3] -gt 20 -and $n.rect[3] -lt 45 -and $n.rect[0] -gt 1000 -and $n.rect[1] -lt 30) { $script:strip += $n }
    foreach ($c in @($n.children)) { Strip $c }
}
foreach ($n in (Get-Tree)) { Strip $n }
$strip = @($script:strip | Sort-Object { $_.rect[0] })
$strip | ForEach-Object { Write-Output ('strip e=' + $_.entity + ' rect=[' + ($_.rect -join ',') + ']') }
if ($strip.Count -lt 1) { throw 'no strip icons' }
$c = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$strip[0].entity }
Write-Output ('[category click] ' + ($c.result | ConvertTo-Json -Compress))
Wait-Idle; Start-Sleep -Milliseconds 800

function DumpTexts {
    $script:hits = @()
    function TW($n) {
        if ($n.kind -eq 'text' -and $n.rect -and $n.rect[2] -gt 0 -and $n.rect[0] -gt 1000 -and $n.rect[1] -gt 30) { $script:hits += $n }
        foreach ($c in @($n.children)) { TW $c }
    }
    foreach ($n in (Get-Tree)) { TW $n }
    $script:hits | Sort-Object { $_.rect[1] } | ForEach-Object {
        Write-Output ('t=[' + $_.text + '] e=' + $_.entity + ' x=' + $_.rect[0] + ' y=' + $_.rect[1] + ' w=' + $_.rect[2] + ' h=' + $_.rect[3])
    }
}
Write-Output '--- texts after category click:'
DumpTexts
