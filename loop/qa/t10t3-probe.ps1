# probe: which component.set value shapes the editor accepts for the
# physics marker (Sensor) and the layer masks.
$Port = 15703
function Brp([string]$method, $params) {
    $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
    if ($params) { $body.params = $params }
    Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -TimeoutSec 20 -Body ($body | ConvertTo-Json -Depth 10)
}
function Op([string]$id, $params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
$TKEY = 'bevy_transform::components::transform::Transform'
$snap = (Brp 'jackdaw/scene_snapshot' @{}).result
# the sensor probe cube sits at (1.5, 1.0, 1.5) from leg A
$target = $null
foreach ($e in @($snap)) {
    $t = $e.components.PSObject.Properties[$TKEY].Value
    if ($t) {
        $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]; $ez = [double]$t.translation[2]
        if ([Math]::Abs($ex - 1.5) -lt 0.6 -and [Math]::Abs($ey - 1.0) -lt 0.6) { $target = $e.entity }
    }
}
Write-Host ("probe target: {0}" -f $target)
if (-not $target) { exit 1 }
foreach ($v in @('Sensor', 'null', '[]', '{}')) {
    $r = Op 'component.set' @{ entity = $target; type_path = 'avian3d::dynamics::rigid_body::Sensor'; field = ''; value = $v }
    Write-Host ("Sensor value [{0}]: {1}" -f $v, ($r.result.warnings -join ';'))
}
foreach ($v in @('2', '{0: 2}', 'LayerMask(2)')) {
    foreach ($f in @('memberships', 'memberships.0')) {
        $r = Op 'component.set' @{ entity = $target; type_path = 'avian3d::collision::layers::CollisionLayers'; field = $f; value = $v }
        Write-Host ("Layers [{0}] = {1}: {2}" -f $f, $v, ($r.result.warnings -join ';'))
    }
}
