# T11-T2 probe 2: does the windowed PIE mode survive where the windowless
# one dies with 0xc0000005? (Environment watch: T10b pinned the crash as a
# driver-state issue; the windowless Vulkan form died 3/3 in leg A v3.)
# Windowed = the game opens its own OS window (debug fallback) = the same
# form the T1 direct-run legs used successfully.
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$Port = 15805,
    [int]$GamePort = 15702
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$OutDir = Join-Path $Repo 'loop\t11t2-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Exe = Join-Path $Repo 'target\debug\jackdaw.exe'
function Brp([string]$method, $params, [int]$retries = 3) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 10)
        } catch { Start-Sleep -Milliseconds (300 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp 'jackdaw/call_operator' @{ id = $id } }
}
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = '1920x1080'
$env:RUST_BACKTRACE = '1'
$editorLog = Join-Path $OutDir 'probe2-editor.log'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"$(Split-Path -Parent $Exe)`" cmd /c `"`"$Exe`" > `"$editorLog`" 2>`&1`""
$ready = $false
for ($i = 0; $i -lt 150; $i++) { Start-Sleep -Seconds 2; if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break } }
if (-not $ready) { Write-Host 'EDITOR_BOOT_FAIL'; exit 1 }
$deadline = (Get-Date).AddSeconds(900)
while ((Get-Date) -lt $deadline) {
    $r = Brp 'jackdaw/wait' @{ until = 'idle' } 1
    if ($r -and $r.result -and $r.result.idle) { break }
    Start-Sleep -Seconds 2
}
Start-Sleep -Seconds 3
# windowed mode first, then play the placement scene
$w = Op 'pie.window_mode_toggle' @{}
Write-Host ("windowed toggle: {0}" -f ($w | ConvertTo-Json -Depth 3 -Compress))
Op 'scene.open' @{ path = 'assets/t11t2-place.bsn' } | Out-Null
Start-Sleep -Seconds 2
Op 'pie.play_current' @{} | Out-Null
$connected = $false
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    $txt = ''
    if (Test-Path $editorLog) { $txt = [IO.File]::ReadAllText($editorLog) }
    if ($txt -match 'connected') { $connected = $true; break }
    if ($txt -match 'exited before connecting') { break }
    Start-Sleep -Milliseconds 500
}
Write-Host ("PROBE2 windowed PIE connected: {0}" -f $connected)
if ($connected) {
    Start-Sleep -Seconds 3
    # does the game's own BRP answer (windowed = direct-run form)?
    $g = $null
    try { $g = Invoke-RestMethod -Uri "http://127.0.0.1:$GamePort/" -Method Post -ContentType 'application/json' -TimeoutSec 10 -Body '{"jsonrpc":"2.0","id":1,"method":"jackdaw/status"}' } catch {}
    Write-Host ("PROBE2 game 15702: {0}" -f $(if ($g) { 'ANSWERS' } else { 'silent' }))
    Start-Sleep -Seconds 15
    $alive = Get-Process t11t1-game -ErrorAction SilentlyContinue
    Write-Host ("PROBE2 game alive after 15s: {0}" -f ($null -ne $alive))
}
Op 'pie.stop' @{} | Out-Null
Start-Sleep -Seconds 3
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host 'PROBE2_DONE'
