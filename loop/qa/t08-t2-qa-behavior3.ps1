# T08-T2 QA behavior leg: the T1 leftover assertion channel through the
# newly registered editor-port scene_snapshot. Fresh template project,
# run 3: the earlier runs raced the schema extraction (schema.json was
# written the same second asset.new fired); this one waits past it.
# Usage: powershell -NoProfile -File loop\qa\t08-t2-qa-behavior3.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'E:\Project\rust\jackdaw\loop\qa-fixture\t08t2qa-fixture'
$Port    = 15703
$OutDir  = Join-Path $Repo 'loop\t08-t2-qa-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

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
    if ($params) { Brp-Try 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp-Try 'jackdaw/call_operator' @{ id = $id } }
}
function Wait-Until([string]$until, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp-Try 'jackdaw/wait' @{ until = $until } 1
        if ($r -and $r.result) {
            if ($until -eq 'idle' -and $r.result.idle) { return $true }
            if ($until -eq 'pie_running' -and "$($r.result.pie)" -eq 'running') { return $true }
        }
        Start-Sleep -Seconds 2
    }
    throw "wait($until) timed out after ${TimeoutSec}s"
}
$TKEY = 'bevy_transform::components::transform::Transform'
# Windows PowerShell 5.1: Invoke-RestMethod gives PSCustomObject, which has
# no string indexer - components[TKEY] silently returns null (the bug that
# kept every earlier "two-frame" run from comparing anything at all).
function Get-T($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) {
        return $e.components.PSObject.Properties[$TKEY].Value
    }
    return $e.components[$TKEY]
}
function Sample-FallingCube([int]$Seconds) {
    $a = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
    Start-Sleep -Seconds $Seconds
    $b = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
    foreach ($eb in @($b)) {
        $ea = $null
        foreach ($cand in @($a)) { if ($cand.entity -eq $eb.entity) { $ea = $cand; break } }
        if (-not $ea) { continue }
        $ta = Get-T $ea; $tb = Get-T $eb
        if ($ta -and $tb) {
            $ya = [double]$ta.translation.y; $yb = [double]$tb.translation.y
            $ra = [double]$ta.rotation.y;    $rb = [double]$tb.rotation.y
            if ($yb -ne $ya) { return @{ dy = ($yb - $ya); drot = ($rb - $ra); entity = $eb.entity } }
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
    -RedirectStandardOutput (Join-Path $OutDir 'behavior3-stdout.log') `
    -RedirectStandardError (Join-Path $OutDir 'behavior3-stderr.log') -PassThru
$proc.Id | Set-Content (Join-Path $OutDir 'behavior3.pid')
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died while booting' }
}
if (-not $ready) { throw 'editor BRP never answered' }
Wait-Until 'idle' 1800
Start-Sleep -Seconds 25
Write-Host 'editor ready (schema settled)'

$configPath = Join-Path $Project 'assets\game-config.bsn'
$created = Op 'asset.new' @{ type = 'game_config'; name = 'game-config' }
$okNew = "$($created.result.result)" -eq 'finished' -and -not $created.result.warnings
Write-Host ("asset.new ok: " + $okNew)
if (-not $okNew) { Write-Host ($created | ConvertTo-Json -Depth 6 -Compress); throw 'asset.new failed again' }

Op 'asset.set' @{ field = 'move_speed'; value = '2.5' } | Out-Null
Op 'asset.set' @{ field = 'gravity'; value = '-9.81' } | Out-Null
Op 'asset.save' @{} | Out-Null
Start-Sleep -Seconds 1
$onDisk = Get-Content $configPath -Raw -Encoding UTF8
Write-Host "game-config.bsn on disk:`n$onDisk"
if ($onDisk -notmatch '2\.5') { throw "move_speed 2.5 did not reach the file" }

Op 'scene.new' @{} | Out-Null
Op 'scene.save' @{} | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' @{} | Out-Null
Wait-Until 'pie_running' 900
Start-Sleep -Seconds 3
$snapCount = @((Brp-Try 'jackdaw/scene_snapshot' @{}).result).Count
$sample25 = Sample-FallingCube 2
Op 'pie.stop' @{} | Out-Null
Wait-Until 'idle' 120
Write-Host ("run@2.5: snapshotCount=$snapCount sample=" + ($sample25 | ConvertTo-Json -Compress))
if (-not $sample25) { throw 'no projected entity moved while playing (move_speed=2.5)' }
if ($sample25.dy -ge 0) { throw "the cube did not fall at gravity -9.81 (dy=$($sample25.dy))" }

Op 'asset.set' @{ field = 'move_speed'; value = '0.5' } | Out-Null
Op 'asset.save' @{} | Out-Null
Start-Sleep -Seconds 1
$onDisk2 = Get-Content $configPath -Raw -Encoding UTF8
if ($onDisk2 -notmatch '0\.5') { throw "move_speed 0.5 did not reach the file" }
Op 'pie.play_current' @{} | Out-Null
Wait-Until 'pie_running' 900
Start-Sleep -Seconds 3
$sample05 = Sample-FallingCube 2
Op 'pie.stop' @{} | Out-Null
Wait-Until 'idle' 120
Write-Host ("run@0.5: sample=" + ($sample05 | ConvertTo-Json -Compress))
if (-not $sample05) { throw 'no projected entity moved while playing (move_speed=0.5)' }
if ($sample05.dy -ge 0) { throw "the cube did not fall on the second run (dy=$($sample05.dy))" }

$spin25 = [Math]::Abs([double]$sample25.drot)
$spin05 = [Math]::Abs([double]$sample05.drot)
$ratio = if ($spin05 -gt 0) { $spin25 / $spin05 } else { 999 }
Write-Host ("spin ratio 2.5:0.5 = " + [Math]::Round($ratio, 2))
if ($ratio -lt 2.5) { throw "spin at 2.5 ($spin25) should clearly outrun spin at 0.5 ($spin05)" }
Write-Output 'T08_T2_QA_BEHAVIOR_PASS'
Stop-Process -Id $proc.Id -Force
