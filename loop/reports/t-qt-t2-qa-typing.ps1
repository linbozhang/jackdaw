# Typing experiment: does ui_input reach a ScrubNumberInput? Select Sun, focus
# the Transform Y input, type without commit, then read the widget's value text
# from the ui_tree and take a window screenshot.
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
function Wait-Idle([int]$T = 60) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes }

$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 4
    if (netstat -ano | Select-String ':15807\s.*LISTENING') { break }
}
Wait-Idle 90
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
Write-Output ('[select Sun] ' + ($r.result | ConvertTo-Json -Compress))
Wait-Idle; Start-Sleep -Milliseconds 500

# find the Y input (retry: the panel rebuilds for a few frames)
$y = $null
for ($try = 1; $try -le 5 -and -not $y; $try++) {
    $script:chain = @(); $script:hit = $false
    function Collect($n, $acc) {
        if ($script:hit) { return }
        if ($n.text -eq 'Y' -and $n.rect[0] -gt 1150) { $script:chain = $acc + @($n); $script:hit = $true; return }
        $newAcc = $acc + @($n)
        foreach ($c in @($n.children)) { Collect $c $newAcc }
    }
    foreach ($n in (Get-Tree)) { Collect $n @() }
    if ($script:hit) {
        $chain = $script:chain
        for ($i = $chain.Count - 1; $i -ge 0; $i--) { if ($chain[$i].rect[2] -gt 1) { $y = $chain[$i]; break } }
    }
    if (-not $y) { Brp-Call 'jackdaw/wait' @{ frames = 6 } | Out-Null; Start-Sleep -Milliseconds 200 }
}
if (-not $y) { throw 'no Y input' }
Write-Output ('[Y input] e=' + $y.entity + ' rect=[' + ($y.rect -join ',') + ']')

# dump the subtree of the input box: labels and value text
function DumpTree($n, [int]$d) {
    $t = if ($n.text) { $n.text } else { '' }
    Write-Output (('  ' * $d) + 'e=' + $n.entity + ' k=' + $n.kind + ' t=[' + $t + '] rect=[' + ($n.rect -join ',') + ']')
    if ($d -lt 4) { foreach ($c in @($n.children)) { DumpTree $c ($d + 1) } }
}
DumpTree $y 0

# type without commit
$in = Brp-Call 'jackdaw/ui_input' @{ entity = [uint64]$y.entity; text = '7.5'; commit = 'none' }
Write-Output ('[ui_input] ' + ($in | ConvertTo-Json -Depth 4 -Compress))
Wait-Idle
Brp-Call 'jackdaw/wait' @{ frames = 10 } | Out-Null

# re-locate the Y input and dump again (value text should show 7.5 if typing landed)
DumpTree $y 0

# screenshot for the record
$rel = 'screenshots/tqt2-typing.png'
Brp-Call 'jackdaw/screenshot' @{ kind = 'window'; path = $rel } 30 | Out-Null
$src = 'C:\Users\linbo.zhang\Projects\my-game\' + $rel
if (Test-Path $src) { Copy-Item $src 'E:\Project\rust\jackdaw\loop\reports\t-qt-t2-live\typing-window.png' -Force; Write-Output '[shot] saved' }
