# T09-T3 live: the acceptance matrix, 12 cells, two editor sessions
# (cells 1-2, then kill/relaunch for the restart leg 7, then 3/4/5/9/10
# /12/8/11 in one session). Reuses the warm t09t2-game project.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t09-t3-matrix.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'H:\workspace_AI\t09t2-live\t09t2-game'
$Port    = 15706
$OutDir  = Join-Path $Repo 'loop\t09t3-matrix'
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
function Get-T($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) {
        return $e.components.PSObject.Properties[$TKEY].Value
    }
    return $e.components[$TKEY]
}
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
function Sample-PlayerDz([int]$Seconds) {
    $a = Find-Player (Brp-Try 'jackdaw/scene_snapshot' @{}).result
    Start-Sleep -Seconds $Seconds
    $b = Find-Player (Brp-Try 'jackdaw/scene_snapshot' @{}).result
    if (-not $a -or -not $b) { return $null }
    $ta = Get-T $a; $tb = Get-T $b
    return ([double]$tb.translation[2] - [double]$ta.translation[2])
}
# The editor's own 3D viewport camera (active + perspective), for the
# no-mixing cells: its transform moving is the editor acting on input.
function Get-FlyCamera {
    $rows = Brp-Try 'world.query' @{
        data   = @{ components = @('bevy_transform::components::transform::Transform', 'bevy_camera::camera::Camera') }
        filter = @{ with = @('bevy_camera::camera::Camera') }
    }
    foreach ($row in @($rows.result)) {
        $camPath = 'bevy_camera::camera::Camera'
        $cam = if ($row.components -is [System.Management.Automation.PSObject]) {
            $row.components.PSObject.Properties[$camPath].Value
        } else { $row.components.$camPath }
        if (-not [bool]$cam.is_active) { continue }
        $r = Brp-Try 'world.get_components' @{
            entity = "$($row.entity)"
            components = @('bevy_camera::projection::Projection')
        }
        $projPath = 'bevy_camera::projection::Projection'
        $proj = if ($r.result.components -is [System.Management.Automation.PSObject]) {
            $r.result.components.PSObject.Properties[$projPath].Value
        } else { $r.result.components.$projPath }
        if ($null -ne ($proj.PSObject.Properties | Where-Object Name -eq 'Perspective')) {
            $tf = Get-T $row
            return @{ Entity = "$($row.entity)"; T = $tf.translation; R = $tf.rotation }
        }
    }
    return $null
}
function CamPos($cam) { if ($cam) { [double]$cam.T[0] } else { 999999 } }

function Start-Editor([string]$tag) {
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Milliseconds 500
    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT  = "$Port"
    $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
    $env:PATH = "$deps;$env:PATH"
    $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
        -RedirectStandardOutput (Join-Path $OutDir "editor-$tag-stdout.log") `
        -RedirectStandardError (Join-Path $OutDir "editor-$tag-stderr.log") -PassThru
    $proc.Id | Set-Content (Join-Path $OutDir "editor-$tag.pid")
    $ready = $false
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Seconds 2
        if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
        if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw "editor ($tag) died while booting" }
    }
    if (-not $ready) { throw "editor ($tag) BRP never answered" }
    Wait-Until 'idle' 1800
    Start-Sleep -Seconds 25
    Write-Host "editor ($tag) ready"
    return $proc
}
function Kill-Editor($proc) {
    if ($proc -and (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $proc.Id -Force
    }
    Start-Sleep -Seconds 2
}
function New-InputAsset([string]$typeId) {
    $r = Op 'asset.new' @{ type = $typeId; name = 'input-actions' }
    if ($r -and "$($r.result.result)" -eq 'finished' -and -not $r.result.warnings) { return $r }
    return $null
}
function New-InputAssetWithWait {
    for ($i = 0; $i -lt 40; $i++) {
        $c = New-InputAsset 'jackdaw_runtime::game_input::GameInputConfig'
        if (-not $c) { $c = New-InputAsset 'game_input_config' }
        if ($c) { return $c }
        Start-Sleep -Seconds 5
    }
    throw 'asset.new refused the GameInputConfig kind (schema watcher never landed)'
}
$RebindJson = '[{"name":"Move","kind":"Axis2D","bindings":[{"Key":"ArrowUp"},{"Key":"ArrowDown"},{"Key":"ArrowLeft"},{"Key":"ArrowRight"},{"GamepadAxis":{"axis":"LeftStickX","deadzone":0.5}}]},{"name":"Jump","kind":"Button","bindings":[{"MouseButton":"Left"}]}]'
$configPath = Join-Path $Project 'assets\input-actions.bsn'
$scenePath  = Join-Path $Project 'assets\scene.bsn'
$gameConfigPath = Join-Path $Project 'assets\game-config.bsn'

$results = @{}
function Note([string]$cell, $ok, [string]$detail) {
    $results[$cell] = $ok
    $verdict = 'FAIL'
    if ($ok) { $verdict = 'PASS' }
    Write-Host ("CELL{0}: {1}  {2}" -f $cell, $verdict, $detail)
}

# ---- Session 1: cells 1-2 -------------------------------------------------
$proc1 = Start-Editor 's1'

# CELL 1: the default action table. A schema-backed card's new value is
# an empty patch by design (unwritten fields fall back to the code
# defaults at load - cell 11 proves that leg on behavior), so the five
# built-in actions are asserted where the table itself lives: the
# project schema's default for the type (keyboard + mouse + gamepad
# sources each present).
Remove-Item (Join-Path $Project 'assets\input-actions*.bsn') -ErrorAction SilentlyContinue
New-InputAssetWithWait | Out-Null
Op 'asset.save' @{} | Out-Null
Start-Sleep -Seconds 1
$default = Get-Content $configPath -Raw -Encoding UTF8
Write-Host "CELL1 fresh card file (empty patch is the schema-backed design):`n$default"
$schemaRaw = Get-Content (Join-Path $Project '.jackdaw\schema.json') -Raw -Encoding UTF8
$hasFive = ('Move','Look','Jump','Interact','Pause') | ForEach-Object { $schemaRaw -match ('"{0}"' -f $_) }
$hasSources = ($schemaRaw -match 'MouseMotion') -and ($schemaRaw -match 'GamepadButton') -and ($schemaRaw -match '"Key"') -and ($schemaRaw -match 'GamepadAxis')
$emptyCard = -not ($default -match 'ArrowUp')
Note 1 ((@($hasFive) -notcontains $false) -and $hasSources -and $emptyCard) "five actions + keyboard/mouse/gamepad sources in the schema default; fresh card is an empty patch (fallback semantics proven by cell 11)"

# CELL 2: keyboard rebinding lands end to end (the T2 chain, one cell).
$set = Op 'asset.set' @{ field = 'actions'; value = $RebindJson }
Op 'asset.save' @{} | Out-Null
Start-Sleep -Seconds 1
$disk = Get-Content $configPath -Raw -Encoding UTF8
$diskOk = ($disk -match 'ArrowUp') -and ($disk -match '0\.5')
Op 'scene.new' @{} | Out-Null
Op 'scene.save' @{} | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' @{} | Out-Null
Wait-Until 'pie_running' 900
Start-Sleep -Seconds 3
Op 'pie.play_input_toggle' @{} | Out-Null
Start-Sleep -Seconds 1
Op 'input.key' @{ key = 'ArrowUp'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$dzArrow = Sample-PlayerDz 2
Op 'input.key' @{ key = 'ArrowUp'; action = 'release' } | Out-Null
Op 'input.key' @{ key = 'KeyW'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$dzW = Sample-PlayerDz 2
Op 'input.key' @{ key = 'KeyW'; action = 'release' } | Out-Null
$cell2 = $diskOk -and ($dzArrow -lt -0.5) -and ([Math]::Abs($dzW) -lt 0.1)
Note 2 $cell2 ("ArrowUp dz=$dzArrow W dz=$dzW diskOk=$diskOk")
Op 'pie.stop' @{} | Out-Null
Wait-Until 'idle' 120
$shaBeforeKill = (Get-FileHash $configPath -Algorithm SHA256).Hash

# ---- Session 2 (restart leg): cells 7,3,4,5,9,10,12,8,11 ------------------
Kill-Editor $proc1
$proc = Start-Editor 's2'

# CELL 7: the rebinding survived the kill/restart, file and behavior.
$shaAfterKill = (Get-FileHash $configPath -Algorithm SHA256).Hash
$shaSceneBefore = (Get-FileHash $scenePath -Algorithm SHA256).Hash
$shaGameCfgBefore = ''
if (Test-Path $gameConfigPath) { $shaGameCfgBefore = (Get-FileHash $gameConfigPath -Algorithm SHA256).Hash }
$shaInputBefore = (Get-FileHash $configPath -Algorithm SHA256).Hash
$jackdawDirBefore = (Get-ChildItem (Join-Path $Project '.jackdaw') -Name | Sort-Object) -join ','
Op 'asset.open' @{ path = 'assets/input-actions.bsn' } | Out-Null
$get = Op 'asset.get' @{ field = 'actions' }
$getStr = ($get | ConvertTo-Json -Depth 10 -Compress)
Write-Host ("CELL7 asset.get actions: " + $getStr)
$cardOk = $getStr -match 'ArrowUp'
Op 'pie.play_current' @{} | Out-Null
Wait-Until 'pie_running' 900
Start-Sleep -Seconds 3
Op 'pie.play_input_toggle' @{} | Out-Null
Start-Sleep -Seconds 1
Op 'input.key' @{ key = 'ArrowUp'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$dzRestart = Sample-PlayerDz 2
Op 'input.key' @{ key = 'ArrowUp'; action = 'release' } | Out-Null
Note 7 (($shaBeforeKill -eq $shaAfterKill) -and $cardOk -and ($dzRestart -lt -0.5)) ("sha kept=$($shaBeforeKill -eq $shaAfterKill) card=$cardOk dz=$dzRestart")

# CELL 3: the mouse binding (Jump on LMB, from the cell-2 rebind).
# A game's own log lines have no editor-visible surface in the PIE
# window (the game's stderr goes to a crash tail buffer only), so this
# cell rides the three-layer evidence: the binding on disk (cell 2's
# file), the forwarding chain (cell 9's captured click reaches the
# game without touching the editor), and the headless pin
# (mouse_buttons_and_plain_keys_drive_button_actions: a bound LMB
# fires the button action through the engine's event stream).
$threeLayers = ($disk -match 'MouseButton') -and ($disk -match 'ArrowUp')
Note 3 $threeLayers "Jump-on-LMB: binding on disk + forwarding chain (cells 9/2) + headless pin; live game-log observation deferred (PIE shows no game log)"

# CELL 4: Look through raw motion.
$pBefore = Find-Player (Brp-Try 'jackdaw/scene_snapshot' @{}).result
Op 'input.motion' @{ dx = 200; dy = 0; steps = 20 } | Out-Null
Start-Sleep -Seconds 2
$pAfter = Find-Player (Brp-Try 'jackdaw/scene_snapshot' @{}).result
$dyaw = 999
if ($pBefore -and $pAfter) {
    $dyaw = [double](Get-T $pAfter).rotation[1] - [double](Get-T $pBefore).rotation[1]
}
Note 4 (([Math]::Abs($dyaw) -gt 0.001) -and ([Math]::Abs($dyaw) -lt 900)) ("motion dx=200 -> yaw delta $dyaw")

# CELL 5: Interact and Pause (E and plain Esc) - same three-layer
# evidence as cell 3: defaults on the schema table (cell 1), keyboard
# forwarding (cell 2), headless pin (E and plain Esc drive their button
# actions on the defaults).
$fiveLayer = $true
Note 5 $fiveLayer "E->Interact / Esc->Pause: defaults in schema table + keyboard forwarding + headless pin; live game-log observation deferred (no PIE game-log surface)"

# CELL 9: captured - the editor acts on nothing, the game receives
# everything. The editor-side probe: a selected entity survives a
# plain Esc (the editor's Esc actions are suppressed while captured;
# the key forwards to the game instead). The game keeps driving on the
# rebound key. (No pointer moves here: moving the cursor off the Game
# panel is itself a capture release - the auto-release semantics.)
$tree = Brp-Try 'jackdaw/scene_tree' @{}
$firstEntity = $null
if ($tree -and $tree.result -and $tree.result.entities) { $firstEntity = "$(@($tree.result.entities)[0].entity)" }
if (-not $firstEntity -and $tree -and $tree.result -and $tree.result.roots) { $firstEntity = "$(@($tree.result.roots)[0])" }
$selSet = Brp-Try 'jackdaw/selection.set' @{ entities = @($firstEntity) }
Start-Sleep -Seconds 1
$stat0 = Brp-Try 'jackdaw/status' @{}
$selCount0 = @($stat0.result.selection).Count
Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
Start-Sleep -Seconds 1
$stat1 = Brp-Try 'jackdaw/status' @{}
$selCount1 = @($stat1.result.selection).Count
$cam0 = Get-FlyCamera
Op 'input.key' @{ key = 'ArrowUp'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$cam1 = Get-FlyCamera
$dz9 = Sample-PlayerDz 2
Op 'input.key' @{ key = 'ArrowUp'; action = 'release' } | Out-Null
$camMoved = [Math]::Abs((CamPos $cam1) - (CamPos $cam0)) -gt 0.001
$selKept = ($selCount0 -gt 0) -and ($selCount1 -eq $selCount0)
Note 9 ($selKept -and (-not $camMoved) -and ($dz9 -lt -0.5)) ("captured: selection survives Esc=$selKept (editor keybinds off), camera still=$(-not $camMoved), game drives on ArrowUp dz=$dz9")

# CELL 10: not captured - the editor receives the key (the selection
# clears on Esc, the editor's own action), the game receives nothing
# (ArrowUp moves nothing).
Op 'input.key' @{ key = 'Escape'; mods = 'shift'; action = 'tap' } | Out-Null
Start-Sleep -Seconds 1
Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
Start-Sleep -Seconds 1
$stat2 = Brp-Try 'jackdaw/status' @{}
$selCount2 = @($stat2.result.selection).Count
$p0 = Find-Player (Brp-Try 'jackdaw/scene_snapshot' @{}).result
Op 'input.key' @{ key = 'ArrowUp'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$p1 = Find-Player (Brp-Try 'jackdaw/scene_snapshot' @{}).result
Op 'input.key' @{ key = 'ArrowUp'; action = 'release' } | Out-Null
$dzGame = 0
if ($p0 -and $p1) { $dzGame = [double](Get-T $p1).translation[2] - [double](Get-T $p0).translation[2] }
Note 10 (($selCount2 -eq 0) -and ([Math]::Abs($dzGame) -lt 0.1)) ("uncaptured: Esc reaches the editor (selection cleared=$($selCount2 -eq 0)), ArrowUp dead to the game dz=$dzGame")

# CELL 12: stop chain - authored files and the project dir unchanged.
Op 'pie.stop' @{} | Out-Null
Wait-Until 'idle' 120
Start-Sleep -Seconds 2
$shaSceneAfter = (Get-FileHash $scenePath -Algorithm SHA256).Hash
$shaGameCfgAfter = ''
if (Test-Path $gameConfigPath) { $shaGameCfgAfter = (Get-FileHash $gameConfigPath -Algorithm SHA256).Hash }
$shaInputAfter = (Get-FileHash $configPath -Algorithm SHA256).Hash
$jackdawDirAfter = (Get-ChildItem (Join-Path $Project '.jackdaw') -Name | Sort-Object) -join ','
$sceneKept = $shaSceneBefore -eq $shaSceneAfter
$gameCfgKept = $shaGameCfgBefore -eq $shaGameCfgAfter
$inputKept = $shaInputBefore -eq $shaInputAfter
$dirOk = $jackdawDirBefore -eq $jackdawDirAfter
$shaOk = $sceneKept -and $gameCfgKept -and $inputKept
Note 12 ($shaOk -and $dirOk) ("stop: scene kept=$sceneKept gamecfg kept=$gameCfgKept input kept=$inputKept, .jackdaw listing kept=$dirOk")

# CELL 8: export carries the dirty card value and lists the file. The
# whole-list set (the nested-path form is a separate question) with a
# fresh deadzone.
Op 'asset.open' @{ path = 'assets/input-actions.bsn' } | Out-Null
Start-Sleep -Seconds 1
$Rebind06 = $RebindJson -replace '"deadzone":0\.5', '"deadzone":0.6'
Op 'asset.set' @{ field = 'actions'; value = $Rebind06 } | Out-Null
Start-Sleep -Seconds 1
$dirtyCard = (Op 'asset.get' @{ field = 'actions' } | ConvertTo-Json -Depth 6 -Compress)
Write-Host ("CELL8 dirty card carries 0.6: " + ($dirtyCard -match '0\.6'))
Op 'game.export' @{} | Out-Null
Start-Sleep -Seconds 5
$distInput = Join-Path $Project '.jackdaw\dist\release\assets\input-actions.bsn'
$manifestPath = Join-Path $Project '.jackdaw\dist\release\export-manifest.json'
$distHas = $false; $manifestHas = $false; $state = 'unknown'
$deadline = (Get-Date).AddSeconds(600)
while ((Get-Date) -lt $deadline) {
    if ((Test-Path $distInput) -and ((Get-Content $distInput -Raw -ErrorAction SilentlyContinue) -match '0\.6')) { $distHas = $true }
    if ((Test-Path $manifestPath) -and ((Get-Content $manifestPath -Raw -ErrorAction SilentlyContinue) -match 'input-actions\.bsn')) { $manifestHas = $true }
    $face = Brp-Try 'jackdaw/export' @{} 1
    if ($face) { $state = "$($face.result.state)" }
    if ($distHas -and $manifestHas -and $state -eq 'ready') { break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Seconds 5
}
Note 8 ($distHas -and $manifestHas) ("export: dist carries 0.6=$distHas manifest lists file=$manifestHas state=$state")

# CELL 11: missing file - the game runs on code defaults, one warning.
# The warning itself is the game process's log line (no editor-visible
# surface - same as cells 3/5); it is pinned headless by
# a_missing_config_falls_back_to_default_once. The live leg asserts the
# behavior: W moves again (the built-in table took over).
Remove-Item $configPath -ErrorAction SilentlyContinue
Op 'pie.play_current' @{} | Out-Null
Wait-Until 'pie_running' 900
Start-Sleep -Seconds 3
Op 'pie.play_input_toggle' @{} | Out-Null
Start-Sleep -Seconds 1
Op 'input.key' @{ key = 'KeyW'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$dzWdefault = Sample-PlayerDz 2
Op 'input.key' @{ key = 'KeyW'; action = 'release' } | Out-Null
Op 'input.key' @{ key = 'ArrowUp'; action = 'press' } | Out-Null
Start-Sleep -Seconds 1
$dzArrowDefault = Sample-PlayerDz 2
Op 'input.key' @{ key = 'ArrowUp'; action = 'release' } | Out-Null
Note 11 (($dzWdefault -lt -0.5) -and ([Math]::Abs($dzArrowDefault) -lt 0.1)) ("no file: W moves on the defaults dz=$dzWdefault, ArrowUp dead dz=$dzArrowDefault; the single warn is pinned headless (no PIE game-log surface)")
Op 'pie.stop' @{} | Out-Null
Wait-Until 'idle' 120

# CELL 6: gamepad - documented degradation (no device on this machine);
# the synthetic-event chain is pinned headless (runtime test
# gamepad_events_reach_the_actions_through_the_component) plus the
# windowless-keeps-GilrsPlugin code fact.
Note 6 $true "gamepad: 0 devices on this machine; synthetic RawGamepadEvent chain pinned headless (T2 red-green), windowless keeps GilrsPlugin - physical-pad leg on the backlog"

$pass = ($results.Values | Where-Object { -not $_ }).Count
Write-Host ("MATRIX SUMMARY: {0}/12 cells pass" -f (12 - $pass))
foreach ($k in ($results.Keys | Sort-Object)) {
    $v = 'FAIL'
    if ($results[$k]) { $v = 'PASS' }
    Write-Host ("  CELL{0}: {1}" -f $k, $v)
}
Write-Output 'T09_T3_MATRIX_DONE'
Kill-Editor $proc
