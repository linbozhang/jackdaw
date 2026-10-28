# N10 fix probe D: the QA-recipe stop channel pushed hard — hammer pie.stop
# every 100ms through the connecting window until it lands right after
# connect (the retry-chain trigger T3 observed), then immediately re-play
# (the rapid play/stop churn variant).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\n10-fix-probe-d.ps1 [-Cycles 3]
param([int]$Cycles = 3)
$ErrorActionPreference = 'Continue'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15731
$OutDir  = Join-Path $Repo 'loop\n10-fix-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port

function Op([string]$Id, $Params = @{}) {
    $p = @{ id = $Id }
    if ($Params.Count) { $p.params = $Params }
    Brp-Result (Brp-Call 'jackdaw/call_operator' $p)
}
function Brp-Alive([int]$TimeoutMs = 3000) {
    try {
        $req = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$Port/")
        $req.Method = 'POST'; $req.ContentType = 'application/json'
        $req.Timeout = $TimeoutMs
        $body = [Text.Encoding]::UTF8.GetBytes('{"jsonrpc":"2.0","id":1,"method":"jackdaw/status","params":{}}')
        $req.ContentLength = $body.Length
        $s = $req.GetRequestStream(); $s.Write($body,0,$body.Length); $s.Close()
        $resp = $req.GetResponse(); $resp.Close(); $true
    } catch { $false }
}
function Cpu-Seconds($Proc) {
    $p = Get-Process -Id $Proc.Id -ErrorAction SilentlyContinue
    if ($p) { $p.TotalProcessorTime.TotalSeconds } else { -1 }
}
# A raw stop attempt; returns 'finished', 'cancelled' or 'timeout'.
function Try-Stop {
    try {
        $r = Brp-Call 'jackdaw/call_operator' @{ id = 'pie.stop' }
        return [string]$r.result.result
    } catch { return 'timeout' }
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
$env:JACKDAW_CONFIG_DIR   = 'E:\Project\rust\jackdaw\loop\t06t3-live\cfg'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$stamp = Get-Date -Format 'HHmmss'
$editor = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir "n10-D-$stamp-stdout.log") `
    -RedirectStandardError (Join-Path $OutDir "n10-D-$stamp-stderr.log") -PassThru
$stderrLog = Join-Path $OutDir "n10-D-$stamp-stderr.log"
Wait-EditorReady -TimeoutSec 240
Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 600 | Out-Null
Write-Host "editor ready pid=$($editor.Id) (idle)"

Op 'scene.open' @{ path = 'assets/t06-qa-n10.bsn' } | Out-Null
Start-Sleep -Seconds 2

$frozeAny = $false
for ($c = 1; $c -le $Cycles; $c++) {
    Write-Host "== cycle $c =="
    Op 'entity.add.cube' | Out-Null   # dirty for the save path
    Start-Sleep -Milliseconds 300
    Op 'pie.play_current' | Out-Null
    Write-Host "  play dispatched; hammering stop every 100ms"
    $attempts = 0; $outcome = 'never'
    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-Date) -lt $deadline) {
        $outcome = Try-Stop
        $attempts++
        if ($outcome -eq 'timeout') { break }
        if ($outcome -eq 'finished') {
            # landed; wait for stopped then immediately re-play
            $stopDeadline = (Get-Date).AddSeconds(10)
            while ((Get-Date) -lt $stopDeadline) {
                try {
                    $pie = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie
                    if ($pie -eq 'stopped') { break }
                } catch { break }
                Start-Sleep -Milliseconds 50
            }
            break
        }
        Start-Sleep -Milliseconds 100
    }
    Write-Host "  stop outcome=$outcome after $attempts attempts"
    if ($outcome -eq 'timeout') {
        Write-Host "  FROZEN during the stop retry chain (cycle $c)"
        $frozeAny = $true
        break
    }
    if (-not (Brp-Alive)) {
        Write-Host "  FROZEN right after stop landed (cycle $c)"
        $frozeAny = $true
        break
    }
    Start-Sleep -Milliseconds 200   # rapid re-play
}

if (-not $frozeAny) {
    Write-Host 'final observation 6s...'
    $cpu1 = Cpu-Seconds $editor
    Start-Sleep -Seconds 6
    $alive = Brp-Alive; $cpu2 = Cpu-Seconds $editor
    Write-Host ("BRP alive={0} CPU delta={1:n1}s/6s" -f $alive, ($cpu2-$cpu1))
    if (-not $alive) { $frozeAny = $true; Write-Host 'FROZEN at the end' }
}

if ($frozeAny) {
    Write-Host '--- stderr tail (40) ---'
    Get-Content $stderrLog -Tail 40 | Write-Host
    $p = Get-Process -Id $editor.Id -ErrorAction SilentlyContinue
    if ($p) {
        $running = @($p.Threads | Where-Object { $_.ThreadState -eq 'Running' }).Count
        Write-Host "threads: $($p.Threads.Count), running: $running"
    }
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process my-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host "N10_PROBE_DONE case=D froze=$frozeAny"
