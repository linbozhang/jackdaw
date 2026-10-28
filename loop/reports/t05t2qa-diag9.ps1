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
# touch keeper (same bytes) to make the watcher rescan
$keeper = 'C:\Users\linbo.zhang\Projects\my-game\assets\props\keeper.bsn'
$text = [System.IO.File]::ReadAllText($keeper)
[System.IO.File]::WriteAllText($keeper, $text)
Start-Sleep -Seconds 3
Wait-Idle
$log = Get-Content "$env:TEMP\t05t2qa-editor2.log" -Encoding UTF8
$idx = $log | Select-String -Pattern 'Indexed' | Select-Object -Last 3
Write-Output '--- Indexed lines now:'
$idx | ForEach-Object { $_.Line }
if (-not $idx) { Write-Output '(still none)' }
# probe: does the asset index answer now?
$refs = Op 'asset.references' @{ path = 'assets/props/keeper.bsn' }
Write-Output ('asset.references -> ' + ($refs | ConvertTo-Json -Depth 6 -Compress))
# retry Rebind
Op 'asset.missing_list' @{} | Out-Null
Wait-Idle
$tree = Get-Tree
$btn = Find-Container $tree 'Rebind'
if (-not $btn) { Write-Output 'no Rebind container (list empty or closed?)'; exit 1 }
Brp-Call 'jackdaw/ui_click' @{ entity = $btn.entity } 30 | Out-Null
Wait-Idle
Start-Sleep -Milliseconds 600
$t2 = Get-Tree
$t2 | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 'E:\Project\rust\jackdaw\loop\reports\t05t2-rebind-qa\diag-after-touch.json'
$noAssets = Find-All $t2 'no assets'
$pick = Find-All $t2 'keeper'
$title = Find-All $t2 'Rebind reference'
Write-Output ('no-assets warn still: ' + @($noAssets).Count + ' ; picker title: ' + @($title).Count + ' ; keeper items: ' + @($pick).Count)
