# N10 fix probe A: replicate the program's original freeze conditions.
# cfg = the program's t06t3-live cfg (leftover sessions -> recovery dialog),
# ready-then-go (prebuild in flight), SpinningCube fixture, add.cube, play_current.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\n10-fix-probe.ps1 [-Case A]
param([string]$Case = 'A', [string]$CfgDir = 'E:\Project\rust\jackdaw\loop\t06t3-live\cfg')
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
$env:JACKDAW_CONFIG_DIR   = $CfgDir
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$stamp = Get-Date -Format 'HHmmss'
$editor = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir "n10-$Case-$stamp-stdout.log") `
    -RedirectStandardError (Join-Path $OutDir "n10-$Case-$stamp-stderr.log") -PassThru
$stderrLog = Join-Path $OutDir "n10-$Case-$stamp-stderr.log"
Wait-EditorReady -TimeoutSec 240
Write-Host "editor ready pid=$($editor.Id) (cfg=$CfgDir, prebuild in flight)"

switch ($Case) {
    'A' {
        # The program's exact sequence: open -> add.cube -> 1s -> play_current.
        Op 'scene.open' @{ path = 'assets/t06-qa-n10.bsn' } | Out-Null
        Start-Sleep -Seconds 2
        Op 'entity.add.cube' | Out-Null
        Start-Sleep -Seconds 1
        $dirty = (Brp-Result (Brp-Call 'jackdaw/status' @{})).dirty
        Write-Host "premise: dirty=$dirty; firing play_current"
        Op 'pie.play_current' | Out-Null
    }
    'B' {
        # freeze_baseline's shape: clean play -> stop -> (dirty) play_current.
        Op 'scene.open' @{ path = 'assets/t06-qa-n10.bsn' } | Out-Null
        Start-Sleep -Seconds 2
        Op 'pie.play_current' | Out-Null
        Start-Sleep -Seconds 4
        $alive = Brp-Alive
        Write-Host "clean play: BRP alive=$alive"
        if ($alive) { Op 'pie.stop' | Out-Null; Write-Host 'stop dispatched' }
        Start-Sleep -Seconds 3
        $alive = Brp-Alive
        Write-Host "after stop: BRP alive=$alive"
        if (-not $alive) { Write-Host 'FROZE at the stop step (freeze_baseline shape)'; break }
        Op 'entity.add.cube' | Out-Null
        Start-Sleep -Seconds 1
        Write-Host 'dirty now; firing second play_current'
        Op 'pie.play_current' | Out-Null
    }
}

Write-Host 'observing 9s...'
$cpu1 = Cpu-Seconds $editor
Start-Sleep -Seconds 5
$alive2 = Brp-Alive; $cpu2 = Cpu-Seconds $editor
Start-Sleep -Seconds 4
$alive3 = Brp-Alive; $cpu3 = Cpu-Seconds $editor
Write-Host ("BRP alive: t5={0} t9={1}" -f $alive2, $alive3)
Write-Host ("editor CPU: t0={0:n1} t5={1:n1} t9={2:n1} (delta {3:n1}s over 9s wall)" -f $cpu1, $cpu2, $cpu3, ($cpu3-$cpu1))
$froze = (-not $alive2) -and (-not $alive3)
if ($froze) {
    Write-Host "FROZEN: BRP dead + spin (case $Case, N10 REPRODUCED)"
    Write-Host '--- stderr tail ---'
    Get-Content $stderrLog -Tail 12 | Write-Host
} else {
    try { $st = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie; Write-Host "not frozen; pie=$st" }
    catch { Write-Host 'not frozen; status read failed' }
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process my-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host "N10_PROBE_DONE case=$Case"
