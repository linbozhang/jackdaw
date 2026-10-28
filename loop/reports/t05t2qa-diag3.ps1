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
$script:hits = New-Object System.Collections.ArrayList
function Walk($ns) {
    foreach ($n in $ns) {
        if ($n.text -and ($n.text -like '*ebind*' -or $n.text -like '*ocate*' -or $n.text -like '*how*' -or $n.text -like '*opy*' -or $n.text -like '*Missing*')) {
            [void]$script:hits.Add([PSCustomObject]@{ text = $n.text; kind = $n.kind; entity = $n.entity; x = [int]$n.rect[0]; y = [int]$n.rect[1] })
        }
        if ($n.children) { Walk $n.children }
    }
}
Walk $nodes
$script:hits | ForEach-Object { Write-Output ("{0,-8} {1,-10} x={2,-6} y={3,-6} e={4}" -f $_.kind, $_.text, $_.x, $_.y, $_.entity) }
