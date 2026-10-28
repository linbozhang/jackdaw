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
$script:texts = New-Object System.Collections.ArrayList
function Walk($ns) {
    foreach ($n in $ns) {
        if ($n.text) { [void]$script:texts.Add([PSCustomObject]@{ text = $n.text; kind = $n.kind; x = [int]$n.rect[0]; y = [int]$n.rect[1]; w = [int]$n.rect[2] }) }
        if ($n.children) { Walk $n.children }
    }
}
Walk $nodes
Write-Output ('total text nodes: ' + $script:texts.Count)
Write-Output '--- texts with x >= 1150 (inspector side):'
$script:texts | Where-Object { $_.x -ge 1150 } | ForEach-Object { Write-Output ("x={0,-5} y={1,-5} {2,-12} {3}" -f $_.x, $_.y, $_.kind, $_.text) }
Write-Output '--- texts containing Probe:'
$script:texts | Where-Object { $_.text -like '*Probe*' } | ForEach-Object { Write-Output ("x={0,-5} y={1,-5} {2,-12} {3}" -f $_.x, $_.y, $_.kind, $_.text) }
