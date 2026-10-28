# T09-T2 live: the five-item checklist (rebinding three states, capture
# lifecycle, gamepad reachability probe, PlayerMarker behavior, I3 mouse
# leg) against a fresh template project on this branch.
# Usage: powershell -NoProfile -File loop\qa\t09-t2-live.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'H:\workspace_AI\t09t2-live\t09t2-game'
$Port    = 15705
$OutDir  = Join-Path $Repo 'loop\t09t2-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Brp-Try([string]$method, $params, [int]$retries = 6) {
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
    throw "wait($until) timed out after ${TimeoutSec}s"
}
$TKEY = 'bevy_transform::components::transform::Transform'
# PowerShell 5.1: PSCustomObject has no string indexer; go through PSObject.
function Get-T($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) {
        return $e.components.PSObject.Properties[$TKEY].Value
    }
    return $e.components[$TKEY]
}
# The projected entity standing at (-2, 0.5, 0) is the template's
# PlayerMarker (the FallingCube spawns at (0, 3, 0), cameras elsewhere).
function Find-Player($snap) {
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if ($t) {
            $x = [double]$t.translation[0]; $y = [double]$t.translation[1]
            if ([Math]::Abs($x - (-2.0)) -lt 1.0 -and [Math]::Abs($y - 0.5) -lt 1.0) { return $e }
        }
    }
    return $null
}
function Sample-Player([int]$Seconds) {
    $a = Find-Player (Brp-Try 'jackdaw/scene_snapshot' @{}).result
    Start-Sleep -Seconds $Seconds
    $b = Find-Player (Brp-Try 'jackdaw/scene_snapshot' @{}).result
    if (-not $a -or -not $b) { return $null }
    $ta = Get-T $a; $tb = Get-T $b
    return @{
        dx = ([double]$tb.translation[0] - [double]$ta.translation[0])
        dz = ([double]$tb.translation[2] - [double]$ta.translation[2])
        ry = ([double]$tb.rotation[1]  - [double]$ta.rotation[1])
    }
}

# [3] Is there a physical gamepad on this machine at all?
$pads = @(Get-WmiObject Win32_GamePad -ErrorAction SilentlyContinue)
Write-Host ("ITEM3 gamepad devices present: " + $pads.Count)

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir 'editor-stdout.log') `
    -RedirectStandardError (Join-Path $OutDir 'editor-stderr.log') -PassThru
$proc.Id | Set-Content (Join-Path $OutDir 'editor.pid')
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died while booting' }
}
if (-not $ready) { throw 'editor BRP never answered' }
Wait-Until 'idle' 1800
Start-Sleep -Seconds 25
Write-Host 'editor ready (schema settled)'

# [1a] Create the rebinding through the editor's own asset flow. The
# schema watcher can land after idle (the earlier runs raced it), so
# poll for the kind instead of assuming it is there.
$configPath = Join-Path $Project 'assets\input-actions.bsn'
Remove-Item (Join-Path $Project 'assets\input-actions*.bsn') -ErrorAction SilentlyContinue
function New-InputAsset([string]$typeId) {
    $r = Op 'asset.new' @{ type = $typeId; name = 'input-actions' }
    if ($r -and "$($r.result.result)" -eq 'finished' -and -not $r.result.warnings) { return $r }
    return $null
}
$created = $null
for ($i = 0; $i -lt 40; $i++) {
    $created = New-InputAsset 'jackdaw_runtime::game_input::GameInputConfig'
    if (-not $created) { $created = New-InputAsset 'game_input_config' }
    if ($created) { break }
    Start-Sleep -Seconds 5
}
if (-not $created) {
    $list = Brp-Try 'jackdaw/call_operator' @{ id = 'asset.new_picker'; params = @{ path = 'assets' } }
    Write-Host ("kinds offered: " + ($list | ConvertTo-Json -Depth 6 -Compress))
    throw 'asset.new refused the GameInputConfig kind'
}
Write-Host 'ITEM1a asset.new GameInputConfig: ok'

# The rebinding itself: Move to the arrow keys + left stick at a 0.5
# deadzone, Jump to the left mouse button (serde enum shapes).
$rebind = Op 'asset.set' @{ field = 'actions'; value = '[{"name":"Move","kind":"Axis2D","bindings":[{"Key":"ArrowUp"},{"Key":"ArrowDown"},{"Key":"ArrowLeft"},{"Key":"ArrowRight"},{"GamepadAxis":{"axis":"LeftStickX","deadzone":0.5}}]},{"name":"Jump","kind":"Button","bindings":[{"MouseButton":"Left"}]}]' }
Write-Host ("ITEM1b asset.set actions: " + ($rebind | ConvertTo-Json -Depth 6 -Compress))
Op 'asset.save' @{} | Out-Null
Start-Sleep -Seconds 1
$onDisk = Get-Content $configPath -Raw -Encoding UTF8
Write-Host "input-actions.bsn on disk:`n$onDisk"
$diskOk = ($onDisk -match 'ArrowUp') -and ($onDisk -match 'LeftStickX') -and ($onDisk -match '0\.5')
Write-Host ("ITEM1c the rebinding landed on disk: " + $diskOk)
if (-not $diskOk) { throw 'the rebinding did not reach the file' }

# Play the current (empty) scene; the game spawns the PlayerMarker.
Op 'scene.new' @{} | Out-Null
Op 'scene.save' @{} | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' @{} | Out-Null
Wait-Until 'pie_running' 900
Start-Sleep -Seconds 3
$snapCount = @((Brp-Try 'jackdaw/scene_snapshot' @{}).result).Count
Write-Host ("projection entity count: " + $snapCount)

# [2a] Engage capture through the operator (the click path's twin).
$t1 = Op 'pie.play_input_toggle' @{}
Start-Sleep -Seconds 1
Write-Host ("ITEM2a capture engage: " + ($t1 | ConvertTo-Json -Depth 4 -Compress))

# [4] Behavior: the file's ArrowUp drives the marker; W does not.
Op 'input.key' @{ key = 'ArrowUp'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$moved = Sample-Player 2
Op 'input.key' @{ key = 'ArrowUp'; action = 'release' } | Out-Null
Write-Host ("ITEM4a ArrowUp held (2s): " + ($moved | ConvertTo-Json -Compress))
$item4 = ($moved -and [Math]::Abs($moved.dz) -gt 0.5)
Write-Host ("ITEM4a PlayerMarker moves on the file's binding: " + $item4)

Op 'input.key' @{ key = 'KeyW'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$wMoved = Sample-Player 2
Op 'input.key' @{ key = 'KeyW'; action = 'release' } | Out-Null
Write-Host ("ITEM4b W held (2s): " + ($wMoved | ConvertTo-Json -Compress))
$item1 = $item4 -and ($wMoved -and [Math]::Abs($wMoved.dz) -lt 0.1)
Write-Host ("ITEM4b/ITEM1d W no longer moves (the file's table won): " + ($wMoved -and [Math]::Abs($wMoved.dz) -lt 0.1))

# [5] I3 mouse leg: raw motion forwards to the game (Look drives yaw)
# while the editor's own bindings are suppressed by the capture. The
# baseline frame goes first: the gesture is over in under a second, so
# sampling must bracket it, not trail it.
$yawBefore = Find-Player (Brp-Try 'jackdaw/scene_snapshot' @{}).result
Op 'input.motion' @{ dx = 240; dy = 0; steps = 24 } | Out-Null
Start-Sleep -Seconds 2
$yawAfter = Find-Player (Brp-Try 'jackdaw/scene_snapshot' @{}).result
$dyaw = 999
if ($yawBefore -and $yawAfter) {
    $ta = Get-T $yawBefore; $tb = Get-T $yawAfter
    $dyaw = [double]$tb.rotation[1] - [double]$ta.rotation[1]
}
Write-Host ("ITEM5 motion dx=240: yaw delta = " + $dyaw)
$item5 = ([Math]::Abs($dyaw) -gt 0.001) -and ([Math]::Abs($dyaw) -lt 900)
Write-Host ("ITEM5 mouse motion reaches the game's Look: " + $item5)

# [2b] Release with the real chord (Shift+Esc through collect_forwards),
# the keyboard falls back to the editor, then re-engage and it works again.
Op 'input.key' @{ key = 'Escape'; mods = 'shift'; action = 'tap' } | Out-Null
Start-Sleep -Seconds 1
Op 'input.key' @{ key = 'ArrowUp'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$afterRelease = Sample-Player 2
Op 'input.key' @{ key = 'ArrowUp'; action = 'release' } | Out-Null
Write-Host ("ITEM2b after Shift+Esc, ArrowUp held: " + ($afterRelease | ConvertTo-Json -Compress))
$released = ($afterRelease -and [Math]::Abs($afterRelease.dz) -lt 0.1)
Write-Host ("ITEM2b release stops the forwarding: " + $released)

$t2 = Op 'pie.play_input_toggle' @{}
Start-Sleep -Seconds 1
Op 'input.key' @{ key = 'ArrowUp'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$reEngaged = Sample-Player 2
Op 'input.key' @{ key = 'ArrowUp'; action = 'release' } | Out-Null
Write-Host ("ITEM2c re-engaged, ArrowUp held: " + ($reEngaged | ConvertTo-Json -Compress))
$item2 = $released -and ($reEngaged -and [Math]::Abs($reEngaged.dz) -gt 0.5)
Write-Host ("ITEM2c re-engage resumes the forwarding: " + ($reEngaged -and [Math]::Abs($reEngaged.dz) -gt 0.5))

Op 'pie.stop' @{} | Out-Null
Wait-Until 'idle' 120

Write-Host ("CHECKLIST: item1(rebind3)={0} item2(capture)={1} item3(pad probe above) item4(marker)={2} item5(mouse)={3}" -f $item1, $item2, $item4, $item5)
Write-Output 'T09_T2_LIVE_DONE'
Stop-Process -Id $proc.Id -Force
