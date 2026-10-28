# T03 rework round 2 QA: independent registry re-probe on the live editor.
# 11 ops must answer allows_undo=false; the two anchors must stay true.
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15820
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
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Output ("PASS  " + $What) }
    else { Write-Output ("FAIL  " + $What); $script:Failures++ }
}
$Failures = 0

$Project = Join-Path $env:TEMP "t03r2qa-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t03r2qa","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = "1920x1080"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru -RedirectStandardOutput (Join-Path $env:TEMP "t03r2qa-stdout.log") -RedirectStandardError (Join-Path $env:TEMP "t03r2qa-stderr.log")
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
    Brp-Call 'jackdaw/call_operator' @{ id = 'input.key'; params = @{ key = 'Escape'; action = 'tap' } } | Out-Null
    Brp-Call 'jackdaw/call_operator' @{ id = 'scene.open'; params = @{ path = 'assets/zone.bsn' } } | Out-Null
    Wait-Idle; Wait-Idle

    $ops = (Brp-Call 'jackdaw/operators' @{ }).result.operators
    $falseIds = @(
        'brush.extend_face_to_brush', 'pie.live_edit_save',
        'clip.delete_keyframes', 'clip.paste_keyframes', 'brush.join', 'pie.live_edits_apply_all',
        'terrain.generate', 'terrain.erode', 'resource.insert', 'resource.remove', 'resource.set_field'
    )
    foreach ($id in $falseIds) {
        $op = @($ops | Where-Object { $_.id -eq $id })
        if ($op.Count -lt 1) { Check $false ("registry: {0} listed" -f $id); continue }
        Check ($op[0].allows_undo -eq $false) ("registry: {0} answers allows_undo=false" -f $id)
    }
    foreach ($id in @('entity.duplicate', 'entity.toggle_visibility')) {
        $op = @($ops | Where-Object { $_.id -eq $id })
        if ($op.Count -lt 1) { Check $false ("anchor: {0} listed" -f $id); continue }
        Check ($op[0].allows_undo -eq $true) ("anchor: {0} still allows_undo=true" -f $id)
    }
    Write-Output ("RESULT failures=" + $Failures)
    if ($Failures -gt 0) { exit 1 }
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
