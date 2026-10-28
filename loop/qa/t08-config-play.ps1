# T08-T1 live: the config-asset play leg on a fresh template project.
# Creates the config in the editor (schema-backed New Asset), sets
# move_speed, plays, and asserts behavior through two scene_snapshot
# frames — then changes the value and plays again to show the game
# reads the file.
# Usage: powershell -NoProfile -File loop\qa\t08-config-play.ps1 -Project <path>
param([string]$Project = 'E:\Project\rust\jackdaw\hworkspace-ait08t1-scaffoldmy-game')
$ErrorActionPreference = 'Stop'

$Repo = 'E:\Project\rust\jackdaw'
$Exe  = Join-Path $Repo 'target\debug\jackdaw.exe'
$Port = 15703
$OutDir = Join-Path $Repo 'loop\t08-t1-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')

function Brp-Try([string]$method, $params, [int]$retries = 6) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = (Get-Random); method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 8)
        } catch { Start-Sleep -Milliseconds (500 * ($i + 1)) }
    }
    return $null
}

function Op([string]$id, $params) {
    # Operator arguments travel nested under `params`.
    if ($params) { Brp-Try 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp-Try 'jackdaw/call_operator' @{ id = $id } }
}

# A retrying wait: one dropped or stale keep-alive call must not end a
# ten-minute build wait. `idle` answers {idle: bool}; the pie states
# answer {pie: "running"|"stopped"}.
function Wait-Until([string]$until, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp-Try 'jackdaw/wait' @{ until = $until } 1
        if ($r -and $r.result) {
            if ($until -eq 'idle' -and $r.result.idle) { return $true }
            if ($until -eq 'pie_running' -and "$($r.result.pie)" -eq 'running') { return $true }
            if ($until -eq 'pie_stopped' -and "$($r.result.pie)" -eq 'stopped') { return $true }
        }
        Start-Sleep -Seconds 2
    }
    throw "wait($until) timed out after ${TimeoutSec}s"
}

# The falling cube's projected transform: snapshots return
# Vec<RemoteEntity> ({entity: bits, components: {type_path: value}});
# the cube is the entity whose translation.y moves while its rotation
# turns. Two snapshots a fixed time apart give the deltas.
$TKEY = 'bevy_transform::components::transform::Transform'
function Sample-FallingCube([int]$Seconds) {
    $a = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
    Start-Sleep -Seconds $Seconds
    $b = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
    foreach ($eb in @($b)) {
        $ea = $null
        foreach ($cand in @($a)) { if ($cand.entity -eq $eb.entity) { $ea = $cand; break } }
        if (-not $ea) { continue }
        # Component keys are full type paths (colons!): index, never dot.
        $ta = $ea.components[$TKEY]
        $tb = $eb.components[$TKEY]
        if ($ta -and $tb) {
            $ya = [double]$ta.translation.y; $yb = [double]$tb.translation.y
            $ra = [double]$ta.rotation.y;    $rb = [double]$tb.rotation.y
            if ($yb -ne $ya) {
                return @{ dy = ($yb - $ya); drot = ($rb - $ra); entity = $eb.entity }
            }
        }
    }
    return $null
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir 'editor-stdout.log') `
    -RedirectStandardError (Join-Path $OutDir 'editor-stderr.log') -PassThru
$proc.Id | Set-Content (Join-Path $OutDir 'editor.pid')
# BRP answers late while the editor boots (the first prebuild of a
# fresh project compiles for minutes); poll with backoff rather than
# brp.ps1's single-shot call.
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    $status = Brp-Try 'jackdaw/status' @{} 1
    if ($status) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died while booting' }
}
if (-not $ready) { throw 'editor BRP never answered' }
Write-Host 'editor BRP is up'
Wait-Until "idle" 1800 | Out-Null
Write-Host "editor ready (prebuild done; GameConfig registered)"

# 1. Create the config asset from the schema the game registered.
# The operator names kinds by id / type path / label — not the bare
# short name ("GameConfig" alone names nothing; its id is
# "game_config").
$created = Op 'asset.new' @{ type = 'game_config'; name = 'game-config' }
Write-Host ("asset.new: " + ($created | ConvertTo-Json -Depth 6 -Compress))
$configPath = Join-Path $Project 'assets\game-config.bsn'

# 2. Set move_speed and save.
Op 'asset.set' @{ field = 'move_speed'; value = '2.5' } | Out-Null
Op 'asset.set' @{ field = 'gravity'; value = '-9.81' } | Out-Null
Op 'asset.save' @{} | Out-Null
Start-Sleep -Seconds 1
$onDisk = Get-Content $configPath -Raw -Encoding UTF8
Write-Host "game-config.bsn on disk:`n$onDisk"
if ($onDisk -notmatch '2\.5') { throw "move_speed 2.5 did not reach the file" }

# 3. A scene to play (a fresh template project has none open): new,
# save, then Play and sample behavior.
Op 'scene.new' @{} | Out-Null
Op 'scene.save' @{} | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' @{} | Out-Null
Wait-Until "pie_running" 900 | Out-Null
Start-Sleep -Seconds 3
$sample25 = Sample-FallingCube 2
Op 'pie.stop' @{} | Out-Null
Wait-Until "idle" 120 | Out-Null
if (-not $sample25) { throw "no projected entity moved while playing (move_speed=2.5)" }
if ($sample25.dy -ge 0) { throw "the cube did not fall at gravity -9.81 (dy=$($sample25.dy))" }
Write-Host ("sample@2.5: dy=$($sample25.dy) drot=$($sample25.drot) entity=$($sample25.entity)")
$alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($alive) {
    $alive.Refresh()
    Save-WindowScreenshot $alive.MainWindowHandle (Join-Path $OutDir 't08t1-playing.png') | Out-Null
}

# 4. Change the value, play again: the behavior follows the file.
Op 'asset.set' @{ field = 'move_speed'; value = '0.5' } | Out-Null
Op 'asset.save' @{} | Out-Null
Start-Sleep -Seconds 1
$onDisk2 = Get-Content $configPath -Raw -Encoding UTF8
if ($onDisk2 -notmatch '0\.5') { throw "move_speed 0.5 did not reach the file" }
Op 'scene.new' @{} | Out-Null
Op 'scene.save' @{} | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' @{} | Out-Null
Wait-Until "pie_running" 900 | Out-Null
Start-Sleep -Seconds 3
$sample05 = Sample-FallingCube 2
Op 'pie.stop' @{} | Out-Null
Wait-Until "idle" 120 | Out-Null
if (-not $sample05) { throw "no projected entity moved while playing (move_speed=0.5)" }
if ($sample05.dy -ge 0) { throw "the cube did not fall on the second run (dy=$($sample05.dy))" }
Write-Host ("sample@0.5: dy=$($sample05.dy) drot=$($sample05.drot) entity=$($sample05.entity)")

# The behavioral proof the file is read: the same cube spins ~5x faster
# at move_speed 2.5 than at 0.5 (rotation is speed * move_speed * dt).
$spin25 = [Math]::Abs([double]$sample25.drot)
$spin05 = [Math]::Abs([double]$sample05.drot)
if ($spin05 -gt 0 -and ($spin25 / $spin05) -lt 2.5) {
    throw "spin at 2.5 ($spin25) should clearly outrun spin at 0.5 ($spin05)"
}
Write-Host ("spin ratio 2.5:0.5 = " + [Math]::Round($spin25 / [Math]::Max($spin05, 0.00001), 2))
Write-Output 'T08_T1_CONFIG_PLAY_PASS'
Stop-Process -Id $proc.Id -Force
