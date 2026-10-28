# T06-T3 QA: independent N10 reproduction (freeze) + three boundary cases.
# Freeze case: named scene -> edit (dirty) -> pie.play_current under the
# default save policy -> expect the editor main thread to spin (BRP dead).
# Boundaries (expect NO freeze): clean+save, dirty+copy, untitled.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t06t3-qa-n10.ps1
$ErrorActionPreference = 'Continue'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15729
$OutDir  = Join-Path $Repo 'loop\t06t3-qa-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port

function Op([string]$Id, $Params = @{}) {
    $p = @{ id = $Id }
    if ($Params.Count) { $p.params = $Params }
    Brp-Result (Brp-Call 'jackdaw/call_operator' $p)
}

function Kill-Editors {
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "killing jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
    }
    Start-Sleep -Milliseconds 500
}

function Start-Editor {
    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT  = "$Port"
    $env:JACKDAW_WINDOW_SIZE  = '1920x1080'
    $env:JACKDAW_CONFIG_DIR   = "$OutDir\cfg"
    $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
    $env:PATH = "$deps;$env:PATH"
    $stamp = Get-Date -Format 'HHmmss'
    $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
        -RedirectStandardOutput (Join-Path $OutDir "qa-editor-$stamp-stdout.log") `
        -RedirectStandardError (Join-Path $OutDir "qa-editor-$stamp-stderr.log") -PassThru
    $script:Stderr = Join-Path $OutDir "qa-editor-$stamp-stderr.log"
    Wait-EditorReady -TimeoutSec 240
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 600 | Out-Null
    Write-Host "editor ready pid=$($proc.Id)"
    $proc
}

# Is the editor's BRP alive? Answer via one short-timeout status call.
function Brp-Alive([int]$TimeoutMs = 3000) {
    try {
        $req = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$Port/")
        $req.Method = 'POST'; $req.ContentType = 'application/json'
        $req.Timeout = $TimeoutMs
        $body = [Text.Encoding]::UTF8.GetBytes('{"jsonrpc":"2.0","id":1,"method":"jackdaw/status","params":{}}')
        $req.ContentLength = $body.Length
        $s = $req.GetRequestStream(); $s.Write($body,0,$body.Length); $s.Close()
        $resp = $req.GetResponse()
        $resp.Close()
        $true
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
    #Anchor
    jackdaw_scene_types::node_id::SceneNodeId(7001)
    bevy_transform::components::transform::Transform
    --
    #Still
    jackdaw_scene_types::node_id::SceneNodeId(7002)
    bevy_transform::components::transform::Transform
]
'@ | Set-Content $probeScene -Encoding ascii

Kill-Editors

# ============ case F: dirty + save policy -> expect FREEZE ============
Write-Host '== case F: dirty named scene + save policy play_current (expect freeze) =='
$editor = Start-Editor
Op 'scene.open' @{ path = 'assets/t06-qa-n10.bsn' } | Out-Null
Start-Sleep -Seconds 2
Op 'entity.add.cube' | Out-Null
Start-Sleep -Seconds 1
$dirty = (Brp-Result (Brp-Call 'jackdaw/status' @{})).dirty
Write-Host "  premise: dirty=$dirty (save policy is the default)"
Op 'pie.play_current' | Out-Null
Write-Host '  play_current dispatched; polling BRP for 12s...'
$alive1 = Brp-Alive
$cpu1 = Cpu-Seconds $editor
Start-Sleep -Seconds 6
$alive2 = Brp-Alive
$cpu2 = Cpu-Seconds $editor
Start-Sleep -Seconds 3
$alive3 = Brp-Alive
$cpu3 = Cpu-Seconds $editor
Write-Host ("  BRP alive: t0={0} t6={1} t9={2}" -f $alive1, $alive2, $alive3)
Write-Host ("  editor CPU seconds: t0={0:n1} t6={1:n1} t9={2:n1} (delta over 9s wall: {3:n1})" -f $cpu1, $cpu2, $cpu3, ($cpu3 - $cpu1))
$froze = (-not $alive2) -and (-not $alive3) -and (($cpu3 - $cpu1) -gt 6.0)
if ($froze) { Write-Host '  FROZEN: BRP dead + main thread spun (N10 reproduced by QA)' }
else { Write-Host '  NOT FROZEN: BRP alive or CPU idle' }
Kill-Editors
Write-Host '== case F done =='

# ============ boundary 1: clean + save policy -> expect OK ============
Write-Host '== case B1: clean named scene + save policy play_current (expect normal) =='
$editor = Start-Editor
Op 'scene.open' @{ path = 'assets/t06-qa-n10.bsn' } | Out-Null
Start-Sleep -Seconds 2
Op 'pie.play_current' | Out-Null
Start-Sleep -Seconds 4
$alive = Brp-Alive
$pie = $null
if ($alive) { $pie = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie }
Write-Host "  BRP alive=$alive pie=$pie"
Op 'pie.stop' | Out-Null
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {
    $pie = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie
    if ($pie -eq 'stopped') { break }
    Start-Sleep -Milliseconds 200
}
Write-Host "  B1 result: alive=$alive stopped=$($pie -eq 'stopped')"
Write-Host '== case B1 done =='

# ============ boundary 2: dirty + copy policy -> expect OK ============
Write-Host '== case B2: dirty named scene + copy policy play_current (expect normal) =='
Op 'entity.add.cube' | Out-Null
Start-Sleep -Seconds 1
Op 'project.set_save_before_play' @{ mode = 'play_unsaved_copy' } | Out-Null
Op 'pie.play_current' | Out-Null
Start-Sleep -Seconds 4
$alive = Brp-Alive
$pie = $null
if ($alive) { $pie = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie }
Write-Host "  BRP alive=$alive pie=$pie"
Op 'pie.stop' | Out-Null
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {
    $pie = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie
    if ($pie -eq 'stopped') { break }
    Start-Sleep -Milliseconds 200
}
Write-Host "  B2 result: alive=$alive stopped=$($pie -eq 'stopped')"
Op 'project.set_save_before_play' @{ mode = 'save' } | Out-Null   # restore default
Write-Host '== case B2 done =='

# ============ boundary 3: untitled (dirty) + save policy -> expect OK ============
Write-Host '== case B3: untitled dirty scene + save policy play_current (expect normal) =='
Op 'scene.new' | Out-Null
Start-Sleep -Milliseconds 500
Op 'entity.add.cube' | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' | Out-Null
Start-Sleep -Seconds 4
$alive = Brp-Alive
$pie = $null
if ($alive) { $pie = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie }
Write-Host "  BRP alive=$alive pie=$pie"
Op 'pie.stop' | Out-Null
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {
    $pie = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie
    if ($pie -eq 'stopped') { break }
    Start-Sleep -Milliseconds 200
}
Write-Host "  B3 result: alive=$alive stopped=$($pie -eq 'stopped')"

Kill-Editors
Remove-Item $probeScene -Force -ErrorAction SilentlyContinue
Remove-Item "$probeScene.bak" -Force -ErrorAction SilentlyContinue
Get-ChildItem (Join-Path $Project 'assets\.jackdaw-pie') -Filter 'current-*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host 'N10_QA_PROBE_DONE'
