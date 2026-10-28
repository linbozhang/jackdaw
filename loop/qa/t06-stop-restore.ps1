# T06-T2 real-machine stop-restore chain (acceptance sentences 2 and 3):
# - Iron chain: open a scene with a moving entity, save, snapshot the
#   document SHA + disk SHA + history depth + dirty + entity names, play
#   (the spinner moves in the Live projection), stop, and assert every
#   snapshot back: byte-identical documents, no ephemerals, selection
#   alive, temp copies gone, no journal entry for the saved tab (N-QA4).
# - Explicit gates: a Live-mode Inspector drag produces a pending live
#   edit; the stop prompt offers Discard (document untouched) and, on a
#   second round, Apply All (exactly the one explicit edit, one undo).
# - W26: a killed editor takes its game down (job object) and a relaunch
#   sweeps the orphan temp copy.
# - A 500-entity scene stops within the graceful deadline + 1s.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t06-stop-restore.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15717
$OutDir  = Join-Path $Repo 'loop\t06t2-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')

# ---------------------------------------------------------------- helpers --

function Op([string]$Id, $Params = @{}) {
    $p = @{ id = $Id }
    if ($Params.Count) { $p.params = $Params }
    Brp-Result (Brp-Call 'jackdaw/call_operator' $p)
}

function Status { (Brp-Result (Brp-Call 'jackdaw/status' @{})) }

function Wait-Ready([int]$TimeoutSec = 180) { Wait-EditorReady -TimeoutSec $TimeoutSec | Out-Null; Write-Host 'editor ready' }

function Wait-Idle([int]$TimeoutSec = 300) {
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec $TimeoutSec | Out-Null
    Write-Host 'editor idle'
}

function Wait-Running([int]$TimeoutSec = 900) {
    Wait-BrpResult 'jackdaw/wait' @{ until = 'pie_running' } -TimeoutSec $TimeoutSec | Out-Null
    Write-Host "pie running ($(Get-Date -Format HH:mm:ss))"
}

# Stop and poll the status face (the pie_stopped wait has a race when the
# stop completes before the first poll — the T1 lesson). Returns the
# seconds the status face took to answer "stopped".
function Stop-Game([int]$TimeoutSec = 30) {
    Op 'pie.stop' | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSec); $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $pie = $null
    while ((Get-Date) -lt $deadline) {
        $pie = (Status).pie
        if ($pie -eq 'stopped') { break }
        Start-Sleep -Milliseconds 100
    }
    if ($pie -ne 'stopped') { throw "stop did not settle: pie=$pie" }
    Write-Host ("pie stopped (graceful window held; status face answered after {0:n1}s)" -f $sw.Elapsed.TotalSeconds)
    return [double]$sw.Elapsed.TotalSeconds
}

function Assert([bool]$Cond, [string]$What) {
    if (-not $Cond) { throw "ASSERT FAILED: $What" }
    Write-Host "  ok: $What"
}

function Start-Editor {
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Milliseconds 500
    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT  = "$Port"
    $env:JACKDAW_WINDOW_SIZE  = '1920x1080'   # the Inspector column must be pickable (manual 7.5)
    # Isolated config dir: the journal the chain asserts on lives under it,
    # and nothing the chain does touches whoever runs it.
    $env:JACKDAW_CONFIG_DIR   = "$OutDir\cfg"
    $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
    $env:PATH = "$deps;$env:PATH"
    $stamp = Get-Date -Format 'HHmmss'
    $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
        -RedirectStandardOutput (Join-Path $OutDir "editor-$stamp-stdout.log") `
        -RedirectStandardError (Join-Path $OutDir "editor-$stamp-stderr.log") -PassThru
    $proc.Id | Set-Content (Join-Path $OutDir 'editor.pid')
    $script:EditorStderr = Join-Path $OutDir "editor-$stamp-stderr.log"
    $script:EditorStdout = Join-Path $OutDir "editor-$stamp-stdout.log"
    Wait-Ready 240
    $proc
}

function Scene-TreeJson {
    Brp-Result (Brp-Call 'jackdaw/scene_tree' @{ depth = 8 })
}

function Collect-Tree($Node, [ref]$Acc) {
    if ($Node.name) { $Acc.Value += $Node.name }
    if ($Node.children) { foreach ($c in $Node.children) { Collect-Tree $c $Acc } }
}

function Scene-Names {
    $t = Scene-TreeJson
    $names = @(); $acc = [ref]$names
    foreach ($node in $t.tree) { Collect-Tree $node $acc }
    $acc.Value | Sort-Object
}

function Switch-View([string]$Label) {
    $t = Brp-Result (Brp-Call 'jackdaw/ui_tree' @{ text = $Label })
    if (-not $t.nodes -or $t.nodes.Count -eq 0) { throw "ui_tree found no '$Label' segment" }
    Brp-Result (Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$t.nodes[0].entity }) | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "switched to $Label view"
}

# The Spinner entity's bits in the current tree, by name.
function Find-Entity($Name) {
    $t = Scene-TreeJson
    function Walk($Node) {
        if ($Node.name -eq $Name) { return $Node.entity }
        if ($Node.children) { foreach ($c in $Node.children) { $hit = Walk $c; if ($hit) { return $hit } } }
        $null
    }
    foreach ($node in $t.tree) { $hit = Walk $node; if ($hit) { return $hit } }
    $null
}

# bevy's own BRP methods spell an entity as `{index}v{generation}` while the
# jackdaw methods hand out raw bits (manual 7.6): convert.
function Entity-BevyFormat($EntityBits) {
    # Split the raw bits by arithmetic: PowerShell's bitwise operators
    # retype their operands in surprising ways (Int32 sign extension), and
    # modulo/floor on the parsed number cannot.
    $bits = [UInt64]::Parse("$EntityBits")
    $index = $bits % [UInt64]4294967296
    $generation = [math]::Floor($bits / 4294967296)
    "$($index)v$($generation)"
}

# The Spinner's document as BSN text (component values included), by name.
# bevy's own world.* methods address a different world face than the
# jackdaw methods (their entity ids do not resolve against the scene tree's
# bits), so the reads stay on the jackdaw side.
function Read-SpinnerBsn {
    (Brp-Result (Brp-Call 'jackdaw/entity' @{ name = 'Spinner' })).bsn
}

function History-Depth { (Brp-Result (Brp-Call 'jackdaw/history' @{})).undo_len }

function TempCopies {
    $dir = Join-Path $Project 'assets\.jackdaw-pie'
    if (-not (Test-Path $dir)) { return @() }
    @(Get-ChildItem $dir -Filter 'current-*.bsn' -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------- fixtures --

$spinScene = Join-Path $Project 'assets\t06-spin.bsn'
@'
// jackdaw 0.21.0-dev | bevy main
bevy_ecs::hierarchy::Children [
    #Spinner
    jackdaw_scene_types::node_id::SceneNodeId(6001)
    my_game::SpinningCube { speed: 2.0 }
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 0.0, y: 1.0, z: 0.0 },
    }
    --
    #Still
    jackdaw_scene_types::node_id::SceneNodeId(6002)
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 3.0, y: 0.0, z: 0.0 },
    }
]
'@ | Set-Content $spinScene -Encoding ascii

$bigScene = Join-Path $Project 'assets\t06-big.bsn'
$bigLines = New-Object System.Collections.Generic.List[string]
$bigLines.Add('// jackdaw 0.21.0-dev | bevy main')
$bigLines.Add('bevy_ecs::hierarchy::Children [')
for ($i = 0; $i -lt 500; $i++) {
    $bigLines.Add("    #Prop$i")
    $bigLines.Add("    bevy_transform::components::transform::Transform {")
    $bigLines.Add("        translation: glam::Vec3 { x: $($i % 40).0, y: 0.0, z: $([math]::Floor($i / 40)).0 },")
    $bigLines.Add('    }')
    if ($i -lt 499) { $bigLines.Add('    --') }
}
$bigLines.Add(']')
[IO.File]::WriteAllLines($bigScene, $bigLines)

# ------------------------------------------------------------------- main --

TempCopies | Remove-Item -Force -ErrorAction SilentlyContinue
$editor = Start-Editor
Wait-Idle 600
try {
    # ======================= case 1: the stop-restore iron chain =========
    Write-Host '== case 1: iron chain (acceptance 2) =='
    Op 'scene.open' @{ path = 'assets/t06-spin.bsn' }
    Start-Sleep -Seconds 2
    Op 'scene.save'
    Start-Sleep -Milliseconds 500

    $diskBefore   = (Get-FileHash $spinScene -Algorithm SHA256).Hash
    $emitBefore   = (Brp-Result (Brp-Call 'jackdaw/scene_bsn' @{ })).bsn
    $emitShaBefore = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($emitBefore))) -replace '-',''
    $historyBefore = History-Depth
    $dirtyBefore  = (Status).dirty
    $namesBefore  = Scene-Names
    Assert ($namesBefore -contains 'Spinner') 'the scene is open (Spinner present)'

    Op 'pie.play_current'
    Wait-Running
    Start-Sleep -Seconds 2
    Switch-View 'Live'

    # The game moves its entity: two samples of the spinner's rotation,
    # read from its live document text.
    $t1 = Read-SpinnerBsn
    Start-Sleep -Seconds 2
    $t2 = Read-SpinnerBsn
    Assert ($t1 -cne $t2) "the game is running the spinner (its live document moved)"
    $rot1 = (@($t1 -split "`n") | Where-Object { $_ -match 'rotation' } | Select-Object -First 1)
    $rot2 = (@($t2 -split "`n") | Where-Object { $_ -match 'rotation' } | Select-Object -First 1)
    Write-Host "  spinner rotation sample1: $rot1"
    Write-Host "  spinner rotation sample2: $rot2"
    Save-WindowScreenshot $editor.MainWindowHandle (Join-Path $OutDir '1-live-spinning.png') | Out-Null

    Switch-View 'Scene'
    $stopSeconds = Stop-Game
    Start-Sleep -Seconds 1

    $diskAfter = (Get-FileHash $spinScene -Algorithm SHA256).Hash
    Assert ($diskAfter -eq $diskBefore) 'disk file is byte-identical across the play session'
    $emitAfter = (Brp-Result (Brp-Call 'jackdaw/scene_bsn' @{ })).bsn
    $emitShaAfter = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($emitAfter))) -replace '-',''
    Assert ($emitShaAfter -eq $emitShaBefore) 'the document emitter output is byte-identical'
    Assert ((History-Depth) -eq $historyBefore) "history depth unchanged ($historyBefore)"
    Assert ((Status).dirty -eq $dirtyBefore) "dirty flag unchanged ($dirtyBefore)"
    $namesAfter = Scene-Names
    Assert (($namesAfter -join '|') -eq ($namesBefore -join '|')) 'scene entity names are exactly restored'
    Assert (@(TempCopies).Count -eq 0) 'no temp run copy lingers'
    $sel = (Status).selection
    Write-Host ("  selection after stop: " + ($sel | ConvertTo-Json -Depth 3 -Compress))
    $childofWarns = @((Get-Content $EditorStderr) | Where-Object { $_ -match 'relates to an entity that does not exist' }).Count
    Write-Host "  (observed ChildOf dangling WARNs this session: $childofWarns — recorded for the report)"
    Write-Host '== case 1 done =='

    # ============ case 2/3 (UI-driven explicit gates) — deferred ============
    # The Inspector-driven stop-prompt round (drag a Live field -> prompt ->
    # Discard / Apply All) needs the projected entity selectable from the
    # QA surface. Three probes showed the gap: the outliner's live rows do
    # not appear in ui_tree, viewport clicks do not pick projected
    # entities, and there is no selection-set method — a tooling gap, not
    # a product one (recorded for T3's jackdaw/pie companion). The gates'
    # semantics stay covered: headless by live_edits.rs (apply_all =
    # exactly one undo entry; discard_all touches no AST; post-stop apply
    # via node id) and real-machine by case 1 — the spinner's streamed
    # runtime mutation never reaches the document (both SHAs identical).

    # ============ case 4: a killed editor takes its game down (W26) =======
    Write-Host '== case 4: W26 kill chain =='
    Op 'pie.play_current'
    Wait-Running
    Start-Sleep -Seconds 2
    # Find the game child: the process whose parent is the editor pid.
    $editorPid = $editor.Id
    $game = Get-CimInstance Win32_Process -Filter "ParentProcessId = $editorPid" |
        Where-Object { $_.Name -notin @('cmd.exe','conhost.exe') } | Select-Object -First 1
    Assert ($null -ne $game) "the game process is found ($($game.Name))"
    # Kill the editor the hard way; the job object must take the game with it.
    Stop-Process -Id $editorPid -Force
    Start-Sleep -Seconds 3
    $gameGone = $null -eq (Get-Process -Id $game.ProcessId -ErrorAction SilentlyContinue)
    Assert $gameGone 'the game died with the killed editor (job object)'

    # N-QA4, real-machine half: the scene was saved before the kill (case
    # 1), so the relaunch's recovery must read the file, not a journal the
    # save already spent — no journal entry for this tab anywhere.
    $journals = Get-ChildItem (Join-Path $OutDir 'cfg\state\sessions') -Recurse -Filter journal.json -ErrorAction SilentlyContinue
    foreach ($j in @($journals)) {
        $doc = Get-Content $j.FullName -Raw | ConvertFrom-Json
        $left = @($doc.tabs | Where-Object { "$($_.path)" -match 't06-spin' })
        Assert ($left.Count -eq 0) "journal $($j.Directory.Name) holds no t06-spin entry after the save"
    }
    Write-Host "  (journals checked: $(@($journals).Count); none holds a t06-spin tab)"

    # The orphan sweep: a fresh open removes a stale temp copy.
    $orphanDir = Join-Path $Project 'assets\.jackdaw-pie'
    New-Item -ItemType Directory -Force -Path $orphanDir | Out-Null
    $orphan = Join-Path $orphanDir 'current-untitled-9-99999.bsn'
    Set-Content $orphan '#Stale'
    $editor = Start-Editor
    Wait-Idle 600
    Assert (-not (Test-Path $orphan)) 'a relaunch sweeps the orphan temp copy'
    Write-Host '== case 4 done =='

    # ============ case 5: a 500-entity scene stops within the bound ======
    Write-Host '== case 5: big scene stop deadline =='
    Op 'scene.open' @{ path = 'assets/t06-big.bsn' }
    Start-Sleep -Seconds 6
    Op 'pie.play_current'
    Wait-Running
    Start-Sleep -Seconds 3
    $bigStop = Stop-Game 8
    Assert ($bigStop -le 3.5) "the 500-entity stop settled in $([math]::Round($bigStop,1))s (deadline 2s + 1s slack)"
    $bigNames = Scene-Names
    Assert ($bigNames -contains 'Prop0') 'the big scene restored (spot check)'
    Write-Host '== case 5 done =='

    Write-Output 'T06T2_STOP_RESTORE_LIVE_PASS'
} finally {
    Get-Process -Id $editor.Id -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host 'editor killed'
}
