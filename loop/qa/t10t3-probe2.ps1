# probe 2: add-then-set chain (component.add Default + component.set field),
# and the viewport rect from ui_tree for pointer aiming.
$Port = 15703
function Brp([string]$method, $params) {
    $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
    if ($params) { $body.params = $params }
    Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -TimeoutSec 20 -Body ($body | ConvertTo-Json -Depth 12)
}
function Op([string]$id, $params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
$TKEY = 'bevy_transform::components::transform::Transform'
$snap = (Brp 'jackdaw/scene_snapshot' @{}).result
$target = $null
foreach ($e in @($snap)) {
    $t = $e.components.PSObject.Properties[$TKEY].Value
    if ($t) {
        $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
        if ([Math]::Abs($ex - 1.5) -lt 0.6 -and [Math]::Abs($ey - 1.0) -lt 0.6) { $target = $e.entity }
    }
}
Write-Host ("probe target: {0}" -f $target)
if (-not $target) { exit 1 }

$r1 = Op 'component.add' @{ entity = $target; type_path = 'avian3d::dynamics::rigid_body::Sensor' }
Write-Host ("add Sensor: {0} warn={1}" -f $r1.result.result, ($r1.result.warnings -join ';'))
$r2 = Op 'component.add' @{ entity = $target; type_path = 'avian3d::collision::layers::CollisionLayers' }
Write-Host ("add CollisionLayers: {0} warn={1}" -f $r2.result.result, ($r2.result.warnings -join ';'))
Start-Sleep -Milliseconds 500
foreach ($f in @('memberships.0', 'memberships')) {
    $r = Op 'component.set' @{ entity = $target; type_path = 'avian3d::collision::layers::CollisionLayers'; field = $f; value = '2' }
    Write-Host ("set {0}=2: warn={1}" -f $f, ($r.result.warnings -join ';'))
}
# verify the components landed
$snap2 = (Brp 'jackdaw/scene_snapshot' @{}).result
foreach ($e in @($snap2)) {
    if ("$($e.entity)" -eq "$target") {
        $names = @($e.components.PSObject.Properties.Name) -join ', '
        Write-Host ("target components: {0}" -f $names)
    }
}
# viewport rect for pointer aiming
$tree = Brp 'jackdaw/ui_tree' @{}
$found = @()
foreach ($n in $tree.result.nodes) {
    if ("$($n.text)" -match 'Viewport|viewport') { $found += $n }
}
foreach ($n in $found) { Write-Host ("ui node: text={0} rect={1}" -f $n.text, ($n.rect -join ',')) }
