# T10-T3 editor leg B: grid 7 green (document roundtrip), grid 10 (save,
# restart, reopen, all components), grid 12 (PIE play with physics + stop
# SHA), grid 9 (export, dist assertions; the exported exe is driven in its
# own step).
param(
    [string]$Project = 'H:\workspace_AI\t10-phys\phys-game',
    [int]$Port = 15703
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$Exe  = Join-Path $Repo 'target\debug\jackdaw.exe'
$OutDir = Join-Path $Repo 'loop\t10t3-live'

function Brp([string]$method, $params, [int]$retries = 4) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 12)
        } catch { Start-Sleep -Milliseconds (400 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp 'jackdaw/call_operator' @{ id = $id } }
}
function Wait-Idle([int]$TimeoutSec = 90) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp 'jackdaw/wait' @{ until = 'idle' } 1
        if ($r -and $r.result -and $r.result.idle) { return $true }
        Start-Sleep -Seconds 1
    }
    Write-Host "wait(idle) timeout (continuing)"
}
function Wait-Pie([string]$state, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp 'jackdaw/wait' @{ until = $state } 1
        if ($r -and $r.result -and "$($r.result.pie)" -eq $state) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
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
function Boot-Editor {
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Milliseconds 800
    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT  = "$Port"
    $env:JACKDAW_WINDOW_SIZE  = '1920x1080'
    $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
    $env:PATH = "$deps;$env:PATH"
    cmd /c "start /B /D `"$(Split-Path -Parent $Exe)`" cmd /c `"`"$Exe`" > `"$OutDir\edB-editor.log`" 2>&1`""
    for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Seconds 2; if (Brp 'jackdaw/status' @{} 1) { return $true } }
    return $false
}

# --- grid 7 green: flip the mask in the saved document, reopen, verify ------------
$bsnPath = Join-Path $Project 'assets\scene.bsn'
$txt = [IO.File]::ReadAllText($bsnPath)
# the writer saves the mask multi-line
$green = $txt.Replace("memberships: 2,`r`n            filters: 4,", "memberships: 2,`r`n            filters: 3,")
if ($green -eq $txt) {
    # line-ending fallback
    $green = $txt.Replace("memberships: 2,`n            filters: 4,", "memberships: 2,`n            filters: 3,")
}
if ($green -ne $txt) {
    [IO.File]::WriteAllText($bsnPath, $green)
    Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
    Wait-Idle 120; Start-Sleep -Seconds 3
    $E_L = Find-Ent (Snap) -2.0 3.0 1.0
    $clGreen = if ($E_L) { Has-Comp (Snap) $E_L 'CollisionLayers' } else { $false }
    Write-Host ("GRID7_GREEN_DOC: reopened entity={0} layersLoaded={1}" -f $E_L, $clGreen)
    if ($clGreen) { Write-Host 'GRID7_GREEN_DOC_PASS' } else { Write-Host 'GRID7_GREEN_DOC_FAIL' }
} else {
    Write-Host 'GRID7_GREEN_DOC_FAIL (mask text not matched)'
}

# --- grid 12: PIE with physics running, then stop keeps the scene ------------------
$sceneFile = $bsnPath
$shaBefore = (Get-FileHash $sceneFile -Algorithm SHA256).Hash
$pok = Op 'pie.play_current' @{}
Write-Host ("EDB_PLAY: {0}" -f ($pok | ConvertTo-Json -Depth 4 -Compress))
$running = Wait-Pie 'pie_running' 300
Write-Host ("EDB_PIE_RUNNING: {0}" -f $running)
$pieGameSnap = $null
if ($running) {
    Start-Sleep -Seconds 4
    # the PIE child is the warm project's own exe with the remote plugin: 15702
    $body = @{ jsonrpc = '2.0'; id = 1; method = 'jackdaw/scene_snapshot'; params = @{} }
    try {
        $pieGameSnap = Invoke-RestMethod -Uri "http://127.0.0.1:15702/" -Method Post `
            -ContentType 'application/json' -TimeoutSec 15 -Body ($body | ConvertTo-Json -Depth 6)
        Write-Host ("EDB_PIE_GAME_ENTITIES: {0}" -f @($pieGameSnap.result).Count)
    } catch { Write-Host ("EDB_PIE_GAME_PORT: unreachable ({0})" -f $_.Exception.Message) }
}
Op 'pie.stop' @{} | Out-Null
$stopped = Wait-Pie 'pie_stopped' 60
Write-Host ("EDB_PIE_STOPPED: {0}" -f $stopped)
Start-Sleep -Seconds 2
$shaAfter = (Get-FileHash $sceneFile -Algorithm SHA256).Hash
if ($shaBefore -eq $shaAfter) { Write-Host 'GRID12_SCENE_SHA_PASS' } else { Write-Host 'GRID12_SCENE_SHA_FAIL' }
$pieTemp = Join-Path $Project '.jackdaw-pie'
if (-not (Test-Path $pieTemp)) { Write-Host 'GRID12_PIE_TEMP_CLEAN_PASS' } else {
    $left = Get-ChildItem $pieTemp -Recurse -File -ErrorAction SilentlyContinue
    Write-Host ("GRID12_PIE_TEMP: {0} files left" -f @($left).Count)
    if (@($left).Count -eq 0) { Write-Host 'GRID12_PIE_TEMP_CLEAN_PASS' } else { Write-Host 'GRID12_PIE_TEMP_CLEAN_FAIL' }
}

# --- grid 10: save, restart the editor, reopen, everything is still there ----------
Op 'scene.save' @{} | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 2
$shaSave = (Get-FileHash $sceneFile -Algorithm SHA256).Hash
$docText = [IO.File]::ReadAllText($sceneFile)
$docSensor = $docText -match 'Sensor'
$docCL = $docText -match 'CollisionLayers'
$docRB = $docText -match 'RigidBody::Dynamic'
$docCollider = $docText -match 'AvianCollider'
Write-Host ("GRID10_DOC: sensor={0} layers={1} dynamic={2} collider={3}" -f $docSensor, $docCL, $docRB, $docCollider)
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 2
$ok = Boot-Editor
if (-not $ok) { Write-Host 'GRID10_BOOT_FAIL'; exit 1 }
Wait-Idle 1800; Start-Sleep -Seconds 5
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Wait-Idle 120; Start-Sleep -Seconds 3
$s10 = Snap
$E10D = Find-Ent $s10 2.0 4.0 1.2
$E10L = Find-Ent $s10 -2.0 3.0 1.2
$E10S = Find-Ent $s10 1.5 1.0 1.2
$alive = @()
if ($E10D) { $alive += ('drop.RigidBody=' + (Has-Comp $s10 $E10D 'RigidBody')) }
if ($E10D) { $alive += ('drop.Collider=' + (Has-Comp $s10 $E10D 'AvianCollider')) }
if ($E10L) { $alive += ('layer.CollisionLayers=' + (Has-Comp $s10 $E10L 'CollisionLayers')) }
if ($E10S) { $alive += ('sensorEnt.Collider=' + (Has-Comp $s10 $E10S 'AvianCollider')) }
Write-Host ("GRID10_REOPEN: {0}" -f ($alive -join ' | '))
$shaReopen = (Get-FileHash $sceneFile -Algorithm SHA256).Hash
if ($shaSave -eq $shaReopen) { Write-Host 'GRID10_SHA_STABLE_PASS' } else { Write-Host 'GRID10_SHA_STABLE_FAIL (reopen touched the file)' }
if (($alive | Where-Object { $_ -match 'False' }).Count -eq 0 -and $alive.Count -ge 3) { Write-Host 'GRID10_PASS' } else { Write-Host 'GRID10_PARTIAL' }

# --- grid 9: export -------------------------------------------------------------
$before = Get-ChildItem (Join-Path $Project 'dist') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
$exp = Op 'game.export' @{}
Write-Host ("EDB_EXPORT: {0}" -f ($exp | ConvertTo-Json -Depth 6 -Compress))
# the export runs a build; wait for the editor to go idle again
Wait-Idle 1800
Start-Sleep -Seconds 5
$after = Get-ChildItem (Join-Path $Project 'dist') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
$newDirs = @($after | Where-Object { $before -notcontains $_ })
Write-Host ("GRID9_NEW_DIST: {0}" -f ($newDirs -join ','))
if ($newDirs.Count -ge 1) {
    $dist = Join-Path (Join-Path $Project 'dist') $newDirs[0]
    $exe = Get-ChildItem $dist -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    $assets = Join-Path $dist 'assets'
    $manifest = Join-Path $dist 'export-manifest.json'
    $hasScene = (Test-Path (Join-Path $assets 'scene.bsn'))
    $manText = if (Test-Path $manifest) { [IO.File]::ReadAllText($manifest) } else { '' }
    $manScene = $manText -match 'scene\.bsn'
    $manSize = if ($exe) { $exe.Length } else { 0 }
    Write-Host ("GRID9_DIST: exe={0} size={1} assetsScene={2} manifestScene={3}" -f ($exe -ne $null), $manSize, $hasScene, $manScene)
    [IO.File]::WriteAllText((Join-Path $OutDir 't10t3-dist-path.txt'), "$dist")
    if ($exe -and $hasScene -and $manScene) { Write-Host 'GRID9_EXPORT_PASS' } else { Write-Host 'GRID9_EXPORT_FAIL' }
} else { Write-Host 'GRID9_EXPORT_FAIL (no new dist dir)' }

# leave the editor running off; cleanup happens in the next step
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host 'T10T3_EDITORB_DONE'
