# Inline rebind: find Rebind text -> click its parent button -> pick keeper -> assert scene_bsn.
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
$out = 'E:\Project\rust\jackdaw\loop\reports\t05t2-rebind-qa'
function Wait-Idle([int]$T = 60) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 40 } 30).result.nodes }
function Fail([string]$What) { Write-Output "FAIL: $What"; exit 1 }

Wait-Idle
# make sure the list is open
Brp-Call 'jackdaw/call_operator' @{ id = 'asset.missing_list'; params = @{} } | Out-Null
Wait-Idle
$tree = Get-Tree
# find the node whose direct child text is 'Rebind' (the button container)
$script:btn = $null
function Walk($ns) {
    foreach ($n in $ns) {
        if ($n.children -and ($n.children | Where-Object { $_.text -eq 'Rebind' })) { $script:btn = $n; return }
        if ($n.children) { Walk $n.children }
    }
}
Walk $tree
if (-not $script:btn) { Fail 'no Rebind button container found' }
Write-Output ("Rebind button container: kind=$($script:btn.kind) entity=$($script:btn.entity) rect=$($script:btn.rect -join ',')")
$click = Brp-Call 'jackdaw/ui_click' @{ entity = $script:btn.entity } 30
Write-Output ("click result: " + ($click | ConvertTo-Json -Depth 5 -Compress))
Wait-Idle
$tree2 = Get-Tree
$tree2 | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 (Join-Path $out 'phase4-after-rebind-click.json')
$script:pick = $null
function Walk2($ns) {
    foreach ($n in $ns) {
        if ($n.text -and $n.text -like '*keeper.bsn*') { $script:pick = $n; return }
        if ($n.children) { Walk2 $n.children }
    }
}
Walk2 $tree2
if (-not $script:pick) { Fail 'the picker does not list props/keeper.bsn after clicking Rebind' }
Write-Output ("picker item: text=$($script:pick.text) kind=$($script:pick.kind) entity=$($script:pick.entity)")
$click2 = Brp-Call 'jackdaw/ui_click' @{ entity = $script:pick.entity } 30
Write-Output ("pick click: " + ($click2 | ConvertTo-Json -Depth 5 -Compress))
Wait-Idle
$bsn = (Brp-Call 'jackdaw/scene_bsn' @{} 30).result
$text = $bsn | ConvertTo-Json -Depth 10
$bsn | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $out 'phase4-scene-bsn.json')
if ($text -notlike '*keeper.bsn*') { Fail 'the authored bsn does not name the held prefab' }
if ($text -like '*victim.bsn*') { Fail 'the authored bsn still names the gone prefab' }
Write-Output 'PASS: the pick rebound the authored reference (victim -> keeper)'
