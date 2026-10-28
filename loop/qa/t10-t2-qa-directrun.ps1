# T10-T2 QA independent rerun: the direct-run leg only (no editor).
# Boots the warm project's game exe directly, samples the game-side
# BRP on 15702: the template FallingCube settling (three samples,
# frame-to-frame delta), the pickup entities, and the player's
# PickupCount. Warm project: H:\workspace_AI\t10-phys\phys-game.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t10-t2-qa-directrun.ps1
$ErrorActionPreference = 'Continue'

$Project = 'H:\workspace_AI\t10-phys\phys-game'
$Exe     = Join-Path $Project 'target\debug\phys-game.exe'
$GamePort = 15702

function Brp([string]$method, $params, [int]$retries = 3) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = (Get-Random); method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$GamePort/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 10)
        } catch { Start-Sleep -Milliseconds (400 * ($i + 1)) }
    }
    return $null
}

$TKEY = 'bevy_transform::components::transform::Transform'
function Get-T($e) {
    if ($e.components -is [System.Management.Automation.PSObject]) {
        return $e.components.PSObject.Properties[$TKEY].Value
    }
    return $e.components[$TKEY]
}
function Snap-Game { (Brp 'jackdaw/scene_snapshot' @{}).result }

# y of the entity nearest a target x inside a y band, plus all
# matching entities' (x, y) for the report.
function Ys-AtX($snap, [double]$x, [double]$yLo, [double]$yHi, [double]$band) {
    $found = @()
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if ($t) {
            $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
            if ([Math]::Abs($ex - $x) -lt $band -and $ey -ge $yLo -and $ey -le $yHi) {
                $found += [pscustomobject]@{ x = $ex; y = $ey }
            }
        }
    }
    return $found
}
function Pickup-Count($snap) {
    foreach ($e in @($snap)) {
        $t = Get-T $e
        if ($t) {
            $ex = [double]$t.translation[0]; $ey = [double]$t.translation[1]
            if ([Math]::Abs($ex - (-2.0)) -lt 1.0 -and [Math]::Abs($ey - 0.5) -lt 0.4) {
                $props = if ($e.components -is [System.Management.Automation.PSObject]) {
                    $e.components.PSObject.Properties
                } else { $e.components }
                foreach ($prop in $props) {
                    if ("$($prop.Name)" -like '*PickupCount') { return $prop.Value }
                }
            }
        }
    }
    return $null
}

# --- clean orphans, boot the game directly --------------------------------
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process jackdaw    -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500

$deps = Join-Path $Project 'target\debug\deps'
$env:PATH = "$deps;$env:PATH"
# Match the programmer's proven boot shape: `cargo run` from the
# project root (a bare exe boot died between adapter init and window
# creation in this environment).
$proc = Start-Process -FilePath 'cargo' -ArgumentList 'run' -WorkingDirectory $Project -PassThru `
    -RedirectStandardError  (Join-Path $Project 'qa-stderr.log') `
    -RedirectStandardOutput (Join-Path $Project 'qa-stdout.log')
$ready = $false
for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 2
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
        Write-Host 'QA_BOOT_FAIL: cargo/game process died'
        Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
        exit 1
    }
}
if (-not $ready) { Write-Host 'QA_BOOT_FAIL: BRP never answered'; Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }; Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; exit 1 }
Write-Host ("game ready, pid={0}" -f $proc.Id)
Start-Sleep -Seconds 4   # let the cube finish its fall before sampling

# --- leg 1: the template FallingCube settles ------------------------------
$s1 = Ys-AtX (Snap-Game) 0.0 0.05 3.0 0.6
Start-Sleep -Seconds 2
$s2 = Ys-AtX (Snap-Game) 0.0 0.05 3.0 0.6
Start-Sleep -Seconds 2
$s3 = Ys-AtX (Snap-Game) 0.0 0.05 3.0 0.6
$y1 = if ($s1.Count) { [Math]::Round($s1[0].y, 7) } else { $null }
$y2 = if ($s2.Count) { [Math]::Round($s2[0].y, 7) } else { $null }
$y3 = if ($s3.Count) { [Math]::Round($s3[0].y, 7) } else { $null }
Write-Host ("QA_CUBE_Y: y1={0} y2={1} y3={2}" -f $y1, $y2, $y3)
if ($null -ne $y1 -and $null -ne $y2 -and $null -ne $y3) {
    $d12 = [Math]::Abs($y2 - $y1); $d23 = [Math]::Abs($y3 - $y2)
    Write-Host ("QA_CUBE_DELTA: d12={0:E1} d23={1:E1}" -f $d12, $d23)
    if ($d12 -lt 0.001 -and $d23 -lt 0.001 -and $y3 -ge 0.25 -and $y3 -le 0.35) {
        Write-Host 'QA_CUBE_SETTLES_PASS'
    } else { Write-Host 'QA_CUBE_FAIL' }
} else { Write-Host 'QA_CUBE_FAIL (missing entity)' }

# --- leg 2: the pickup chain ----------------------------------------------
$snap = Snap-Game
$pLeft  = Ys-AtX $snap -1.0 0.3 0.7 0.4
$pMid   = Ys-AtX $snap  0.0 0.3 0.7 0.4
$pRight = Ys-AtX $snap  1.0 0.3 0.7 0.4
Write-Host ("QA_PICKUPS: left={0} mid={1} right={2}" -f $pLeft.Count, $pMid.Count, $pRight.Count)
$count = Pickup-Count $snap
$countJson = $count | ConvertTo-Json -Compress
$countNum = if ("$countJson" -match '(\d+)') { [int]$Matches[1] } else { -1 }
Write-Host ("QA_PICKUPCOUNT: {0}" -f $countJson)
if ($pLeft.Count -ge 1 -and $pRight.Count -ge 1 -and $pMid.Count -eq 0 -and $countNum -ge 1) {
    Write-Host 'QA_PICKUP_CHAIN_PASS'
} else { Write-Host 'QA_PICKUP_CHAIN_PARTIAL' }

# --- cleanup ---------------------------------------------------------------
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
Get-Process phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process jackdaw    -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host 'QA_DIRECTRUN_DONE'
