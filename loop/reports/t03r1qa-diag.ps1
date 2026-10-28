# Diagnostic: dump world.query row shape + selection state + chord routing.
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15816
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

$Project = Join-Path $env:TEMP "t03r1qa-diag-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"diag","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = "1920x1080"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru -RedirectStandardOutput (Join-Path $env:TEMP "t03r1qa-diag-stdout.log") -RedirectStandardError (Join-Path $env:TEMP "t03r1qa-diag-stderr.log")
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
    Op 'selection.select' @{ name = 'Cube' } | Out-Null
    Wait-Idle
    $sel1 = Op 'selection.select' @{ name = 'Cube' }
    Write-Output ("[select.cube raw] " + ($sel1.result | ConvertTo-Json -Depth 6 -Compress))
    Op 'animation.toggle_keyframe' @{ component_type_path = 'bevy_transform::components::transform::Transform'; field_path = 'translation' } | Out-Null
    Wait-Idle; Wait-Idle; Wait-Idle
    Start-Sleep -Milliseconds 1500

    $q = $null
    for ($i = 0; $i -lt 20; $i++) {
        $q = Brp-Call 'world.query' @{
            data = @{ components = @('jackdaw_animation::Vec3Keyframe') }
            filter = @{ with = @('jackdaw_animation::Vec3Keyframe') }
        }
        if ($q.result -and @($q.result.rows).Count -ge 1) { break }
        Start-Sleep -Milliseconds 500
    }
    Write-Output ("[kf query raw] " + ($q.result | ConvertTo-Json -Depth 6 -Compress))

    # grab the keyframe id robustly from whatever shape comes back
    $rows = @()
    if ($q.result) { $rows = @($q.result.rows) }
    if ($rows.Count -ge 1) {
        $ent = $rows[0].entity
        if ($null -ne $ent) { Write-Output ("[entity shape] type=" + $ent.GetType().FullName + " json=" + ($ent | ConvertTo-Json -Depth 6 -Compress)) }
        $bits = $null
        if ($ent -is [string]) {
            $parts = $ent -split ';'
            $bits = [uint64]([uint64]$parts[0] + ([uint64]$parts[1] -shl 32))
        } elseif ($ent.PSObject.Properties['bits']) {
            $bits = [uint64]$ent.bits
        } elseif ($ent.PSObject.Properties['id']) {
            $parts = ([string]$ent.id) -split ';'
            $bits = [uint64]([uint64]$parts[0] + ([uint64]$parts[1] -shl 32))
        }
        Write-Output ("[kf bits] " + $bits)
        if ($bits) {
            $selk = Op 'selection.select' @{ entities = ("{0}" -f $bits) }
            Write-Output ("[select.kf raw] " + ($selk.result | ConvertTo-Json -Depth 6 -Compress))
        }
        # focus timeline then press Delete for real
        $tl = Brp-Call 'jackdaw/ui_tree' @{ text = 'Timeline'; depth = 0 }
        Write-Output ("[timeline node] " + ($tl.result | ConvertTo-Json -Depth 6 -Compress))
        if (@($tl.result.nodes).Count -gt 0) {
            Brp-Call 'jackdaw/ui_click' @{ text = 'Timeline' } | Out-Null
            Wait-Idle
        }
        $h1 = Brp-Call 'jackdaw/history' @{ entries = 6 }
        Op 'input.key' @{ key = 'Delete'; action = 'tap' } | Out-Null
        Wait-Idle; Wait-Idle; Wait-Idle
        $h2 = Brp-Call 'jackdaw/history' @{ entries = 6 }
        $q2 = Brp-Call 'world.query' @{
            data = @{ components = @('jackdaw_animation::Vec3Keyframe') }
            filter = @{ with = @('jackdaw_animation::Vec3Keyframe') }
        }
        Write-Output ("[delete] undo_len " + $h1.result.undo_len + " -> " + $h2.result.undo_len + " top=" + $h2.result.top + " live_kf=" + @($q2.result.rows).Count)
        Write-Output ("[undo labels] " + (($h2.result.undo | ForEach-Object { $_.label }) -join ' | '))
    } else {
        Write-Output "[diag] no keyframe rows appeared after polling"
    }
    Write-Output "DONE"
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
