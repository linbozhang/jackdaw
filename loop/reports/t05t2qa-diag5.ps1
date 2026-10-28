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
Brp-Call 'jackdaw/wait' @{ until = 'idle' } 60 | Out-Null
$nodes = (Brp-Call 'jackdaw/ui_tree' @{ depth = 40 }).result.nodes
$target = 4294962767  # the Rebind text entity from diag3
$script:parent = $null
$script:chain = New-Object System.Collections.ArrayList
function Walk($ns) {
    foreach ($n in $ns) {
        if ($n.children) {
            foreach ($c in $n.children) { if ($c.entity -eq $target -or ($c.children | Where-Object { $_.entity -eq $target })) { } }
            $direct = $n.children | Where-Object { $_.entity -eq $target }
            if ($direct) { $script:parent = $n; [void]$script:chain.Add(('parent kind=' + $n.kind + ' entity=' + $n.entity + ' rect=' + ($n.rect -join ','))) }
            $hasDeep = $false
            foreach ($c in $n.children) { if ($c.children) { $hit = $c.children | Where-Object { $_.entity -eq $target }; if ($hit) { $hasDeep = $true; [void]$script:chain.Add(('grand kind=' + $c.kind + ' entity=' + $c.entity)) } } }
        }
        if ($n.children) { Walk $n.children }
    }
}
Walk $nodes
$script:chain | ForEach-Object { Write-Output $_ }
