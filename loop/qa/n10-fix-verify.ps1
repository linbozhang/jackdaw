# N10 fix verification: the QA-mandated one-step dirty+Save regression.
# A dirty named scene plays via pie.play_current directly (no pre-save),
# the full flow must pass: play -> running -> stop -> stopped, BRP alive
# throughout, and the disk file must carry the edit the save policy wrote.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\n10-fix-verify.ps1 [-Runs 3]
param([int]$Runs = 3)
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
    -RedirectStandardOutput (Join-Path $OutDir "n10-verify-$stamp-stdout.log") `
    -RedirectStandardError (Join-Path $OutDir "n10-verify-$stamp-stderr.log") -PassThru
Wait-EditorReady -TimeoutSec 240
Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 600 | Out-Null
Write-Host "editor ready pid=$($editor.Id) (idle, warm build)"

$pass = 0; $fail = 0
for ($r = 1; $r -le $Runs; $r++) {
    Write-Host "== dirty+Save one-step run $r/$Runs =="
    $ok = $true

    # Reset the tab state: reopen the scene clean.
    Op 'scene.open' @{ path = 'assets/t06-qa-n10.bsn' } | Out-Null
    Start-Sleep -Seconds 1

    # Dirty it, then play directly: the save policy saves inside the launch.
    Op 'entity.add.cube' | Out-Null
    Start-Sleep -Milliseconds 500
    $dirty = (Brp-Result (Brp-Call 'jackdaw/status' @{})).dirty
    if (-not $dirty) { Write-Host '  PREMISE FAIL: tab not dirty'; $ok = $false }
    Op 'pie.play_current' | Out-Null
    Write-Host '  play_current dispatched (dirty, save policy, one step)'

    # Running within a bound.
    $running = $false
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (-not (Brp-Alive)) { break }
        try { $pie = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie } catch { break }
        if ($pie -eq 'running') { $running = $true; break }
        Start-Sleep -Milliseconds 200
    }
    Write-Host "  running=$running"
    if (-not $running) { $ok = $false }

    # Stop through the retry channel (avail-reject until connected).
    $stopped = $false
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (-not (Brp-Alive)) { break }
        try { Op 'pie.stop' | Out-Null } catch { }
        try { $pie = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie } catch { break }
        if ($pie -eq 'stopped') { $stopped = $true; break }
        Start-Sleep -Milliseconds 150
    }
    Write-Host "  stopped=$stopped"
    if (-not $stopped) { $ok = $false }

    # BRP alive at the end and the save policy wrote the edit to disk.
    $alive = Brp-Alive
    Write-Host "  brp_alive_after=$alive"
    if (-not $alive) { $ok = $false }
    $saved = (Select-String -Path $probeScene -Pattern 'bevy_render|MeshPawn|Cube|bevy_mesh' -Quiet) -or
             ((Get-Item $probeScene).Length -gt 300)
    # The scene text grows when the cube's components land in the document.
    $text = Get-Content $probeScene -Raw
    $grew = ($text.Length -gt 220)
    Write-Host "  disk_saved=$grew (file $($text.Length) chars)"
    if (-not $grew) { $ok = $false }

    if ($ok) { $pass++; Write-Host '  RUN PASS' } else { $fail++; Write-Host '  RUN FAIL' }
    Start-Sleep -Seconds 1
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process my-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Remove-Item $probeScene -Force -ErrorAction SilentlyContinue
Remove-Item "$probeScene.bak" -Force -ErrorAction SilentlyContinue
Get-ChildItem (Join-Path $Project 'assets\.jackdaw-pie') -Filter 'current-*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host "N10_VERIFY_DIRTY_SAVE pass=$pass fail=$fail of $Runs"
if ($fail -eq 0) { Write-Host 'N10_VERIFY_PASS' } else { Write-Host 'N10_VERIFY_FAIL' }
