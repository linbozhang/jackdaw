# T08-T2 rework live re-verification (QA §十 minimal set).
#   Leg A (ruling A): untitled scene + Save policy + dirty asset card +
#     pie.play_current -> the card's value is on disk (the untitled
#     branch of the save chain now saves assets too).
#   Leg B (QA-1): saved scene (clean baseline) + asset.set ->
#     jackdaw/history dirty stays false.
#   Leg C (QA-3): QA fixture, both config fields written to the file by
#     hand (editor's on-disk form), play, two-frame rotation rate at
#     move_speed 2.5 vs 0.5 — with the old template's stacked systems
#     the rate is 1.0 + 1.0*ms, so 3.5 vs 1.5; what matters is it
#     MOVES with the file's value.
# Usage: powershell -NoProfile -File loop\qa\t08-t2-rework-live.ps1
$ErrorActionPreference = 'Stop'

$Repo = 'E:\Project\rust\jackdaw'
$Exe  = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Fixture = 'E:\Project\rust\jackdaw\loop\qa-fixture\t08t2qa-fixture'
$Port = 15703
$OutDir = Join-Path $Repo 'loop\t08-t2-rework-live'
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
    return $false
}
function Start-Editor([string]$project) {
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Milliseconds 500
    $env:JACKDAW_OPEN_PROJECT = $project
    $env:JACKDAW_REMOTE_PORT  = "$Port"
    $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
    $env:PATH = "$deps;$env:PATH"
    $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
        -RedirectStandardOutput (Join-Path $OutDir 'editor-stdout.log') `
        -RedirectStandardError (Join-Path $OutDir 'editor-stderr.log') -PassThru
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Seconds 2
        if (Brp-Try 'jackdaw/status' @{} 1) { break }
        if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died booting' }
    }
    Wait-Until 'idle' 1800 | Out-Null
    $proc
}

# ================= Leg A + B: my-game =================
$proc = Start-Editor $Project
Write-Host 'editor ready (my-game)'

$assetPath = Join-Path $Project 'assets\t08rw.bsn'
Remove-Item $assetPath -Force -ErrorAction SilentlyContinue

# Leg B first: saved scene + asset edit -> history dirty stays false.
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Op 'scene.save' @{} | Out-Null
Start-Sleep -Seconds 1
$h0 = Brp-Try 'jackdaw/history' @{ }
$dirty0 = $h0.result.dirty
Op 'asset.new' @{ type = 'material'; name = 't08rw' } | Out-Null
Start-Sleep -Seconds 1
Op 'asset.set' @{ field = 'perceptual_roughness'; value = '0.42' } | Out-Null
Start-Sleep -Seconds 2
$h1 = Brp-Try 'jackdaw/history' @{ }
$dirty1 = $h1.result.dirty
Write-Host ("LEG B saved-scene dirty: before={0} after-asset-set={1} (expect False/False)" -f $dirty0, $dirty1)

# Leg A: close the card's tab state does not matter; leave the card
# dirty (asset.set, unsaved), make the scene in front untitled, play.
Op 'scene.new' @{} | Out-Null
Start-Sleep -Seconds 1
$prePlay = if (Test-Path $assetPath) { Get-Content $assetPath -Raw } else { '' }
Op 'pie.play_current' @{} | Out-Null
$running = Wait-Until 'pie_running' 900
Write-Host ("LEG A running: " + $running)
Start-Sleep -Seconds 3
Op 'pie.stop' @{} | Out-Null
Wait-Until 'idle' 120 | Out-Null
Start-Sleep -Seconds 2
$alive = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
$postPlay = if (Test-Path $assetPath) { Get-Content $assetPath -Raw } else { '' }
$saved = ($postPlay -match '0\.42')
Write-Host ("LEG A untitled+Save policy: alive={0} card-value-on-disk={1}" -f $alive, $saved)
Remove-Item $assetPath -Force -ErrorAction SilentlyContinue
Stop-Process -Id $proc.Id -Force
Start-Sleep -Seconds 2

# ================= Leg C: QA fixture, rotation rate =================
if (Test-Path (Join-Path $Fixture 'Cargo.toml')) {
    $proc = Start-Editor $Fixture
    Write-Host 'editor ready (QA fixture)'
    $cfg = Join-Path $Fixture 'assets\game-config.bsn'
    $tkey = 'bevy_transform::components::transform::Transform'
    function Spin-Rate([double]$ms) {
        $tp = "my_game::GameConfig"
        if (Test-Path "$Fixture\src\lib.rs") {
            $crate = (Select-String -Path "$Fixture\src\lib.rs" -Pattern 'pub struct GameConfig' -List).Path
        }
        # Use the project's own crate name from its manifest for the
        # type path header.
        $crateName = (Select-String -Path "$Fixture\Cargo.toml" -Pattern '^name = "(.+)"').Matches[0].Groups[1].Value.Replace('-','_')
        $tp = "${crateName}::GameConfig"
        $body = @"
// jackdaw asset $tp
#"game-config"
${tp} {
    player_health: 150.0,
    move_speed: $ms,
    gravity: -9.81,
}
"@
        [System.IO.File]::WriteAllText($cfg, $body)
        Op 'pie.play_current' @{} | Out-Null
        if (-not (Wait-Until 'pie_running' 900)) { throw 'play never ran' }
        Start-Sleep -Seconds 3
        $a = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
        Start-Sleep -Seconds 2
        $b = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
        Op 'pie.stop' @{} | Out-Null
        Wait-Until 'idle' 120 | Out-Null
        Start-Sleep -Seconds 1
        # Rotation as yaw unwrapped from the quaternion: atan2(2*(w*y), 1-2*y^2).
        $rate = $null
        foreach ($eb in @($b)) {
            foreach ($ea in @($a)) {
                if ($ea.entity -ne $eb.entity) { continue }
                $ra = $ea.components.$tkey.rotation; $rb = $eb.components.$tkey.rotation
                if (-not $ra -or -not $rb) { continue }
                $ya = [double]$ra[1]; $wa = [double]$ra[3]
                $yb = [double]$rb[1]; $wb = [double]$rb[3]
                $angA = [Math]::Atan2(2*($wa*$ya), 1-2*$ya*$ya)
                $angB = [Math]::Atan2(2*($wb*$yb), 1-2*$yb*$yb)
                $d = $angB - $angA
                while ($d -gt [Math]::PI) { $d -= 2*[Math]::PI }
                while ($d -lt -[Math]::PI) { $d += 2*[Math]::PI }
                if ($d -ne 0) { $rate = [Math]::Abs($d) / 2.0; break }
            }
            if ($rate) { break }
        }
        $rate
    }
    $r25 = Spin-Rate 2.5
    $r05 = Spin-Rate 0.5
    Write-Host ("LEG C spin rates: ms=2.5 -> {0} rad/s; ms=0.5 -> {1} rad/s" -f $r25, $r05)
    Stop-Process -Id $proc.Id -Force
} else {
    Write-Host 'LEG C skipped: QA fixture not found'
}
Write-Output 'T08_T2_REWORK_LIVE_DONE'
