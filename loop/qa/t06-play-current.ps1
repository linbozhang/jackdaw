# T06-T1: "Play the current scene" live verification.
# Channel: any open scene (named, untitled/dirty) runs through the
# JACKDAW_PIE_SCENE override; evidence = editor launch log + the Live
# projection's scene_tree (structural, no camera needed) + screenshots.
# Decision 6 (dot-prefixed .jackdaw-pie temp copy loadable by the game's
# asset server) is proven by case A: an untitled scene whose only possible
# load path is the temp copy.
#
# Usage: powershell -NoProfile -File loop\qa\t06-play-current.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15713
$OutDir  = Join-Path $Repo 'loop\t06t1-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')

# ---------------------------------------------------------------- helpers --

function Kill-StaleEditors {
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
    }
    Start-Sleep -Milliseconds 500
}

function Start-Editor {
    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT  = "$Port"
    $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
    $env:PATH = "$deps;$env:PATH"
    $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
        -RedirectStandardOutput (Join-Path $OutDir 'editor-stdout.log') `
        -RedirectStandardError (Join-Path $OutDir 'editor-stderr.log') -PassThru
    $proc.Id | Set-Content (Join-Path $OutDir 'editor.pid')
    Wait-EditorReady -TimeoutSec 180
    Write-Host "editor ready pid=$($proc.Id)"
    $proc
}

function Op([string]$Id, $Params = @{}) {
    $p = @{ id = $Id }
    if ($Params.Count) { $p.params = $Params }
    Brp-Result (Brp-Call 'jackdaw/call_operator' $p)
}

function Wait-Idle([int]$TimeoutSec = 120) {
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec $TimeoutSec | Out-Null
    Write-Host 'editor idle'
}

function Wait-Running([int]$TimeoutSec = 900) {
    Wait-BrpResult 'jackdaw/wait' @{ until = 'pie_running' } -TimeoutSec $TimeoutSec | Out-Null
    Write-Host "pie running ($(Get-Date -Format HH:mm:ss))"
}

function Stop-Game([string]$Tag) {
    # The stop operator's availability gate needs PlayState != Stopped,
    # which flips when the child connects — a stop fired into that window
    # comes back cancelled. Retry once into the connected window.
    $pie = $null
    foreach ($attempt in 1..3) {
        Op 'pie.stop'
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $deadline) {
            $st = Brp-Result (Brp-Call 'jackdaw/status' @{})
            $pie = $st.pie
            if ($pie -eq 'stopped') { break }
            Start-Sleep -Milliseconds 200
        }
        if ($pie -eq 'stopped') { break }
        Start-Sleep -Seconds 2
    }
    if ($pie -ne 'stopped') {
        Write-Host "WARN: stop did not settle ($Tag): pie=$pie"
        $alive = Get-Process -Id $editor.Id -ErrorAction SilentlyContinue
        Write-Host ("  editor process: " + $(if ($alive) { "alive" } else { "DEAD" }))
        if ($alive) {
            try { Save-WindowScreenshot $alive.MainWindowHandle (Join-Path $OutDir "stop-hang-$Tag.png") | Out-Null } catch {}
        }
        throw "stop did not settle ($Tag)"
    }
    Write-Host 'pie stopped (status face)'
    Wait-Idle
}

function Count-Tree($Node) {
    $n = 1
    if ($Node.children) { foreach ($c in $Node.children) { $n += Count-Tree $c } }
    $n
}

function Collect-Names($Node, [ref]$Acc) {
    if ($Node.name) { $Acc.Value += $Node.name }
    if ($Node.children) { foreach ($c in $Node.children) { Collect-Names $c $Acc } }
}

function Live-TreeJson {
    # Every scene_tree node (count) and every named node, once the Live
    # projection is in.
    $r = Brp-Result (Brp-Call 'jackdaw/scene_tree' @{ depth = 8 })
    $count = 0
    $names = @()
    $acc = [ref]$names
    foreach ($node in $r.tree) {
        $count += Count-Tree $node
        Collect-Names $node $acc
    }
    @{ count = $count; names = $acc.Value }
}

function Count-OverrideLines {
    $log = Join-Path $OutDir 'editor-stderr.log'
    if (-not (Test-Path $log)) { return 0 }
    @((Get-Content $log) | Where-Object { $_ -match 'launched with scene override' }).Count
}

function Switch-View([string]$Label) {
    $t = Brp-Result (Brp-Call 'jackdaw/ui_tree' @{ text = $Label })
    if (-not $t.nodes -or $t.nodes.Count -eq 0) { throw "ui_tree found no '$Label' segment" }
    $target = [uint64]$t.nodes[0].entity
    Brp-Result (Brp-Call 'jackdaw/ui_click' @{ entity = $target }) | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "switched to $Label view (entity $target)"
}

function Switch-ToLive { Switch-View 'Live' }
function Switch-ToScene { Switch-View 'Scene' }

function Assert([bool]$Cond, [string]$What) {
    if (-not $Cond) { throw "ASSERT FAILED: $What" }
    Write-Host "  ok: $What"
}

function TempCopies {
    $dir = Join-Path $Project 'assets\.jackdaw-pie'
    if (-not (Test-Path $dir)) { return @() }
    @(Get-ChildItem $dir -Filter 'current-*.bsn' -ErrorAction SilentlyContinue)
}

# ------------------------------------------------------------------- main --

Kill-StaleEditors
# Clean probe leftovers from earlier runs.
TempCopies | Remove-Item -Force -ErrorAction SilentlyContinue
$probeScene = Join-Path $Project 'assets\pie-probe.bsn'
Remove-Item $probeScene -Force -ErrorAction SilentlyContinue

$editor = Start-Editor
Wait-Idle 600   # prebuild on open may compile the game (path-dep jackdaw_runtime)

try {
    # ---- Case A: an untitled scene runs from the temp copy (decision 6) --
    Write-Host '== case A: untitled scene -> temp copy =='
    Op 'scene.new'
    Start-Sleep -Milliseconds 500
    Op 'entity.add.cube' | Out-Null
    Start-Sleep -Seconds 1
    $tree = Live-TreeJson   # (Scene mode here: the authored preview)
    Assert ($tree.count -ge 1) "authored preview holds the new cube (count=$($tree.count))"

    Op 'pie.play_current'
    Wait-Running
    Start-Sleep -Seconds 3
    $alive = Get-Process -Id $editor.Id -ErrorAction SilentlyContinue
    Assert ($null -ne $alive) 'editor alive while playing an untitled scene'

    $copies = TempCopies
    Assert ($copies.Count -eq 1) "one temp run copy exists: $($copies.Name)"
    $copyText = Get-Content $copies[0].FullName -Raw
    Assert ($copyText -match 'Brush') 'the temp copy carries the cube document'

    # Decision 6: the game loaded the dot-prefixed copy — proven by the
    # Live projection holding exactly the probe content (1 cube + camera
    # default from scene.new), not the large startup scene.
    Switch-ToLive
    $live = Live-TreeJson
    Write-Host ("  live tree: count=" + $live.count + " names=[" + ($live.names -join ',') + "]")
    Assert ($live.count -le 8) "the game is playing the tiny probe scene, not scene.bsn (count=$($live.count))"
    Save-WindowScreenshot $editor.MainWindowHandle (Join-Path $OutDir 'A-playing-untitled.png') | Out-Null
    Switch-ToScene

    # keep the copy's document: it becomes the named probe scene for case B
    Copy-Item $copies[0].FullName $probeScene -Force

    Stop-Game 'A'
    Start-Sleep -Seconds 1
    Assert (@(TempCopies).Count -eq 0) 'stop removed the temp run copy'
    Write-Host '== case A done =='

    # ---- Case B: a named non-scene.bsn scene runs by path ---------------
    Write-Host '== case B: named scene (pie-probe.bsn) -> path override =='
    Op 'scene.open' @{ path = 'assets/pie-probe.bsn' }
    Start-Sleep -Seconds 2
    Op 'pie.play_current'
    Wait-Running
    Start-Sleep -Seconds 2
    $overridesAfterB = Count-OverrideLines
    Assert ($overridesAfterB -ge 1) "launch log records the override (count=$overridesAfterB)"
    $stderr = Get-Content (Join-Path $OutDir 'editor-stderr.log') -Raw
    Assert ($stderr -match "launched with scene override 'pie-probe\.bsn'") "the override names 'pie-probe.bsn'"
    Assert (@(TempCopies).Count -eq 0) 'a clean named scene writes no temp copy'

    Switch-ToLive
    $liveB = Live-TreeJson
    Write-Host ("  live tree: count=" + $liveB.count + " names=[" + ($liveB.names -join ',') + "]")
    Assert ($liveB.count -le 8) "the game plays pie-probe.bsn's content, not scene.bsn (count=$($liveB.count))"
    Save-WindowScreenshot $editor.MainWindowHandle (Join-Path $OutDir 'B-playing-named.png') | Out-Null
    Switch-ToScene
    Stop-Game 'B'
    Write-Host '== case B done =='

    # ---- Case C: the Ask dialog's three answers --------------------------
    Write-Host '== case C: ask policy dialog =='
    $probeBefore = Get-FileHash $probeScene   # the disk file must not move
    Op 'entity.add.cube' | Out-Null   # dirty the named probe
    Start-Sleep -Seconds 1
    Op 'project.set_save_before_play' @{ mode = 'ask' }
    Op 'pie.play_current'
    Start-Sleep -Seconds 1
    $dlg = Brp-Result (Brp-Call 'jackdaw/ui_tree' @{ text = 'Unsaved Scene' })
    Assert ($dlg.nodes -and $dlg.nodes.Count -ge 1) 'the Ask dialog is up'
    foreach ($label in @('Save', 'Play Unsaved Copy', 'Cancel')) {
        $row = Brp-Result (Brp-Call 'jackdaw/ui_tree' @{ text = $label })
        Assert ($row.nodes -and $row.nodes.Count -ge 1) "dialog answers include '$label'"
    }
    $copyBtn = Brp-Result (Brp-Call 'jackdaw/ui_tree' @{ text = 'Play Unsaved Copy' })
    Brp-Result (Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$copyBtn.nodes[0].entity }) | Out-Null
    Wait-Running
    $copiesC = TempCopies
    Assert ($copiesC.Count -eq 1) "the Copy answer runs from a temp copy: $($copiesC.Name)"
    $probeAfter = Get-FileHash $probeScene
    Assert ($probeAfter.Hash -eq $probeBefore.Hash) 'the disk file is unchanged (unsaved edit not written)'
    $overridesAfterC = Count-OverrideLines
    Assert ($overridesAfterC -eq ($overridesAfterB + 1)) "one more override launch (count=$overridesAfterC)"
    Save-WindowScreenshot $editor.MainWindowHandle (Join-Path $OutDir 'C-ask-copy.png') | Out-Null
    Stop-Game 'C'
    Write-Host '== case C done =='

    # ---- Case D: startup-scene play keeps the game's own scene ----------
    Write-Host '== case D: startup scene (pie.play) control =='
    Op 'pie.play'
    Wait-Running
    Start-Sleep -Seconds 3
    $overridesAfterD = Count-OverrideLines
    Assert ($overridesAfterD -eq $overridesAfterC) "startup play launches with no scene override (count=$overridesAfterD)"
    Switch-ToLive
    $liveD = Live-TreeJson
    Write-Host ("  live tree: count=" + $liveD.count)
    Assert ($liveD.count -gt 8) "the startup scene is the big scene.bsn (count=$($liveD.count))"
    Save-WindowScreenshot $editor.MainWindowHandle (Join-Path $OutDir 'D-startup-control.png') | Out-Null
    Switch-ToScene
    Stop-Game 'D'
    Write-Host '== case D done =='

    Write-Output 'T06T1_PLAY_CURRENT_LIVE_PASS'
} finally {
    Get-Process -Id $editor.Id -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "editor killed"
}
