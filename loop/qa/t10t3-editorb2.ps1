# editor leg B completion, by hand after the scripted run stalled:
# grid 10 reopen assertions on the live (restarted) editor, then grid 9
# export. The editor is already up (pid from the boot in leg B).
param([int]$Port = 15703)
$ErrorActionPreference = 'Continue'
$Project = 'H:\workspace_AI\t10-phys\phys-game'
$OutDir = 'E:\Project\rust\jackdaw\loop\t10t3-live'
function Brp([string]$method, $params, [int]$retries = 2) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 12)
        } catch { Start-Sleep -Milliseconds 400 }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp 'jackdaw/call_operator' @{ id = $id } }
}
$TKEY = 'bevy_transform::components::transform::Transform'
function Get-T($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) {
        return $e.components.PSObject.Properties[$TKEY].Value
    }
    return $e.components[$TKEY]
}
function Snap { (Brp 'jackdaw/scene_snapshot' @{}).result }
function Find-Ent([object]$snap, [double]$x, [double]$y, [double]$band) {
    $best = $null; $bestD = 1e9
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if ($t) {
            $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
            $d = [Math]::Abs($ex - $x) + [Math]::Abs($ey - $y)
            if ($d -lt $bestD) { $bestD = $d; $best = $e.entity }
        }
    }
    if ($bestD -lt $band) { return $best } else { return $null }
}
function Has-Comp([object]$snap, $entity, [string]$suffix) {
    foreach ($e in @($snap)) {
        if ("$($e.entity)" -eq "$entity") {
            $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
            foreach ($p in $props) { if ("$($p.Name)" -like "*$suffix") { return $true } }
        }
    }
    return $false
}

# grid 10: open the saved scene on the restarted editor, assert components
$bsnPath = Join-Path $Project 'assets\scene.bsn'
$shaSave = (Get-FileHash $bsnPath -Algorithm SHA256).Hash
$op = Op 'scene.open' @{ path = 'assets/scene.bsn' }
Write-Host ("open: {0}" -f ($op | ConvertTo-Json -Depth 4 -Compress))
Start-Sleep -Seconds 5
$s10 = Snap
Write-Host ("snapshot entities: {0}" -f @($s10).Count)
$E10D = Find-Ent $s10 2.0 4.0 1.2
$E10L = Find-Ent $s10 -2.0 3.0 1.2
$E10S = Find-Ent $s10 1.5 1.0 1.2
Write-Host ("GRID10_ENTS: drop={0} layer={1} sensor={2}" -f $E10D, $E10L, $E10S)
$alive = @()
if ($E10D) { $alive += ('drop.RigidBody=' + (Has-Comp $s10 $E10D 'RigidBody')); $alive += ('drop.Collider=' + (Has-Comp $s10 $E10D 'AvianCollider')) }
if ($E10L) { $alive += ('layer.CollisionLayers=' + (Has-Comp $s10 $E10L 'CollisionLayers')) }
if ($E10S) { $alive += ('sensorEnt.Collider=' + (Has-Comp $s10 $E10S 'AvianCollider')) }
Write-Host ("GRID10_REOPEN: {0}" -f ($alive -join ' | '))
$shaReopen = (Get-FileHash $bsnPath -Algorithm SHA256).Hash
if ($shaSave -eq $shaReopen) { Write-Host 'GRID10_SHA_STABLE_PASS' } else { Write-Host 'GRID10_SHA_STABLE_FAIL' }
if (($alive | Where-Object { $_ -match 'False' }).Count -eq 0 -and $alive.Count -ge 3) { Write-Host 'GRID10_PASS' } else { Write-Host 'GRID10_PARTIAL' }

# grid 9: export through the operator, watch for the new dist dir
$before = @(Get-ChildItem (Join-Path $Project 'dist') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
$exp = Op 'game.export' @{}
Write-Host ("export op: {0}" -f ($exp | ConvertTo-Json -Depth 6 -Compress))
# the build can take tens of minutes; poll the dist dir and progress
$deadline = (Get-Date).AddMinutes(45)
$newDirs = @()
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 30
    $after = @(Get-ChildItem (Join-Path $Project 'dist') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $newDirs = @($after | Where-Object { $before -notcontains $_ })
    if ($newDirs.Count -ge 1) {
        # let the export finish writing (manifest appears last)
        $dist = Join-Path (Join-Path $Project 'dist') $newDirs[0]
        $manifest = Join-Path $dist 'export-manifest.json'
        if (Test-Path $manifest) { break }
    }
}
Write-Host ("GRID9_NEW_DIST: {0}" -f ($newDirs -join ','))
if ($newDirs.Count -ge 1) {
    $dist = Join-Path (Join-Path $Project 'dist') $newDirs[0]
    $exe = Get-ChildItem $dist -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    $hasScene = (Test-Path (Join-Path $dist 'assets\scene.bsn'))
    $manifest = Join-Path $dist 'export-manifest.json'
    $manText = if (Test-Path $manifest) { [IO.File]::ReadAllText($manifest) } else { '' }
    $manScene = $manText -match 'scene\.bsn'
    Write-Host ("GRID9_DIST: exe={0} size={1} assetsScene={2} manifestScene={3}" -f ($exe -ne $null), $(if ($exe) { $exe.Length } else { 0 }), $hasScene, $manScene)
    [IO.File]::WriteAllText((Join-Path $OutDir 't10t3-dist-path.txt'), "$dist")
    if ($exe -and $hasScene -and $manScene) { Write-Host 'GRID9_EXPORT_PASS' } else { Write-Host 'GRID9_EXPORT_FAIL' }
} else { Write-Host 'GRID9_EXPORT_FAIL (no new dist dir)' }
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host 'T10T3_EDITORB2_DONE'
