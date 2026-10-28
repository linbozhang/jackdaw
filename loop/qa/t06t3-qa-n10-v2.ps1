# T06-T3 QA N10 probe v2: fire play_current while the startup prebuild is
# still compiling (replicates the program's baseline timing, where the freeze
# hit ~5.5s after launch, prebuild still in flight).
$ErrorActionPreference = 'Continue'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15729
$OutDir  = Join-Path $Repo 'loop\t06t3-qa-live'

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
    #Anchor
    jackdaw_scene_types::node_id::SceneNodeId(7001)
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
    -RedirectStandardOutput (Join-Path $OutDir "qa-v2-editor-$stamp-stdout.log") `
    -RedirectStandardError (Join-Path $OutDir "qa-v2-editor-$stamp-stderr.log") -PassThru
$stderrLog = Join-Path $OutDir "qa-v2-editor-$stamp-stderr.log"
Wait-EditorReady -TimeoutSec 240
Write-Host "editor ready pid=$($editor.Id); going straight in (prebuild in flight)"

# The freeze window: play while the prebuild still compiles.
Op 'scene.open' @{ path = 'assets/t06-qa-n10.bsn' } | Out-Null
Start-Sleep -Seconds 2
Op 'entity.add.cube' | Out-Null
Start-Sleep -Seconds 1
$dirty = (Brp-Result (Brp-Call 'jackdaw/status' @{})).dirty
Write-Host "premise: dirty=$dirty; firing play_current (save policy default)"
$prebuildRunning = (Select-String -Path $stderrLog -Pattern 'pre-building' -Quiet)
Write-Host "prebuild was started at launch: $prebuildRunning"
Op 'pie.play_current' | Out-Null
Write-Host 'play_current dispatched; observing 9s...'
$cpu1 = Cpu-Seconds $editor
Start-Sleep -Seconds 5
$alive2 = Brp-Alive; $cpu2 = Cpu-Seconds $editor
Start-Sleep -Seconds 4
$alive3 = Brp-Alive; $cpu3 = Cpu-Seconds $editor
Write-Host ("BRP alive: t5={0} t9={1}" -f $alive2, $alive3)
Write-Host ("editor CPU: t0={0:n1} t5={1:n1} t9={2:n1} (delta {3:n1}s over 9s wall)" -f $cpu1, $cpu2, $cpu3, ($cpu3-$cpu1))
$froze = (-not $alive2) -and (-not $alive3)
if ($froze) { Write-Host 'FROZEN: BRP dead (N10 reproduced by QA, v2 timing)' }
else {
    try { $st = (Brp-Result (Brp-Call 'jackdaw/status' @{})).pie; Write-Host "not frozen; pie=$st" } catch { Write-Host 'status read failed' }
}
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Remove-Item $probeScene -Force -ErrorAction SilentlyContinue
Remove-Item "$probeScene.bak" -Force -ErrorAction SilentlyContinue
Get-ChildItem (Join-Path $Project 'assets\.jackdaw-pie') -Filter 'current-*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host 'N10_QA_PROBE_V2_DONE'
