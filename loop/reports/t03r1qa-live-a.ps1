# T03 rework round 1 QA: independent live probe (registry + keybind paths).
# a) clip delete (Delete) / paste (Ctrl+V) keybind paths leave exactly ONE
#    undo entry, and one undo restores/cleans exactly one keyframe.
# c) registry: the nine reworked ops answer allows_undo=false.
# d) reverse spot-check: entity.duplicate / entity.toggle_visibility stay true.
# e) new-finding corroboration: brush.extend_face_to_brush answers true.
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15815
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
function Op([string]$Id, $Params) { $r = Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params }; $r }
function HistProbe {
    $r = Brp-Call 'jackdaw/history' @{ entries = 6 }
    if ($r.error) { Write-Output ("[history] ERROR: " + ($r.error | ConvertTo-Json -Compress)) }
    $r.result
}
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Output ("PASS  " + $What) }
    else { Write-Output ("FAIL  " + $What); $script:Failures++ }
}
# live keyframe count via bevy world.query on the Vec3Keyframe component
function Live-Keyframes {
    $r = Brp-Call 'world.query' @{
        data = @{ components = @('jackdaw_animation::Vec3Keyframe') }
        filter = @{ with = @('jackdaw_animation::Vec3Keyframe') }
    }
    if ($r.error) { Write-Output ("[query] ERROR: " + ($r.error | ConvertTo-Json -Compress)); return -1 }
    @($r.result.rows).Count
}
# "N;M" (index;generation) -> raw bits u64
function To-Bits([string]$Nm) {
    $parts = $Nm -split ';'
    [uint64]([uint64]$parts[0] + ([uint64]$parts[1] -shl 32))
}
# first live keyframe entity id string
function First-Keyframe-Id {
    $r = Brp-Call 'world.query' @{
        data = @{ components = @('jackdaw_animation::Vec3Keyframe') }
        filter = @{ with = @('jackdaw_animation::Vec3Keyframe') }
    }
    if ($r.error -or @($r.result.rows).Count -lt 1) { return $null }
    [string]@($r.result.rows)[0].entity
}
$Failures = 0

$Project = Join-Path $env:TEMP "t03r1qa-live-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t03r1qa","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = "1920x1080"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru -RedirectStandardOutput (Join-Path $env:TEMP "t03r1qa-live-stdout.log") -RedirectStandardError (Join-Path $env:TEMP "t03r1qa-live-stderr.log")
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

    # ---------- c) registry: the nine reworked ops ----------
    $ops = (Brp-Call 'jackdaw/operators' @{ }).result.operators
    foreach ($id in @(
        'clip.delete_keyframes', 'clip.paste_keyframes', 'brush.join', 'pie.live_edits_apply_all',
        'terrain.generate', 'terrain.erode', 'resource.insert', 'resource.remove', 'resource.set_field'
    )) {
        $op = @($ops | Where-Object { $_.id -eq $id })
        if ($op.Count -lt 1) { Check $false ("registry: {0} listed" -f $id); continue }
        Check ($op[0].allows_undo -eq $false) ("registry: {0} answers allows_undo=false" -f $id)
    }
    # ---------- d) reverse spot-checks stay true ----------
    foreach ($id in @('entity.duplicate', 'entity.toggle_visibility')) {
        $op = @($ops | Where-Object { $_.id -eq $id })
        if ($op.Count -lt 1) { Check $false ("registry: {0} listed" -f $id); continue }
        Check ($op[0].allows_undo -eq $true) ("reverse: {0} still allows_undo=true" -f $id)
    }
    # ---------- e) new finding corroboration ----------
    $ef = @($ops | Where-Object { $_.id -eq 'brush.extend_face_to_brush' })
    if ($ef.Count -ge 1) {
        Write-Output ("[note] brush.extend_face_to_brush allows_undo=" + $ef[0].allows_undo + " (expected TRUE per current code: undeclared)")
    } else { Write-Output "[note] brush.extend_face_to_brush not listed" }
    $sv = @($ops | Where-Object { $_.id -eq 'pie.live_edit_save' })
    if ($sv.Count -ge 1) { Write-Output ("[note] pie.live_edit_save allows_undo=" + $sv[0].allows_undo) }

    # ---------- a) keybind delete / paste ----------
    $h0 = HistProbe
    Write-Output ("[base] undo_len=" + $h0.undo_len)
    Check ($h0.undo_len -eq 0) "baseline after scene.open has empty undo stack"

    Op 'entity.add.cube' @{} | Out-Null
    Wait-Idle; Wait-Idle
    Op 'selection.select' @{ name = 'Cube' } | Out-Null
    Wait-Idle
    $r = Op 'animation.toggle_keyframe' @{ component_type_path = 'bevy_transform::components::transform::Transform'; field_path = 'translation' }
    Wait-Idle; Wait-Idle; Wait-Idle
    $kf = First-Keyframe-Id
    Write-Output ("[setup] toggle result=" + ($r.result | ConvertTo-Json -Compress) + " keyframe=" + $kf)
    Check ($null -ne $kf) "a keyframe exists after animation.toggle_keyframe on the selected cube"

    if ($null -ne $kf) {
        $bits = To-Bits $kf
        Op 'selection.select' @{ entities = ("{0}" -f $bits) } | Out-Null
        Wait-Idle
        # focus the timeline panel the way a press inside it would
        $tl = Brp-Call 'jackdaw/ui_tree' @{ text = 'Timeline'; depth = 0 }
        Write-Output ("[setup] timeline nodes=" + (@($tl.result.nodes).Count))
        if (@($tl.result.nodes).Count -gt 0) {
            Brp-Call 'jackdaw/ui_click' @{ text = 'Timeline' } | Out-Null
            Wait-Idle
        }
        $h1 = HistProbe
        Write-Output ("[pre-delete] undo_len=" + $h1.undo_len + " live_kf=" + (Live-Keyframes))

        Op 'input.key' @{ key = 'Delete'; action = 'tap' } | Out-Null
        Wait-Idle; Wait-Idle; Wait-Idle
        $h2 = HistProbe
        $lk2 = Live-Keyframes
        Write-Output ("[post-delete] undo_len=" + $h2.undo_len + " (+" + ($h2.undo_len - $h1.undo_len) + ") top=" + $h2.top + " live_kf=" + $lk2)
        Check (($h2.undo_len - $h1.undo_len) -eq 1) ("keybind Delete: exactly ONE new undo entry (got +" + ($h2.undo_len - $h1.undo_len) + ")")
        Check ($lk2 -eq 0) "keybind Delete removed the live keyframe"

        Op 'history.undo' @{} | Out-Null
        Wait-Idle; Wait-Idle
        $h3 = HistProbe
        $lk3 = Live-Keyframes
        Write-Output ("[post-undo] undo_len=" + $h3.undo_len + " live_kf=" + $lk3)
        Check ($h3.undo_len -eq $h1.undo_len) "one undo returns the stack depth"
        Check ($lk3 -eq 1) ("one undo restores EXACTLY one live keyframe, no duplicate (got " + $lk3 + ")")

        # paste chain: make a keyframe again, select it, Ctrl+C then Ctrl+V
        Op 'selection.select' @{ name = 'Cube' } | Out-Null
        Wait-Idle
        Op 'animation.toggle_keyframe' @{ component_type_path = 'bevy_transform::components::transform::Transform'; field_path = 'translation' } | Out-Null
        Wait-Idle; Wait-Idle; Wait-Idle
        $kf2 = First-Keyframe-Id
        if ($null -ne $kf2) {
            $bits2 = To-Bits $kf2
            Op 'selection.select' @{ entities = ("{0}" -f $bits2) } | Out-Null
            Wait-Idle
            $tl2 = Brp-Call 'jackdaw/ui_tree' @{ text = 'Timeline'; depth = 0 }
            if (@($tl2.result.nodes).Count -gt 0) { Brp-Call 'jackdaw/ui_click' @{ text = 'Timeline' } | Out-Null; Wait-Idle }

            $hp0 = HistProbe
            Op 'input.key' @{ key = 'KeyC'; mods = 'ctrl'; action = 'tap' } | Out-Null
            Wait-Idle; Wait-Idle
            $hpc = HistProbe
            Write-Output ("[post-copy] undo_len=" + $hpc.undo_len + " (delta " + ($hpc.undo_len - $hp0.undo_len) + ")")
            Check (($hpc.undo_len - $hp0.undo_len) -eq 0) "keybind Ctrl+C records nothing"

            Op 'input.key' @{ key = 'KeyV'; mods = 'ctrl'; action = 'tap' } | Out-Null
            Wait-Idle; Wait-Idle; Wait-Idle
            $hp1 = HistProbe
            $lkp = Live-Keyframes
            Write-Output ("[post-paste] undo_len=" + $hp1.undo_len + " (+" + ($hp1.undo_len - $hpc.undo_len) + ") top=" + $hp1.top + " live_kf=" + $lkp)
            Check (($hp1.undo_len - $hpc.undo_len) -eq 1) ("keybind Ctrl+V: exactly ONE new undo entry (got +" + ($hp1.undo_len - $hpc.undo_len) + ")")
            Check ($lkp -eq 2) "the pasted keyframe exists beside the original"

            Op 'history.undo' @{} | Out-Null
            Wait-Idle; Wait-Idle
            $hp2 = HistProbe
            $lkp2 = Live-Keyframes
            Write-Output ("[post-paste-undo] undo_len=" + $hp2.undo_len + " live_kf=" + $lkp2)
            Check ($lkp2 -eq 1) ("one undo takes only the pasted keyframe away (got " + $lkp2 + ")")
        } else {
            Write-Output "SKIP paste chain: second keyframe could not be created"
            $Failures++
        }
    } else {
        Write-Output "SKIP keybind chains: no keyframe could be created"
        $Failures++
    }

    Write-Output ("RESULT failures=" + $Failures)
    if ($Failures -gt 0) { exit 1 }
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
