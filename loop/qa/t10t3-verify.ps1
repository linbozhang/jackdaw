# verify the avian registration fix: boot fresh, add Sensor, read the log.
$Port = 15703
$Project = 'H:\workspace_AI\t10-phys\phys-game'
$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe'
$OutDir = 'E:\Project\rust\jackdaw\loop\t10t3-live'
function Brp([string]$method, $params) {
    $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
    if ($params) { $body.params = $params }
    for ($i = 0; $i -lt 4; $i++) {
        try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 12) }
        catch { Start-Sleep -Milliseconds 400 }
    }
    return $null
}
function Op([string]$id, $params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = '1920x1080'
$deps = 'E:\Project\rust\jackdaw\target\debug\deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"E:\Project\rust\jackdaw\target\debug`" cmd /c `"`"$Exe`" > `"$OutDir\edv-editor.log`" 2>&1`""
for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Seconds 2; if (Brp 'jackdaw/status' @{}) { break } }
$deadline = (Get-Date).AddSeconds(600)
while ((Get-Date) -lt $deadline) {
    $r = Brp 'jackdaw/wait' @{ until = 'idle' } 1
    if ($r -and $r.result -and $r.result.idle) { break }
    Start-Sleep -Seconds 2
}
Start-Sleep -Seconds 4
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Start-Sleep -Seconds 2
# find DroppingCube (wherever the dirty scene left it): nearest to (2,4) band 3
$TKEY = 'bevy_transform::components::transform::Transform'
$snap = (Brp 'jackdaw/scene_snapshot' @{}).result
$cand = $null
foreach ($e in @($snap)) {
    $t = $e.components.PSObject.Properties[$TKEY].Value
    if ($t) {
        $props = $e.components.PSObject.Properties.Name
        if ($props -match 'RigidBody') { $cand = $e.entity; break }
    }
}
Write-Host ("target with RigidBody: {0}" -f $cand)
if ($cand) {
    $r = Op 'component.add' @{ entity = $cand; type_path = 'avian3d::dynamics::rigid_body::Sensor' }
    Write-Host ("add Sensor: {0} warn=[{1}]" -f $r.result.result, ($r.result.warnings -join ';'))
    $r2 = Op 'component.add' @{ entity = $cand; type_path = 'avian3d::collision::layers::CollisionLayers' }
    Write-Host ("add CL: {0} warn=[{1}]" -f $r2.result.result, ($r2.result.warnings -join ';'))
    $r3 = Op 'component.set' @{ entity = $cand; type_path = 'avian3d::collision::layers::CollisionLayers'; field = 'memberships.0'; value = '2' }
    Write-Host ("set m.0=2: warn=[{0}]" -f ($r3.result.warnings -join ';'))
}
