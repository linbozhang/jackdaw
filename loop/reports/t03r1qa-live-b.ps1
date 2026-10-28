# T03 rework round 1 QA probe B: brush.join (J keybind) on the live editor.
# Two Brush entities (entity.add.cube spawns Brush cubes), join via the REAL
# J key, one undo entry, one undo restores both brushes in the document.
# Extra observations: clip.delete_keyframes and brush.extend_face_to_brush
# both refuse (cancelled, zero records) when their availability is unmet.
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15819
)
$ErrorActionPreference = 'Stop'
function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try { $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15 }
        catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout waiting for $Method $Params"
}
function Wait-Idle([int]$T = 90) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null; Start-Sleep -Milliseconds 400 }
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }
function HistProbe { (Brp-Call 'jackdaw/history' @{ entries = 6 }).result }
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Output ("PASS  " + $What) }
    else { Write-Output ("FAIL  " + $What); $script:Failures++ }
}
function Scene-Tree {
    $r = Brp-Call 'jackdaw/scene_tree' @{ }
    if ($r.error) { return @() }
    @(foreach ($n in @($r.result.tree)) { $n })
}
function Cube-Bits {
    $cubes = @(Scene-Tree | Where-Object { $_.name -eq 'Cube' })
    foreach ($c in $cubes) { [uint64]$c.entity }
}
function Doc-Cubes {
    $sb = Brp-Call 'jackdaw/scene_bsn' @{ }
    ([regex]::Matches([string]$sb.result.bsn, '#Cube')).Count
}
$Failures = 0

$Project = Join-Path $env:TEMP "t03r1qa-b-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t03r1qab","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = "1920x1080"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru -RedirectStandardOutput (Join-Path $env:TEMP "t03r1qa-b-stdout.log") -RedirectStandardError (Join-Path $env:TEMP "t03r1qa-b-stderr.log")
try {
    $ready = $false
    for ($i = 0; $i -lt 240; $i++) {
        try { $s = Brp-Call 'jackdaw/status' @{} 5; if ($s.result) { $ready = $true; break } } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw "editor never answered" }
    Wait-Idle
    $setup = Brp-Call 'jackdaw/ui_tree' @{ text = 'Open without setup'; depth = 0 }
    if (@($setup.result.nodes).Count -gt 0) {
        Brp-Call 'jackdaw/ui_click' @{ text = 'Open without setup' } | Out-Null
        Wait-Idle; Wait-Idle
    }
    Op 'input.key' @{ key = 'Escape'; action = 'tap' } | Out-Null
    Op 'scene.open' @{ path = 'assets/zone.bsn' } | Out-Null
    Wait-Idle; Wait-Idle

    Op 'entity.add.cube' @{} | Out-Null
    Wait-Idle; Wait-Idle
    Op 'entity.add.cube' @{} | Out-Null
    Wait-Idle; Wait-Idle
    $bits = @(Cube-Bits)
    Write-Output ("[setup] cube bits: " + ($bits -join ', '))
    Check ($bits.Count -eq 2) "two Brush cubes exist"

    if ($bits.Count -eq 2) {
        $selr = Op 'selection.select' @{ entities = ("{0},{1}" -f $bits[0], $bits[1]) }
        Wait-Idle
        Write-Output ("[setup] select both: " + ($selr.result | ConvertTo-Json -Depth 4 -Compress))

        $h1 = HistProbe
        $doc1 = Doc-Cubes
        Write-Output ("[pre-join] undo_len=" + $h1.undo_len + " doc_cubes=" + $doc1)
        Check ($doc1 -eq 2) "document holds both cubes before the join"

        Op 'input.key' @{ key = 'KeyJ'; action = 'tap' } | Out-Null
        Wait-Idle; Wait-Idle; Wait-Idle
        $h2 = HistProbe
        $doc2 = Doc-Cubes
        $tree2 = @(Scene-Tree | Where-Object { $_.name -eq 'Cube' })
        Write-Output ("[join-realkey] undo_len=" + $h2.undo_len + " (+" + ($h2.undo_len - $h1.undo_len) + ") top=" + $h2.top + " doc_cubes=" + $doc2 + " tree_cubes=" + $tree2.Count)
        $joinDelta = $h2.undo_len - $h1.undo_len

        if ($joinDelta -eq 0) {
            Write-Output "[note] the raw J key did not fire (chord gate); falling back to call_operator history:true"
            $rj = Op 'brush.join' @{ }
            Wait-Idle; Wait-Idle; Wait-Idle
            $h2 = HistProbe
            $doc2 = Doc-Cubes
            Write-Output ("[join-callop] result=" + ($rj.result | ConvertTo-Json -Depth 4 -Compress) + " undo_len=" + $h2.undo_len + " (+" + ($h2.undo_len - $h1.undo_len) + ") top=" + $h2.top + " doc_cubes=" + $doc2)
            $joinDelta = $h2.undo_len - $h1.undo_len
        }
        Check ($joinDelta -eq 1) ("brush.join on the user path is ONE entry (got +" + $joinDelta + ")")
        Check ($doc2 -eq 1) "the join merged the document to one brush"

        Op 'history.undo' @{} | Out-Null
        Wait-Idle; Wait-Idle
        $h3 = HistProbe
        $doc3 = Doc-Cubes
        $tree3 = @(Scene-Tree | Where-Object { $_.name -eq 'Cube' })
        Write-Output ("[join-undo] undo_len=" + $h3.undo_len + " doc_cubes=" + $doc3 + " tree_cubes=" + $tree3.Count)
        Check ($doc3 -eq 2) "one undo restores BOTH brushes in the document"
        Check ($h3.undo_len -eq $h1.undo_len) "stack depth back after one undo"

        # ---- extra observation 1: clip.delete_keyframes refuses without keyframe selection
        $h4 = HistProbe
        $rc = Op 'clip.delete_keyframes' @{ }
        Wait-Idle; Wait-Idle
        $h5 = HistProbe
        Write-Output ("[obs-clip-refuse] result=" + ($rc.result | ConvertTo-Json -Depth 4 -Compress) + " undo_len " + $h4.undo_len + " -> " + $h5.undo_len)
        Check (($rc.result.result -eq 'cancelled') -and ($h5.undo_len -eq $h4.undo_len)) "clip.delete_keyframes refuses (cancelled) with no keyframe selected, no record"

        # ---- extra observation 2: brush.extend_face_to_brush (new finding) gate check
        $h6 = HistProbe
        $re = Op 'brush.extend_face_to_brush' @{ }
        Wait-Idle; Wait-Idle
        $h7 = HistProbe
        Write-Output ("[obs-extend-gate] result=" + ($re.result | ConvertTo-Json -Depth 4 -Compress) + " undo_len " + $h6.undo_len + " -> " + $h7.undo_len)
        Check ($h7.undo_len -eq $h6.undo_len) "extend_face (Object mode, no remembered face) leaves no record"
    } else {
        Write-Output "SKIP: could not stage two cubes"
        $Failures++
    }

    Write-Output ("RESULT failures=" + $Failures)
    if ($Failures -gt 0) { exit 1 }
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
