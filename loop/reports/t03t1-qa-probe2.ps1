param([int]$Port = 15809)
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
function Wait-Idle([int]$T = 90) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }

$Project = Join-Path $env:TEMP "t03t1-probe-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"probe","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath "E:\Project\rust\jackdaw\target\debug\jackdaw.exe" -PassThru
try {
    for ($i = 0; $i -lt 240; $i++) {
        try { $s = Brp-Call 'jackdaw/status' @{} 5; if ($s.result) { break } } catch { Start-Sleep -Milliseconds 500 }
    }
    Wait-Idle
    $setup = Brp-Call 'jackdaw/ui_tree' @{ text = 'Open without setup'; depth = 0 }
    if (@($setup.result.nodes).Count -gt 0) { Brp-Call 'jackdaw/ui_click' @{ text = 'Open without setup' } | Out-Null; Wait-Idle }
    Brp-Call 'jackdaw/call_operator' @{ id = 'scene.new'; params = @{} } | Out-Null; Wait-Idle
    Brp-Call 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} } | Out-Null; Wait-Idle

    $g = Brp-Call 'bevy/get' @{ components = @('jackdaw_scene_types::Name', 'bevy_transform::components::transform::Transform') }
    Write-Output ('bevy/get raw: ' + ($g | ConvertTo-Json -Depth 12 -Compress))
    $e = Brp-Call 'jackdaw/entity' @{ }
    Write-Output ('jackdaw/entity raw: ' + ($e | ConvertTo-Json -Depth 12 -Compress))
} finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
