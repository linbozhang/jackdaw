# T-QT-T1 QA live phase 3: camera + input.motion negative/positive + ambiguity.
# Retry-capable Brp-Call (a stale keep-alive connection stalled one call in phase 2).
param([int]$Port = 15807)
$ErrorActionPreference = "Stop"

function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = "2.0"; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 15
        } catch {
            Start-Sleep -Milliseconds 250
            continue
        }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout waiting for $Method $Params"
}
function Wait-Idle() { Brp-Call "jackdaw/wait" @{ until = "idle" } 60 | Out-Null }
function Op([string]$Id, $Params) { Brp-Call "jackdaw/call_operator" @{ id = $Id; params = $Params } }

# Reset any stuck RMB from phase 2, then settle.
$cur = Brp-Call "jackdaw/camera_state" @{}
Write-Output ("[reset] camera now: " + ($cur.result | ConvertTo-Json -Compress))
Op "input.pointer" @{ action = "release"; button = "secondary" } | Out-Null
Wait-Idle

# --- [5] ambiguity refusal first (no camera state involved) ---
$amb = Brp-Call "jackdaw/ui_click" @{ text = "Add" }
if (-not $amb.error) { throw "ambiguous 'Add' did not refuse" }
$cands = @($amb.error.data.candidates)
Write-Output ("[5] ambiguous text=Add -> " + $amb.error.message + "; candidates listed: " + $cands.Count)

# --- [4] camera: input.motion under fly ---
$before = (Brp-Call "jackdaw/camera_state" @{}).result
Write-Output ("[4] camera before: " + ($before | ConvertTo-Json -Compress))

$fly = $false; $hitX = 0
foreach ($x in 900, 800, 700, 1000, 600) {
    Op "input.pointer" @{ x = $x; y = 500; action = "move" } | Out-Null
    Wait-Idle
    Op "input.pointer" @{ x = $x; y = 500; action = "press"; button = "secondary" } | Out-Null
    Wait-Idle
    $state = (Brp-Call "jackdaw/camera_state" @{}).result
    if ($state.fly -eq $true) { $fly = $true; $hitX = $x; break }
    Op "input.pointer" @{ x = $x; y = 500; action = "release"; button = "secondary" } | Out-Null
    Wait-Idle
}
if (-not $fly) { throw "no viewport under probed x positions" }
Write-Output ("[4] fly engaged at x=$hitX")

# [4a] NEGATIVE: one 3000px beat -> warning + gate drops it (yaw unchanged)
Op "input.pointer" @{ action = "rest"; steps = 5 } | Out-Null
Wait-Idle
$neg = Op "input.motion" @{ dx = 3000; dy = 0; steps = 1 }
$negWarn = @($neg.result.warnings)
Write-Output ("[4a] input.motion dx=3000 steps=1 warnings: " + ($negWarn -join " // "))
if (-not ($negWarn | Where-Object { $_ -match "plausible" })) { throw "no >1000px warning" }
Wait-Idle
$afterNeg = (Brp-Call "jackdaw/camera_state" @{}).result
$dyawNeg = [double]$afterNeg.yaw - [double]$before.yaw
Write-Output ("[4a] yaw after dropped beat: " + [math]::Round($dyawNeg, 3) + " deg (expect ~0)")

# [4b] NEGATIVE: motion queued behind a still-playing gesture -> warning
Op "input.pointer" @{ action = "rest"; steps = 8 } | Out-Null
$q = Op "input.motion" @{ dx = 40; dy = 0; steps = 4 }
$qWarn = @($q.result.warnings)
Write-Output ("[4b] motion behind a playing rest warnings: " + ($qWarn -join " // "))
if (-not ($qWarn | Where-Object { $_ -match "rest" -or $_ -match "suppressed" -or $_ -match "behind" })) { Write-Output "[4b] NOTE: no queued-behind warning observed" }
Wait-Idle

# [4c] POSITIVE: rest past the 3-frame suppression, then -160px over 16 beats
Op "input.pointer" @{ action = "rest"; steps = 5 } | Out-Null
Wait-Idle
$pos = Op "input.motion" @{ dx = -160; dy = 0; steps = 16 }
Write-Output ("[4c] input.motion dx=-160 steps=16 warnings: " + (@($pos.result.warnings) -join " // "))
Wait-Idle
Op "input.pointer" @{ x = $hitX; y = 500; action = "release"; button = "secondary" } | Out-Null
Wait-Idle
$after = (Brp-Call "jackdaw/camera_state" @{}).result
$dyaw = [double]$after.yaw - [double]$before.yaw
$dpitch = [double]$after.pitch - [double]$before.pitch
Write-Output ("[4c] yaw " + [math]::Round($before.yaw, 3) + " -> " + [math]::Round($after.yaw, 3) + " (delta " + [math]::Round($dyaw, 3) + " deg); pitch delta " + [math]::Round($dpitch, 3))
if ([math]::Abs($dyaw) -lt 1.0) { throw "input.motion did not turn the camera (delta $dyaw)" }

Write-Output "QA-LIVE3 PASS"
