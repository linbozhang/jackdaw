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
Wait-Idle
$nodes = (Brp-Call 'jackdaw/ui_tree' @{ depth = 40 } 30).result.nodes
Write-Output ('root count: ' + $nodes.Count)
foreach ($r in $nodes) { Write-Output ('root kind=' + $r.kind + ' rect=' + ($r.rect -join ',') + ' children=' + @($r.children).Count) }
# find Rebind button container and its rect again
$script:btn = $null
function Walk($ns) {
    foreach ($n in $ns) {
        if ($n.children -and ($n.children | Where-Object { $_.text -eq 'Rebind' })) { $script:btn = $n; return }
        if ($n.children) { Walk $n.children }
    }
}
Walk $nodes
if ($script:btn) {
    Write-Output ("Rebind container rect: " + ($script:btn.rect -join ','))
    # ui_click once more and immediately re-read the tree for a picker
    $click = Brp-Call 'jackdaw/ui_click' @{ entity = $script:btn.entity } 30
    Write-Output ("click at: " + ($click.result.at -join ','))
    Wait-Idle
    $t2 = (Brp-Call 'jackdaw/ui_tree' @{ depth = 40 } 30).result.nodes
    $t2 | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 (Join-Path $out 'diag-after-click2.json')
    $script:pick = $null
    function Walk2($ns) {
        foreach ($n in $ns) {
            if ($n.text -and ($n.text -like '*keeper*' -or $n.text -like '*Search assets*' -or $n.text -like '*Rebind reference*')) { $script:pick = $n; return }
            if ($n.children) { Walk2 $n.children }
        }
    }
    Walk2 $t2
    if ($script:pick) { Write-Output ('PICKER VISIBLE: ' + $script:pick.text) } else { Write-Output 'PICKER STILL NOT VISIBLE' }
} else { Write-Output 'Rebind button not found (list closed?)' }
