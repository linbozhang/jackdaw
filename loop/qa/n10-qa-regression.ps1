# N10 fix QA regression (independent rerun on the fixed build 6cfb1358):
# - dirty+save one-step play x2 (dirty -> play_current -> running -> stop
#   -> stopped -> BRP alive -> the save actually reached disk)
# - one boundary: dirty+copy
# - stop hammer: 3 fast play/stop/dirty-play cycles (retry-stop recipe)
$ErrorActionPreference = 'Continue'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15731
$OutDir  = Join-Path $Repo 'loop\n10-qa-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port

function Op([string]$Id, $Params = @{}) {
    $p = @{ id = $Id }
    if ($Params.Count) { $p.params = $Params }
    Brp-Result (Brp-Call 'jackdaw/call_operator' $p)
}
function Status-Pie { (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie }
function Brp-Alive([int]$TimeoutMs = 3000) {
    try {
        $req = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$Port/")
        $req.Method = 'POST'; $req.ContentType = 'application/json'; $req.Timeout = $TimeoutMs
        $body = [Text.Encoding]::UTF8.GetBytes('{"jsonrpc":"2.0","id":1,"method":"jackdaw/status","params":{}}')
        $req.ContentLength = $body.Length
        $s = $req.GetRequestStream(); $s.Write($body,0,$body.Length); $s.Close()
        $resp = $req.GetResponse(); $resp.Close(); $true
    } catch { $false }
}
# Stop with the retry recipe (the connecting-window avail refusal is the
# established interaction; retry until the connected window takes it).
function Stop-Game([int]$TimeoutSec = 30) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Op 'pie.stop' | Out-Null
        $sub = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $sub) {
            if ((Status-Pie) -eq 'stopped') { return $true }
            Start-Sleep -Milliseconds 150
        }
    }
    $false
}

$probeScene = Join-Path $Project 'assets\n10-qa-spin.bsn'
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
$env:JACKDAW_CONFIG_DIR   = "$OutDir\cfg"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$stamp = Get-Date -Format 'HHmmss'
$editor = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir "qa-editor-$stamp-stdout.log") `
    -RedirectStandardError (Join-Path $OutDir "qa-editor-$stamp-stderr.log") -PassThru
Wait-EditorReady -TimeoutSec 240
Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 600 | Out-Null
Write-Host "editor ready pid=$($editor.Id)"

try {
    # ---- round 1 & 2: dirty + save one-step play ------------------------
    foreach ($round in 1..2) {
        Write-Host "== dirty+save one-step round $round =="
        Op 'scene.open' @{ path = 'assets/n10-qa-spin.bsn' } | Out-Null
        Start-Sleep -Seconds 2
        Op 'entity.add.cube' | Out-Null
        Start-Sleep -Seconds 1
        $dirty = (Brp-Result (Brp-Call 'jackdaw/status' @{})).dirty
        $lenBefore = (Get-Content $probeScene -Raw).Length
        Write-Host "  premise dirty=$dirty fileLen=$lenBefore"
        Op 'pie.play_current' | Out-Null
        # running?
        $running = $false
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline) {
            if ((Status-Pie) -eq 'running') { $running = $true; break }
            Start-Sleep -Milliseconds 250
        }
        $aliveMid = Brp-Alive
        Write-Host "  running=$running aliveMid=$aliveMid"
        $stopped = Stop-Game
        $aliveEnd = Brp-Alive
        $lenAfter = (Get-Content $probeScene -Raw).Length
        $grew = $lenAfter -gt $lenBefore
        Write-Host "  stopped=$stopped aliveEnd=$aliveEnd fileGrew=$grew ($lenBefore -> $lenAfter)"
        if ($running -and $aliveMid -and $stopped -and $aliveEnd -and $grew) {
            Write-Host "  ROUND $round OK"
        } else { Write-Host "  ROUND $round FAIL" }
        # back to clean for the next round: reopen the (now saved) scene
        Op 'scene.close' @{ force = $true } | Out-Null
        Start-Sleep -Milliseconds 500
    }

    # ---- boundary: dirty + copy -----------------------------------------
    Write-Host '== boundary: dirty + copy =='
    Op 'scene.open' @{ path = 'assets/n10-qa-spin.bsn' } | Out-Null
    Start-Sleep -Seconds 2
    Op 'entity.add.cube' | Out-Null
    Start-Sleep -Seconds 1
    $lenBefore = (Get-Content $probeScene -Raw).Length
    Op 'project.set_save_before_play' @{ mode = 'play_unsaved_copy' } | Out-Null
    Op 'pie.play_current' | Out-Null
    $running = $false
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline) {
        if ((Status-Pie) -eq 'running') { $running = $true; break }
        Start-Sleep -Milliseconds 250
    }
    $stopped = Stop-Game
    $lenAfter = (Get-Content $probeScene -Raw).Length
    Write-Host ("  dirty+copy: running={0} stopped={1} diskUntouched={2}" -f $running, $stopped, ($lenBefore -eq $lenAfter))
    Op 'project.set_save_before_play' @{ mode = 'save' } | Out-Null
    Op 'scene.close' @{ force = $true } | Out-Null

    # ---- stop hammer: 3 fast play/stop/dirty-play cycles -----------------
    Write-Host '== stop hammer: 3 fast cycles =='
    foreach ($cycle in 1..3) {
        Op 'scene.open' @{ path = 'assets/n10-qa-spin.bsn' } | Out-Null
        Start-Sleep -Seconds 1
        Op 'pie.play_current' | Out-Null          # clean play
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline -and (Status-Pie) -ne 'running') { Start-Sleep -Milliseconds 200 }
        $s1 = Stop-Game
        Op 'entity.add.cube' | Out-Null           # dirty
        Start-Sleep -Milliseconds 300
        Op 'pie.play_current' | Out-Null          # dirty play (save policy)
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline -and (Status-Pie) -ne 'running') { Start-Sleep -Milliseconds 200 }
        $s2 = Stop-Game
        $alive = Brp-Alive
        Write-Host ("  cycle {0}: cleanStop={1} dirtyStop={2} alive={3}" -f $cycle, $s1, $s2, $alive)
        Op 'scene.close' @{ force = $true } | Out-Null
        Start-Sleep -Milliseconds 300
    }
    Write-Output 'N10_QA_REGRESSION_DONE'
} finally {
    Get-Process -Id $editor.Id -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Remove-Item $probeScene -Force -ErrorAction SilentlyContinue
    Remove-Item "$probeScene.bak" -Force -ErrorAction SilentlyContinue
    Get-ChildItem (Join-Path $Project 'assets\.jackdaw-pie') -Filter 'current-*' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host 'cleaned'
}
