# QA driver: generate the before-snapshot the t04t1 save phase expects,
# wait for editor readiness first.
$ErrorActionPreference = 'Stop'
$Port = 15812
$Proj = 'C:\Users\linbo.zhang\Projects\my-game'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t04t1-live'
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
$s = Brp-Call 'jackdaw/status' @{} 90
Write-Output ("[status] active scene: " + $s.result.active_scene)
Brp-Call 'jackdaw/wait' @{ until = 'idle' } 120 | Out-Null
Start-Sleep -Milliseconds 500
$before = @{}
Get-ChildItem -Path $Proj -Recurse -Filter *.bsn -File | ForEach-Object { $before[$_.FullName] = $_.LastWriteTimeUtc.Ticks }
$before.GetEnumerator() | ForEach-Object { "$($_.Key)|$($_.Value)" } |
    Set-Content -Encoding UTF8 (Join-Path $OutDir 'before-bsn.txt')
Write-Output ("[bsn files before] " + $before.Count)
