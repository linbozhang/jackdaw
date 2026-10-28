# Isolate the B2 boundary (dirty + copy policy) with per-call timing so a
# slow BRP round trip cannot hide: every op is timed, the stop is retried
# through the avail-reject window with timing, and the pie face is logged.
param([int]$Runs = 2)
$ErrorActionPreference = 'Continue'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15731
$OutDir  = Join-Path $Repo 'loop\n10-fix-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port

function Timed-Op([string]$Id, $Params = @{}) {
    $p = @{ id = $Id }
    if ($Params.Count) { $p.params = $Params }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Brp-Call 'jackdaw/call_operator' $p
        $outcome = if ($r.error) { "err" } else { [string]$r.result.result }
        $ms = $sw.ElapsedMilliseconds
        Write-Host ("    {0} -> {1} ({2} ms)" -f $Id, $outcome, $ms)
        return $outcome
    } catch {
        Write-Host ("    {0} -> THROW after {1} ms: {2}" -f $Id, $sw.ElapsedMilliseconds, $_.Exception.Message.Split("`n")[0])
        return 'throw'
    }
}
function Timed-Status-Pie {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Brp-Call 'jackdaw/status' @{}
        $pie = [string]$r.result.pie
        Write-Host ("    status.pie={0} ({1} ms)" -f $pie, $sw.ElapsedMilliseconds)
        return $pie
    } catch {
        Write-Host ("    status THROW after {0} ms" -f $sw.ElapsedMilliseconds)
        return 'throw'
    }
}

$probeScene = Join-Path $Project 'assets\t06-qa-n10.bsn'
@'
// jackdaw 0.21.0-dev | bevy main
bevy_ecs::hierarchy::Children [
    #Spinner
    jackdaw_scene_types::node_id::SceneNodeId(7001)
    my_game::SpinningCube { speed: 2.0 }
    bevy_transform::components::transform::Transform
    --
    #Still
    jackdaw_scene_types::node_id::SceneNodeId(7002)
    bevy_transform::components::transform::Transform
]
'@ | Set-Content $probeScene -Encoding ascii

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$env:JACKDAW_WINDOW_SIZE  = '1920x1080'
$env:JACKDAW_CONFIG_DIR   = Join-Path $OutDir 'cfg'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$stamp = Get-Date -Format 'HHmmss'
$editor = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir "n10-b2-$stamp-stdout.log") `
    -RedirectStandardError (Join-Path $OutDir "n10-b2-$stamp-stderr.log") -PassThru
$stderrLog = Join-Path $OutDir "n10-b2-$stamp-stderr.log"
Wait-EditorReady -TimeoutSec 240
Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 600 | Out-Null
Write-Host "editor ready pid=$($editor.Id)"

for ($r = 1; $r -le $Runs; $r++) {
    Write-Host "== B2 isolated run $r/$Runs =="
    Timed-Op 'scene.open' @{ path = 'assets/t06-qa-n10.bsn' } | Out-Null
    Start-Sleep -Seconds 1
    Timed-Op 'entity.add.cube' | Out-Null
    Start-Sleep -Milliseconds 500
    Timed-Op 'project.set_save_before_play' @{ mode = 'play_unsaved_copy' } | Out-Null
    Timed-Op 'pie.play_current' | Out-Null
    Start-Sleep -Seconds 4
    $pie = Timed-Status-Pie
    # Retry stop through the avail window, every call timed.
    $deadline = (Get-Date).AddSeconds(30)
    $final = 'timeout'
    while ((Get-Date) -lt $deadline) {
        $outcome = Timed-Op 'pie.stop'
        if ($outcome -eq 'finished') { $final = 'dispatched'; break }
        if ($outcome -eq 'throw') { $final = 'throw'; break }
        Start-Sleep -Milliseconds 150
    }
    # Wait for the stopped face.
    $stopped = $false
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $pie = Timed-Status-Pie
        if ($pie -eq 'stopped') { $stopped = $true; break }
        Start-Sleep -Milliseconds 250
    }
    Write-Host "  run ${r}: stop=${final} stopped=${stopped}"
    Start-Sleep -Seconds 1
}
Timed-Op 'project.set_save_before_play' @{ mode = 'save' } | Out-Null

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process my-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Remove-Item $probeScene -Force -ErrorAction SilentlyContinue
Remove-Item "$probeScene.bak" -Force -ErrorAction SilentlyContinue
Get-ChildItem (Join-Path $Project 'assets\.jackdaw-pie') -Filter 'current-*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host 'N10_B2_ISOLATED_DONE'
