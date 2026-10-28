# N10 fix probe C: stop inside the connecting window (the 100% freeze path
# from the T3 experiment, needs the probe build with relaxed pie.stop avail).
# Sequence: wait idle (prebuild done) -> play (clean, instant spawn from
# cache) -> stop 0.3s later (child connecting) -> observe.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\n10-fix-probe-c.ps1 [-StopDelayMs 300]
param([int]$StopDelayMs = 300)
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
$env:JACKDAW_CONFIG_DIR   = Join-Path $OutDir 'cfg'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$stamp = Get-Date -Format 'HHmmss'
$editor = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir "n10-C-$stamp-stdout.log") `
    -RedirectStandardError (Join-Path $OutDir "n10-C-$stamp-stderr.log") -PassThru
$stderrLog = Join-Path $OutDir "n10-C-$stamp-stderr.log"
Wait-EditorReady -TimeoutSec 240
Write-Host "editor ready pid=$($editor.Id); waiting for prebuild idle"
Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 600 | Out-Null
Write-Host 'idle; playing'

Op 'scene.open' @{ path = 'assets/t06-qa-n10.bsn' } | Out-Null
Start-Sleep -Seconds 2
Op 'pie.play_current' | Out-Null
Write-Host "play dispatched; stopping after ${StopDelayMs}ms (connecting window)"
Start-Sleep -Milliseconds $StopDelayMs
try { Op 'pie.stop' | Out-Null } catch { Write-Host "stop call itself: $_" }
Write-Host 'stop dispatched; observing 8s...'
$cpu1 = Cpu-Seconds $editor
Start-Sleep -Seconds 4
$alive2 = Brp-Alive; $cpu2 = Cpu-Seconds $editor
Start-Sleep -Seconds 4
$alive3 = Brp-Alive; $cpu3 = Cpu-Seconds $editor
Write-Host ("BRP alive: t4={0} t8={1}" -f $alive2, $alive3)
Write-Host ("editor CPU: t0={0:n1} t4={1:n1} t8={2:n1} (delta {3:n1}s over 8s wall)" -f $cpu1, $cpu2, $cpu3, ($cpu3-$cpu1))
$froze = (-not $alive2) -and (-not $alive3)
if ($froze) {
    Write-Host 'FROZEN: connecting-window stop froze the editor (N10 family REPRODUCED)'
    Write-Host '--- stderr tail (30) ---'
    Get-Content $stderrLog -Tail 30 | Write-Host
    # Sample thread states like freeze2 did.
    $p = Get-Process -Id $editor.Id -ErrorAction SilentlyContinue
    if ($p) {
        $running = @($p.Threads | Where-Object { $_.ThreadState -eq 'Running' }).Count
        Write-Host "threads: $($p.Threads.Count), running: $running"
    }
} else {
    try { $st = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie; Write-Host "not frozen; pie=$st" }
    catch { Write-Host 'not frozen; status read failed' }
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process my-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host "N10_PROBE_DONE case=C delay=${StopDelayMs}ms"
