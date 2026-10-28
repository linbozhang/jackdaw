# T03 rework round 1 QA probe A2: clip keybind-path re-enactment on the live editor.
# Keybind-equivalent dispatch = call_operator with history:true (default). Source
# basis: jackdaw_api_internal/src/operator.rs - the framework snapshot is taken
# when (creates_history_entry && allows_undo); Execute vs Invoke only picks the
# system entry point, so the record behaviour of this dispatch equals the
# keybind path (Invoke + creates_history_entry:true).
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15817
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
function Kf-Rows {
    $r = Brp-Call 'world.query' @{
        data = @{ components = @('jackdaw_animation::Vec3Keyframe') }
        filter = @{ with = @('jackdaw_animation::Vec3Keyframe') }
    }
    if ($r.error -or $null -eq $r.result) { return @() }
    @($r.result.rows)
}
function Live-Keyframes { @(Kf-Rows).Count }
function Row-Bits($row) {
    $ent = $row.entity
    if ($ent -is [string]) {
        $p = $ent -split ';'
        return [uint64]([uint64]$p[0] + ([uint64]$p[1] -shl 32))
    }
    if ($ent.PSObject.Properties['bits']) { return [uint64]$ent.bits }
    if ($ent.PSObject.Properties['id']) {
        $p = ([string]$ent.id) -split ';'
        return [uint64]([uint64]$p[0] + ([uint64]$p[1] -shl 32))
    }
    return $null
}
$Failures = 0

$Project = Join-Path $env:TEMP "t03r1qa-a2-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t03r1qa2","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = "1920x1080"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru -RedirectStandardOutput (Join-Path $env:TEMP "t03r1qa-a2-stdout.log") -RedirectStandardError (Join-Path $env:TEMP "t03r1qa-a2-stderr.log")
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

    # --- focus the Timeline panel FIRST, the way the keybind path needs ---
    $tl = Brp-Call 'jackdaw/ui_tree' @{ text = 'Timeline'; depth = 2 }
    Write-Output ("[setup] timeline candidates=" + (@($tl.result.nodes).Count))
    if (@($tl.result.nodes).Count -gt 0) {
        $c = Brp-Call 'jackdaw/ui_click' @{ text = 'Timeline' }
        Write-Output ("[setup] timeline click: " + ($c.result | ConvertTo-Json -Depth 4 -Compress))
        Wait-Idle; Wait-Idle
    }

    Op 'entity.add.cube' @{} | Out-Null
    Wait-Idle; Wait-Idle
    Op 'selection.select' @{ name = 'Cube' } | Out-Null
    Wait-Idle
    $rt = Op 'animation.toggle_keyframe' @{ component_type_path = 'bevy_transform::components::transform::Transform'; field_path = 'translation' }
    Wait-Idle; Wait-Idle; Wait-Idle
    Write-Output ("[setup] toggle=" + ($rt.result | ConvertTo-Json -Depth 4 -Compress))

    $kfRows = @()
    for ($i = 0; $i -lt 24; $i++) {
        $kfRows = @(Kf-Rows)
        if ($kfRows.Count -ge 1) { break }
        Start-Sleep -Milliseconds 500
    }
    Write-Output ("[setup] live keyframes=" + $kfRows.Count)
    Check ($kfRows.Count -eq 1) "exactly one live keyframe after toggle"

    if ($kfRows.Count -ge 1) {
        $row0 = $kfRows[0]
        Write-Output ("[setup] row shape: " + ($row0 | ConvertTo-Json -Depth 6 -Compress))
        $bits = Row-Bits $row0
        Write-Output ("[setup] keyframe bits=" + $bits)
        $selk = Op 'selection.select' @{ entities = ("{0}" -f $bits) }
        Write-Output ("[setup] select kf: " + ($selk.result | ConvertTo-Json -Depth 4 -Compress))
        Wait-Idle

        $h1 = HistProbe
        Write-Output ("[pre] undo_len=" + $h1.undo_len + " live_kf=" + (Live-Keyframes))

        # keybind-path dispatch of the clip delete (history defaults to true)
        $rd = Op 'clip.delete_keyframes' @{}
        Wait-Idle; Wait-Idle
        $h2 = HistProbe
        $lk2 = Live-Keyframes
        Write-Output ("[delete] result=" + ($rd.result | ConvertTo-Json -Depth 4 -Compress) + " undo_len=" + $h2.undo_len + " (+" + ($h2.undo_len - $h1.undo_len) + ") top=" + $h2.top + " live_kf=" + $lk2)
        Check (($h2.undo_len - $h1.undo_len) -eq 1) ("clip.delete_keyframes user dispatch is ONE entry (got +" + ($h2.undo_len - $h1.undo_len) + ")")
        Check ($lk2 -eq 0) "the delete removed the live keyframe"

        Op 'history.undo' @{} | Out-Null
        Wait-Idle; Wait-Idle
        $h3 = HistProbe
        $lk3 = Live-Keyframes
        Write-Output ("[undo] undo_len=" + $h3.undo_len + " live_kf=" + $lk3)
        Check ($lk3 -eq 1) ("one undo restores EXACTLY one keyframe (got " + $lk3 + ")")
        Check ($h3.undo_len -eq $h1.undo_len) "stack depth back after one undo"

        # paste chain: copy records nothing; paste is one entry whose undo is clean
        $rows2 = @(Kf-Rows)
        if ($rows2.Count -ge 1) {
            $bits2 = Row-Bits $rows2[0]
            Op 'selection.select' @{ entities = ("{0}" -f $bits2) } | Out-Null
            Wait-Idle
            $hp0 = HistProbe
            $rc = Op 'clip.copy_keyframes' @{}
            Wait-Idle; Wait-Idle
            $hpc = HistProbe
            Write-Output ("[copy] result=" + ($rc.result | ConvertTo-Json -Depth 4 -Compress) + " undo_len=" + $hpc.undo_len + " (delta " + ($hpc.undo_len - $hp0.undo_len) + ")")
            Check (($hpc.undo_len - $hp0.undo_len) -eq 0) "clip.copy_keyframes records nothing"

            $rp = Op 'clip.paste_keyframes' @{}
            Wait-Idle; Wait-Idle; Wait-Idle
            $hp1 = HistProbe
            $lkp = Live-Keyframes
            Write-Output ("[paste] result=" + ($rp.result | ConvertTo-Json -Depth 4 -Compress) + " undo_len=" + $hp1.undo_len + " (+" + ($hp1.undo_len - $hpc.undo_len) + ") top=" + $hp1.top + " live_kf=" + $lkp)
            Check (($hp1.undo_len - $hpc.undo_len) -eq 1) ("clip.paste_keyframes user dispatch is ONE entry (got +" + ($hp1.undo_len - $hpc.undo_len) + ")")
            Check ($lkp -eq 2) "the pasted keyframe exists beside the original"

            Op 'history.undo' @{} | Out-Null
            Wait-Idle; Wait-Idle
            $hp2 = HistProbe
            $lkp2 = Live-Keyframes
            Write-Output ("[paste-undo] undo_len=" + $hp2.undo_len + " live_kf=" + $lkp2)
            Check ($lkp2 -eq 1) ("one undo removes only the pasted keyframe (got " + $lkp2 + ")")
        } else { Write-Output "SKIP paste: keyframe missing"; $Failures++ }

        # real-key observation: raw Delete and Ctrl+V chord routing (informational)
        $rows3 = @(Kf-Rows)
        if ($rows3.Count -ge 1) {
            $bits3 = Row-Bits $rows3[0]
            Op 'selection.select' @{ entities = ("{0}" -f $bits3) } | Out-Null
            Wait-Idle
            $ho0 = HistProbe
            Op 'input.key' @{ key = 'Delete'; action = 'tap' } | Out-Null
            Wait-Idle; Wait-Idle
            $ho1 = HistProbe
            Write-Output ("[realkey Delete] undo_len " + $ho0.undo_len + " -> " + $ho1.undo_len + " top=" + $ho1.top + " live_kf=" + (Live-Keyframes) + " (chord routes Delete: clip.delete_keyframes / entity.delete / brush.delete_element)")
        }
    } else {
        Write-Output "SKIP chains: no keyframe appeared"
        $Failures++
    }

    Write-Output ("RESULT failures=" + $Failures)
    if ($Failures -gt 0) { exit 1 }
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}

