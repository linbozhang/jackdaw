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
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 40 } 30).result.nodes }
function Find-All($nodes, [string]$text) {
    $found = @()
    foreach ($n in $nodes) {
        if ($n.text -and $n.text -like "*$text*") { $found += $n }
        if ($n.children) { $found += Find-All $n.children $text }
    }
    return $found
}
function Find-Container($nodes, [string]$label) {
    foreach ($n in $nodes) {
        if ($n.children -and ($n.children | Where-Object { $_.text -eq $label })) { return $n }
        if ($n.children) { $hit = Find-Container $n.children $label; if ($hit) { return $hit } }
    }
    return $null
}
Wait-Idle
Op 'asset.missing_list' @{} | Out-Null
Wait-Idle
$tree = Get-Tree
$btn = Find-Container $tree 'Rebind'
if (-not $btn) { Write-Output 'no Rebind container'; exit 1 }
Write-Output ("clicking Rebind container entity=" + $btn.entity)
Brp-Call 'jackdaw/ui_click' @{ entity = $btn.entity } 30 | Out-Null
Wait-Idle
Start-Sleep -Milliseconds 600
$t2 = Get-Tree
$t2 | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 'E:\Project\rust\jackdaw\loop\reports\t05t2-rebind-qa\diag-after-rebind3.json'
foreach ($pat in @('open it first', 'no assets', 'rebound', 'Rebind reference', 'keeper')) {
    $hits = Find-All $t2 $pat
    $extra = ''
    if (@($hits).Count -gt 0) { $extra = ' -> ' + @($hits)[0].text }
    Write-Output ("pattern '" + $pat + "': " + @($hits).Count + $extra)
}
