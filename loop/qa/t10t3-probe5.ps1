$Port = 15703
function Brp([string]$method, $params) {
    $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
    if ($params) { $body.params = $params }
    Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -TimeoutSec 25 -Body ($body | ConvertTo-Json -Depth 12)
}
$r = Brp 'jackdaw/scene_snapshot' @{}
Write-Host ("entities: {0}" -f @($r.result).Count)
$TKEY = 'bevy_transform::components::transform::Transform'
foreach ($e in @($r.result)) {
    $t = $e.components.PSObject.Properties[$TKEY].Value
    $pos = if ($t) { "{0},{1}" -f [Math]::Round([double]$t.translation[0],1), [Math]::Round([double]$t.translation[1],1) } else { '-' }
    $names = @($e.components.PSObject.Properties.Name) -join ','
    Write-Host ("{0} @({1}): {2}" -f $e.entity, $pos, ($names.Substring(0, [Math]::Min(120, $names.Length))))
}
$o = Brp 'jackdaw/call_operator' @{ id = 'scene.open'; params = @{ path = 'assets/scene.bsn' } }
Write-Host ("scene.open: {0}" -f ($o | ConvertTo-Json -Depth 5 -Compress))
Start-Sleep -Seconds 3
$r2 = Brp 'jackdaw/scene_snapshot' @{}
Write-Host ("entities after reopen: {0}" -f @($r2.result).Count)
