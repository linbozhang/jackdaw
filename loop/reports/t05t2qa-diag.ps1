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
$st = (Brp-Call 'jackdaw/scene_tree' @{}).result
$st | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $out 'diag-scene-tree.json')
$names = @()
function Walk($nodes) { foreach ($n in $nodes) { $names += $n.name; if ($n.children) { Walk $n.children } } }
Walk $st.nodes
Write-Output ('scene tree names: ' + ($names -join ', '))
$tree = (Brp-Call 'jackdaw/ui_tree' @{ depth = 30 }).result.nodes
$tree | ConvertTo-Json -Depth 14 | Set-Content -Encoding UTF8 (Join-Path $out 'diag-full-tree.json')
# inspector-side texts containing 'victim' or 'source' or 'IsA'
$hits = @()
function Walk2($nodes) { foreach ($n in $nodes) { if ($n.text -and ($n.text -like '*victim*' -or $n.text -like '*IsA*' -or $n.text -like '*Prefab*')) { $hits += [PSCustomObject]@{ text = $n.text; kind = $n.kind; rect = $n.rect } } ; if ($n.children) { Walk2 $n.children } } }
Walk2 $tree
Write-Output '--- matching UI nodes:'
$hits | ConvertTo-Json -Depth 4
