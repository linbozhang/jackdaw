# T10-T3 matrix, step 0: create assets/game-config.bsn (gravity -9.81)
# through the editor's real New Asset chain, so the game legs run from an
# authored file (T08 regression ride-along). Detached boot via cmd start /B
# (the QA-proven shape; Start-Process from a piped host has died 0xc0000005).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t10t3-cfg.ps1
param(
    [string]$Project = 'H:\workspace_AI\t10-phys\phys-game',
    [int]$Port = 15703
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$Exe  = Join-Path $Repo 'target\debug\jackdaw.exe'
$OutDir = Join-Path $Repo 'loop\t10t3-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Brp([string]$method, $params, [int]$retries = 4) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 10)
        } catch { Start-Sleep -Milliseconds (400 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp 'jackdaw/call_operator' @{ id = $id } }
}
function Wait-Idle([int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp 'jackdaw/wait' @{ until = 'idle' } 1
        if ($r -and $r.result -and $r.result.idle) { return $true }
        Start-Sleep -Seconds 2
    }
    throw "wait(idle) timed out after ${TimeoutSec}s"
}

# --- detached boot ---------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$env:JACKDAW_WINDOW_SIZE  = '1920x1080'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$work = Split-Path -Parent $Exe
cmd /c "start /B /D `"$work`" cmd /c `"`"$Exe`" > `"$OutDir\cfg-editor.log`" 2>&1`""
$ready = $false
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 2
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
}
if (-not $ready) { Write-Host 'CFG_FAIL: editor BRP never answered'; Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force; exit 1 }
Wait-Idle 1800 | Out-Null
Start-Sleep -Seconds 5
Write-Host 'editor ready'

# --- the config asset ------------------------------------------------------
$configPath = Join-Path $Project 'assets\game-config.bsn'
if (Test-Path $configPath) { Remove-Item $configPath -Force }
$created = Op 'asset.new' @{ type = 'game_config'; name = 'game-config' }
Write-Host ("asset.new: " + ($created | ConvertTo-Json -Depth 6 -Compress))
Op 'asset.set' @{ field = 'gravity'; value = '-9.81' } | Out-Null
Op 'asset.save' @{} | Out-Null
Start-Sleep -Seconds 2
$onDisk = [IO.File]::ReadAllText($configPath)
Write-Host "game-config.bsn on disk:`n$onDisk"
if ($onDisk -notmatch '-9\.81') { Write-Host 'CFG_FAIL: gravity -9.81 not in file' }
else { Write-Host 'CFG_OK' }

# --- exit -------------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
Write-Host 'T10T3_CFG_DONE'
