# T03 rework round 1: independent BRP line probe.
# 1) Registry: the nine reworked ops answer allows_undo=false in jackdaw/operators.
# 2) Behaviour: entity.add.terrain then terrain.generate through call_operator
#    (history defaults true - the user path): the generate must leave exactly
#    ONE new undo entry.
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15814
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
function HistProbe {
    $r = Brp-Call 'jackdaw/history' @{ entries = 5 }
    if ($r.error) { Write-Host ("[history] ERROR: " + ($r.error | ConvertTo-Json -Compress)) }
    $r.result
}
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Output ("PASS  " + $What) }
    else { Write-Output ("FAIL  " + $What); $script:Failures++ }
}
$Failures = 0

$Project = Join-Path $env:TEMP "t03r1-probe-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t03r1-probe","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = "1920x1080"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru
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

    # --- 1) registry probe ---
    $ops = (Brp-Call 'jackdaw/operators' @{ }).result.operators
    foreach ($id in @(
        'clip.delete_keyframes', 'clip.paste_keyframes', 'brush.join', 'pie.live_edits_apply_all',
        'terrain.generate', 'terrain.erode', 'resource.insert', 'resource.remove', 'resource.set_field'
    )) {
        $op = @($ops | Where-Object { $_.id -eq $id })
        if ($op.Count -lt 1) { Check $false ("registry: {0} listed" -f $id); continue }
        Check ($op[0].allows_undo -eq $false) ("registry: {0} answers allows_undo=false" -f $id)
    }

    # --- 2) behavioural spot: add terrain, generate through the user path ---
    Op 'entity.add.terrain' @{} | Out-Null
    Wait-Idle; Wait-Idle
    $h1 = HistProbe
    Op 'terrain.generate' @{} | Out-Null
    Wait-Idle; Wait-Idle
    $h2 = HistProbe
    Write-Output ("[probe] terrain.generate: undo_len {0} -> {1} (top: {2})" -f $h1.undo_len, $h2.undo_len, $h2.top)
    Check ($h2.undo_len -eq ($h1.undo_len + 1)) ("behaviour: terrain.generate through call_operator (history=true) is ONE entry")

    Write-Output ("RESULT failures=" + $Failures)
    if ($Failures -gt 0) { exit 1 }
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
