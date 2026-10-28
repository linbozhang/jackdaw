# T10-T2 live: the physics ground truth on the real editor, two
# assertion channels. The editor port (Live-mirrored scene entities):
# the scene's DroppingCube falls and settles. The game port (the game
# process answers BRP directly): the template's own falling cube and
# the pickup chain end to end. Warm project:
# H:\workspace_AI\t10-phys\phys-game.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t10-triggers.ps1
$ErrorActionPreference = 'Continue'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'H:\workspace_AI\t10-phys\phys-game'
$EditorPort = 15703
$GamePort   = 15702
$OutDir  = Join-Path $Repo 'loop\t10t2-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Brp([int]$Port, [string]$method, $params, [int]$retries = 6) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = (Get-Random); method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 10)
        } catch { Start-Sleep -Milliseconds (500 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp $EditorPort 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp $EditorPort 'jackdaw/call_operator' @{ id = $id } }
}
function Wait-Until([string]$until, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp $EditorPort 'jackdaw/wait' @{ until = $until } 1
        if ($r -and $r.result) {
            if ($until -eq 'idle' -and $r.result.idle) { return $true }
            if ($until -eq 'pie_running' -and "$($r.result.pie)" -eq 'running') { return $true }
        }
        Start-Sleep -Seconds 2
    }
    throw "wait($until) timed out after ${TimeoutSec}s"
}
$TKEY = 'bevy_transform::components::transform::Transform'
function Get-T($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) {
        return $e.components.PSObject.Properties[$TKEY].Value
    }
    return $e.components[$TKEY]
}
function Snap-Editor { (Brp $EditorPort 'jackdaw/scene_snapshot' @{}).result }
function Snap-Game   { (Brp $GamePort   'jackdaw/scene_snapshot' @{}).result }
# Any entity near a target x on a low y band.
function Find-AtX($snap, [double]$x, [double]$yLo, [double]$yHi, [double]$band) {
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if ($t) {
            $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
            if ([Math]::Abs($ex - $x) -lt $band -and $ey -ge $yLo -and $ey -le $yHi) { return $ey }
        }
    }
    return $null
}
function Y-At([double]$port, [double]$x, [double]$yLo, [double]$yHi) {
    $snap = if ($port -eq $GamePort) { Snap-Game } else { Snap-Editor }
    Find-AtX $snap $x $yLo $yHi 0.6
}

# --- boot ---------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$EditorPort"
$env:JACKDAW_WINDOW_SIZE  = '1600x900'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru `
    -RedirectStandardError  (Join-Path $OutDir 'live-editor-stderr.log') `
    -RedirectStandardOutput (Join-Path $OutDir 'live-editor-stdout.log')
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp $EditorPort 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died while booting' }
}
if (-not $ready) { throw 'editor BRP never answered' }
Wait-Until 'idle' 1800 | Out-Null
Start-Sleep -Seconds 15
Write-Host 'editor ready'

$sceneFile = Join-Path $Project 'assets\scene.bsn'
$sceneShaBefore = (Get-FileHash $sceneFile -Algorithm SHA256).Hash

# --- play ----------------------------------------------------------------
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Start-Sleep -Seconds 2
Op 'pie.play_current' | Out-Null
Wait-Until 'pie_running' 600 | Out-Null
Write-Host 'pie running'

# Game port alive?
$gameSnap = Snap-Game
Write-Host ("game-port entities: {0}" -f (@($gameSnap).Count))

# --- leg 1a: scene cube via the editor (Live mirror) ---------------------
Start-Sleep -Seconds 3
$e1 = Y-At $EditorPort 2.0 0.05 3.0
Start-Sleep -Seconds 1
$e2 = Y-At $EditorPort 2.0 0.05 3.0
Write-Host ("editor channel DroppingCube: y1={0} y2={1}" -f $e1, $e2)
if ($null -ne $e1 -and $null -ne $e2 -and [Math]::Abs($e2 - $e1) -lt 0.005 -and $e2 -ge 0.24 -and $e2 -le 0.40) {
    Write-Host 'LEG1A_EDITOR_CUBE_LANDS_PASS'
} else { Write-Host 'LEG1A_FAIL' }

# --- leg 1b: template cube via the game port -----------------------------
$g1 = Y-At $GamePort 0.0 0.05 3.0
Start-Sleep -Seconds 1
$g2 = Y-At $GamePort 0.0 0.05 3.0
Write-Host ("game channel template cube: y1={0} y2={1}" -f $g1, $g2)
if ($null -ne $g1 -and $null -ne $g2 -and [Math]::Abs($g2 - $g1) -lt 0.005 -and $g2 -ge 0.24 -and $g2 -le 0.40) {
    Write-Host 'LEG1B_GAME_CUBE_LANDS_PASS'
} else { Write-Host 'LEG1B_FAIL' }

# --- leg 2: pickup chain via the game port -------------------------------
function Player-Pickups {
    $snap = Snap-Game
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if ($t) {
            $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
            if ([Math]::Abs($ex - (-2.0)) -lt 1.0 -and [Math]::Abs($ey - 0.5) -lt 0.4) {
                $props = if ($e.components -is [System.Management.Automation.PSObject]) {
                    $e.components.PSObject.Properties
                } else { $e.components }
                foreach ($prop in $props) {
                    if ("$($prop.Name)" -like '*PickupCount') { return $prop.Value }
                }
            }
        }
    }
    return $null
}
Op 'pie.play_input_toggle' | Out-Null
Start-Sleep -Milliseconds 400
for ($leg = 0; $leg -lt 4; $leg++) {
    Op 'input.key' @{ key = 'KeyD'; action = 'press' } | Out-Null
    Start-Sleep -Milliseconds 250
    Op 'input.key' @{ key = 'KeyD'; action = 'release' } | Out-Null
    Start-Sleep -Milliseconds 700
}
$endCount = Player-Pickups
$countJson = $endCount | ConvertTo-Json -Compress
$countNum = if ("$countJson" -match '(\d+)') { [int]$Matches[1] } else { -1 }
Write-Host ("PickupCount after sweep: {0}" -f $countJson)
if ($countNum -ge 1) { Write-Host 'LEG2_PICKUP_CHAIN_PASS' }
else { Write-Host 'LEG2_FAIL' }

# --- stop: the authored scene is untouched --------------------------------
Op 'pie.stop' | Out-Null
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    $st = (Brp $EditorPort 'jackdaw/status' @{}).result.pie
    if ("$st" -eq 'stopped') { break }
    Start-Sleep -Milliseconds 300
}
Start-Sleep -Seconds 2
$sceneShaAfter = (Get-FileHash $sceneFile -Algorithm SHA256).Hash
if ($sceneShaBefore -eq $sceneShaAfter) { Write-Host 'STOP_SCENE_UNCHANGED_PASS' }
else { Write-Host 'STOP_SCENE_CHANGED_FAIL' }

Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host 'T10_T2_LIVE_DONE'
