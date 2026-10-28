# Sample the game port's snapshot: every Transform entity's position.
$ErrorActionPreference = 'Continue'
function Snap {
    (Invoke-RestMethod -Uri 'http://127.0.0.1:15702/' -Method Post `
        -ContentType 'application/json' `
        -Body '{"jsonrpc":"2.0","id":2,"method":"jackdaw/scene_snapshot"}' `
        -TimeoutSec 15).result
}
$t1 = Snap
Start-Sleep -Seconds 1
$t2 = Snap
Write-Host ("count: {0} {1}" -f @($t1).Count, @($t2).Count)
$TKEY = 'bevy_transform::components::transform::Transform'
foreach ($e in @($t2)) {
    $t = if ($e.components -is [System.Management.Automation.PSObject]) {
        $e.components.PSObject.Properties[$TKEY].Value
    } else { $e.components[$TKEY] }
    if ($t) {
        Write-Host ("x={0:N3} y={1:N3} z={2:N3}" -f `
            [double]$t.translation[0], [double]$t.translation[1], [double]$t.translation[2])
    }
}
Write-Host 'SAMPLE_DONE'
