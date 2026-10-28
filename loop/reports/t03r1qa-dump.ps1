# One-shot structural dump to decide the keyframe-entity selection channel.
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15818
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
    throw "timeout waiting for $Method"
}
function DJ($o, [int]$Max = 2000) {
    if ($null -eq $o) { return '<null>' }
    $s = (ConvertTo-Json -InputObject $o -Depth 10 -Compress)
    if ($s.Length -gt $Max) { return $s.Substring(0, $Max) + '...<cut>' }
    return $s
}
function Wait-Idle([int]$T = 90) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null; Start-Sleep -Milliseconds 400 }
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }

$Project = Join-Path $env:TEMP "t03r1qa-dump-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"dump","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = "1920x1080"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru -RedirectStandardOutput (Join-Path $env:TEMP "t03r1qa-dump-stdout.log") -RedirectStandardError (Join-Path $env:TEMP "t03r1qa-dump-stderr.log")
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

    # 1) is Vec3Keyframe a registered reflect component for bevy BRP?
    $lc = Brp-Call 'world.list_components' @{ }
    if ($lc.error) { Write-Output "[list_components] ERROR " + (DJ $lc.error 300) }
    else {
        $names = $lc.result
        $flat = DJ $names 100
        $hits = @()
        if ($names -is [array]) { $hits = @($names | Where-Object { $_ -match 'Keyframe' }) }
        elseif ($names.components) { $hits = @($names.components | Where-Object { $_ -match 'Keyframe' }) }
        Write-Output ("[list_components] keyframe-hits=" + $hits.Count + " " + (($hits | Select-Object -First 6) -join ', '))
    }

    # 2) focus timeline, make a keyframe
    $tl = Brp-Call 'jackdaw/ui_tree' @{ text = 'Timeline'; depth = 2 }
    if (@($tl.result.nodes).Count -gt 0) { Brp-Call 'jackdaw/ui_click' @{ text = 'Timeline' } | Out-Null; Wait-Idle; Wait-Idle }
    Op 'entity.add.cube' @{} | Out-Null
    Wait-Idle; Wait-Idle
    Op 'selection.select' @{ name = 'Cube' } | Out-Null
    Wait-Idle
    $rt = Op 'animation.toggle_keyframe' @{ component_type_path = 'bevy_transform::components::transform::Transform'; field_path = 'translation' }
    Wait-Idle; Wait-Idle; Wait-Idle
    Start-Sleep -Milliseconds 1200
    Write-Output ("[toggle] " + (DJ $rt.result 200))

    # 3) world.query raw shape
    $q = Brp-Call 'world.query' @{
        data = @{ components = @('jackdaw_animation::Vec3Keyframe') }
        filter = @{ with = @('jackdaw_animation::Vec3Keyframe') }
    }
    Write-Output ("[query.kf] " + (DJ $q 800))

    # query with Name too, to see the row shape on a known entity
    $qn = Brp-Call 'world.query' @{
        data = @{ components = @('bevy_core::name::Name') }
        filter = @{ with = @('bevy_core::name::Name') }
    }
    Write-Output ("[query.name] " + (DJ $qn 800))

    # 4) scene_bsn doc text
    $sb = Brp-Call 'jackdaw/scene_bsn' @{ }
    $bsnText = [string]$sb.result.bsn
    Write-Output ("[scene_bsn] len=" + $bsnText.Length + " kf-hits=" + ([regex]::Matches($bsnText, 'Vec3Keyframe')).Count)
    Write-Output ("[scene_bsn head] " + $bsnText.Substring(0, [Math]::Min(400, $bsnText.Length)))

    # 5) scene_tree raw
    $st = Brp-Call 'jackdaw/scene_tree' @{ }
    Write-Output ("[scene_tree] " + (DJ $st 1200))

    # 6) ui_tree full (find keyframe visuals under the timeline panel)
    $ut = Brp-Call 'jackdaw/ui_tree' @{ depth = 4 }
    Write-Output ("[ui_tree] " + (DJ $ut 2500))
    Write-Output "DONE"
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
